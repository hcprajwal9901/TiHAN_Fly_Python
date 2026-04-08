from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty, QTimer, QThread, QUrl
from pymavlink import mavutil
from modules.mavlink_thread import MAVLinkThread
from modules.drone_commander import DroneCommander
from modules.auto_connect_worker import AutoConnectWorker
from modules.pnp_watcher import PnpWatcher
import time
import os
import sys
import serial.tools.list_ports
import threading

KEY = "870d932088789c9844cce38cc0cc3b3f18db16211c30f956637f6686bd893f7a"
KEY = bytes.fromhex(KEY)


class ConnectionWorker(QThread):
    connectionSuccess = pyqtSignal(object)
    connectionFailed  = pyqtSignal(str)

    def __init__(self, uri, baud, target_system=1, target_component=1):
        super().__init__()
        self.uri              = uri
        self.baud             = baud
        self.target_system    = target_system
        self.target_component = target_component
        self._should_stop     = False

    def run(self):
        try:
            print(f"[ConnectionWorker] Opening MAVLink connection to {self.uri}...")
            drone = mavutil.mavlink_connection(
                self.uri, baud=self.baud,
                source_system=255, source_component=0,
                force_connected=True)

            if self._should_stop:
                return

            print("[ConnectionWorker] Waiting for heartbeat...")
            drone.wait_heartbeat(timeout=10)

            if self._should_stop:
                drone.close()
                return

            print(f"[ConnectionWorker] ✅ Connection established!")
            print(f"[ConnectionWorker] System ID: {drone.target_system}, Component ID: {drone.target_component}")
            self.connectionSuccess.emit(drone)

        except Exception as e:
            if not self._should_stop:
                print(f"[ConnectionWorker] ❌ Connection failed: {e}")
                self.connectionFailed.emit(str(e))

    def stop(self):
        self._should_stop = True


class DroneModel(QObject):
    telemetryChanged      = pyqtSignal()
    statusTextsChanged    = pyqtSignal()
    droneConnectedChanged = pyqtSignal()
    gpsLocationChanged    = pyqtSignal()
    missionPathUpdated    = pyqtSignal('QVariantList')
    mavlinkMessageReceived = pyqtSignal(object)

    autoConnectStarted  = pyqtSignal()
    autoConnectProgress = pyqtSignal(str)
    autoConnectFound    = pyqtSignal(str, int)
    autoConnectFailed   = pyqtSignal()
    autoConnectHotplug  = pyqtSignal(str)

    # ✅ NEW: emitted when RC channel 5 PWM changes
    rcChannel5Changed = pyqtSignal()

    def __init__(self):
        super().__init__()
        self._mavlink_write_lock = threading.Lock()

        self._telemetry = {
            'mode': "UNKNOWN",
            'armed': False,
            'lat': 0.0,
            'lon': 0.0,
            'alt': 0.0,
            'rel_alt': 0.0,
            'gps_fix_type': 0,
            'satellites_visible': 0,
            'hdop': 0.0,
            'gps_vel': 0.0,
            'gps_cog': 0.0,
            'gps_eph': 0.0,
            'gps_epv': 0.0,
            'roll': 0.0,
            'pitch': 0.0,
            'yaw': 0.0,
            'heading': 0.0,
            'groundspeed': 0.0,
            'airspeed': 0.0,
            'battery_remaining': 0.0,
            'voltage_battery': 0.0,
            'current_battery': 0.0,
            'battery_remaining_mah': 0.0,
            'safety_armed': False,
            'ekf_ok': False,
            'vibration_x': 0.0,
            'vibration_y': 0.0,
            'vibration_z': 0.0,
            # ✅ NEW
            'rc_channel5': 0,
        }

        self._status_texts      = []
        self._drone             = None
        self._thread            = None
        self._drone_commander   = None
        self._is_connected      = False
        self._connection_monitor = QTimer()
        self._connection_monitor.timeout.connect(self._check_connection_health)
        self._connection_worker      = None
        self._auto_connect_worker    = None

        self._pnp_watcher = PnpWatcher()
        self._pnp_watcher.deviceArrived.connect(self._on_usb_device_arrived)
        self._pnp_watcher.deviceRemoved.connect(self._on_usb_device_removed)
        QTimer.singleShot(10000, self._start_pnp_watcher)
        print("[DroneModel] PnpWatcher scheduled to start in 10 s")

        self._last_uri       = None
        self._last_baud      = None
        self._last_drone_id  = "custom"

        self._prev_mode           = None
        self._prev_armed          = None
        self._prev_ekf_ok         = None
        self._prev_gps_fix        = None
        self._prev_satellites     = None
        self._prev_battery_level  = None
        self._has_received_gps    = False

        self._last_waypoint_time         = 0
        self._suppress_waypoint_interval = 10.0
        self._message_cooldowns          = {}

        self._last_telemetry_emit    = 0.0
        self._last_gps_emit          = 0.0
        self._TELEMETRY_EMIT_INTERVAL = 0.1

        self._status_flush_timer = QTimer()
        self._status_flush_timer.setSingleShot(True)
        self._status_flush_timer.setInterval(200)
        self._status_flush_timer.timeout.connect(self._flush_status_texts)

        self._mission_waypoints = []
        self._drone_icon_path   = self._get_drone_icon_path()
        print(f"[DroneModel] Drone icon path: {self._drone_icon_path}")
        print("[DroneModel] Initialized with GPS tracking enabled.")

    def _get_drone_icon_path(self):
        if getattr(sys, 'frozen', False):
            app_dir = os.path.dirname(sys.executable)
        else:
            app_dir = os.path.dirname(os.path.abspath(__file__))

        possible_paths = [
            os.path.join(app_dir, '..', 'App', 'images', 'drone.png'),
            os.path.join(app_dir, 'App', 'images', 'drone.png'),
            os.path.join(app_dir, '..', '..', 'App', 'images', 'drone.png'),
            '/home/tihan_0512/Videos/Tflypython/Tfly Final Pyversion/App/images/drone.png',
            os.path.join(app_dir, 'images', 'drone.png'),
        ]

        for path in possible_paths:
            normalized_path = os.path.normpath(path)
            if os.path.exists(normalized_path):
                print(f"[DroneModel] ✅ Found drone icon at: {normalized_path}")
                return QUrl.fromLocalFile(normalized_path).toString()

        print("[DroneModel] ⚠️ Drone icon not found, using default marker")
        return ""

    @pyqtProperty(str, constant=True)
    def droneIconPath(self):
        return self._drone_icon_path

    @pyqtProperty(float, notify=gpsLocationChanged)
    def droneLat(self):
        return self._telemetry.get('lat', 0.0)

    @pyqtProperty(float, notify=gpsLocationChanged)
    def droneLon(self):
        return self._telemetry.get('lon', 0.0)

    @pyqtProperty(float, notify=gpsLocationChanged)
    def droneAlt(self):
        return self._telemetry.get('rel_alt', 0.0)

    @pyqtProperty(float, notify=telemetryChanged)
    def droneHeading(self):
        return self._telemetry.get('heading', 0.0)

    @pyqtProperty(str, notify=telemetryChanged)
    def droneMode(self):
        return self._telemetry.get('mode', "UNKNOWN")

    @pyqtProperty(bool, notify=telemetryChanged)
    def isDroneArmed(self):
        return self._telemetry.get('armed', False)

    # ✅ NEW: expose RC channel 5 PWM to QML for FlightMode LIVE badge
    @pyqtProperty(int, notify=rcChannel5Changed)
    def rcChannel5(self):
        return int(self._telemetry.get('rc_channel5', 0))

    # ✅ NEW: expose flight mode string directly for QML binding
    @pyqtProperty(str, notify=telemetryChanged)
    def flightMode(self):
        return self._telemetry.get('mode', "UNKNOWN")

    # ═══════════════════════════════════════════════════════════════════════
    # MISSION PATH MANAGEMENT
    # ═══════════════════════════════════════════════════════════════════════

    @pyqtSlot('QVariantList')
    def setMissionPath(self, waypoints):
        try:
            print(f"[DroneModel] 📍 setMissionPath called with {len(waypoints)} waypoints")
            self._mission_waypoints = list(waypoints)
            self.missionPathUpdated.emit(waypoints)
            print(f"[DroneModel] ✅ Mission path broadcasted")
            self.addStatusText(f"📍 Mission path updated: {len(waypoints)} waypoints")
        except Exception as e:
            print(f"[DroneModel] ❌ Error in setMissionPath: {e}")
            import traceback
            traceback.print_exc()

    @pyqtSlot()
    def clearMissionPath(self):
        print("[DroneModel] 🗑️ Clearing mission path...")
        self._mission_waypoints = []
        self.missionPathUpdated.emit([])
        self.addStatusText("🗑️ Mission path cleared")

    @pyqtProperty('QVariantList', notify=missionPathUpdated)
    def missionWaypoints(self):
        return self._mission_waypoints

    # ═══════════════════════════════════════════════════════════════════════
    # CALIBRATION
    # ═══════════════════════════════════════════════════════════════════════

    def setCalibrationModel(self, calibration_model):
        self._calibration_model = calibration_model
        print("[DroneModel] CalibrationModel reference set.")

    @pyqtSlot()
    def triggerLevelCalibration(self):
        from datetime import datetime
        ts = datetime.now().strftime("%H:%M:%S")
        if hasattr(self, '_calibration_model'):
            print("[DroneModel] Triggering level calibration...")
            self._calibration_model.startLevelCalibration()
            self._status_texts.append(f"[{ts}] ✅ Drone Leveled")
        else:
            print("[DroneModel] CalibrationModel not available.")
            self._status_texts.append(f"[{ts}] ❌ Level calibration: CalibrationModel not available")
        if len(self._status_texts) > 100:
            self._status_texts.pop(0)
        self.statusTextsChanged.emit()

    @pyqtSlot()
    def triggerAccelCalibration(self):
        if hasattr(self, '_calibration_model'):
            print("[DroneModel] Triggering accelerometer calibration...")
            self._calibration_model.startAccelCalibration()
        else:
            print("[DroneModel] CalibrationModel not available.")

    # ═══════════════════════════════════════════════════════════════════════
    # AUTO-CONNECT
    # ═══════════════════════════════════════════════════════════════════════

    @pyqtSlot()
    def autoConnectMavlink(self):
        print("[DroneModel] 🔍 autoConnectMavlink() called")

        if self._auto_connect_worker and self._auto_connect_worker.isRunning():
            print("[DroneModel] Stopping previous auto-connect scan…")
            self._auto_connect_worker.stop()
            self._auto_connect_worker.wait(2000)

        self._auto_connect_worker = AutoConnectWorker()
        self._auto_connect_worker.autoConnectProgress.connect(
            lambda msg: self.autoConnectProgress.emit(msg))
        self._auto_connect_worker.autoConnectFound.connect(self._on_auto_connect_found)
        self._auto_connect_worker.autoConnectFailed.connect(self._on_auto_connect_failed)

        self.autoConnectStarted.emit()
        self.addStatusText("🔍 Auto-connect: scanning serial ports…")
        self._auto_connect_worker.start()

    @pyqtSlot()
    def cancelAutoConnect(self):
        if self._auto_connect_worker and self._auto_connect_worker.isRunning():
            print("[DroneModel] ❌ Auto-connect scan cancelled by user")
            self._auto_connect_worker.stop()
            self.addStatusText("❌ Auto-connect cancelled")

    def _on_auto_connect_found(self, port, baud):
        print(f"[DroneModel] 🎯 Auto-connect found device on {port} @ {baud}")
        self.autoConnectFound.emit(port, baud)
        self.addStatusText(f"✅ Auto-connect: found device on {port} @ {baud} baud")
        conn_id = f"auto-{port.replace(':', '-')}"
        self.connectToDrone(conn_id, port, baud)

    def _on_auto_connect_failed(self):
        print("[DroneModel] ❌ Auto-connect: no MAVLink device found")
        self.autoConnectFailed.emit()
        self.addStatusText("❌ Auto-connect: no MAVLink device found")

    def _start_pnp_watcher(self):
        if self._pnp_watcher and not self._pnp_watcher.isRunning():
            self._pnp_watcher.start()
            print("[DroneModel] PnpWatcher started — hotplug detection active")

    @pyqtSlot(str)
    def _on_usb_device_arrived(self, port: str):
        print(f"[DroneModel] 🔌 USB device arrived on {port}")
        if self._is_connected:
            print("[DroneModel]   → Already connected — ignoring hotplug event")
            return
        if self._auto_connect_worker and self._auto_connect_worker.isRunning():
            print("[DroneModel]   → Scan already in progress — ignoring hotplug event")
            return
        self.addStatusText(f"🔌 USB device detected on {port}")
        self.autoConnectHotplug.emit(port)

    @pyqtSlot(str)
    def _on_usb_device_removed(self, port: str):
        print(f"[DroneModel] 🔌 USB device removed from {port}")
        if self._is_connected and self._last_uri == port:
            self.addStatusText(f"⚠️ USB device unplugged from {port}")

    # ═══════════════════════════════════════════════════════════════════════
    # CONNECTION
    # ═══════════════════════════════════════════════════════════════════════

    @pyqtSlot(str, str, int, result=bool)
    def connectToDrone(self, drone_id, uri, baud):
        print(f"[DroneModel] 🚀 Starting connection to {uri}...")
        self._last_uri      = uri
        self._last_baud     = baud
        self._last_drone_id = drone_id

        if self._is_connected:
            print("[DroneModel] Cleaning up existing connection...")
            self.cleanup()
            time.sleep(0.5)

        if self._connection_worker and self._connection_worker.isRunning():
            print("[DroneModel] Stopping previous connection attempt...")
            self._connection_worker.stop()
            self._connection_worker.wait(2000)

        self._connection_worker = ConnectionWorker(uri, baud)
        self._connection_worker.connectionSuccess.connect(self._on_connection_success)
        self._connection_worker.connectionFailed.connect(self._on_connection_failed)
        self._connection_worker.start()

        print("[DroneModel] ✅ Connection worker started (non-blocking)")
        return True

    def _on_connection_success(self, drone):
        print("[DroneModel] 🎉 Connection successful! Setting up...")

        self._drone        = drone
        self._is_connected = True
        self.addStatusText("✅ Drone connected successfully")

        print("[DroneModel] 📡 Creating DroneCommander...")
        self._drone_commander = DroneCommander(self)
        print("[DroneModel] ✅ DroneCommander created")

        print("[DroneModel] 🧵 Creating MAVLinkThread with DroneCommander...")
        self._thread = MAVLinkThread(self._drone, drone_commander=self._drone_commander)

        self._thread.telemetryUpdated.connect(self.updateTelemetry)
        self._thread.statusTextChanged.connect(self._handleRawStatusText)

        if hasattr(self, '_calibration_model'):
            if hasattr(self._calibration_model, 'push_mavlink_msg'):
                self._thread.register_msg_callback(self._calibration_model.push_mavlink_msg)
            self._thread.register_msg_callback(self._calibration_model.handle_mavlink_message)
            self._calibration_model.mav = self._drone

        self._thread.start()
        print("[DroneModel] ✅ MAVLinkThread started with parameter support")

        self.droneConnectedChanged.emit()

        threading.Thread(
            target=self._configure_drone_safe, daemon=True,
            name="DroneModel-configure"
        ).start()

        self._connection_monitor.start(5000)
        print("[DroneModel] 📥 Scheduling parameter request...")
        QTimer.singleShot(3000, self._request_parameters_on_connect)
        print("[DroneModel] ✅ Setup complete - waiting for GPS lock...")

    def _request_parameters_on_connect(self):
        if self._drone_commander and self._is_connected:
            print("[DroneModel] 📥 Auto-requesting parameters from drone...")
            try:
                self._drone_commander.requestAllParameters()
                self.addStatusText("📥 Loading parameters from drone...")
            except Exception as e:
                print(f"[DroneModel] ⚠️ Error requesting parameters: {e}")
                self.addStatusText("⚠️ Failed to load parameters")
        else:
            print("[DroneModel] ⚠️ Cannot request parameters: not connected or no commander")

    def _on_connection_failed(self, error_message):
        print(f"[DroneModel] ❌ Connection failed: {error_message}")
        self.addStatusText(f"❌ Connection failed: {error_message}")
        self._is_connected = False
        self.droneConnectedChanged.emit()

    def _configure_drone_safe(self):
        import time as _time
        _time.sleep(1.5)

        if not self._is_connected or not self._drone:
            return

        print("[DroneModel] Configuring message rates (locked)...")
        message_rates = [
            (33,  200000),
            (30,  100000),
            (74,  200000),
            (1,   500000),
            (24,  500000),
            (193, 1000000),
            (241, 1000000),
            # ✅ NEW: Request RC_CHANNELS at 10 Hz for LIVE badge
            (65,  100000),
        ]

        for msg_id, interval in message_rates:
            if not self._is_connected or not self._drone:
                return
            try:
                with self._mavlink_write_lock:
                    self._drone.mav.command_long_send(
                        self._drone.target_system,
                        self._drone.target_component,
                        mavutil.mavlink.MAV_CMD_SET_MESSAGE_INTERVAL,
                        0, msg_id, interval, 0, 0, 0, 0, 0
                    )
            except Exception as e:
                print(f"[DroneModel] Warning setting msg {msg_id}: {e}")
            _time.sleep(0.15)

        if self._is_connected and self._drone:
            try:
                with self._mavlink_write_lock:
                    self._drone.mav.request_data_stream_send(
                        self._drone.target_system,
                        self._drone.target_component,
                        mavutil.mavlink.MAV_DATA_STREAM_ALL,
                        4, 1
                    )
            except Exception as e:
                print(f"[DroneModel] Warning requesting data stream: {e}")

        self.addStatusText("📡 Telemetry streams active")
        self.addStatusText("📍 Waiting for GPS lock...")

    def _check_connection_health(self):
        if not self._is_connected or not self._drone:
            self._connection_monitor.stop()

    def _handleRawStatusText(self, text):
        if "waypoint" in text.lower() or "📍" in text:
            current_time = time.time()
            if current_time - self._last_waypoint_time < self._suppress_waypoint_interval:
                return
            self._last_waypoint_time = current_time
        self.addStatusText(text)

    # ═══════════════════════════════════════════════════════════════════════
    # TELEMETRY UPDATE
    # ═══════════════════════════════════════════════════════════════════════

    def updateTelemetry(self, data):
        try:
            updated     = False
            gps_updated = False
            rc5_updated = False

            new_telemetry = self._telemetry.copy()

            for key, value in data.items():

                if key == "hdop":
                    value = float(value) / 100.0 if value else 0.0

                if new_telemetry.get(key) != value:
                    old_value = new_telemetry.get(key)
                    new_telemetry[key] = value
                    updated = True

                    if key in ['lat', 'lon', 'alt', 'rel_alt']:
                        gps_updated = True
                        if not self._has_received_gps and key in ['lat', 'lon'] and value != 0:
                            print(f"[DroneModel] 📍 GPS LOCK ACQUIRED!")
                            print(f"[DroneModel]    Latitude: {new_telemetry.get('lat', 0):.6f}°")
                            print(f"[DroneModel]    Longitude: {new_telemetry.get('lon', 0):.6f}°")
                            print(f"[DroneModel]    Altitude: {new_telemetry.get('alt', 0):.1f}m")
                            self._has_received_gps = True
                            self.addStatusText("📍 GPS lock acquired - drone location available")

                    # ✅ NEW: track RC channel 5 changes separately
                    if key == 'rc_channel5':
                        rc5_updated = True

                    self._detect_status_changes(key, old_value, value)

            now = time.time()
            if updated:
                self._telemetry = new_telemetry
                if (now - self._last_telemetry_emit) >= self._TELEMETRY_EMIT_INTERVAL:
                    self._last_telemetry_emit = now
                    self.telemetryChanged.emit()

            if gps_updated and (now - self._last_gps_emit) >= self._TELEMETRY_EMIT_INTERVAL:
                self._last_gps_emit = now
                self.gpsLocationChanged.emit()

            # ✅ NEW: dedicated signal so QML rcChannel5 property updates instantly
            if rc5_updated:
                self.rcChannel5Changed.emit()

        except Exception as e:
            print(f"[DroneModel ERROR] updateTelemetry: {e}")

    def _detect_status_changes(self, key, old_value, new_value):

        if key == 'armed' and old_value is not None and old_value != new_value:
            if new_value:
                self.addStatusText("🔴 ARMED - Motors enabled!")
            else:
                self.addStatusText("🟢 DISARMED - Motors safe")

        if key == 'ekf_ok':
            if old_value is None and not new_value:
                self.addStatusText("⚠️ EKF: Initializing...")
            elif old_value is not None and old_value != new_value:
                if new_value:
                    self.addStatusText("✅ EKF: Healthy - Ready to fly")
                else:
                    self.addStatusText("❌ EKF: FAILURE - DO NOT FLY!")

        if key == 'gps_fix_type' and (old_value is None or old_value != new_value):
            gps_map = {
                0: ("❌ GPS: No GPS",           "error"),
                1: ("❌ GPS: No Fix",           "error"),
                2: ("⚠️ GPS: 2D Fix (weak)",    "warning"),
                3: ("✅ GPS: 3D Fix - Good",    "success"),
                4: ("✅ GPS: DGPS - Excellent", "success"),
                5: ("✅ GPS: RTK Float",        "success"),
                6: ("✅ GPS: RTK Fixed - Best", "success")
            }
            status, level = gps_map.get(new_value, (f"GPS: Unknown ({new_value})", "info"))
            if old_value is None or abs(new_value - old_value) >= 1:
                self.addStatusText(status)
                if new_value < 3:
                    self.addStatusText("   → Wait for 3D fix before arming")

        if key == 'satellites_visible':
            prev_sats = self._prev_satellites
            if prev_sats is not None:
                if new_value >= 10 and prev_sats < 10:
                    self.addStatusText(f"📡 Satellites: {new_value} - Excellent")
                elif new_value < 6 and prev_sats >= 6:
                    self.addStatusText(f"⚠️ Satellites: {new_value} - Too low!")
                elif new_value == 0 and prev_sats > 0:
                    self.addStatusText("❌ Satellites: Signal lost!")
            elif new_value > 0:
                if new_value >= 10:
                    self.addStatusText(f"📡 Satellites: {new_value} - Excellent")
                elif new_value >= 6:
                    self.addStatusText(f"📡 Satellites: {new_value} - Good")
                else:
                    self.addStatusText(f"⚠️ Satellites: {new_value} - Low")
            self._prev_satellites = new_value

        if key == 'battery_remaining':
            if new_value is not None:
                prev_level = self._prev_battery_level
                if new_value <= 10 and (prev_level is None or prev_level > 10):
                    self.addStatusText(f"🔋 CRITICAL: Battery {new_value}% - LAND NOW!")
                    if self._drone_commander:
                        crit_action = self._drone_commander.getParameterValue('BATT_FS_CRT_ACT')
                        if crit_action == 2.0:
                            self.addStatusText("🔴 Auto-triggering RTL (Critical Battery Failsafe)")
                            self._drone_commander.setMode("RTL")
                        elif crit_action in (1.0, 4.0):
                            self.addStatusText("🔴 Auto-triggering LAND (Critical Battery Failsafe)")
                            self._drone_commander.land()
                elif new_value <= 20 and (prev_level is None or prev_level > 20):
                    self.addStatusText(f"⚠️ Battery LOW: {new_value}% - Return home")
                    if self._drone_commander:
                        low_action = self._drone_commander.getParameterValue('BATT_FS_LOW_ACT')
                        if low_action == 2.0:
                            self.addStatusText("🔴 Auto-triggering RTL (Low Battery Failsafe)")
                            self._drone_commander.setMode("RTL")
                        elif low_action in (1.0, 4.0):
                            self.addStatusText("🔴 Auto-triggering LAND (Low Battery Failsafe)")
                            self._drone_commander.land()
                elif new_value <= 30 and (prev_level is None or prev_level > 30):
                    self.addStatusText(f"🔋 Battery: {new_value}% - Plan landing")
                self._prev_battery_level = new_value

        if key == 'voltage_battery' and new_value and new_value > 0:
            if new_value < 10.5:
                if not self._check_message_cooldown('low_voltage', 30):
                    self.addStatusText(f"⚠️ Voltage: {new_value:.1f}V - Very low!")
            elif new_value < 11.1:
                if not self._check_message_cooldown('low_voltage', 60):
                    self.addStatusText(f"🔋 Voltage: {new_value:.1f}V - Low")

    def _check_message_cooldown(self, msg_id, cooldown_seconds):
        current_time = time.time()
        last_time    = self._message_cooldowns.get(msg_id, 0)
        if current_time - last_time < cooldown_seconds:
            return True
        self._message_cooldowns[msg_id] = current_time
        return False

    @pyqtSlot(str)
    def addStatusText(self, text):
        try:
            from datetime import datetime
            timestamp = datetime.now().strftime("%H:%M:%S")
            formatted = f"[{timestamp}] {text}"
            self._status_texts.append(formatted)
            if len(self._status_texts) > 100:
                self._status_texts.pop(0)
            if not self._status_flush_timer.isActive():
                self._status_flush_timer.start()
        except Exception as e:
            print(f"[DroneModel ERROR] addStatusText: {e}")

    def _flush_status_texts(self):
        self.statusTextsChanged.emit()

    @pyqtSlot()
    def clearStatusTexts(self):
        print("[DroneModel] Clearing status texts...")
        self._status_texts.clear()
        self.statusTextsChanged.emit()
        self.addStatusText("🧹 Status cleared")

    @pyqtSlot()
    def disconnectDrone(self):
        print("[DroneModel] 🔌 Disconnecting...")
        self.addStatusText("🔌 Disconnecting...")

        if self._connection_worker and self._connection_worker.isRunning():
            print("[DroneModel] Stopping connection worker...")
            self._connection_worker.stop()
            self._connection_worker.wait(2000)
            self._connection_worker = None

        was_connected      = self._is_connected
        self._is_connected = False
        self._has_received_gps = False

        if was_connected:
            print("[DroneModel] ⚡ Emitting droneConnectedChanged (disconnected)")
            self.droneConnectedChanged.emit()

        self.cleanup()
        self.addStatusText("❌ Disconnected")
        print("[DroneModel] ✅ Disconnect complete")

    @pyqtSlot()
    def scheduleReconnect(self):
        if not self._last_uri:
            print("[DroneModel] ❌ Cannot schedule reconnect: No previous connection.")
            return
        print(f"[DroneModel] 🔄 Scheduling reconnect to {self._last_uri} in 5 seconds...")
        self.disconnectDrone()
        QTimer.singleShot(5000, self._executeReconnect)

    def _executeReconnect(self):
        if self._last_uri:
            print(f"[DroneModel] 🔄 Executing scheduled reconnect to {self._last_uri}...")
            self.connectToDrone(self._last_drone_id, self._last_uri, self._last_baud)

    @pyqtProperty(QObject, constant=True)
    def droneCommander(self):
        return self._drone_commander

    @pyqtProperty('QVariant', notify=telemetryChanged)
    def telemetry(self):
        return self._telemetry

    @pyqtProperty('QVariantList', notify=statusTextsChanged)
    def statusTexts(self):
        return self._status_texts

    @pyqtProperty(bool, notify=droneConnectedChanged)
    def isConnected(self):
        return self._is_connected

    @property
    def drone_connection(self):
        return self._drone

    def cleanup(self):
        print("[DroneModel] 🧹 Cleanup starting...")

        if hasattr(self, '_pnp_watcher') and self._pnp_watcher and self._pnp_watcher.isRunning():
            print("[DroneModel]   ⏸️ Stopping PnpWatcher...")
            self._pnp_watcher.stop()

        if self._auto_connect_worker and self._auto_connect_worker.isRunning():
            self._auto_connect_worker.stop()
            self._auto_connect_worker.wait(1500)

        if self._connection_monitor.isActive():
            self._connection_monitor.stop()
            print("[DroneModel]   ✓ Connection monitor stopped")

        if self._thread:
            print("[DroneModel]   ⏸️ Stopping MAVLink thread...")
            self._thread.stop()
            self._thread.wait(2000)
            self._thread = None
            print("[DroneModel]   ✓ MAVLink thread stopped")

        if self._drone:
            try:
                print("[DroneModel]   🔌 Closing drone connection...")
                self._drone.close()
                print("[DroneModel]   ✓ Drone connection closed")
            except Exception as e:
                print(f"[DroneModel]   ⚠️ Close error: {e}")
            self._drone = None

        self._drone_commander      = None
        self._prev_mode            = None
        self._prev_armed           = None
        self._prev_ekf_ok          = None
        self._prev_gps_fix         = None
        self._prev_satellites      = None
        self._prev_battery_level   = None
        self._has_received_gps     = False
        self._message_cooldowns.clear()
        self._mission_waypoints    = []

        self._telemetry = {
            'mode': "UNKNOWN",
            'armed': False,
            'lat': 0.0,
            'lon': 0.0,
            'alt': 0.0,
            'rel_alt': 0.0,
            'roll': 0.0,
            'pitch': 0.0,
            'yaw': 0.0,
            'heading': 0.0,
            'groundspeed': 0.0,
            'airspeed': 0.0,
            'battery_remaining': 0.0,
            'voltage_battery': 0.0,
            'current_battery': 0.0,
            'battery_remaining_mah': 0.0,
            'safety_armed': False,
            'ekf_ok': False,
            'gps_status': 0,
            'satellites_visible': 0,
            'gps_fix_type': 0,
            'vibration_x': 0.0,
            'vibration_y': 0.0,
            'vibration_z': 0.0,
            'hdop': 0.0,
            # ✅ NEW
            'rc_channel5': 0,
        }
        self.telemetryChanged.emit()
        print("[DroneModel] ✅ Cleanup complete")