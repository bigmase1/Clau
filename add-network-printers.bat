@echo off
REM ============================================================
REM  add-network-printers.bat
REM  Discovers shared printers on the local Windows network and
REM  installs each one for the current user.
REM
REM  Usage:   add-network-printers.bat          (discover + install)
REM           add-network-printers.bat /list    (discover only, no install)
REM           add-network-printers.bat /default <name>   (set default after install)
REM
REM  Requires: Windows, network access, File and Printer Sharing
REM            enabled on the LAN. Run from an elevated Command
REM            Prompt if per-machine driver install is needed.
REM ============================================================

setlocal EnableDelayedExpansion

set "MODE=install"
set "DEFAULT_PRINTER="

:parse_args
if "%~1"=="" goto :args_done
if /I "%~1"=="/list"    ( set "MODE=list" & shift & goto :parse_args )
if /I "%~1"=="/default" ( set "DEFAULT_PRINTER=%~2" & shift & shift & goto :parse_args )
if /I "%~1"=="/?"       goto :usage
if /I "%~1"=="-h"       goto :usage
if /I "%~1"=="--help"   goto :usage
echo Unknown argument: %~1
goto :usage
:args_done

echo.
echo === Network Printer Setup ===
echo Mode: %MODE%
echo.

REM ---- 1. Enumerate computers visible on the network ----
echo [1/3] Discovering computers on the network...
set "HOSTS_FILE=%TEMP%\npp_hosts.txt"
if exist "%HOSTS_FILE%" del "%HOSTS_FILE%" >nul 2>&1

for /f "usebackq tokens=1" %%H in (`net view 2^>nul ^| findstr /B "\\\\"`) do (
    echo %%H>>"%HOSTS_FILE%"
)

if not exist "%HOSTS_FILE%" (
    echo   No hosts returned by "net view".
    echo   Ensure Network Discovery and File and Printer Sharing are enabled.
    goto :cleanup
)

for /f %%C in ('type "%HOSTS_FILE%" ^| find /c /v ""') do set "HOST_COUNT=%%C"
echo   Found !HOST_COUNT! host(s).
echo.

REM ---- 2. Enumerate shared printers on each host ----
echo [2/3] Scanning hosts for shared printers...
set "PRINTERS_FILE=%TEMP%\npp_printers.txt"
if exist "%PRINTERS_FILE%" del "%PRINTERS_FILE%" >nul 2>&1

for /f "usebackq delims=" %%H in ("%HOSTS_FILE%") do (
    echo   - %%H
    for /f "usebackq tokens=1,2 delims= " %%S in (`net view %%H /all 2^>nul ^| findstr /I "Print"`) do (
        if /I "%%T"=="Print" (
            echo %%H\%%S>>"%PRINTERS_FILE%"
            echo       found: %%H\%%S
        )
    )
)

if not exist "%PRINTERS_FILE%" (
    echo.
    echo   No shared printers discovered.
    goto :cleanup
)

for /f %%C in ('type "%PRINTERS_FILE%" ^| find /c /v ""') do set "PRINTER_COUNT=%%C"
echo.
echo   Discovered !PRINTER_COUNT! shared printer(s).
echo.

if /I "%MODE%"=="list" (
    echo === Discovered printers ===
    type "%PRINTERS_FILE%"
    goto :cleanup
)

REM ---- 3. Install each discovered printer ----
echo [3/3] Installing printers for the current user...
set "INSTALLED=0"
set "FAILED=0"

for /f "usebackq delims=" %%P in ("%PRINTERS_FILE%") do (
    echo   Adding \\%%P ...
    rundll32 printui.dll,PrintUIEntry /in /q /n "\\%%P"
    if errorlevel 1 (
        echo       FAILED ^(error %errorlevel%^)
        set /a FAILED+=1
    ) else (
        echo       OK
        set /a INSTALLED+=1
    )
)

echo.
echo === Summary ===
echo   Installed: !INSTALLED!
echo   Failed:    !FAILED!

if defined DEFAULT_PRINTER (
    echo.
    echo Setting default printer to "%DEFAULT_PRINTER%"...
    rundll32 printui.dll,PrintUIEntry /y /n "%DEFAULT_PRINTER%"
    if errorlevel 1 (
        echo   Failed to set default. Make sure the name matches an installed printer.
    ) else (
        echo   Default printer set.
    )
)

:cleanup
if exist "%HOSTS_FILE%"    del "%HOSTS_FILE%"    >nul 2>&1
if exist "%PRINTERS_FILE%" del "%PRINTERS_FILE%" >nul 2>&1
endlocal
exit /b 0

:usage
echo.
echo Usage:
echo   add-network-printers.bat              Discover and install all shared printers.
echo   add-network-printers.bat /list        List discovered printers without installing.
echo   add-network-printers.bat /default "\\SERVER\PrinterName"
echo                                         After install, set this printer as default.
echo.
endlocal
exit /b 1
