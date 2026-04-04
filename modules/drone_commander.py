import time
import queue
import threading
from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty
from pymavlink import mavutil
from pymavlink.dialects.v20 import ardupilotmega as mavlink_dialect

from modules.param_metadata_loader import ParamMetadataLoader
from modules.battery_failsafe_commander import BatteryFailSafeExtension

class DroneCommander(QObject, BatteryFailSafeExtension):
    commandFeedback       = pyqtSignal(str)
    armDisarmCompleted    = pyqtSignal(bool, str)
    parametersUpdated     = pyqtSignal()
    parameterReceived     = pyqtSignal(str, float)
    missionUploaded       = pyqtSignal(list)
    missionCurrentChanged = pyqtSignal(int)
    missionPathUpdated    = pyqtSignal('QVariantList')
    # ✅ MERGED from Doc 3: emitted when takeoff is blocked because the drone is in an NFZ
    takeoffBlockedByNFZ   = pyqtSignal(str)   # zone name
    parameterFetchProgress = pyqtSignal(int, int)

    def __init__(self, drone_model):
        super().__init__()
        self.drone_model = drone_model
        self._parameters = {}
        self._param_lock = threading.Lock()
        self._fetching_params = False
        # ✅ MERGED from Doc 4: bounded queue prevents unbounded memory growth
        self._param_queue = queue.Queue(maxsize=2000)
        self._param_request_active = False
        self._rally_points = []
        self._rally_point_lock = threading.Lock()

        # Track whether the user has explicitly enabled a geo-fence.
        # Takeoff will respect this and NOT disable the fence when True.
        self._geofence_enabled = False
        # FENCE_TYPE bitmask last written: 1=Alt, 2=Circle, 3=Both
        self._geofence_type = 3
        # GCS-side software fence config (mirrors what was written to FC)
        self._geofence_radius   = 150.0
        self._geofence_alt_max  = 100.0
        self._geofence_action   = 1       # 1=RTL, 2=Land
        # Software monitor thread control
        self._geofence_monitor_active = False
        self._geofence_monitor_thread = None

        self._mission_waypoints = []  # Store uploaded mission
        self._mission_current = -1    # Track current waypoint

        self._upload_mission_queue = [] # Queue for async upload
        self._upload_mission_active = False # Flag for async upload

        # ✅ MERGED from Doc 3: NFZ manager – set by main.py after both objects are created
        self.nfz_manager = None

        self._param_metadata = ParamMetadataLoader(vehicle_type="ArduCopter")
        print("[DroneCommander] ✅ ParamMetadataLoader started")

    @property
    def _drone(self):
        return self.drone_model.drone_connection

    def _is_drone_ready(self):
        if not self._drone or not self.drone_model.isConnected:
            self.commandFeedback.emit("Error: Drone not connected or ready.")
            return False

        if self._drone.target_system == 0:
            self._drone.target_system = 1
        if self._drone.target_component == 0:
            self._drone.target_component = 1

        return True

    # ═══════════════════════════════════════════════════════════════════════
    # BASIC DRONE COMMANDS
    # ═══════════════════════════════════════════════════════════════════════

    @pyqtSlot(result=bool)
    def arm(self):
        """Arm the drone motors"""
        if not self._is_drone_ready():
            self.armDisarmCompleted.emit(False, "Drone not connected.")
            return False
        try:
            self._drone.mav.command_long_send(
                self._drone.target_system,
                self._drone.target_component,
                mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
                0, 1, 0, 0, 0, 0, 0, 0)
            self.commandFeedback.emit("🔐 Arm command sent")
            return True
        except Exception as e:
            msg = f"Error sending ARM command: {e}"
            self.commandFeedback.emit(msg)
            self.armDisarmCompleted.emit(False, msg)
            return False

    @pyqtSlot(result=bool)
    def disarm(self):
        """Disarm the drone motors"""
        if not self._is_drone_ready():
            self.armDisarmCompleted.emit(False, "Drone not connected.")
            return False
        try:
            self._drone.mav.command_long_send(
                self._drone.target_system,
                self._drone.target_component,
                mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
                0, 0, 0, 0, 0, 0, 0, 0)
            self.commandFeedback.emit("🔓 Disarm command sent")
            return True
        except Exception as e:
            msg = f"Error sending DISARM command: {e}"
            self.commandFeedback.emit(msg)
            self.armDisarmCompleted.emit(False, msg)
            return False

    @pyqtSlot(float, float, result=bool)
    def takeoff(self, target_altitude, target_speed):
        """Takeoff to specified altitude – blocked when drone is in an NFZ."""
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Drone not connected")
            return False

        # ── NFZ Backend Safety Gate ──────────────────────────────────────────
        # ✅ MERGED from Doc 3: server-side NFZ check before allowing takeoff
        if self.nfz_manager is not None:
            try:
                tel = self.drone_model.telemetry
                if tel is not None:
                    lat = float(tel.get("lat", 0.0)) if isinstance(tel, dict) else float(getattr(tel, "lat", 0.0))
                    lon = float(tel.get("lon", 0.0)) if isinstance(tel, dict) else float(getattr(tel, "lon", 0.0))
                    if lat != 0.0 and lon != 0.0:
                        breached, zone_name = self.nfz_manager._check_position(lat, lon)
                        if breached:
                            msg = f"🚫 TAKEOFF BLOCKED – Drone is inside No-Fly Zone: {zone_name}"
                            self.commandFeedback.emit(msg)
                            self.takeoffBlockedByNFZ.emit(zone_name)
                            print(f"[DroneCommander] {msg}")
                            return False
            except Exception as nfz_err:
                print(f"[DroneCommander] ⚠️ NFZ check error (non-fatal): {nfz_err}")
        # ─────────────────────────────────────────────────────────────────────

        t = threading.Thread(target=self._execute_takeoff_sequence,
                             args=(target_altitude, target_speed), daemon=True)
        t.start()
        self.commandFeedback.emit("🚁 Takeoff sequence started...")
        return True

    def _execute_takeoff_sequence(self, target_altitude, target_speed):
        """Execute full takeoff sequence with arming and mode changes"""
        try:
            # Configure safety parameters
            self.commandFeedback.emit("⚙️ Configuring parameters...")
            params = {
                b'FS_THR_ENABLE':    0,   # Disable RC throttle failsafe
                b'FS_GCS_ENABLE':    0,   # Disable GCS failsafe
                b'ARMING_CHECK':     0,   # Skip pre-arm checks (SITL)
                # ── Battery failsafe ─────────────────────────────────────────
                # FS_BATT_ENABLE does NOT exist in ArduCopter.  The correct
                # parameters are BATT_FS_LOW_ACT and BATT_FS_CRT_ACT:
                #   0 = None (no action), 1 = Land, 2 = RTL, …
                b'BATT_FS_LOW_ACT': 0,   # Battery low  → no action
                b'BATT_FS_CRT_ACT': 0,   # Battery crit → no action
                # ── SITL battery capacity ───────────────────────────────────
                # SITL simulates battery drain; the default capacity is tiny
                # and runs out on long missions.  100,000 mAh = effectively
                # infinite for testing.
                b'SIM_BATT_CAP_AH': 100000,  # 100 Ah — never runs out
            }

            # Only disable geofence if the user has NOT explicitly enabled it
            # from the GeoFence panel. Preserving user intent is critical.
            if not self._geofence_enabled:
                params[b'FENCE_ENABLE'] = 0
                print("[DroneCommander] 🛡️  GeoFence: user has NOT enabled fence — disabling for takeoff")
            else:
                print("[DroneCommander] 🛡️  GeoFence: user-enabled fence will remain ACTIVE during flight")
                fence_desc = {
                    1: "altitude limit",
                    2: "radius limit",
                    3: "altitude & radius limits",
                }.get(self._geofence_type, "altitude & radius limits")
                self.commandFeedback.emit(f"🛡️ GeoFence is ACTIVE — enforcing {fence_desc}")

            for p, v in params.items():
                self._drone.mav.param_set_send(
                    self._drone.target_system,
                    self._drone.target_component,
                    p, v, mavutil.mavlink.MAV_PARAM_TYPE_INT32)
                time.sleep(0.3)
            time.sleep(6)

            # Switch to GUIDED mode
            self.commandFeedback.emit("🎯 Switching to GUIDED mode...")
            mode_id = self._drone.mode_mapping().get("GUIDED")
            self._drone.mav.set_mode_send(
                self._drone.target_system,
                mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
                mode_id)
            time.sleep(2)

            if self._drone.flightmode != "GUIDED":
                self.commandFeedback.emit("❌ Failed to enter GUIDED mode")
                return False

            # Arm motors
            self.commandFeedback.emit("🔐 Arming drone...")
            for _ in range(5):
                self._drone.mav.command_long_send(
                    self._drone.target_system,
                    self._drone.target_component,
                    mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
                    0, 1, 0, 0, 0, 0, 0, 0)
                time.sleep(0.4)
            time.sleep(2)

            if not self._drone.motors_armed():
                self.commandFeedback.emit("❌ Failed to arm")
                return False

            self.commandFeedback.emit("✅ Drone armed")
            self.armDisarmCompleted.emit(True, "Drone Armed Successfully!")

            # Execute takeoff
            self.commandFeedback.emit(f"🚁 Taking off to {target_altitude}m...")
            self._drone.mav.command_long_send(
                self._drone.target_system,
                self._drone.target_component,
                mavutil.mavlink.MAV_CMD_NAV_TAKEOFF,
                0, 0, 0, 0, 0, 0, 0, target_altitude)

            # Monitor takeoff progress using RELATIVE altitude (above home),
            # NOT absolute MSL altitude. MSL alt at SITL Canberra is ~578 m,
            # so using drone.location().alt would give wrong % and never
            # detect a successful 10 m climb.
            start_rel_alt = None
            start_time = time.time()

            while time.time() - start_time < 30:
                # Pull rel_alt from live telemetry (updated by MAVLinkThread)
                try:
                    tel = self.drone_model.telemetry
                    rel_alt = tel.get("rel_alt", 0.0) if isinstance(tel, dict) else getattr(tel, "rel_alt", 0.0)
                except Exception:
                    rel_alt = 0.0

                if start_rel_alt is None:
                    start_rel_alt = rel_alt

                gain = rel_alt - start_rel_alt

                if gain > 0:
                    pct = min(100, int((gain / target_altitude) * 100))
                    self.commandFeedback.emit(f"🚁 Climbing: {rel_alt:.1f}m above home ({pct}%)")

                if not self._drone.motors_armed():
                    self.commandFeedback.emit("❌ Disarmed during takeoff")
                    return False

                if gain >= target_altitude * 0.8:   # reached 80% of target
                    self.commandFeedback.emit("✅ Takeoff successful!")
                    return True

                time.sleep(0.5)

            self.commandFeedback.emit("❌ Takeoff timeout")
            return False

        except Exception as e:
            self.commandFeedback.emit(f"❌ Takeoff error: {e}")
            return False

    @pyqtSlot(result=bool)
    def land(self):
        """Send LAND command to drone — switches to LAND mode so ArduPilot
        descends from the current position.

        NOTE: sending MAV_CMD_NAV_LAND via command_long with lat/lon/alt = 0
        tells ArduPilot to land at (0°N, 0°E) which is accepted but never
        executed.  The reliable approach is set_mode → LAND.
        """
        if not self._is_drone_ready():
            self.commandFeedback.emit("Error: Drone not connected.")
            return False

        try:
            print("[DroneCommander] 🛬 Sending LAND command (mode switch)...")

            mode_id = self._drone.mode_mapping().get("LAND")
            if mode_id is None:
                self.commandFeedback.emit("Error: LAND mode not supported by this firmware.")
                return False

            self._drone.mav.set_mode_send(
                self._drone.target_system,
                mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
                mode_id
            )

            self.commandFeedback.emit("🛬 Landing initiated!")
            print("[DroneCommander] ✅ LAND mode set — drone will descend from current position")
            return True

        except Exception as e:
            error_msg = f"Error sending LAND command: {e}"
            self.commandFeedback.emit(error_msg)
            print(f"[DroneCommander] ❌ {error_msg}")
            return False

    @pyqtSlot(result=bool)
    def rebootAutopilot(self):
        """Send reboot command to the autopilot and trigger auto-reconnect."""
        if not self._is_drone_ready():
            self.commandFeedback.emit("Error: Drone not connected.")
            return False

        try:
            print("[DroneCommander] 🔄 Sending Reboot Command to Autopilot...")
            
            # MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN (246)
            self._drone.mav.command_long_send(
                self._drone.target_system,
                self._drone.target_component,
                mavutil.mavlink.MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN,
                0,  # confirmation
                1,  # param1: 1 = reboot autopilot
                0, 0, 0, 0, 0, 0)
            
            self.commandFeedback.emit("🔄 Reboot command sent. Reconnecting...")
            print("[DroneCommander] ✅ Reboot command sent.")
            
            # Tell DroneModel to disconnect and then schedule a reconnect
            if hasattr(self.drone_model, 'scheduleReconnect'):
                self.drone_model.scheduleReconnect()
                
            return True

        except Exception as e:
            error_msg = f"Error sending reboot command: {e}"
            self.commandFeedback.emit(error_msg)
            print(f"[DroneCommander] ❌ {error_msg}")
            return False

    @pyqtSlot(str, result=bool)
    def setMode(self, mode_name):
        """Change flight mode (RTL, LOITER, CIRCLE, GUIDED, AUTO, etc.)"""
        if not self._is_drone_ready():
            self.commandFeedback.emit("Error: Drone not connected.")
            return False

        try:
            mode_name_upper = mode_name.upper()
            print(f"[DroneCommander] 🔄 Setting mode to: {mode_name_upper}")

            mode_id = self._drone.mode_mapping().get(mode_name_upper)
            if mode_id is None:
                error_msg = f"Error: Unknown mode '{mode_name}'"
                self.commandFeedback.emit(error_msg)
                return False

            self._drone.mav.command_long_send(
                self._drone.target_system,
                self._drone.target_component,
                mavutil.mavlink.MAV_CMD_DO_SET_MODE,
                0,
                mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
                mode_id,
                0, 0, 0, 0, 0)

            # Also send set_mode as backup
            self._drone.mav.set_mode_send(
                self._drone.target_system,
                mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
                mode_id)

            success_msg = f"✅ Mode change to '{mode_name_upper}' sent successfully!"
            self.commandFeedback.emit(success_msg)
            print(f"[DroneCommander] {success_msg}")
            return True

        except Exception as e:
            error_msg = f"Error sending mode change command: {e}"
            self.commandFeedback.emit(error_msg)
            return False

    # ═══════════════════════════════════════════════════════════════════════
    # MISSION UPLOAD - SIMPLIFIED JSON FORMAT
    @pyqtSlot('QVariantList', result=bool)
    def uploadMission(self, waypoints):
        """Parse waypoints and instantly start the asynchronous upload transaction.
        Time Complexity: O(1) blocking time. Send happens efficiently via _process_message."""
 
        print("=" * 60)
        print("[DroneCommander] 📤 UPLOADING MISSION (ASYNC)")
        print("=" * 60)
 
        if not waypoints:
            print("[DroneCommander] ❌ No waypoints provided")
            self.commandFeedback.emit("❌ No waypoints to upload")
            return False
 
        if not self._is_drone_ready():
            return False
 
        print(f"[DroneCommander] 📦 Received {len(waypoints)} waypoints")
 
        # ── Parse QVariantList → plain dicts (runs on calling thread, fast) ──
        mission_waypoints = []
        command_map = {
            'TAKEOFF':         22,
            'WAYPOINT':        16,
            'LAND':            21,
            'RETURN':          20,
            'DO_CHANGE_SPEED': 178,   # MAVLink MAV_CMD_DO_CHANGE_SPEED
        }
 
        for i, wp in enumerate(waypoints):
            lat = lng = alt = 0.0
            command_str = "WAYPOINT"
            speed_ms = 1.5  # default navigation speed
            try:
                if isinstance(wp, dict):
                    lat         = float(wp.get('latitude', 0))
                    lng         = float(wp.get('longitude', 0))
                    alt         = float(wp.get('altitude', 0))
                    command_str = wp.get('command', 'WAYPOINT')
                    speed_ms    = float(wp.get('speed', 1.5))
                elif hasattr(wp, '__getitem__'):
                    try:
                        lat         = float(wp['latitude'])
                        lng         = float(wp['longitude'])
                        alt         = float(wp['altitude'])
                        command_str = wp.get('command', 'WAYPOINT')
                        speed_ms    = float(wp.get('speed', 1.5))
                    except (KeyError, TypeError):
                        lat         = float(wp.get('lat', 0))
                        lng         = float(wp.get('lng', 0))
                        alt         = float(wp.get('altitude', 0))
                elif hasattr(wp, 'latitude'):
                    lat         = float(wp.latitude)
                    lng         = float(wp.longitude)
                    alt         = float(wp.altitude)
                    command_str = getattr(wp, 'command', 'WAYPOINT')
                    speed_ms    = float(getattr(wp, 'speed', 1.5))
                else:
                    print(f"[DroneCommander] ❌ Unknown WP format: {wp}")
                    continue
            except Exception as e:
                print(f"[DroneCommander] ❌ WP{i+1} parse error: {e}")
                continue
 
            cmd_upper   = command_str.upper()
            mavlink_cmd = command_map.get(cmd_upper, 16)
 
            # ── DO_CHANGE_SPEED: speed goes in param2, not x/y/z ────────────
            if cmd_upper == 'DO_CHANGE_SPEED':
                print(f"[DroneCommander] ⚡ WP{i}: DO_CHANGE_SPEED → {speed_ms} m/s")
                mission_waypoints.append({
                    'seq':          i,
                    'frame':        0,          # MAV_FRAME_GLOBAL (ignored for this cmd)
                    'command':      mavlink_cmd, # 178
                    'current':      0,
                    'autocontinue': 1,
                    'param1': 1,                # 1 = groundspeed
                    'param2': speed_ms,         # speed in m/s  e.g. 1.5
                    'param3': -1,               # throttle: -1 = no change
                    'param4': 0,
                    'x': 0, 'y': 0, 'z': 0,
                    'mission_type': 0,
                    'str_cmd': cmd_upper
                })
                continue  # skip the lat/lon 0,0 guard below
            # ─────────────────────────────────────────────────────────────────
 
            if lat == 0.0 and lng == 0.0:
                print(f"[DroneCommander] ⚠️ WP{i+1} has 0,0 coords – skipped")
                continue
 
            mission_waypoints.append({
                'seq':          i,
                'frame':        3,
                'command':      mavlink_cmd,
                'current':      1 if i == 0 else 0,
                'autocontinue': 1,
                'param1': 0, 'param2': 0, 'param3': 0, 'param4': 0,
                'x': lat, 'y': lng, 'z': alt,
                'mission_type': 0,
                'str_cmd': cmd_upper
            })
 
        if not mission_waypoints:
            print("[DroneCommander] ❌ No valid waypoints extracted!")
            self.commandFeedback.emit("❌ No valid waypoints to upload")
            return False
 
        # Re-sequence all items so seq numbers are 0-based and contiguous
        for idx, item in enumerate(mission_waypoints):
            item['seq'] = idx
            # First non-speed item should be 'current'
            if idx == 0:
                item['current'] = 0   # DO_CHANGE_SPEED is never 'current'
            elif idx == 1 and mission_waypoints[0]['command'] == 178:
                item['current'] = 1   # first real nav waypoint is current
 
        print(f"[DroneCommander] ✅ Parsed {len(mission_waypoints)} waypoints (incl. speed cmd)")
        self.commandFeedback.emit(f"📡 Uploading {len(mission_waypoints)} waypoints…")
 
        # Set up the async queue and start the transaction
        self._upload_mission_queue = mission_waypoints
        self._upload_mission_active = True
 
        try:
            print("[DroneCommander] 🗑️ Sending MISSION_COUNT to initiate upload...")
            self._drone.mav.mission_count_send(
                self._drone.target_system,
                self._drone.target_component,
                len(mission_waypoints))
        except Exception as e:
            print(f"[DroneCommander] ❌ Failed to start upload: {e}")
            self.commandFeedback.emit("❌ Failed to initiate mission upload")
            self._upload_mission_active = False
            return False
 
        return True   # "started" – result handled via async events
 
 
    def _execute_takeoff_sequence(self, target_altitude, target_speed):
        """Execute full takeoff sequence with arming and mode changes"""
        try:
            # Configure safety parameters
            self.commandFeedback.emit("⚙️ Configuring parameters...")
            params = {
                b'FS_THR_ENABLE':    0,   # Disable RC throttle failsafe
                b'FS_GCS_ENABLE':    0,   # Disable GCS failsafe
                b'ARMING_CHECK':     0,   # Skip pre-arm checks (SITL)
                # ── Battery failsafe ─────────────────────────────────────────
                b'BATT_FS_LOW_ACT': 0,   # Battery low  → no action
                b'BATT_FS_CRT_ACT': 0,   # Battery crit → no action
                # ── SITL battery capacity ───────────────────────────────────
                b'SIM_BATT_CAP_AH': 100000,  # 100 Ah — never runs out
                # ── Waypoint navigation speed ────────────────────────────────
                # WPNAV_SPEED is in cm/s in ArduCopter.
                # 150 cm/s = 1.5 m/s — matches the QML DO_CHANGE_SPEED default.
                b'WPNAV_SPEED':     150,  # 1.5 m/s
            }
 
            # Only disable geofence if the user has NOT explicitly enabled it
            if not self._geofence_enabled:
                params[b'FENCE_ENABLE'] = 0
                print("[DroneCommander] 🛡️  GeoFence: user has NOT enabled fence — disabling for takeoff")
            else:
                print("[DroneCommander] 🛡️  GeoFence: user-enabled fence will remain ACTIVE during flight")
                fence_desc = {
                    1: "altitude limit",
                    2: "radius limit",
                    3: "altitude & radius limits",
                }.get(self._geofence_type, "altitude & radius limits")
                self.commandFeedback.emit(f"🛡️ GeoFence is ACTIVE — enforcing {fence_desc}")
 
            for p, v in params.items():
                self._drone.mav.param_set_send(
                    self._drone.target_system,
                    self._drone.target_component,
                    p, v, mavutil.mavlink.MAV_PARAM_TYPE_INT32)
                time.sleep(0.3)
            time.sleep(6)
 
            # Switch to GUIDED mode
            self.commandFeedback.emit("🎯 Switching to GUIDED mode...")
            mode_id = self._drone.mode_mapping().get("GUIDED")
            self._drone.mav.set_mode_send(
                self._drone.target_system,
                mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
                mode_id)
            time.sleep(2)
 
            if self._drone.flightmode != "GUIDED":
                self.commandFeedback.emit("❌ Failed to enter GUIDED mode")
                return False
 
            # Arm motors
            self.commandFeedback.emit("🔐 Arming drone...")
            for _ in range(5):
                self._drone.mav.command_long_send(
                    self._drone.target_system,
                    self._drone.target_component,
                    mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM,
                    0, 1, 0, 0, 0, 0, 0, 0)
                time.sleep(0.4)
            time.sleep(2)
 
            if not self._drone.motors_armed():
                self.commandFeedback.emit("❌ Failed to arm")
                return False
 
            self.commandFeedback.emit("✅ Drone armed")
            self.armDisarmCompleted.emit(True, "Drone Armed Successfully!")
 
            # Execute takeoff
            self.commandFeedback.emit(f"🚁 Taking off to {target_altitude}m...")
            self._drone.mav.command_long_send(
                self._drone.target_system,
                self._drone.target_component,
                mavutil.mavlink.MAV_CMD_NAV_TAKEOFF,
                0, 0, 0, 0, 0, 0, 0, target_altitude)
 
            # Monitor takeoff progress using RELATIVE altitude (above home)
            start_rel_alt = None
            start_time = time.time()
 
            while time.time() - start_time < 30:
                try:
                    tel = self.drone_model.telemetry
                    rel_alt = tel.get("rel_alt", 0.0) if isinstance(tel, dict) else getattr(tel, "rel_alt", 0.0)
                except Exception:
                    rel_alt = 0.0
 
                if start_rel_alt is None:
                    start_rel_alt = rel_alt
 
                gain = rel_alt - start_rel_alt
 
                if gain > 0:
                    pct = min(100, int((gain / target_altitude) * 100))
                    self.commandFeedback.emit(f"🚁 Climbing: {rel_alt:.1f}m above home ({pct}%)")
 
                if not self._drone.motors_armed():
                    self.commandFeedback.emit("❌ Disarmed during takeoff")
                    return False
 
                if gain >= target_altitude * 0.8:   # reached 80% of target
                    self.commandFeedback.emit("✅ Takeoff successful!")
                    return True
 
                time.sleep(0.5)
 
            self.commandFeedback.emit("❌ Takeoff timeout")
            return False
 
        except Exception as e:
            self.commandFeedback.emit(f"❌ Takeoff error: {e}")
            return False
 
    def _send_item(self, wp):
        """Helper: send a single MISSION_ITEM_INT for the given waypoint dict."""
        self._drone.mav.mission_item_int_send(
            self._drone.target_system,
            self._drone.target_component,
            wp['seq'],
            wp['frame'],
            wp['command'],
            wp['current'],
            wp['autocontinue'],
            wp['param1'],
            wp['param2'],
            wp['param3'],
            wp['param4'],
            int(wp['x'] * 1e7),
            int(wp['y'] * 1e7),
            float(wp['z']))

    # ═══════════════════════════════════════════════════════════════════════
    # WAYPOINT EXECUTION TRACKING
    # ═══════════════════════════════════════════════════════════════════════

    def _process_message(self, msg):
        """Process incoming MAVLink messages dynamically"""
        msg_type = msg.get_type()

        # ── 1. ASYNC MISSION UPLOAD HANDLER ───────────────────────────────
        if self._upload_mission_active:
            if msg_type in ('MISSION_REQUEST', 'MISSION_REQUEST_INT'):
                seq = msg.seq
                queue_len = len(self._upload_mission_queue)

                if seq < queue_len:
                    wp = self._upload_mission_queue[seq]
                    print(f"[DroneCommander] 📤 FC requested WP {seq+1}/{queue_len} – Sending instantly")
                    self._send_item(wp)
                    
                    # Optional: debounce feedback to avoid spamming UI on massive files
                    if seq % max(1, queue_len // 20) == 0 or seq == queue_len - 1:
                        self.commandFeedback.emit(f"📤 Uploading WP {seq+1}/{queue_len}…")

            elif msg_type == 'MISSION_ACK':
                if msg.type == mavutil.mavlink.MAV_MISSION_ACCEPTED:
                    queued_wps = len(self._upload_mission_queue)
                    print(f"[DroneCommander] 🎉 Mission accepted! ({queued_wps} WPs)")
                    self.commandFeedback.emit(f"✅ Mission uploaded successfully! ({queued_wps} WPs)")
                    self._upload_mission_active = False

                    # Broadcast to QML seamlessly right after upload
                    try:
                        waypoints_for_qml = []
                        for dict_wp in self._upload_mission_queue:
                            waypoints_for_qml.append({
                                'lat': dict_wp['x'], 'lng': dict_wp['y'], 'altitude': dict_wp['z'],
                                'command': dict_wp.get('str_cmd', 'WAYPOINT')
                            })
                        if hasattr(self, 'drone_model') and self.drone_model:
                            self.drone_model.setMissionPath(waypoints_for_qml)
                    except Exception as e:
                        print(f"[DroneCommander] ⚠️ missionPath QML broadcast error: {e}")
                else:
                    codes = { 1: 'ERROR', 2: 'UNSUPPORTED_FRAME', 3: 'INVALID_SEQUENCE',
                              4: 'INVALID_PARAM', 5: 'INVALID_COUNT', 6: 'UNSUPPORTED' }
                    code_name = codes.get(msg.type, f'code {msg.type}')
                    print(f"[DroneCommander] ❌ Mission rejected: {code_name}")
                    self.commandFeedback.emit(f"❌ Mission rejected: {code_name}")
                    self._upload_mission_active = False
        # ───────────────────────────────────────────────────────────────────

        if msg_type == 'MISSION_CURRENT':
            new_wp = msg.seq

            if new_wp != self._mission_current and new_wp > 0:
                old_wp = self._mission_current
                self._mission_current = new_wp

                print(f"\n[DroneCommander] 🎯 Waypoint changed: {old_wp} → {new_wp}")

                self.missionCurrentChanged.emit(new_wp)

                if new_wp < len(self._mission_waypoints):
                    self._execute_waypoint_command(new_wp)

        elif msg_type == 'PARAM_VALUE':
            if self._param_request_active:
                self.add_parameter_to_queue(msg)
            else:
                self._process_param_message(msg)

    def _execute_waypoint_command(self, waypoint_index):
        """Execute special command for reached waypoint"""
        if waypoint_index >= len(self._mission_waypoints):
            return

        waypoint = self._mission_waypoints[waypoint_index]
        command_type = waypoint.get('commandType', 'waypoint')

        print(f"[DroneCommander] 📋 WP{waypoint_index}: Type={command_type}")

        if command_type == "return":
            print(f"[DroneCommander] 🏠 Executing RTL...")

            try:
                self._drone.mav.mission_clear_all_send(
                    self._drone.target_system,
                    self._drone.target_component)
                time.sleep(0.2)

                self._drone.mav.command_long_send(
                    self._drone.target_system,
                    self._drone.target_component,
                    mavutil.mavlink.MAV_CMD_NAV_RETURN_TO_LAUNCH,
                    0, 0, 0, 0, 0, 0, 0, 0)

                mode_id = self._drone.mode_mapping().get("RTL")
                if mode_id is not None:
                    self._drone.mav.set_mode_send(
                        self._drone.target_system,
                        mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
                        mode_id)

                self.commandFeedback.emit(f"🏠 WP{waypoint_index}: RTL activated")
                print(f"[DroneCommander] ✅ RTL command sent")

            except Exception as e:
                print(f"[DroneCommander] ❌ RTL error: {e}")

    @pyqtSlot('QVariantList')
    def setMissionPath(self, waypoints):
        """Broadcast mission path to QML"""
        print(f"[DroneCommander] 📍 Broadcasting {len(waypoints)} waypoints")
        self.missionPathUpdated.emit(waypoints)

    # ═══════════════════════════════════════════════════════════════════════
    # RALLY POINT MANAGEMENT
    # ═══════════════════════════════════════════════════════════════════════

    @pyqtSlot(float, float, float, result=bool)
    def sendRallyPoint(self, lat, lon, alt):
        """
        Send a rally point to the autopilot using proper ArduPilot protocol.
        Rally points are safe return locations for failsafe operations.

        WHY THIS METHOD:
        ----------------
        ArduPilot does NOT use MAV_CMD_NAV_RALLY_POINT with command_long_send().
        Instead, rally points MUST be sent using the RALLY_POINT MAVLink message
        via rally_point_send().

        CRITICAL REQUIREMENTS:
        ----------------------
        1. Index is 0-based (first rally = 0, second = 1, etc.)
        2. Total count must be correct (total rally points after adding this one)
        3. Altitude MUST be in CENTIMETERS (cm), not meters
        4. Lat/Lon MUST be in 1e7 format (degrees * 10,000,000)

        Args:
            lat (float): Latitude in degrees
            lon (float): Longitude in degrees
            alt (float): Altitude in METERS (will be converted to cm internally)

        Returns:
            bool: True if command sent successfully
        """
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Cannot send rally point: Drone not connected")
            return False

        try:
            rally_index = len(self._rally_points)
            total_count = rally_index + 1

            print(f"[DroneCommander] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print(f"[DroneCommander] 🏁 Sending Rally Point {total_count}")
            print(f"[DroneCommander]    Index: {rally_index} of {total_count}")
            print(f"[DroneCommander]    Lat: {lat:.6f}°")
            print(f"[DroneCommander]    Lon: {lon:.6f}°")
            print(f"[DroneCommander]    Alt: {alt:.1f}m (relative to home)")

            self._drone.mav.rally_point_send(
                self._drone.target_system,
                self._drone.target_component,
                rally_index,
                total_count,
                int(lat * 1e7),
                int(lon * 1e7),
                int(alt * 100),   # altitude in CENTIMETERS
                0,                # break_alt: not used by ArduCopter
                0,                # land_dir: not used by ArduCopter
                0                 # flags
            )

            with self._rally_point_lock:
                rally_point = {
                    "index": rally_index,
                    "lat": lat,
                    "lon": lon,
                    "alt": alt,
                    "timestamp": time.time()
                }
                self._rally_points.append(rally_point)

            success_msg = f"🏁 Rally Point {total_count} uploaded successfully"
            self.commandFeedback.emit(success_msg)
            print(f"[DroneCommander] ✅ {success_msg}")
            print(f"[DroneCommander]    Total rally points: {len(self._rally_points)}")
            print(f"[DroneCommander] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return True

        except Exception as e:
            error_msg = f"Error sending rally point: {e}"
            self.commandFeedback.emit(f"❌ {error_msg}")
            print(f"[DroneCommander] ❌ {error_msg}")
            import traceback
            traceback.print_exc()
            return False

    @pyqtSlot(result=bool)
    def clearAllRallyPoints(self):
        """
        Clear all rally points from the autopilot.

        HOW IT WORKS:
        -------------
        Send a rally_point_send() with count=0. ArduPilot interprets this
        as a command to delete all existing rally points.
        """
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Cannot clear rally points: Drone not connected")
            return False

        try:
            print("[DroneCommander] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("[DroneCommander] 🗑️ Clearing all rally points...")

            self._drone.mav.rally_point_send(
                self._drone.target_system,
                self._drone.target_component,
                0, 0,   # idx=0, count=0 → CLEAR ALL
                0, 0, 0, 0, 0, 0
            )

            with self._rally_point_lock:
                self._rally_points.clear()

            success_msg = "✅ All rally points cleared"
            self.commandFeedback.emit(success_msg)
            print(f"[DroneCommander] {success_msg}")
            print(f"[DroneCommander] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            return True

        except Exception as e:
            error_msg = f"Error clearing rally points: {e}"
            self.commandFeedback.emit(f"❌ {error_msg}")
            print(f"[DroneCommander] ❌ {error_msg}")
            return False

    @pyqtSlot(result=int)
    def getRallyPointCount(self):
        """Get the number of rally points currently stored"""
        with self._rally_point_lock:
            return len(self._rally_points)

    @pyqtSlot(result='QVariantList')
    def getAllRallyPoints(self):
        """Get all rally points as a list"""
        with self._rally_point_lock:
            return list(self._rally_points)

    # ═══════════════════════════════════════════════════════════════════════
    # GEO-FENCE CONFIGURATION
    # ═══════════════════════════════════════════════════════════════════════

    @pyqtSlot(bool, int, int, int, int)
    def writeGeoFence(self, enabled, fence_type, fence_action, max_altitude, max_radius):
        """
        Write geo-fence parameters to ArduPilot (runs in background thread).

        Each parameter is confirmed with a PARAM_VALUE ACK before moving to
        the next one, so the FC actually stores every value.

        Args:
            enabled      (bool): True = enable the fence after writing
            fence_type   (int) : FENCE_TYPE bitmask  (1=Alt, 2=Circle, 3=Alt+Circle)
            fence_action (int) : FENCE_ACTION         (0=RTL, 1=Land)
            max_altitude (int) : FENCE_ALT_MAX in metres
            max_radius   (int) : FENCE_RADIUS in metres
        """
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ GeoFence write failed: Drone not connected")
            return

        # Persist intent immediately so takeoff knows before the thread finishes
        self._geofence_enabled  = bool(enabled)
        self._geofence_type     = int(fence_type)   # 1=Alt, 2=Circle, 3=Both
        self._geofence_radius   = float(max_radius)
        self._geofence_alt_max  = float(max_altitude)
        self._geofence_action   = int(fence_action)  # 1=RTL, 2=Land

        # Start / stop the GCS-side software enforcement monitor
        if enabled:
            self._start_geofence_monitor()
        else:
            self._stop_geofence_monitor()

        # Run the actual MAVLink writes in a daemon thread so the UI stays
        # responsive during the confirmation round-trips.
        t = threading.Thread(
            target=self._write_geofence_thread,
            args=(enabled, fence_type, fence_action, max_altitude, max_radius),
            daemon=True,
            name="GeoFence-write"
        )
        t.start()

    def _write_geofence_thread(self, enabled, fence_type, fence_action, max_altitude, max_radius):
        """Background worker: sends each fence param and waits for ACK."""
        try:
            print("[DroneCommander] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print(f"[DroneCommander] 🛡️  Writing GeoFence parameters")
            print(f"[DroneCommander]    Enabled   : {enabled}")
            print(f"[DroneCommander]    Type      : {fence_type}  (1=Alt, 2=Circle, 3=Both)")
            print(f"[DroneCommander]    Action    : {fence_action} (ArduPilot: 1=RTL, 2=Land)")
            print(f"[DroneCommander]    Max Alt   : {max_altitude} m")
            print(f"[DroneCommander]    Max Radius: {max_radius} m")

            self.commandFeedback.emit("🛡️ Writing GeoFence to drone...")

            # Send all params with ACK confirmation.
            # FENCE_ENABLE is written last so the FC validates the rest first.
            param_jobs = [
                (b'FENCE_TYPE',    fence_type,          mavutil.mavlink.MAV_PARAM_TYPE_INT32),
                (b'FENCE_ACTION',  fence_action,         mavutil.mavlink.MAV_PARAM_TYPE_INT32),
                (b'FENCE_ALT_MAX', float(max_altitude),  mavutil.mavlink.MAV_PARAM_TYPE_REAL32),
                (b'FENCE_RADIUS',  float(max_radius),    mavutil.mavlink.MAV_PARAM_TYPE_REAL32),
                (b'FENCE_ENABLE',  1 if enabled else 0,  mavutil.mavlink.MAV_PARAM_TYPE_INT32),
            ]

            failed = []
            for param_id, value, ptype in param_jobs:
                ok = self._send_param_set(param_id, value, ptype)
                name = param_id.decode().rstrip('\x00')
                if ok:
                    print(f"[DroneCommander] ✅ {name} = {value} confirmed")
                else:
                    print(f"[DroneCommander] ⚠️  {name} = {value} not ACK'd (may still have applied)")
                    failed.append(name)

            status = "ENABLED" if enabled else "disabled"
            if not failed:
                msg = (f"✅ GeoFence {status} — "
                       f"Alt:{max_altitude}m  Radius:{max_radius}m  "
                       f"Action:{'RTL' if fence_action == 1 else 'Land'}")
            else:
                msg = (f"⚠️ GeoFence written (some params unconfirmed: {', '.join(failed)}) — "
                       f"{status}")

            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
            print("[DroneCommander] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        except Exception as e:
            error_msg = f"❌ GeoFence write error: {e}"
            self.commandFeedback.emit(error_msg)
            print(f"[DroneCommander] {error_msg}")
            import traceback
            traceback.print_exc()

    # ═══════════════════════════════════════════════════════════════════════
    # GCS-SIDE SOFTWARE GEOFENCE MONITOR
    # ═══════════════════════════════════════════════════════════════════════

    def _start_geofence_monitor(self):
        """Start the background GCS-side geofence enforcement thread."""
        # Don't spawn a second thread if one is already running
        if self._geofence_monitor_thread and self._geofence_monitor_thread.is_alive():
            print("[DroneCommander] 🛡️  GeoFence monitor already running")
            return
        self._geofence_monitor_active = True
        self._geofence_monitor_thread = threading.Thread(
            target=self._geofence_monitor_loop,
            daemon=True,
            name="GeoFence-monitor"
        )
        self._geofence_monitor_thread.start()
        print("[DroneCommander] 🛡️  GCS GeoFence monitor STARTED")

    def _stop_geofence_monitor(self):
        """Signal the monitor loop to stop."""
        self._geofence_monitor_active = False
        print("[DroneCommander] 🛡️  GCS GeoFence monitor STOPPED")

    @staticmethod
    def _haversine_m(lat1, lon1, lat2, lon2):
        """Return great-circle distance in metres between two GPS points."""
        import math
        R = 6_371_000
        phi1, phi2 = math.radians(lat1), math.radians(lat2)
        dphi = math.radians(lat2 - lat1)
        dlam = math.radians(lon2 - lon1)
        a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2
        return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    def _geofence_monitor_loop(self):
        """
        Background thread: independently enforces the geo-fence from GCS side.
        This is the backup layer when ArduPilot's onboard fence does not trigger
        reliably (e.g. SITL, bad home-point, firmware quirks).
        """
        import math
        print("[DroneCommander] 🛡️  GeoFence monitor loop running")

        home_lat = home_lon = None
        alt_breach_active  = False
        circ_breach_active = False
        home_set           = False

        while self._geofence_monitor_active:
            time.sleep(1.0)

            # Stop silently if fence was disabled
            if not self._geofence_enabled:
                continue

            try:
                if not self._drone or not self.drone_model.isConnected:
                    continue

                tel = self.drone_model.telemetry
                if tel is None:
                    continue

                if isinstance(tel, dict):
                    lat     = float(tel.get("lat",     0.0))
                    lon     = float(tel.get("lon",     0.0))
                    rel_alt = float(tel.get("rel_alt", 0.0))
                else:
                    lat     = float(getattr(tel, "lat",     0.0))
                    lon     = float(getattr(tel, "lon",     0.0))
                    rel_alt = float(getattr(tel, "rel_alt", 0.0))

                if lat == 0.0 or lon == 0.0:
                    continue

                # ── Capture home on first valid GPS fix ──────────────────────
                if not home_set:
                    home_lat, home_lon = lat, lon
                    home_set = True
                    print(f"[DroneCommander] 🏠 GeoFence home locked: "
                          f"{home_lat:.6f}, {home_lon:.6f}")
                    self.commandFeedback.emit(
                        f"🏠 GeoFence home: {home_lat:.5f}, {home_lon:.5f}")
                    continue

                # ── Circle / radius check ────────────────────────────────────
                if self._geofence_type in (2, 3):   # Circle or Both
                    dist = self._haversine_m(home_lat, home_lon, lat, lon)

                    if dist > self._geofence_radius and not circ_breach_active:
                        circ_breach_active = True
                        msg = (f"🚨 GCS GeoFence BREACH — "
                               f"{dist:.0f}m from home (limit: {self._geofence_radius:.0f}m)")
                        print(f"[DroneCommander] {msg}")
                        self.commandFeedback.emit(msg)
                        self._trigger_fence_action()

                    elif dist <= self._geofence_radius:
                        circ_breach_active = False   # Back inside — reset

                # ── Altitude check ───────────────────────────────────────────
                if self._geofence_type in (1, 3):   # Alt or Both
                    if rel_alt > self._geofence_alt_max and not alt_breach_active:
                        alt_breach_active = True
                        msg = (f"🚨 GCS GeoFence BREACH — "
                               f"Alt {rel_alt:.1f}m above limit ({self._geofence_alt_max:.0f}m)")
                        print(f"[DroneCommander] {msg}")
                        self.commandFeedback.emit(msg)
                        self._trigger_fence_action()

                    elif rel_alt <= self._geofence_alt_max:
                        alt_breach_active = False    # Back inside — reset

            except Exception as e:
                print(f"[DroneCommander] ⚠️  GeoFence monitor error: {e}")

        print("[DroneCommander] 🛡️  GeoFence monitor loop exited")

    def _trigger_fence_action(self):
        """Execute the user-configured fence breach action (RTL or Land)."""
        action_name = "RTL" if self._geofence_action == 1 else "LAND"
        print(f"[DroneCommander] 🛡️  GeoFence action: triggering {action_name}")
        try:
            mode_id = self._drone.mode_mapping().get(action_name)
            if mode_id is None:
                print(f"[DroneCommander] ❌ Mode '{action_name}' not found in mode map")
                return
            self._drone.mav.set_mode_send(
                self._drone.target_system,
                mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
                mode_id)
            self.commandFeedback.emit(
                f"🛡️ GeoFence action executed: {action_name}")
            print(f"[DroneCommander] ✅ GeoFence {action_name} mode set")
        except Exception as e:
            print(f"[DroneCommander] ❌ GeoFence action error: {e}")

    # ═══════════════════════════════════════════════════════════════════════
    # BATTERY FAILSAFE CONFIGURATION
    # ═══════════════════════════════════════════════════════════════════════

    @pyqtSlot(str, result=bool)
    def setBatteryFailSafe(self, action):
        """Configure battery failsafe action when battery is critically low."""
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Cannot set battery failsafe: Drone not connected")
            return False

        action = action.strip().upper()
        print(f"[DroneCommander] ⚡ Setting Battery FailSafe to: {action}")

        action_map = {
            "NONE": (0, 0),
            "LAND": (1, 1),
            "RTL":  (2, 2),
            "HOLD": (0, 0),
        }

        if action not in action_map:
            error_msg = f"❌ Invalid battery failsafe action: '{action}'. Use: None, Land, RTL, or Hold"
            self.commandFeedback.emit(error_msg)
            print(f"[DroneCommander] {error_msg}")
            return False

        low_action, crit_action = action_map[action]
        success = True

        if not self._send_param_set(b'BATT_FS_LOW_ACT', low_action,
                                    mavutil.mavlink.MAV_PARAM_TYPE_INT8):
            success = False
            self.commandFeedback.emit(f"⚠️ Failed to set BATT_FS_LOW_ACT")
        else:
            print(f"[DroneCommander] ✅ BATT_FS_LOW_ACT set to {low_action}")

        time.sleep(0.2)

        if not self._send_param_set(b'BATT_FS_CRT_ACT', crit_action,
                                    mavutil.mavlink.MAV_PARAM_TYPE_INT8):
            success = False
            self.commandFeedback.emit(f"⚠️ Failed to set BATT_FS_CRT_ACT")
        else:
            print(f"[DroneCommander] ✅ BATT_FS_CRT_ACT set to {crit_action}")

        if success:
            feedback_msg = f"✅ Battery FailSafe set to: {action}"
            self.commandFeedback.emit(feedback_msg)
            print(f"[DroneCommander] {feedback_msg}")

        return success

    @pyqtSlot(str, result=bool)
    def setRCFailSafe(self, action):
        """Configure RC failsafe action when RC signal is lost."""
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Cannot set RC failsafe: Drone not connected")
            return False

        action = action.strip().upper()
        print(f"[DroneCommander] 📡 Setting RC FailSafe to: {action}")

        action_map = {
            "NONE": 0,
            "RTL":  1,
            "LAND": 4,
            "HOLD": 0,
        }

        if action not in action_map:
            error_msg = f"❌ Invalid RC failsafe action: '{action}'. Use: None, Land, RTL, or Hold"
            self.commandFeedback.emit(error_msg)
            print(f"[DroneCommander] {error_msg}")
            return False

        fs_value = action_map[action]
        success = self._send_param_set(b'FS_THR_ENABLE', fs_value,
                                       mavutil.mavlink.MAV_PARAM_TYPE_INT8)

        if success:
            feedback_msg = f"✅ RC FailSafe set to: {action}"
            self.commandFeedback.emit(feedback_msg)
            print(f"[DroneCommander] {feedback_msg}")
        else:
            self.commandFeedback.emit(f"⚠️ Failed to set RC failsafe")

        return success

    def _send_param_set(self, param_id, param_value, param_type=None, timeout=5.0):
        """
        Send a parameter set command and wait for confirmation.

        Args:
            param_id (bytes): Parameter name (e.g., b'BATT_FS_LOW_ACT')
            param_value (int/float): Value to set
            param_type (int, optional): MAV_PARAM_TYPE_* constant
            timeout (float): Seconds to wait for confirmation

        Returns:
            bool: True if parameter was confirmed, False otherwise
        """
        if not self._is_drone_ready():
            return False

        try:
            if isinstance(param_id, str):
                param_id = param_id.encode('utf-8')

            if param_type is None:
                if isinstance(param_value, float):
                    param_type = mavutil.mavlink.MAV_PARAM_TYPE_REAL32
                else:
                    param_type = mavutil.mavlink.MAV_PARAM_TYPE_INT32

            if param_type in [mavutil.mavlink.MAV_PARAM_TYPE_REAL32,
                               mavutil.mavlink.MAV_PARAM_TYPE_REAL64]:
                param_value = float(param_value)
            else:
                param_value = int(param_value)

            param_name = param_id.decode('utf-8').strip('\x00')
            print(f"[DroneCommander] 📤 Setting {param_name} = {param_value} (type={param_type})")

            max_retries = 3
            for attempt in range(max_retries):
                self._drone.mav.param_set_send(
                    self._drone.target_system,
                    self._drone.target_component,
                    param_id,
                    param_value,
                    param_type
                )

                start_time = time.time()
                while time.time() - start_time < 2.0:
                    time.sleep(0.1)
                    with self._param_lock:
                        if param_name in self._parameters:
                            cached_value = self._parameters[param_name]['value']
                            if param_type in [mavutil.mavlink.MAV_PARAM_TYPE_REAL32,
                                              mavutil.mavlink.MAV_PARAM_TYPE_REAL64]:
                                value_match = abs(float(cached_value) - float(param_value)) < 0.001
                            else:
                                value_match = int(float(cached_value)) == int(param_value)
                            if value_match:
                                print(f"[DroneCommander] ✅ {param_name} confirmed: {cached_value}")
                                self.parameterReceived.emit(param_name, float(cached_value))
                                return True

                if attempt < max_retries - 1:
                    print(f"[DroneCommander] ⚠️ {param_name}: Retry {attempt + 2}/{max_retries}")

            print(f"[DroneCommander] ❌ {param_name}: No confirmation (timeout)")
            return False

        except Exception as e:
            error_msg = f"Error setting parameter {param_id}: {e}"
            print(f"[DroneCommander] ❌ {error_msg}")
            self.commandFeedback.emit(f"❌ {error_msg}")
            return False

    @pyqtSlot(str, result='QVariant')
    def getParameterValue(self, param_name):
        """Get current value of a parameter from local cache."""
        with self._param_lock:
            if param_name in self._parameters:
                return float(self._parameters[param_name]['value'])
            return None

    @pyqtSlot(result=str)
    def getBatteryFailSafeStatus(self):
        """Get battery failsafe status for UI display"""
        try:
            print("[DroneCommander] getBatteryFailSafeStatus() called")
            with self._param_lock:
                if 'BATT_FS_LOW_ACT' not in self._parameters or 'BATT_FS_CRT_ACT' not in self._parameters:
                    print(f"[DroneCommander] Parameters not found. Available: {list(self._parameters.keys())[:10]}")
                    return "Parameters not loaded"
                try:
                    low_act = int(float(self._parameters['BATT_FS_LOW_ACT']['value']))
                    crt_act = int(float(self._parameters['BATT_FS_CRT_ACT']['value']))
                except (KeyError, ValueError) as e:
                    print(f"[DroneCommander] Error parsing values: {e}")
                    return "Error reading values"
                action_names = {0: "None", 1: "Land", 2: "RTL", 3: "SmartRTL", 4: "Terminate"}
                low_name = action_names.get(low_act, "Unknown")
                crt_name = action_names.get(crt_act, "Unknown")
                result = f"{low_name} on low, {crt_name} on critical"
                print(f"[DroneCommander] Battery FS: {result}")
                return result
        except Exception as e:
            print(f"[DroneCommander] ❌ Error getting battery FS status: {e}")
            import traceback
            traceback.print_exc()
            return "Error reading status"

    @pyqtSlot(result=str)
    def getRCFailSafeStatus(self):
        """Get RC failsafe status for UI display"""
        try:
            print("[DroneCommander] getRCFailSafeStatus() called")
            with self._param_lock:
                if 'FS_THR_ENABLE' not in self._parameters:
                    print(f"[DroneCommander] FS_THR_ENABLE not found. Available: {list(self._parameters.keys())[:10]}")
                    return "Parameters not loaded"
                try:
                    fs_thr = int(float(self._parameters['FS_THR_ENABLE']['value']))
                except (KeyError, ValueError) as e:
                    print(f"[DroneCommander] Error parsing value: {e}")
                    return "Error reading value"
                status_names = {
                    0: "Disabled",
                    1: "RTL on RC loss",
                    2: "Continue AUTO on RC loss",
                    3: "SmartRTL on RC loss",
                    4: "Land on RC loss"
                }
                result = status_names.get(fs_thr, "Unknown")
                print(f"[DroneCommander] RC FS: {result}")
                return result
        except Exception as e:
            print(f"[DroneCommander] ❌ Error getting RC FS status: {e}")
            import traceback
            traceback.print_exc()
            return "Error reading status"

    @pyqtSlot(result=bool)
    def configureAllFailSafes(self):
        """Configure all failsafe parameters to safe defaults."""
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Drone not connected")
            return False

        self.commandFeedback.emit("⚙️ Configuring failsafe parameters...")
        print("[DroneCommander] 🔧 Setting recommended failsafe configuration...")

        failsafe_params = {
            b'BATT_FS_LOW_ACT': (2,   mavutil.mavlink.MAV_PARAM_TYPE_INT8),
            b'BATT_FS_CRT_ACT': (1,   mavutil.mavlink.MAV_PARAM_TYPE_INT8),
            b'BATT_LOW_VOLT':   (10.5, mavutil.mavlink.MAV_PARAM_TYPE_REAL32),
            b'BATT_CRT_VOLT':   (10.0, mavutil.mavlink.MAV_PARAM_TYPE_REAL32),
            b'FS_THR_ENABLE':   (1,   mavutil.mavlink.MAV_PARAM_TYPE_INT8),
            b'FS_GCS_ENABLE':   (0,   mavutil.mavlink.MAV_PARAM_TYPE_INT8),
            b'FS_EKF_ACTION':   (1,   mavutil.mavlink.MAV_PARAM_TYPE_INT8),
            b'FS_EKF_THRESH':   (0.8, mavutil.mavlink.MAV_PARAM_TYPE_REAL32),
        }

        success_count = 0
        total_params = len(failsafe_params)

        for param_id, (value, param_type) in failsafe_params.items():
            param_name = param_id.decode('utf-8')
            if self._send_param_set(param_id, value, param_type, timeout=5.0):
                success_count += 1
                print(f"[DroneCommander]   ✓ {param_name} = {value}")
            else:
                print(f"[DroneCommander]   ✗ {param_name} failed")
            time.sleep(0.3)

        if success_count == total_params:
            msg = f"✅ All {total_params} failsafe parameters configured successfully"
            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
            return True
        elif success_count > 0:
            msg = f"⚠️ Partial success: {success_count}/{total_params} parameters set"
            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
            return False
        else:
            msg = "❌ Failed to configure failsafe parameters"
            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
            return False

    # ═══════════════════════════════════════════════════════════════════════
    # PARAMETER MANAGEMENT
    # ═══════════════════════════════════════════════════════════════════════

    @staticmethod
    def _make_param_entry(param_id, param_value, param_type, param_index, param_count):
        """Create standard parameter dictionary"""
        return {
            "name":        param_id,
            "value":       str(param_value),
            "type":        "FLOAT" if param_type in [9, 10] else "INT32",
            "index":       param_index,
            "count":       param_count,
            "synced":      True,
            "units":       "",
            "options":     "",
            "desc":        "",
            "range":       "",
            "default":     "",
            "description": "",
        }

    def _enrich_params(self, collected_params: dict):
        """Enrich parameters with metadata"""
        print("[DroneCommander] ⏳ Waiting for metadata loader...")
        loaded = self._param_metadata.wait_until_loaded(timeout=30.0)
        print(f"[DroneCommander] Metadata ready: {loaded}")

        self._param_metadata.enrich_parameters(collected_params)

        enriched_count = 0
        for data in collected_params.values():
            if data.get("description"):
                data["desc"] = data["description"]
                enriched_count += 1
            if data.get("range"):
                data["options"] = data["range"]

        print(f"[DroneCommander] ✅ Enriched {enriched_count} parameters")

    @pyqtSlot(result=bool)
    def requestAllParameters(self):
        """Request all parameters from drone"""
        if not self._is_drone_ready():
            return False
        if self._fetching_params:
            return False

        print("[DroneCommander] ✅ Starting parameter fetch")
        self._fetching_params = True
        self._param_request_active = True

        with self._param_lock:
            self._parameters.clear()

        while not self._param_queue.empty():
            try:
                self._param_queue.get_nowait()
            except queue.Empty:
                break

        for _ in range(3):
            self._drone.mav.param_request_list_send(
                self._drone.target_system,
                self._drone.target_component)
            time.sleep(0.1)

        t = threading.Thread(target=self._process_parameter_queue, daemon=True)
        t.start()
        
        # Reset progress bar to 0 initially
        self.parameterFetchProgress.emit(0, 1)

        self.commandFeedback.emit("Requesting parameters from drone...")
        return True

    def _process_parameter_queue(self):
        """Process parameter queue in background thread"""
        try:
            collected_params = {}
            total_params = None
            start_time = time.time()
            last_param_time = time.time()

            while time.time() - start_time < 60:
                try:
                    param_data = self._param_queue.get(timeout=0.5)

                    if param_data:
                        last_param_time = time.time()
                        param_id = param_data['name']

                        if total_params is None:
                            total_params = param_data['count']
                            print(f"[DroneCommander] 📊 Total: {total_params}")

                        if param_id not in collected_params:
                            collected_params[param_id] = self._make_param_entry(
                                param_id,
                                param_data['value'],
                                param_data['type'],
                                param_data['index'],
                                param_data['count'])
                                
                            if total_params:
                                self.parameterFetchProgress.emit(len(collected_params), total_params)

                            if len(collected_params) % 100 == 0:
                                pct = (len(collected_params) * 100 // total_params) if total_params else 0
                                print(f"[DroneCommander] 📥 {len(collected_params)}/{total_params} ({pct}%)")

                        if total_params and len(collected_params) >= total_params:
                            break

                except queue.Empty:
                    if time.time() - last_param_time > 3:
                        break

            if len(collected_params) > 0:
                try:
                    self._enrich_params(collected_params)
                except Exception as e:
                    print(f"[DroneCommander] ⚠️ Enrichment error: {e}")

                with self._param_lock:
                    self._parameters = collected_params

                self.parametersUpdated.emit()
                self.parameterFetchProgress.emit(len(collected_params), len(collected_params))
                self.commandFeedback.emit(f"✅ Loaded {len(collected_params)} parameters!")

        except Exception as e:
            print(f"[DroneCommander] ❌ Parameter fetch error: {e}")
        finally:
            self._fetching_params = False
            self._param_request_active = False

    def add_parameter_to_queue(self, param_msg):
        """Add parameter message to queue (non-blocking to protect MAVLink thread)"""
        if not self._param_request_active:
            return
        try:
            param_id = param_msg.param_id
            if isinstance(param_id, bytes):
                param_id = param_id.decode('utf-8').strip('\x00')

            # ✅ MERGED from Doc 4: use put_nowait so we never block the MAVLink
            # thread; drop the message silently if the queue is full.
            try:
                self._param_queue.put_nowait({
                    'name':  param_id,
                    'value': float(param_msg.param_value),
                    'type':  int(param_msg.param_type),
                    'index': int(param_msg.param_index),
                    'count': int(param_msg.param_count)
                })
            except queue.Full:
                pass  # Queue full — parameter will be re-requested if missing
        except Exception as e:
            print(f"[DroneCommander] ⚠️ Queue error: {e}")

    def _process_param_message(self, msg):
        """Update local parameter cache from a PARAM_VALUE MAVLink message."""
        try:
            param_id = msg.param_id
            if isinstance(param_id, bytes):
                param_id = param_id.decode('utf-8').strip('\x00')
            elif isinstance(param_id, str):
                param_id = param_id.strip('\x00')
            else:
                param_id = str(param_id).strip('\x00')

            param_value = float(msg.param_value)
            param_type  = int(msg.param_type)
            param_index = int(msg.param_index)
            param_count = int(msg.param_count)

            # ✅ MERGED from Doc 4: do NOT emit parameterReceived here — that
            # signal fires cross-thread on every PARAM_VALUE message and would
            # flood Qt's event queue during a full parameter download.
            with self._param_lock:
                if param_id in self._parameters:
                    self._parameters[param_id]['value'] = str(param_value)
                else:
                    self._parameters[param_id] = self._make_param_entry(
                        param_id, param_value, param_type, param_index, param_count)

        except Exception as e:
            print(f"[DroneCommander] ⚠️ Param process error: {e}")

    @pyqtProperty('QVariant', notify=parametersUpdated)
    def parameters(self):
        """Get all parameters"""
        with self._param_lock:
            return dict(self._parameters)

    @pyqtSlot(str, result=bool)
    def writeParameters(self, params_json):
        """
        Write multiple parameters to drone from JSON string.
        Called from QML when user clicks "Write" button.

        Args:
            params_json (str): JSON string like '{"PARAM_NAME": 123.45, "PARAM2": 67.89}'

        Returns:
            bool: True if all parameters written successfully
        """
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Drone not connected")
            return False

        try:
            import json

            params_dict = json.loads(params_json)

            if not params_dict:
                self.commandFeedback.emit("⚠️ No parameters to write")
                return False

            print(f"\n[DroneCommander] 📝 Writing {len(params_dict)} parameters to drone")
            print("=" * 60)

            success_count = 0
            failed_params = []

            for param_name, param_value in params_dict.items():
                print(f"[DroneCommander] 📤 Writing {param_name} = {param_value}")

                param_type = mavutil.mavlink.MAV_PARAM_TYPE_REAL32
                if param_name in self._parameters:
                    if self._parameters[param_name].get('type') == 'INT32':
                        param_type = mavutil.mavlink.MAV_PARAM_TYPE_INT32
                        param_value = int(float(param_value))
                    else:
                        param_value = float(param_value)
                else:
                    param_value = float(param_value)

                param_id_bytes = param_name.encode('utf-8')

                if self._send_param_set(param_id_bytes, param_value, param_type, timeout=5.0):
                    success_count += 1
                    print(f"[DroneCommander]   ✅ {param_name} confirmed")
                else:
                    failed_params.append(param_name)
                    print(f"[DroneCommander]   ❌ {param_name} failed")

                time.sleep(0.2)

            print("=" * 60)
            total = len(params_dict)

            if success_count == total:
                msg = f"✅ All {total} parameters written successfully!"
                self.commandFeedback.emit(msg)
                print(f"[DroneCommander] {msg}")
                self.parametersUpdated.emit()
                return True

            elif success_count > 0:
                msg = f"⚠️ Partial success: {success_count}/{total} parameters written"
                if failed_params:
                    msg += f"\nFailed: {', '.join(failed_params[:3])}"
                    if len(failed_params) > 3:
                        msg += f" (+{len(failed_params)-3} more)"
                self.commandFeedback.emit(msg)
                print(f"[DroneCommander] {msg}")
                self.parametersUpdated.emit()
                return False

            else:
                msg = "❌ Failed to write parameters to drone"
                self.commandFeedback.emit(msg)
                print(f"[DroneCommander] {msg}")
                return False

        except json.JSONDecodeError as e:
            error_msg = f"❌ Invalid JSON format: {e}"
            self.commandFeedback.emit(error_msg)
            print(f"[DroneCommander] {error_msg}")
            return False

        except Exception as e:
            error_msg = f"❌ Error writing parameters: {e}"
            self.commandFeedback.emit(error_msg)
            print(f"[DroneCommander] {error_msg}")
            import traceback
            traceback.print_exc()
            return False

    @pyqtSlot(str, float, result=bool)
    def setParameter(self, param_id, param_value):
        """Set single parameter using the shared _send_param_set helper"""
        # ✅ MERGED from Doc 4: cleaner implementation reusing _send_param_set
        if not self._is_drone_ready():
            return False
        try:
            param_id_bytes = param_id.encode('utf-8')
            param_type = mavutil.mavlink.MAV_PARAM_TYPE_REAL32
            if param_id in self._parameters:
                if self._parameters[param_id].get('type') == 'INT32':
                    param_type = mavutil.mavlink.MAV_PARAM_TYPE_INT32
                    param_value = int(param_value)
            return self._send_param_set(param_id_bytes, param_value, param_type, timeout=3.0)
        except Exception as e:
            self.commandFeedback.emit(f"Error setting parameter: {e}")
            return False

    @pyqtSlot(bool, int, int, int, int, result=bool)
    def setGeoFence(self, enabled, fence_type, fence_action, max_altitude, max_radius):
        """
        Configure geofence parameters on the drone.

        Args:
            enabled (bool): Enable/disable geofence
            fence_type (int): 0=Alt+Circle, 1=Alt Only, 2=Circle Only
            fence_action (int): 0=RTL, 1=Land
            max_altitude (int): Maximum altitude in meters
            max_radius (int): Maximum radius in meters

        Returns:
            bool: True if all parameters set successfully
        """
        if not self._is_drone_ready():
            self.commandFeedback.emit("❌ Cannot set geofence: Drone not connected")
            return False

        print(f"[DroneCommander] 🛡️ Configuring GeoFence:")
        print(f"                  Enabled: {enabled}")
        print(f"                  Type: {fence_type}")
        print(f"                  Action: {fence_action}")
        print(f"                  Max Alt: {max_altitude}m")
        print(f"                  Max Radius: {max_radius}m")

        fence_type_map   = {0: 3, 1: 1, 2: 2}
        fence_action_map = {0: 1, 1: 2}

        if fence_type not in fence_type_map:
            self.commandFeedback.emit(f"❌ Invalid fence type: {fence_type}")
            return False
        if fence_action not in fence_action_map:
            self.commandFeedback.emit(f"❌ Invalid fence action: {fence_action}")
            return False

        fence_enable_value = 1 if enabled else 0
        fence_type_value   = fence_type_map[fence_type]
        fence_action_value = fence_action_map[fence_action]

        geofence_params = {
            b'FENCE_ENABLE':  (fence_enable_value,    mavutil.mavlink.MAV_PARAM_TYPE_INT8),
            b'FENCE_TYPE':    (fence_type_value,       mavutil.mavlink.MAV_PARAM_TYPE_INT8),
            b'FENCE_ACTION':  (fence_action_value,     mavutil.mavlink.MAV_PARAM_TYPE_INT8),
            b'FENCE_ALT_MAX': (float(max_altitude),    mavutil.mavlink.MAV_PARAM_TYPE_REAL32),
            b'FENCE_RADIUS':  (float(max_radius),      mavutil.mavlink.MAV_PARAM_TYPE_REAL32),
        }

        self.commandFeedback.emit("⚙️ Configuring geofence parameters...")
        success_count = 0
        failed_params = []

        for param_id, (value, param_type) in geofence_params.items():
            param_name = param_id.decode('utf-8')
            print(f"[DroneCommander] 📤 Setting {param_name} = {value}")
            if self._send_param_set(param_id, value, param_type, timeout=5.0):
                success_count += 1
                print(f"[DroneCommander]   ✅ {param_name} confirmed")
            else:
                failed_params.append(param_name)
                print(f"[DroneCommander]   ❌ {param_name} failed")
            time.sleep(0.2)

        total_params = len(geofence_params)
        if success_count == total_params:
            status = "enabled" if enabled else "disabled"
            type_names   = {0: "Alt+Circle", 1: "Alt Only", 2: "Circle Only"}
            action_names = {0: "RTL", 1: "Land"}
            msg = f"✅ GeoFence {status}: {type_names[fence_type]}, {action_names[fence_action]}, {max_altitude}m, {max_radius}m"
            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
            return True
        elif success_count > 0:
            msg = f"⚠️ Partial success: {success_count}/{total_params} geofence parameters set"
            if failed_params:
                msg += f"\nFailed: {', '.join(failed_params)}"
            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
            return False
        else:
            msg = "❌ Failed to configure geofence parameters"
            self.commandFeedback.emit(msg)
            print(f"[DroneCommander] {msg}")
            return False

    # ═══════════════════════════════════════════════════════════════════════
    # GIMBAL CONTROL
    # ═══════════════════════════════════════════════════════════════════════

    @pyqtSlot(float, float, float, result=bool)
    def setGimbalAngle(self, pitch: float, yaw: float, roll: float) -> bool:
        """
        Point the gimbal to the given angles (degrees).
        Uses MAV_CMD_DO_MOUNT_CONTROL (205).

        Args:
            pitch:  -90 (down) to +30 (up)
            yaw:   -180 to +180
            roll:   -30 to +30
        """
        print(f"[DroneCommander] 🎯 Gimbal: pitch={pitch:.1f}° yaw={yaw:.1f}° roll={roll:.1f}°")

        if not self._is_drone_ready():
            print("[DroneCommander] ⚠️ Gimbal command skipped — drone not connected")
            return False

        try:
            self._drone.mav.command_long_send(
                self._drone.target_system,
                self._drone.target_component,
                mavutil.mavlink.MAV_CMD_DO_MOUNT_CONTROL,  # 205
                0,
                pitch,
                roll,
                yaw,
                0, 0, 0,
                2   # MAV_MOUNT_MODE_MAVLINK_TARGETING
            )
            self.commandFeedback.emit(
                f"🎯 Gimbal → P:{pitch:.0f}° Y:{yaw:.0f}° R:{roll:.0f}°")
            return True
        except Exception as e:
            print(f"[DroneCommander] ❌ setGimbalAngle error: {e}")
            return False

    @pyqtSlot(result=bool)
    def centerGimbal(self) -> bool:
        """Reset the gimbal to straight-forward (0 / 0 / 0 degrees)."""
        print("[DroneCommander] ⊙ Centering gimbal")
        return self.setGimbalAngle(0.0, 0.0, 0.0)