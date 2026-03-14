"""
Video Analyzer for iPhone (Pyto IDE)
Analyzes videos for content editing: scene changes, motion, faces, audio spikes.
Optional AI mode: describe what you want to find and Claude Vision will detect it.

Set your video_path in CONFIG below, then tap Run.
To use AI mode: set your api_key and describe what to find in ai_prompt.
"""

import cv2
import numpy as np
import json
import os
import time
import wave
import struct
import base64
import urllib.request
import urllib.error

# ============================================================================
# CONFIGURATION — Edit these values before running
# ============================================================================

CONFIG = {
    # --- Input ---
    "video_path": "/path/to/your/video.mov",   # SET THIS to your video file path
    "audio_path": "",                           # Optional: path to WAV file for audio analysis
    "output_path": "",                          # Optional: path for JSON output (empty = console only)

    # --- AI-Powered Detection (requires internet) ---
    "ai_enabled": False,        # Set to True to enable prompt-based AI detection
    "api_key": "",              # Your Anthropic API key (starts with "sk-ant-")
    "ai_prompt": "",            # Describe what to find, e.g. "someone raising their hand"
    "ai_frame_interval": 30,    # Check every Nth analyzed frame with AI (controls API cost)
    "ai_resize_width": 512,     # Resize frames sent to API (smaller = faster + cheaper)

    # --- Performance ---
    "frame_skip": 5,            # Analyze every Nth frame (higher = faster, less precise)
    "resize_width": 480,        # Downscale frames to this width (0 = no resize)

    # --- Scene Change Detection ---
    "scene_threshold": 0.45,    # Histogram correlation below this = scene change (0-1, lower = stricter)

    # --- Motion Detection ---
    "motion_threshold": 8.0,    # Optical flow magnitude above this = high motion
    "motion_method": "flow",    # "flow" (accurate) or "absdiff" (faster)

    # --- Face Detection ---
    "face_enabled": True,
    "face_min_size": (60, 60),
    "face_scale_factor": 1.2,
    "face_min_neighbors": 5,
    "face_cooldown_sec": 2.0,   # Suppress repeated face detections within N seconds

    # --- Audio Spike Detection ---
    "audio_spike_std_mult": 3.0,    # Spike = amplitude > mean + N * std_dev
    "audio_window_ms": 50,          # RMS window size in milliseconds
    "audio_chunk_sec": 30,          # Process audio in N-second chunks (saves memory)

    # --- Output ---
    "merge_window_sec": 1.0,    # Merge same-type events within N seconds
    "progress_interval": 100,   # Print progress every N analyzed frames
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def resize_frame(frame, max_width):
    if max_width <= 0:
        return frame
    h, w = frame.shape[:2]
    if w <= max_width:
        return frame
    scale = max_width / w
    return cv2.resize(frame, (max_width, int(h * scale)), interpolation=cv2.INTER_AREA)


def format_timestamp(seconds):
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = seconds % 60
    return f"{h:02d}:{m:02d}:{s:06.3f}"


def merge_nearby_events(events, window_sec):
    if not events:
        return events
    events.sort(key=lambda e: (e["type"], e["timestamp_sec"]))
    merged = []
    current = None
    for event in events:
        if (current is not None
                and event["type"] == current["type"]
                and event["timestamp_sec"] - current["timestamp_sec"] <= window_sec):
            # Keep the event with the stronger signal
            continue
        else:
            if current is not None:
                merged.append(current)
            current = event
    if current is not None:
        merged.append(current)
    merged.sort(key=lambda e: e["timestamp_sec"])
    return merged


def print_progress(analyzed, total, start_time):
    elapsed = time.time() - start_time
    pct = (analyzed / total) * 100 if total > 0 else 0
    if analyzed > 0 and elapsed > 0:
        eta = (elapsed / analyzed) * (total - analyzed)
        print(f"  Progress: {pct:5.1f}% ({analyzed}/{total} frames) | "
              f"Elapsed: {format_timestamp(elapsed)} | ETA: {format_timestamp(eta)}")
    else:
        print(f"  Progress: {pct:5.1f}% ({analyzed}/{total} frames)")


# ============================================================================
# SCENE CHANGE DETECTOR
# ============================================================================

class SceneChangeDetector:
    def __init__(self, config):
        self.threshold = config["scene_threshold"]
        self.prev_hist = None
        self.events = []

    def process_frame(self, frame, frame_number, fps):
        hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
        hist = cv2.calcHist([hsv], [0, 1], None, [50, 60], [0, 180, 0, 256])
        cv2.normalize(hist, hist)

        if self.prev_hist is not None:
            corr = cv2.compareHist(self.prev_hist, hist, cv2.HISTCMP_CORREL)
            if corr < self.threshold:
                ts = frame_number / fps
                self.events.append({
                    "timestamp_sec": ts,
                    "timestamp": format_timestamp(ts),
                    "type": "SCENE_CHANGE",
                    "details": {"histogram_corr": round(corr, 3)}
                })

        self.prev_hist = hist

    def get_events(self):
        return self.events


# ============================================================================
# MOTION DETECTOR
# ============================================================================

class MotionDetector:
    def __init__(self, config):
        self.threshold = config["motion_threshold"]
        self.method = config["motion_method"]
        self.prev_gray = None
        self.events = []

    def process_frame(self, frame, frame_number, fps):
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        if self.prev_gray is not None:
            if self.method == "flow":
                flow = cv2.calcOpticalFlowFarneback(
                    self.prev_gray, gray, None,
                    pyr_scale=0.5, levels=3, winsize=15,
                    iterations=3, poly_n=5, poly_sigma=1.2, flags=0
                )
                magnitude = np.sqrt(flow[..., 0] ** 2 + flow[..., 1] ** 2)
                mean_mag = float(np.mean(magnitude))
            else:
                diff = cv2.absdiff(self.prev_gray, gray)
                mean_mag = float(np.mean(diff))

            if mean_mag > self.threshold:
                ts = frame_number / fps
                self.events.append({
                    "timestamp_sec": ts,
                    "timestamp": format_timestamp(ts),
                    "type": "HIGH_MOTION",
                    "details": {"magnitude": round(mean_mag, 2)}
                })

        self.prev_gray = gray

    def get_events(self):
        return self.events


# ============================================================================
# FACE DETECTOR
# ============================================================================

class FaceDetector:
    def __init__(self, config):
        self.enabled = config["face_enabled"]
        self.min_size = config["face_min_size"]
        self.scale_factor = config["face_scale_factor"]
        self.min_neighbors = config["face_min_neighbors"]
        self.cooldown = config["face_cooldown_sec"]
        self.last_detection_time = -999.0
        self.events = []
        self.cascade = None

        if self.enabled:
            cascade_path = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"
            if os.path.exists(cascade_path):
                self.cascade = cv2.CascadeClassifier(cascade_path)
            else:
                print(f"WARNING: Haar cascade not found at {cascade_path}")
                print("         Face detection will be disabled.")
                self.enabled = False

    def process_frame(self, frame, frame_number, fps):
        if not self.enabled or self.cascade is None:
            return

        ts = frame_number / fps
        if ts - self.last_detection_time < self.cooldown:
            return

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.equalizeHist(gray)

        faces = self.cascade.detectMultiScale(
            gray,
            scaleFactor=self.scale_factor,
            minNeighbors=self.min_neighbors,
            minSize=self.min_size
        )

        if len(faces) > 0:
            self.last_detection_time = ts
            self.events.append({
                "timestamp_sec": ts,
                "timestamp": format_timestamp(ts),
                "type": "FACE_DETECTED",
                "details": {"count": len(faces)}
            })

    def get_events(self):
        return self.events


# ============================================================================
# AUDIO SPIKE DETECTOR
# ============================================================================

class AudioSpikeDetector:
    def __init__(self, config):
        self.audio_path = config["audio_path"]
        self.spike_mult = config["audio_spike_std_mult"]
        self.window_ms = config["audio_window_ms"]
        self.chunk_sec = config["audio_chunk_sec"]
        self.events = []

    def analyze(self):
        if not self.audio_path or not os.path.exists(self.audio_path):
            return

        print("Analyzing audio...")
        try:
            wf = wave.open(self.audio_path, "rb")
        except wave.Error as e:
            print(f"WARNING: Could not open audio file: {e}")
            return

        n_channels = wf.getnchannels()
        sample_width = wf.getsampwidth()
        framerate = wf.getframerate()
        total_frames = wf.getnframes()

        if sample_width not in (1, 2, 4):
            print(f"WARNING: Unsupported sample width {sample_width} bytes. Skipping audio.")
            wf.close()
            return

        fmt_map = {1: "b", 2: "h", 4: "i"}
        sample_fmt = fmt_map[sample_width]
        max_val = float(2 ** (sample_width * 8 - 1))

        window_samples = int(framerate * self.window_ms / 1000.0)
        chunk_frames = int(framerate * self.chunk_sec)

        all_rms = []
        all_times = []

        frames_read = 0
        while frames_read < total_frames:
            read_count = min(chunk_frames, total_frames - frames_read)
            raw = wf.readframes(read_count)
            n_samples = read_count * n_channels
            samples = struct.unpack(f"<{n_samples}{sample_fmt}", raw)
            arr = np.array(samples, dtype=np.float32) / max_val

            if n_channels > 1:
                arr = arr.reshape(-1, n_channels).mean(axis=1)

            # Compute RMS in sliding windows
            for i in range(0, len(arr) - window_samples, window_samples):
                window = arr[i:i + window_samples]
                rms = float(np.sqrt(np.mean(window ** 2)))
                t = (frames_read + i) / framerate
                all_rms.append(rms)
                all_times.append(t)

            frames_read += read_count

        wf.close()

        if not all_rms:
            return

        rms_arr = np.array(all_rms)
        mean_rms = float(np.mean(rms_arr))
        std_rms = float(np.std(rms_arr))
        threshold = mean_rms + self.spike_mult * std_rms

        for i, rms in enumerate(all_rms):
            if rms > threshold:
                self.events.append({
                    "timestamp_sec": all_times[i],
                    "timestamp": format_timestamp(all_times[i]),
                    "type": "AUDIO_SPIKE",
                    "details": {"rms": round(rms, 3), "threshold": round(threshold, 3)}
                })

        print(f"  Audio: found {len(self.events)} spike(s) (threshold RMS: {threshold:.3f})")

    def get_events(self):
        return self.events


# ============================================================================
# AI PROMPT DETECTOR (Claude Vision API)
# ============================================================================

class PromptDetector:
    """Sends sampled frames to Claude Vision to detect user-described events."""

    API_URL = "https://api.anthropic.com/v1/messages"

    def __init__(self, config):
        self.enabled = config.get("ai_enabled", False)
        self.api_key = config.get("api_key", "")
        self.prompt = config.get("ai_prompt", "")
        self.frame_interval = config.get("ai_frame_interval", 30)
        self.resize_width = config.get("ai_resize_width", 512)
        self.events = []
        self._frame_counter = 0

        if self.enabled and not self.api_key:
            print("WARNING: ai_enabled is True but no api_key provided. AI detection disabled.")
            self.enabled = False
        if self.enabled and not self.prompt:
            print("WARNING: ai_enabled is True but no ai_prompt provided. AI detection disabled.")
            self.enabled = False
        if self.enabled:
            print(f"AI Detection: looking for \"{self.prompt}\"")
            print(f"  Checking every {self.frame_interval}th analyzed frame via Claude Vision")

    def _frame_to_base64(self, frame):
        resized = resize_frame(frame, self.resize_width)
        _, buf = cv2.imencode(".jpg", resized, [cv2.IMWRITE_JPEG_QUALITY, 70])
        return base64.b64encode(buf).decode("utf-8")

    def _call_api(self, image_b64):
        system_msg = (
            "You are analyzing a single video frame. The user wants to know if a "
            "specific thing is happening in this frame. Respond with ONLY a JSON object: "
            '{"detected": true/false, "confidence": "high"/"medium"/"low", '
            '"description": "brief description of what you see"}. '
            "No other text."
        )
        user_msg = (
            f"Is the following happening in this frame: \"{self.prompt}\"?\n"
            "Look carefully at the image and respond with the JSON format specified."
        )

        body = json.dumps({
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 150,
            "system": system_msg,
            "messages": [{
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": image_b64
                        }
                    },
                    {
                        "type": "text",
                        "text": user_msg
                    }
                ]
            }]
        }).encode("utf-8")

        req = urllib.request.Request(
            self.API_URL,
            data=body,
            headers={
                "Content-Type": "application/json",
                "x-api-key": self.api_key,
                "anthropic-version": "2023-06-01"
            },
            method="POST"
        )

        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                result = json.loads(resp.read().decode("utf-8"))
                text = result["content"][0]["text"]
                # Parse JSON from response
                text = text.strip()
                if text.startswith("```"):
                    text = text.split("\n", 1)[1].rsplit("```", 1)[0].strip()
                return json.loads(text)
        except urllib.error.HTTPError as e:
            error_body = e.read().decode("utf-8", errors="replace")
            print(f"  AI API error ({e.code}): {error_body[:200]}")
            return None
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"  AI API connection error: {e}")
            return None
        except (json.JSONDecodeError, KeyError, IndexError):
            return None

    def process_frame(self, frame, frame_number, fps):
        if not self.enabled:
            return

        self._frame_counter += 1
        if self._frame_counter % self.frame_interval != 0:
            return

        ts = frame_number / fps
        image_b64 = self._frame_to_base64(frame)
        result = self._call_api(image_b64)

        if result and result.get("detected"):
            confidence = result.get("confidence", "unknown")
            description = result.get("description", "")
            self.events.append({
                "timestamp_sec": ts,
                "timestamp": format_timestamp(ts),
                "type": "AI_DETECTED",
                "details": {
                    "prompt": self.prompt,
                    "confidence": confidence,
                    "description": description
                }
            })
            print(f"  ** AI match at {format_timestamp(ts)}: {description} [{confidence}]")

    def get_events(self):
        return self.events


# ============================================================================
# MAIN ANALYSIS ENGINE
# ============================================================================

def analyze_video(config):
    video_path = config["video_path"]

    # Validate input
    if not os.path.exists(video_path):
        print(f"ERROR: Video file not found: {video_path}")
        print("Tip: In Pyto, tap the file icon to browse and copy the file path.")
        return

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"ERROR: Could not open video: {video_path}")
        print("Tip: Try converting the video to MP4 (H.264) format.")
        return

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    duration = total_frames / fps

    frame_skip = config["frame_skip"]
    frames_to_analyze = total_frames // frame_skip

    print("=" * 50)
    print("VIDEO ANALYZER")
    print("=" * 50)
    print(f"File:       {os.path.basename(video_path)}")
    print(f"Duration:   {format_timestamp(duration)}")
    print(f"Resolution: {width}x{height} @ {fps:.1f}fps")
    print(f"Analyzing:  every {frame_skip}th frame ({frames_to_analyze} of {total_frames})")
    print("-" * 50)

    # Initialize detectors
    scene_det = SceneChangeDetector(config)
    motion_det = MotionDetector(config)
    face_det = FaceDetector(config)
    audio_det = AudioSpikeDetector(config)
    prompt_det = PromptDetector(config)

    # Run audio analysis first (separate pass)
    audio_det.analyze()

    # Frame analysis loop
    print("Analyzing video frames...")
    start_time = time.time()
    analyzed_count = 0

    try:
        for frame_idx in range(0, total_frames, frame_skip):
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            ret, frame = cap.read()
            if not ret:
                break

            frame = resize_frame(frame, config["resize_width"])

            scene_det.process_frame(frame, frame_idx, fps)
            motion_det.process_frame(frame, frame_idx, fps)
            face_det.process_frame(frame, frame_idx, fps)
            prompt_det.process_frame(frame, frame_idx, fps)

            analyzed_count += 1
            if analyzed_count % config["progress_interval"] == 0:
                print_progress(analyzed_count, frames_to_analyze, start_time)

    except KeyboardInterrupt:
        print("\nAnalysis interrupted. Showing partial results...")
    except MemoryError:
        print("\nWARNING: Low memory. Showing partial results...")

    cap.release()
    elapsed = time.time() - start_time

    # Collect and merge events
    all_events = (
        scene_det.get_events()
        + motion_det.get_events()
        + face_det.get_events()
        + audio_det.get_events()
        + prompt_det.get_events()
    )
    all_events = merge_nearby_events(all_events, config["merge_window_sec"])

    # Count by type
    counts = {}
    for e in all_events:
        counts[e["type"]] = counts.get(e["type"], 0) + 1

    # Print results
    print()
    print("=" * 50)
    print(f"RESULTS — {len(all_events)} events found")
    print("=" * 50)
    print(f"Analysis time: {format_timestamp(elapsed)}")
    print(f"Frames analyzed: {analyzed_count}")
    print()

    if all_events:
        for event in all_events:
            details_str = ", ".join(f"{k}={v}" for k, v in event["details"].items())
            print(f"[{event['timestamp']}] {event['type']:15s} | {details_str}")

        print()
        print("--- SUMMARY ---")
        for event_type, count in sorted(counts.items()):
            print(f"  {event_type}: {count}")
    else:
        print("No events detected. Try adjusting thresholds in CONFIG.")

    # Optional JSON output
    output_path = config.get("output_path", "")
    if output_path:
        output_data = {
            "video_info": {
                "path": video_path,
                "duration_sec": round(duration, 3),
                "fps": fps,
                "resolution": [width, height]
            },
            "config_used": {k: v for k, v in config.items()
                           if k not in ("video_path", "audio_path", "output_path")},
            "events": all_events,
            "summary": counts
        }
        with open(output_path, "w") as f:
            json.dump(output_data, f, indent=2)
        print(f"\nResults saved to: {output_path}")

    print()


# ============================================================================
# ENTRY POINT
# ============================================================================

if __name__ == "__main__":
    analyze_video(CONFIG)
