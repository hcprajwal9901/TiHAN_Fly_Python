# TIHANFly — Camera, Gimbal & Video Streaming Integration

## Overview

This document describes the new modules integrated into TIHANFly for Camera Control, Gimbal Control, Multi-Camera Support, and GPU-accelerated RTSP Streaming.

**All changes are strictly additive.** No existing modules (DroneCommander, MAVLinkThread, DroneModel, CameraModel, etc.) were modified.

---

## Architecture Summary

```
main.py (additive registration only)
├── modules/CameraManager.py         → MAVLink camera commands
├── modules/GimbalManager.py         → MAVLink gimbal commands
├── modules/VideoStreamManager.py    → Multi-camera GStreamer orchestrator
│   ├── modules/GStreamerPipelineFactory.py  → GPU auto-detection + pipeline builder
│   └── modules/VideoWorkerThread.py         → Dedicated QThread per stream
└── App/qml/
    ├── VideoPanel.qml               → Live frame display
    ├── CameraControlPanel.qml       → Camera UI
    └── GimbalControlPanel.qml       → Gimbal UI
```

### Thread Isolation

| Component              | Thread                    |
|------------------------|---------------------------|
| CameraManager          | Main thread (Qt slot)     |
| GimbalManager          | Main thread (Qt slot)     |
| VideoWorkerThread      | Dedicated QThread per cam |
| MAVLink routing        | MAVLinkThread (existing)  |
| QML rendering          | Main thread               |

---

## New Python Modules

### GStreamerPipelineFactory
**File:** `modules/GStreamerPipelineFactory.py`

Auto-detects GPU hardware and builds optimal pipeline strings.

| Profile           | Decoder         | Detection           |
|-------------------|-----------------|---------------------|
| `nvidia_desktop`  | `nvh264dec`     | gst-inspect         |
| `nvidia_jetson`   | `nvv4l2decoder` | gst-inspect         |
| `intel_vaapi`     | `vaapih264dec`  | gst-inspect         |
| `software`        | `decodebin`     | Fallback            |

```python
factory = GStreamerPipelineFactory()
pipeline = factory.build_pipeline("rtsp://host/stream", username, password)
```

### VideoWorkerThread
**File:** `modules/VideoWorkerThread.py`

- Owns one GStreamer pipeline per instance
- Runs in a dedicated `QThread`
- Converts GStreamer buffers to `QImage` and emits via `frameReady(QImage)`
- Auto-reconnect with 2s countdown on any error/EOS
- Max 2 frame buffers, old frames dropped

### VideoStreamManager *(GStreamer edition)*
**File:** `modules/VideoStreamManager.py`

- Manages up to **3 concurrent** streams
- QML Context Property: `videoStreamManager`

**Key QML Slots:**

```qml
videoStreamManager.startStream("cam1", "rtsp://host/path")
videoStreamManager.startStreamWithAuth("cam1", "rtsp://...", "user", "pass")
videoStreamManager.stopStream("cam1")
videoStreamManager.switchActiveCamera("cam2")
```

**Key Signals:**

| Signal                              | Description              |
|-------------------------------------|--------------------------|
| `frameReady(camera_id, QImage)`     | New decoded video frame  |
| `streamStarted(camera_id)`          | Pipeline active          |
| `streamStopped(camera_id)`          | Pipeline stopped         |
| `streamError(camera_id, msg)`       | Error with auto-reconnect|
| `connectionStatusChanged(id, msg)`  | Status text update       |

### CameraManager
**File:** `modules/CameraManager.py`

- QML Context Property: `cameraManager`
- Hooks into `MAVLinkThread.current_msg` (read-only, non-destructive)
- Camera registry auto-populated from `CAMERA_INFORMATION` MAVLink messages

**Key QML Slots:**

```qml
cameraManager.setActiveCamera("cam1")
cameraManager.startImageCapture()
cameraManager.stopImageCapture()
cameraManager.startVideoCapture()
cameraManager.stopVideoCapture()
cameraManager.setZoom(5.0)     // 1.0–10.0
cameraManager.setFocus(3.0)    // 0.0–10.0
```

**MAVLink Commands Sent:**

| Command                        | ID   |
|-------------------------------|------|
| MAV_CMD_IMAGE_START_CAPTURE   | 2000 |
| MAV_CMD_IMAGE_STOP_CAPTURE    | 2001 |
| MAV_CMD_VIDEO_START_CAPTURE   | 2500 |
| MAV_CMD_VIDEO_STOP_CAPTURE    | 2501 |
| MAV_CMD_SET_CAMERA_ZOOM       | 531  |
| MAV_CMD_SET_CAMERA_FOCUS      | 532  |

**MAVLink Messages Listened:**

- `CAMERA_INFORMATION` → Populates camera registry
- `CAMERA_SETTINGS` → Updates zoom/mode
- `CAMERA_CAPTURE_STATUS` → Confirms capture start/stop

### GimbalManager
**File:** `modules/GimbalManager.py`

- QML Context Property: `gimbalManager`
- Rate-limited: **100ms** between consecutive commands
- Supports smooth slider drag via internal pending-command queue

**Key QML Slots:**

```qml
gimbalManager.setPitchYaw(-45.0, 30.0)
gimbalManager.setPitch(-90.0)           // Nadir
gimbalManager.setYaw(180.0)
gimbalManager.setMode("follow")         // "lock" | "follow" | "roi"
gimbalManager.setROI(lat, lon, alt)
gimbalManager.centerGimbal()
```

**MAVLink Commands Sent:**

| Command                              | ID   |
|--------------------------------------|------|
| MAV_CMD_DO_GIMBAL_MANAGER_PITCHYAW  | 1000 |
| MAV_CMD_DO_SET_ROI_LOCATION         | 195  |

**MAVLink Messages Listened:**

- `GIMBAL_MANAGER_STATUS` → Status flags
- `GIMBAL_DEVICE_ATTITUDE_STATUS` → Live pitch/yaw from quaternion

---

## New QML Components

### VideoPanel.qml
Displays live RTSP frames. Binds to `videoStreamManager`.

**Features:**
- Frame display with `PreserveAspectFit`
- "NO SIGNAL" overlay with status message
- HUD top bar: resolution, FPS, channel label
- Blinking LIVE indicator when connected
- Status bar at bottom

### CameraControlPanel.qml
**Features:**
- Camera selector `ComboBox` (populated from `cameraManager.cameraList`)
- RTSP URL input + Connect/Disconnect button
- Snapshot button → `cameraManager.startImageCapture()`
- Record toggle → `cameraManager.startVideoCapture()` / `stopVideoCapture()`
- Zoom Slider (1.0–10.0×) → `cameraManager.setZoom()`
- Focus Slider (0–10) → `cameraManager.setFocus()`

### GimbalControlPanel.qml
**Features:**
- Mode selector: FOLLOW / LOCK / ROI
- `pitch_slider` (−90° to +45°) → `gimbalManager.setPitch()`
- `yaw_slider` (−180° to +180°) → `gimbalManager.setYaw()`
- CENTER button → `gimbalManager.centerGimbal()`
- NADIR button → `gimbalManager.setPitchYaw(-90, 0)`

---

## Integration in main.py

Changes to `main.py` are **purely additive**:

1. Try-import block (lines ~99–112): imports new modules with graceful fallback
2. Initialization block (lines ~680–700): instantiates 3 new managers after RTSP provider
3. Signal routing (lines ~830–865): connects `MAVLinkThread.current_msg` to camera/gimbal handlers; deferred until drone connects
4. QML context (lines ~865–868): registers `cameraManager`, `gimbalManager`, `videoStreamManager`

---

## Using the New Components in QML

Drop these into any QML layout:

```qml
// In any .qml file
VideoPanel {
    width: 640; height: 480
}

CameraControlPanel {
    width: 360; height: 420
}

GimbalControlPanel {
    width: 320; height: 380
}
```

They automatically bind to the global `videoStreamManager`, `cameraManager`, and `gimbalManager` context properties.

---

## Security

- RTSP authentication via `startStreamWithAuth(id, url, username, password)` 
- Credentials passed directly to GStreamer rtspsrc (not stored in code)
- For persistent secure storage, use the existing `tihanfly_secure.db` SQLCipher database

---

## Testing Checklist

| Test | Method |
|------|--------|
| Camera capture via MAVLink | Connect to ArduPilot SITL, call `cameraManager.startVideoCapture()`, verify MAVLink CMD 2500 in logs |
| Gimbal pitch/yaw | Drag sliders, verify MAVLink CMD 1000 in logs at ≤10Hz |
| Multi-camera switching | Start 3 streams, call `switchActiveCamera()` |
| GPU detection | Check startup log for hardware profile |
| Auto-reconnect | Kill RTSP source; verify reconnect within 2s |
| Network drop | Disable network adapter; verify no crash, reconnect on restore |
| 30-min stress | Run stream continuously, check CPU and memory growth |
| UI responsiveness | Perform gimbal drag while stream active; HUD must not stutter |
