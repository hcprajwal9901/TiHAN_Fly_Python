"""
CameraModel — Backend for the Camera System panel in MapViewQML.qml

Handles:
  • RTSP stream connection state (QML MediaPlayer uses the URL directly)
  • Recording flag (pipeline to GStreamer if available, else flag-only)
  • Snapshot trigger (via snapshotReady signal → QML grabs the window)
  • Zoom level (local bookkeeping + MAVLink if drone connected)
  • Active camera source switching (cam1 / cam2 / thermal)
"""

import os
import time
import threading
from datetime import datetime
from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty, QStandardPaths


class CameraModel(QObject):

    # ── Signals ──────────────────────────────────────────────────────────────
    isStreamingChanged  = pyqtSignal()
    isRecordingChanged  = pyqtSignal()
    streamUrlChanged    = pyqtSignal()
    zoomChanged         = pyqtSignal()
    cameraChanged       = pyqtSignal()
    statusMessage       = pyqtSignal(str)          # one-line feedback to QML
    snapshotReady       = pyqtSignal(str)          # emitted with saved file path

    def __init__(self, drone_commander=None, parent=None):
        super().__init__(parent)
        self._drone_commander = drone_commander

        self._rtsp_url       = ""
        self._is_streaming   = False
        self._is_recording   = False
        self._zoom_level     = 1.0        # 1.0 – 10.0
        self._active_cam_id  = "cam1"     # "cam1" | "cam2" | "thermal"

        # GStreamer recording pipeline (optional)
        self._gst_process    = None

        # Snapshot save directory
        self._snapshot_dir = QStandardPaths.writableLocation(
            QStandardPaths.PicturesLocation)
        if not self._snapshot_dir:
            self._snapshot_dir = os.path.expanduser("~/Pictures")
        os.makedirs(self._snapshot_dir, exist_ok=True)

        print("[CameraModel] ✅ Initialized")
        print(f"[CameraModel]   Snapshot dir : {self._snapshot_dir}")

    # ── Read-only properties ──────────────────────────────────────────────────

    @pyqtProperty(bool, notify=isStreamingChanged)
    def isStreaming(self):
        return self._is_streaming

    @pyqtProperty(bool, notify=isRecordingChanged)
    def isRecording(self):
        return self._is_recording

    @pyqtProperty(str, notify=streamUrlChanged)
    def rtspUrl(self):
        return self._rtsp_url

    @pyqtProperty(float, notify=zoomChanged)
    def zoomLevel(self):
        return self._zoom_level

    @pyqtProperty(str, notify=cameraChanged)
    def activeCameraId(self):
        return self._active_cam_id

    # ── Stream control ────────────────────────────────────────────────────────

    @pyqtSlot(str)
    def connectStream(self, url: str):
        """Store the RTSP URL and set streaming=True so QML MediaPlayer loads it."""
        url = url.strip()
        if not url:
            self.statusMessage.emit("⚠️ Please enter a stream URL")
            return

        print(f"[CameraModel] 🎬 Connecting to: {url}")
        self._rtsp_url     = url
        self._is_streaming = True
        self.streamUrlChanged.emit()
        self.isStreamingChanged.emit()
        self.statusMessage.emit(f"✅ Stream connected: {url}")

    @pyqtSlot()
    def disconnectStream(self):
        """Stop streaming and clear URL."""
        print("[CameraModel] ⬛ Disconnecting stream")
        if self._is_recording:
            self.stopRecording()
        self._is_streaming = False
        self._rtsp_url     = ""
        self.isStreamingChanged.emit()
        self.streamUrlChanged.emit()
        self.statusMessage.emit("⬛ Stream disconnected")

    # ── Snapshot ──────────────────────────────────────────────────────────────

    @pyqtSlot()
    def takeSnapshot(self):
        """
        Signal QML to grab the video frame.
        QML should connect to snapshotReady and call VideoOutput.grabToImage().
        We emit snapshotReady with a target file path.
        """
        ts   = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = os.path.join(self._snapshot_dir, f"tfly_snap_{ts}.jpg")
        print(f"[CameraModel] 📸 Snapshot requested → {path}")
        self.statusMessage.emit(f"📸 Snapshot saved: tfly_snap_{ts}.jpg")
        # Emit path so QML can call VideoOutput.grabToImage(path)
        self.snapshotReady.emit(path)

    # ── Recording ─────────────────────────────────────────────────────────────

    @pyqtSlot()
    def startRecording(self):
        if self._is_recording:
            return
        if not self._is_streaming:
            self.statusMessage.emit("⚠️ Connect a stream first")
            return

        print("[CameraModel] ⏺ Starting recording...")
        self._is_recording = True
        self.isRecordingChanged.emit()

        # Try GStreamer pipeline in background thread
        threading.Thread(target=self._gst_record_pipeline, daemon=True).start()

    @pyqtSlot()
    def stopRecording(self):
        if not self._is_recording:
            return
        print("[CameraModel] ⏹ Stopping recording...")
        self._is_recording = False
        self.isRecordingChanged.emit()

        if self._gst_process:
            try:
                self._gst_process.terminate()
            except Exception:
                pass
            self._gst_process = None

        self.statusMessage.emit("⏹ Recording stopped")

    def _gst_record_pipeline(self):
        """Attempt to record via GStreamer (best-effort, falls back gracefully)."""
        try:
            import subprocess
            ts   = datetime.now().strftime("%Y%m%d_%H%M%S")
            path = os.path.join(self._snapshot_dir, f"tfly_rec_{ts}.mp4")

            cmd = [
                "gst-launch-1.0",
                "rtspsrc", f"location={self._rtsp_url}", "latency=100", "!",
                "rtph264depay", "!", "h264parse", "!",
                "mp4mux", "!",
                "filesink", f"location={path}"
            ]
            print(f"[CameraModel] 🎥 GStreamer: {' '.join(cmd)}")
            self._gst_process = subprocess.Popen(cmd,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.statusMessage.emit(f"⏺ Recording → {os.path.basename(path)}")

            # Wait until stopped
            while self._is_recording:
                time.sleep(0.5)
            self._gst_process.terminate()

        except FileNotFoundError:
            # gst-launch-1.0 not installed — flag-only mode is fine
            print("[CameraModel] ⚠️ GStreamer not found — recording flag set only")
            self.statusMessage.emit("⏺ Recording (GStreamer not installed — flag only)")
        except Exception as e:
            print(f"[CameraModel] ⚠️ Recording error: {e}")

    # ── Zoom ──────────────────────────────────────────────────────────────────

    @pyqtSlot()
    def zoomIn(self):
        if self._zoom_level < 10.0:
            self._zoom_level = min(10.0, round(self._zoom_level + 1.0, 1))
            self.zoomChanged.emit()
            self._send_zoom_mavlink()
            self.statusMessage.emit(f"🔍 Zoom: {self._zoom_level:.0f}×")
            print(f"[CameraModel] 🔍 Zoom In  → {self._zoom_level}×")

    @pyqtSlot()
    def zoomOut(self):
        if self._zoom_level > 1.0:
            self._zoom_level = max(1.0, round(self._zoom_level - 1.0, 1))
            self.zoomChanged.emit()
            self._send_zoom_mavlink()
            self.statusMessage.emit(f"🔍 Zoom: {self._zoom_level:.0f}×")
            print(f"[CameraModel] 🔎 Zoom Out → {self._zoom_level}×")

    def _send_zoom_mavlink(self):
        """Send MAV_CMD_SET_CAMERA_ZOOM if drone is connected."""
        try:
            if (self._drone_commander
                    and hasattr(self._drone_commander, '_is_drone_ready')
                    and self._drone_commander._is_drone_ready()):
                drone = self._drone_commander._drone
                from pymavlink import mavutil
                drone.mav.command_long_send(
                    drone.target_system,
                    drone.target_component,
                    mavutil.mavlink.MAV_CMD_SET_CAMERA_ZOOM,  # 531
                    0,
                    2,                    # ZOOM_TYPE_STEP = 1, CONTINUOUS = 2 (absolute)
                    self._zoom_level,     # zoom value (1–10)
                    0, 0, 0, 0, 0)
                print(f"[CameraModel] 📡 MAVLink zoom sent: {self._zoom_level}×")
        except Exception as e:
            print(f"[CameraModel] ⚠️ Zoom MAVLink error (non-fatal): {e}")

    # ── Camera source switching ───────────────────────────────────────────────

    @pyqtSlot(str)
    def switchCamera(self, cam_id: str):
        """
        Switch active camera. cam_id: 'cam1', 'cam2', 'thermal'.
        Sends MAV_CMD_SET_CAMERA_SOURCE (command 2004) if drone connected.
        """
        if cam_id not in ("cam1", "cam2", "thermal"):
            print(f"[CameraModel] ⚠️ Unknown camera id: {cam_id}")
            return

        self._active_cam_id = cam_id
        self.cameraChanged.emit()

        # Human-readable label
        labels = {"cam1": "Camera 1 (RGB)", "cam2": "Camera 2 (RGB)", "thermal": "Thermal IR"}
        label = labels[cam_id]
        self.statusMessage.emit(f"📷 Switched to {label}")
        print(f"[CameraModel] 📷 Camera switched → {label}")

        self._send_camera_source_mavlink(cam_id)

    def _send_camera_source_mavlink(self, cam_id: str):
        """Send camera source change via MAVLink (best-effort)."""
        # Map to camera instance numbers expected by ArduPilot
        cam_instance = {"cam1": 1, "cam2": 2, "thermal": 3}
        instance = cam_instance.get(cam_id, 1)

        try:
            if (self._drone_commander
                    and hasattr(self._drone_commander, '_is_drone_ready')
                    and self._drone_commander._is_drone_ready()):
                drone = self._drone_commander._drone
                from pymavlink import mavutil
                # MAV_CMD_SET_CAMERA_SOURCE = 2004 (ArduPilot extension)
                drone.mav.command_long_send(
                    drone.target_system,
                    drone.target_component,
                    2004,        # MAV_CMD_SET_CAMERA_SOURCE
                    0,
                    instance,    # param1: camera instance (1-based)
                    0, 0, 0, 0, 0, 0)
                print(f"[CameraModel] 📡 MAVLink camera source sent: instance={instance}")
        except Exception as e:
            print(f"[CameraModel] ⚠️ Camera source MAVLink error (non-fatal): {e}")

    # ── Channel label for HUD ─────────────────────────────────────────────────

    @pyqtProperty(str, notify=cameraChanged)
    def channelLabel(self):
        """Short label displayed in the video HUD top bar."""
        return {"cam1": "CH 1 · RGB", "cam2": "CH 2 · RGB", "thermal": "CH 3 · IR"}.get(
            self._active_cam_id, "CH 1 · RGB")

    @pyqtProperty(str, notify=zoomChanged)
    def zoomLabel(self):
        """Zoom label for HUD bottom bar, e.g. '3.0×'."""
        return f"{self._zoom_level:.0f}×"

    # ── Cleanup ───────────────────────────────────────────────────────────────

    def cleanup(self):
        print("[CameraModel] 🧹 Cleanup...")
        if self._is_recording:
            self.stopRecording()
        if self._is_streaming:
            self.disconnectStream()
        print("[CameraModel] ✅ Cleanup complete")
