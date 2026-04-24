<#
.SYNOPSIS
    Discover and install network printers on the current LAN.

.DESCRIPTION
    Scans the active IPv4 subnet for devices listening on TCP port 9100
    (RAW / HP JetDirect), creates a standard TCP/IP printer port for each
    responding host, and installs a printer using the generic
    "Microsoft IPP Class Driver" so no vendor driver download is required.

    Also enumerates SMB-shared printers via Get-Printer / net view.

.PARAMETER Subnet
    Override the subnet to scan in CIDR-style /24 form, e.g. "192.168.1".
    If omitted, it is inferred from the primary active IPv4 adapter.

.PARAMETER ListOnly
    Discover printers but do not install them.

.PARAMETER Default
    Name of a printer to mark as the default after installation.

.EXAMPLE
    .\add-network-printers.ps1
    .\add-network-printers.ps1 -ListOnly
    .\add-network-printers.ps1 -Subnet 10.0.0 -Default "HP-Office"

.NOTES
    Run from an elevated PowerShell prompt. Requires Windows 10/11 or
    Server 2016+ (PrintManagement module).
#>

[CmdletBinding()]
param(
    [string]$Subnet,
    [switch]$ListOnly,
    [string]$Default
)

$ErrorActionPreference = 'Stop'

function Get-LocalSubnet {
    $cfg = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        Select-Object -First 1
    if (-not $cfg) { throw "No active IPv4 adapter with a default gateway was found." }
    $ip = $cfg.IPv4Address.IPAddress
    return ($ip -split '\.')[0..2] -join '.'
}

function Test-PrinterPort {
    param([string]$IPAddress, [int]$Port = 9100, [int]$TimeoutMs = 400)
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect($IPAddress, $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) {
            $client.EndConnect($async) | Out-Null
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Resolve-HostName {
    param([string]$IPAddress)
    try { return [System.Net.Dns]::GetHostEntry($IPAddress).HostName }
    catch { return $IPAddress }
}

if (-not $Subnet) { $Subnet = Get-LocalSubnet }
Write-Host "Scanning subnet $Subnet.0/24 for printers on port 9100..." -ForegroundColor Cyan

$jobs = 1..254 | ForEach-Object {
    $ip = "$Subnet.$_"
    Start-ThreadJob -ScriptBlock {
        param($addr)
        $c = [System.Net.Sockets.TcpClient]::new()
        try {
            $async = $c.BeginConnect($addr, 9100, $null, $null)
            if ($async.AsyncWaitHandle.WaitOne(400, $false) -and $c.Connected) {
                $c.EndConnect($async) | Out-Null
                return $addr
            }
        } catch { }
        finally { $c.Close() }
        return $null
    } -ArgumentList $ip
}

$ipPrinters = $jobs | Receive-Job -Wait -AutoRemoveJob | Where-Object { $_ }
Write-Host ("  Found {0} IP printer(s): {1}" -f $ipPrinters.Count, ($ipPrinters -join ', ')) -ForegroundColor Green

Write-Host "Enumerating SMB-shared printers via 'net view'..." -ForegroundColor Cyan
$shared = @()
try {
    $hosts = (net view 2>$null) |
        Select-String -Pattern '^\\\\\S+' |
        ForEach-Object { ($_.Line -split '\s+')[0] }
    foreach ($h in $hosts) {
        (net view $h /all 2>$null) |
            Select-String -Pattern '\s+Print\s' |
            ForEach-Object {
                $share = ($_.Line -split '\s+')[0]
                $shared += "$h\$share"
            }
    }
} catch { }
Write-Host ("  Found {0} shared printer(s)." -f $shared.Count) -ForegroundColor Green

if ($ListOnly) {
    Write-Host "`n=== Discovered printers ===" -ForegroundColor Yellow
    $ipPrinters | ForEach-Object { Write-Host "  IP:     $_" }
    $shared     | ForEach-Object { Write-Host "  Shared: $_" }
    return
}

$installed = 0
$failed    = 0

foreach ($ip in $ipPrinters) {
    $name     = Resolve-HostName $ip
    $portName = "IP_$ip"
    $printerName = "Net_$name"
    try {
        if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
            Add-PrinterPort -Name $portName -PrinterHostAddress $ip
        }
        if (-not (Get-Printer -Name $printerName -ErrorAction SilentlyContinue)) {
            Add-Printer -Name $printerName -PortName $portName -DriverName 'Microsoft IPP Class Driver'
        }
        Write-Host "  Installed $printerName ($ip)" -ForegroundColor Green
        $installed++
    } catch {
        Write-Warning "  Failed $ip : $($_.Exception.Message)"
        $failed++
    }
}

foreach ($unc in $shared) {
    try {
        rundll32 printui.dll,PrintUIEntry /in /q /n "\\$unc"
        Write-Host "  Connected \\$unc" -ForegroundColor Green
        $installed++
    } catch {
        Write-Warning "  Failed \\$unc : $($_.Exception.Message)"
        $failed++
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Yellow
Write-Host "  Installed: $installed"
Write-Host "  Failed:    $failed"

if ($Default) {
    try {
        (New-Object -ComObject WScript.Network).SetDefaultPrinter($Default)
        Write-Host "  Default set to '$Default'" -ForegroundColor Green
    } catch {
        Write-Warning "  Could not set default to '$Default': $($_.Exception.Message)"
    }
}
