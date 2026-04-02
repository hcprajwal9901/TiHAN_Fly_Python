"""
modules/GimbalManager.py
========================
TiHAN GCS — MAVLink Gimbal Control Manager
Version: 1.0.0

Manages gimbal pitch/yaw control and mode switching via MAVLink.
Rate-limited command dispatch (100ms min interval between commands)
to ensure smooth, non-flooding motion.

Supported MAVLink commands:
  • MAV_CMD_DO_GIMBAL_MANAGER_PITCHYAW  (1000)
  • MAV_CMD_DO_SET_ROI_LOCATION         (195)

Listens for incoming MAVLink messages:
  • GIMBAL_MANAGER_STATUS
  • GIMBAL_DEVICE_ATTITUDE_STATUS

Design rules:
  • NEVER touches DroneCommander or MAVLinkThread internals
  • Hooks into current_msg signal (read-only)
  • All command sends are non-blocking
  • Rate-limited to 100ms between sends
"""

import time
import logging
import math
from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty, QTimer

logger = logging.getLogger(__name__)

# MAVLink gimbal manager flag constants
GIMBAL_MANAGER_FLAGS_NONE   = 0
GIMBAL_MANAGER_FLAGS_LOCK   = 2      # Lock to body frame
GIMBAL_MANAGER_FLAGS_FOLLOW = 3      # Follow vehicle yaw


class GimbalManager(QObject):
    """
    MAVLink Gimbal Control Manager.
    Exposes pitch/yaw control, mode selection, and ROI pointing to QML.
    """

    # ── Signals ───────────────────────────────────────────────────────────────
    commandFeedback     = pyqtSignal(str)
    gimbalStatusUpdated = pyqtSignal('QVariantMap')   # Live gimbal status dict
    pitchChanged        = pyqtSignal(float)
    yawChanged          = pyqtSignal(float)
    modeChanged         = pyqtSignal(str)

    # Rate limit — minimum ms between consecutive command sends
    MIN_CMD_INTERVAL_MS = 100

    def __init__(self, drone_commander=None, parent=None):
        """
        Args:
            drone_commander: Shared reference to DroneCommander (read-only).
        """
        super().__init__(parent)
        self._drone_commander = drone_commander

        # Current gimbal state (from feedback)
        self._pitch_deg   = 0.0
        self._yaw_deg     = 0.0
        self._mode        = "follow"    # "lock" | "follow" | "roi"
        self._last_cmd_time = 0.0
        self._min_interval  = self.MIN_CMD_INTERVAL_MS / 1000.0

        # Rate-limit timer for continuous slider drag
        self._pending_pitch = None
        self._pending_yaw   = None
        self._rate_timer = QTimer(self)
        self._rate_timer.setSingleShot(True)
        self._rate_timer.setInterval(self.MIN_CMD_INTERVAL_MS)
        self._rate_timer.timeout.connect(self._flush_pending_command)

        print("[GimbalManager] ✅ Initialized")

    # ── Qt Properties ─────────────────────────────────────────────────────────

    @pyqtProperty(float, notify=pitchChanged)
    def pitch(self) -> float:
        return self._pitch_deg

    @pyqtProperty(float, notify=yawChanged)
    def yaw(self) -> float:
        return self._yaw_deg

    @pyqtProperty(str, notify=modeChanged)
    def mode(self) -> str:
        return self._mode

    # ── Public Slots (callable from QML) ──────────────────────────────────────

    @pyqtSlot(float, float)
    def setPitchYaw(self, pitch_deg: float, yaw_deg: float):
        """
        Set gimbal pitch and yaw angles (degrees).
        pitch: −90 (straight down) to +45 (slightly up)
        yaw:   −180 to +180 relative to vehicle nose
        Sends rate-limited: fast drag generates one command per 100ms.
        """
        self._pending_pitch = float(pitch_deg)
        self._pending_yaw   = float(yaw_deg)

        # If timer not already running, send immediately then arm timer
        if not self._rate_timer.isActive():
            self._flush_pending_command()
            self._rate_timer.start()

    @pyqtSlot(float)
    def setPitch(self, pitch_deg: float):
        """Set pitch only — keep current yaw."""
        self.setPitchYaw(float(pitch_deg), self._yaw_deg)

    @pyqtSlot(float)
    def setYaw(self, yaw_deg: float):
        """Set yaw only — keep current pitch."""
        self.setPitchYaw(self._pitch_deg, float(yaw_deg))

    @pyqtSlot(str)
    def setMode(self, mode: str):
        """
        Set gimbal control mode.
        mode: "lock" | "follow" | "roi"
        """
        mode = mode.lower()
        if mode not in ("lock", "follow", "roi"):
            self.commandFeedback.emit(f"⚠️ Unknown gimbal mode: {mode}")
            return

        self._mode = mode
        self.modeChanged.emit(mode)

        if mode != "roi":
            # Re-issue current pitch/yaw with new flags
            self._send_pitchyaw_command(self._pitch_deg, self._yaw_deg)
        self.commandFeedback.emit(f"🎯 Gimbal mode → {mode}")
        print(f"[GimbalManager] Mode → {mode}")

    @pyqtSlot()
    def centerGimbal(self):
        """Return gimbal to forward-looking neutral position."""
        self.setPitchYaw(0.0, 0.0)
        self.commandFeedback.emit("🎯 Gimbal centered")

    @pyqtSlot(float, float, float)
    def setROI(self, lat: float, lon: float, alt: float):
        """
        Point gimbal at a GPS location (Region of Interest).
        Sends MAV_CMD_DO_SET_ROI_LOCATION
        """
        self._mode = "roi"
        self.modeChanged.emit("roi")
        self._send_roi_command(lat, lon, alt)
        self.commandFeedback.emit(f"🎯 Gimbal ROI → {lat:.5f}, {lon:.5f}, {alt:.1f}m")

    # ── MAVLink message listener ───────────────────────────────────────────────

    @pyqtSlot(object)
    def handleMAVLinkMessage(self, msg):
        """
        Hook into MAVLinkThread.current_msg to receive gimbal feedback.
        Connect: mavlink_thread.current_msg.connect(gimbal_manager.handleMAVLinkMessage)
        """
        if msg is None:
            return
        msg_type = msg.get_type()

        if msg_type == "GIMBAL_MANAGER_STATUS":
            self._handle_gimbal_manager_status(msg)
        elif msg_type == "GIMBAL_DEVICE_ATTITUDE_STATUS":
            self._handle_gimbal_attitude_status(msg)

    # ── Cleanup ───────────────────────────────────────────────────────────────

    def cleanup(self):
        print("[GimbalManager] 🧹 Cleanup")
        self._rate_timer.stop()

    # ── Internal helpers ──────────────────────────────────────────────────────

    def _get_drone(self):
        """Return the underlying pymavlink connection or None."""
        try:
            if (self._drone_commander
                    and hasattr(self._drone_commander, '_is_drone_ready')
                    and self._drone_commander._is_drone_ready()):
                return self._drone_commander._drone
        except Exception:
            pass
        return None

    def _flush_pending_command(self):
        """Send the most recent queued pitch/yaw command."""
        if self._pending_pitch is None:
            return
        pitch = self._pending_pitch
        yaw   = self._pending_yaw
        self._pending_pitch = None
        self._pending_yaw   = None
        self._send_pitchyaw_command(pitch, yaw)

    def _send_pitchyaw_command(self, pitch_deg: float, yaw_deg: float):
        """Send MAV_CMD_DO_GIMBAL_MANAGER_PITCHYAW (1000)."""
        now = time.monotonic()
        if now - self._last_cmd_time < self._min_interval:
            return
        self._last_cmd_time = now

        drone = self._get_drone()
        if drone is None:
            return

        flags = {
            "lock":   GIMBAL_MANAGER_FLAGS_LOCK,
            "follow": GIMBAL_MANAGER_FLAGS_FOLLOW,
            "roi":    GIMBAL_MANAGER_FLAGS_FOLLOW,  # ROI uses separate command
        }.get(self._mode, GIMBAL_MANAGER_FLAGS_FOLLOW)

        try:
            drone.mav.command_long_send(
                drone.target_system,
                drone.target_component,
                1000,                   # MAV_CMD_DO_GIMBAL_MANAGER_PITCHYAW
                0,                      # confirmation
                float(pitch_deg),       # p1: pitch (deg)
                float(yaw_deg),         # p2: yaw (deg)
                float("nan"),           # p3: pitch rate — NaN = unused
                float("nan"),           # p4: yaw rate
                float(flags),           # p5: gimbal manager flags
                0.0,                    # p6: reserved
                0.0                     # p7: gimbal device id (0 = primary)
            )
            logger.info(f"[GimbalManager] PitchYaw sent: P={pitch_deg:.1f}° Y={yaw_deg:.1f}°")
            print(f"[GimbalManager] 📡 PitchYaw → Pitch={pitch_deg:.1f}°, Yaw={yaw_deg:.1f}°")
        except Exception as exc:
            err = f"Gimbal command error: {exc}"
            self.commandFeedback.emit(f"❌ {err}")
            logger.error(f"[GimbalManager] {err}")

    def _send_roi_command(self, lat: float, lon: float, alt: float):
        """Send MAV_CMD_DO_SET_ROI_LOCATION (195)."""
        drone = self._get_drone()
        if drone is None:
            self.commandFeedback.emit("⚠️ ROI ignored — drone not connected")
            return

        try:
            drone.mav.command_long_send(
                drone.target_system,
                drone.target_component,
                195,        # MAV_CMD_DO_SET_ROI_LOCATION
                0,
                0.0,        # p1: gimbal device id (0 = primary)
                0.0,        # p2–4: reserved
                0.0,
                0.0,
                float(lat),
                float(lon),
                float(alt)
            )
            logger.info(f"[GimbalManager] ROI set: {lat:.5f}, {lon:.5f}, {alt:.1f}m")
            print(f"[GimbalManager] 📡 ROI → {lat:.5f}, {lon:.5f}, {alt:.1f}m")
        except Exception as exc:
            err = f"ROI command error: {exc}"
            self.commandFeedback.emit(f"❌ {err}")
            logger.error(f"[GimbalManager] {err}")

    def _handle_gimbal_manager_status(self, msg):
        """Process GIMBAL_MANAGER_STATUS feedback."""
        try:
            d = msg.to_dict()
            status = {
                "flags":          d.get("flags", 0),
                "gimbal_device_id": d.get("gimbal_device_id", 0),
            }
            self.gimbalStatusUpdated.emit(status)
        except Exception as exc:
            logger.warning(f"[GimbalManager] GIMBAL_MANAGER_STATUS parse error: {exc}")

    def _handle_gimbal_attitude_status(self, msg):
        """Process GIMBAL_DEVICE_ATTITUDE_STATUS — extract pitch/yaw from quaternion."""
        try:
            d = msg.to_dict()
            q = d.get("q", None)
            if q and len(q) == 4:
                # Convert quaternion (w, x, y, z) → Euler (pitch, yaw)
                w, x, y, z = q[0], q[1], q[2], q[3]

                # Pitch (rotation around X)
                sinr_cosp = 2.0 * (w * x + y * z)
                cosr_cosp = 1.0 - 2.0 * (x * x + y * y)
                pitch_rad = math.atan2(sinr_cosp, cosr_cosp)

                # Yaw (rotation around Z)
                siny_cosp = 2.0 * (w * z + x * y)
                cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
                yaw_rad   = math.atan2(siny_cosp, cosy_cosp)

                new_pitch = math.degrees(pitch_rad)
                new_yaw   = math.degrees(yaw_rad)

                if abs(new_pitch - self._pitch_deg) > 0.1:
                    self._pitch_deg = new_pitch
                    self.pitchChanged.emit(new_pitch)

                if abs(new_yaw - self._yaw_deg) > 0.1:
                    self._yaw_deg = new_yaw
                    self.yawChanged.emit(new_yaw)

        except Exception as exc:
            logger.warning(f"[GimbalManager] GIMBAL_DEVICE_ATTITUDE_STATUS parse error: {exc}")
