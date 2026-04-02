"""
modules/CameraManager.py
========================
TiHAN GCS — MAVLink Camera Control Manager
Version: 1.0.0

Manages camera commands via MAVLink protocol (non-blocking).
Supports multiple camera IDs, a camera registry, and runtime switching.

Supported MAVLink commands:
  • MAV_CMD_IMAGE_START_CAPTURE  (2000)
  • MAV_CMD_IMAGE_STOP_CAPTURE   (2001)
  • MAV_CMD_VIDEO_START_CAPTURE  (2500)
  • MAV_CMD_VIDEO_STOP_CAPTURE   (2501)
  • MAV_CMD_SET_CAMERA_ZOOM      (531)
  • MAV_CMD_SET_CAMERA_FOCUS     (532)

Listens for incoming MAVLink messages:
  • CAMERA_INFORMATION
  • CAMERA_SETTINGS

Design rules:
  • NEVER modifies DroneCommander or MAVLinkThread
  • Hooks into current_msg signal from MAVLinkThread (read-only)
  • All MAVLink sends are fire-and-forget (non-blocking)
  • Rate-limited command sends to avoid flooding the bus
"""

import time
import logging
from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty, QTimer

logger = logging.getLogger(__name__)


class CameraManager(QObject):
    """
    MAVLink camera control module.
    Connect to a MAVLinkThread.current_msg signal to receive camera feedback.
    """

    # ── Signals ───────────────────────────────────────────────────────────────
    commandFeedback         = pyqtSignal(str)          # Human-readable result
    cameraRegistryChanged   = pyqtSignal()             # Camera list updated
    activeCameraChanged     = pyqtSignal(str)          # Active camera_id changed
    cameraInfoReceived      = pyqtSignal(str, 'QVariantMap')  # (camera_id, info_dict)
    imageCaptureConfirmed   = pyqtSignal(str, int)     # (camera_id, image_number)
    videoStartConfirmed     = pyqtSignal(str)           # camera_id
    videoStopConfirmed      = pyqtSignal(str)           # camera_id

    def __init__(self, drone_commander=None, parent=None):
        """
        Args:
            drone_commander: Reference to DroneCommander for MAVLink access.
                             Kept as read-only reference — not modified.
        """
        super().__init__(parent)
        self._drone_commander  = drone_commander
        self._camera_registry  = {}          # {camera_id: {name, vendor, model, ...}}
        self._active_camera_id = ""
        self._last_cmd_time    = 0.0
        self._min_cmd_interval = 0.1         # 100ms

        print("[CameraManager] ✅ Initialized")

    # ── Qt Properties ─────────────────────────────────────────────────────────

    @pyqtProperty(str, notify=activeCameraChanged)
    def activeCameraId(self) -> str:
        return self._active_camera_id

    @pyqtProperty('QVariantList', notify=cameraRegistryChanged)
    def cameraList(self) -> list:
        """List of registered camera_ids."""
        return list(self._camera_registry.keys())

    @pyqtProperty(int, notify=cameraRegistryChanged)
    def cameraCount(self) -> int:
        return len(self._camera_registry)

    # ── Public API (callable from QML) ────────────────────────────────────────

    @pyqtSlot(str)
    def setActiveCamera(self, camera_id: str):
        """Switch control context to a specific camera_id."""
        if camera_id and camera_id != self._active_camera_id:
            self._active_camera_id = camera_id
            self.activeCameraChanged.emit(camera_id)
            self.commandFeedback.emit(f"📷 Active camera → {camera_id}")
            print(f"[CameraManager] Active camera → {camera_id}")

    @pyqtSlot()
    def startImageCapture(self):
        """Start single image capture on the active camera."""
        self._send_camera_command(
            2000,       # MAV_CMD_IMAGE_START_CAPTURE
            p1=0,       # reserved
            p2=0.5,     # capture interval (seconds)
            p3=1,       # total images (1 = single)
            description="Image capture"
        )

    @pyqtSlot()
    def stopImageCapture(self):
        """Stop continuous image capture."""
        self._send_camera_command(
            2001,       # MAV_CMD_IMAGE_STOP_CAPTURE
            description="Stop image capture"
        )

    @pyqtSlot()
    def startVideoCapture(self):
        """Start video capture on the active camera."""
        self._send_camera_command(
            2500,       # MAV_CMD_VIDEO_START_CAPTURE
            p2=0,       # video stream id 0 = all
            description="Video recording start"
        )

    @pyqtSlot()
    def stopVideoCapture(self):
        """Stop video capture on the active camera."""
        self._send_camera_command(
            2501,       # MAV_CMD_VIDEO_STOP_CAPTURE
            description="Video recording stop"
        )

    @pyqtSlot(float)
    def setZoom(self, level: float):
        """
        Set camera zoom level.
        level: 1.0 (no zoom) – 10.0 (max zoom), ZOOM_TYPE_STEP = 1, absolute = 2
        """
        level = max(1.0, min(10.0, float(level)))
        self._send_camera_command(
            531,        # MAV_CMD_SET_CAMERA_ZOOM
            p1=2,       # ZOOM_TYPE_CONTINUOUS_RANGE (absolute)
            p2=level,
            description=f"Zoom {level:.1f}×"
        )

    @pyqtSlot(float)
    def setFocus(self, level: float):
        """
        Set camera focus level.
        level: 0.0 (near) – 10.0 (far), FOCUS_TYPE_CONTINUOUS = 2 (absolute)
        """
        level = max(0.0, min(10.0, float(level)))
        self._send_camera_command(
            532,        # MAV_CMD_SET_CAMERA_FOCUS
            p1=2,       # FOCUS_TYPE_RANGE (absolute)
            p2=level,
            description=f"Focus {level:.1f}"
        )

    # ── MAVLink message listener (connect to MAVLinkThread.current_msg) ───────

    @pyqtSlot(object)
    def handleMAVLinkMessage(self, msg):
        """
        Called for every incoming MAVLink message.
        Connect: mavlink_thread.current_msg.connect(camera_manager.handleMAVLinkMessage)
        """
        if msg is None:
            return

        msg_type = msg.get_type()

        if msg_type == "CAMERA_INFORMATION":
            self._handle_camera_information(msg)
        elif msg_type == "CAMERA_SETTINGS":
            self._handle_camera_settings(msg)
        elif msg_type == "CAMERA_CAPTURE_STATUS":
            self._handle_camera_capture_status(msg)

    # ── Cleanup ───────────────────────────────────────────────────────────────

    def cleanup(self):
        print("[CameraManager] 🧹 Cleanup")
        self._camera_registry.clear()
        self.cameraRegistryChanged.emit()

    # ── Internal helpers ──────────────────────────────────────────────────────

    def _get_drone(self):
        """Return the underlying MAVLink connection or None."""
        try:
            if (self._drone_commander
                    and hasattr(self._drone_commander, '_is_drone_ready')
                    and self._drone_commander._is_drone_ready()):
                return self._drone_commander._drone
        except Exception:
            pass
        return None

    def _build_camera_instance(self) -> int:
        """Convert active_camera_id to a 1-based camera instance number."""
        try:
            return int(self._active_camera_id.replace("cam", ""))
        except (ValueError, AttributeError):
            return 1

    def _send_camera_command(
        self, command_id: int,
        p1=0.0, p2=0.0, p3=0.0, p4=0.0, p5=0.0, p6=0.0, p7=0.0,
        description: str = ""
    ):
        """
        Send a MAVLink camera command (non-blocking, rate-limited).
        """
        now = time.monotonic()
        if now - self._last_cmd_time < self._min_cmd_interval:
            logger.debug(f"[CameraManager] Rate-limited: {description}")
            return

        self._last_cmd_time = now
        drone = self._get_drone()
        if drone is None:
            msg = f"⚠️ Camera command ignored — drone not connected ({description})"
            self.commandFeedback.emit(msg)
            logger.warning(f"[CameraManager] {msg}")
            return

        try:
            drone.mav.command_long_send(
                drone.target_system,
                drone.target_component,
                command_id,
                0,                    # confirmation
                float(p1), float(p2),
                float(p3), float(p4),
                float(p5), float(p6),
                float(p7)
            )
            cam_id = self._active_camera_id or "cam1"
            self.commandFeedback.emit(f"📷 {description} → {cam_id}")
            logger.info(f"[CameraManager] MAVLink cmd {command_id}: {description} cam={cam_id}")
            print(f"[CameraManager] 📡 CMD {command_id}: {description}")
        except Exception as exc:
            err = f"Camera command error ({description}): {exc}"
            self.commandFeedback.emit(f"❌ {err}")
            logger.error(f"[CameraManager] {err}")

    def _handle_camera_information(self, msg):
        """Process CAMERA_INFORMATION message — update/add camera registry entry."""
        try:
            d = msg.to_dict()
            camera_id = f"cam{d.get('camera_id', 1)}"
            info = {
                "camera_id":    camera_id,
                "vendor_name":  bytes(d.get("vendor_name", [])).decode("utf-8", errors="ignore").rstrip('\x00'),
                "model_name":   bytes(d.get("model_name", [])).decode("utf-8", errors="ignore").rstrip('\x00'),
                "firmware_version": d.get("firmware_version", 0),
                "focal_length": d.get("focal_length", 0.0),
                "sensor_size_h": d.get("sensor_size_h", 0.0),
                "sensor_size_v": d.get("sensor_size_v", 0.0),
                "resolution_h": d.get("resolution_h", 0),
                "resolution_v": d.get("resolution_v", 0),
            }
            new = camera_id not in self._camera_registry
            self._camera_registry[camera_id] = info

            if not self._active_camera_id:
                self._active_camera_id = camera_id
                self.activeCameraChanged.emit(camera_id)

            if new:
                self.cameraRegistryChanged.emit()
                print(f"[CameraManager] 📷 Camera registered: {camera_id} "
                      f"({info['vendor_name']} {info['model_name']})")

            self.cameraInfoReceived.emit(camera_id, info)

        except Exception as exc:
            logger.warning(f"[CameraManager] CAMERA_INFORMATION parse error: {exc}")

    def _handle_camera_settings(self, msg):
        """Process CAMERA_SETTINGS — update zoom/mode in registry."""
        try:
            d = msg.to_dict()
            camera_id = f"cam{d.get('camera_id', 1)}"
            if camera_id in self._camera_registry:
                self._camera_registry[camera_id].update({
                    "mode":       d.get("mode", 0),
                    "zoom_level": d.get("zoom_level", 1.0),
                    "focus_level": d.get("focus_level", 0.0),
                })
                logger.debug(f"[CameraManager] Settings updated: {camera_id}")
        except Exception as exc:
            logger.warning(f"[CameraManager] CAMERA_SETTINGS parse error: {exc}")

    def _handle_camera_capture_status(self, msg):
        """Process CAMERA_CAPTURE_STATUS — emit confirmation signals."""
        try:
            d = msg.to_dict()
            camera_id = f"cam{d.get('camera_id', 1)}"
            image_total = d.get("image_count", 0)
            video_status = d.get("video_status", 0)

            if video_status == 1:
                self.videoStartConfirmed.emit(camera_id)
            elif video_status == 0 and image_total > 0:
                self.imageCaptureConfirmed.emit(camera_id, image_total)

        except Exception as exc:
            logger.warning(f"[CameraManager] CAMERA_CAPTURE_STATUS parse error: {exc}")
