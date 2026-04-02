"""
TFlySimulator v2.0 — Native Simulation Engine for TihanFly GCS
===============================================================
Completely MAVLink-independent. Acts as a drop-in "drone connection"
by calling DroneModel.connectSimulator() instead of connectToDrone().

Connection flow (mirrors real drone connection):
    User clicks "CONNECT SIM"
        → simulator.connectSim()
            → DroneModel._on_sim_connection_success()   (marks isConnected=True)
            → 20 Hz physics loop starts
            → DroneModel.telemetryChanged fires every 50 ms
            → QML HUD, map, telemetry panels all update normally

Every command (takeoff, land, set_mode, RTL) is a pyqtSlot so QML
can call simulator.takeoff(30) directly from any button.
"""

import math
from enum import Enum, auto
from PyQt5.QtCore import QObject, QTimer, pyqtSignal, pyqtSlot, pyqtProperty


# ═══════════════════════════════════════════════════════════════════════════════
# FLIGHT MODES
# ═══════════════════════════════════════════════════════════════════════════════

class SimMode(Enum):
    READY    = auto()   # On ground, disarmed
    TAKEOFF  = auto()   # Climbing to target altitude
    LOITER   = auto()   # Hovering in place
    FORWARD  = auto()   # Flying forward on heading
    RTL      = auto()   # Returning to home
    LAND     = auto()   # Descending to ground


# ═══════════════════════════════════════════════════════════════════════════════
# PHYSICS CONSTANTS  (all tuneable)
# ═══════════════════════════════════════════════════════════════════════════════

EARTH_RADIUS_M        = 6_371_000.0
DT                    = 0.05        # seconds per tick  (20 Hz)

DEFAULT_TAKEOFF_ALT   = 30.0        # metres
MAX_ALTITUDE          = 120.0       # metres — hard ceiling

FORWARD_TARGET_SPEED  = 8.0         # m/s cruise
RTL_TARGET_SPEED      = 6.0         # m/s RTL cruise
SPEED_ACCEL           = 1.5         # m/s² acceleration
SPEED_DECEL           = 2.0         # m/s² deceleration

TAKEOFF_CLIMB_RATE    = 2.5         # m/s upward
LAND_DESCENT_RATE     = 1.2         # m/s downward
YAW_RATE_DEG_S        = 45.0        # deg/s max yaw rotation

BATTERY_DRAIN_IDLE    = 0.005       # %/s on ground
BATTERY_DRAIN_HOVER   = 0.020       # %/s hovering
BATTERY_DRAIN_CRUISE  = 0.030       # %/s forward/RTL
BATTERY_DRAIN_CLIMB   = 0.040       # %/s takeoff/land

RTL_ARRIVAL_RADIUS_M  = 3.0         # metres — snap to home within this
LAND_THRESHOLD_M      = 0.15        # metres — call it "landed"


# ═══════════════════════════════════════════════════════════════════════════════
# GEO HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

def _move_latlon(lat, lon, heading_deg, dist_m):
    """Flat-earth position integration. Accurate ±1 m over 1 km."""
    h = math.radians(heading_deg)
    dn = math.cos(h) * dist_m
    de = math.sin(h) * dist_m
    dlat = dn / EARTH_RADIUS_M * (180 / math.pi)
    dlon = de / (EARTH_RADIUS_M * math.cos(math.radians(lat))) * (180 / math.pi)
    return lat + dlat, lon + dlon


def _bearing(lat1, lon1, lat2, lon2):
    """Great-circle bearing from A to B, degrees [0, 360)."""
    r1, r2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    x = math.sin(dl) * math.cos(r2)
    y = math.cos(r1) * math.sin(r2) - math.sin(r1) * math.cos(r2) * math.cos(dl)
    return (math.degrees(math.atan2(x, y)) + 360) % 360


def _haversine(lat1, lon1, lat2, lon2):
    """Distance in metres between two GPS points."""
    R = EARTH_RADIUS_M
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R * math.asin(math.sqrt(max(0, a)))


def _smooth_yaw(cur, tgt, rate, dt):
    """Rotate cur toward tgt at max rate deg/s, shortest path."""
    diff = (tgt - cur + 180) % 360 - 180
    step = rate * dt
    if abs(diff) <= step:
        return float(tgt) % 360
    return (cur + math.copysign(step, diff)) % 360


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN CLASS
# ═══════════════════════════════════════════════════════════════════════════════

class TFlySimulator(QObject):
    """
    TihanFly native simulation engine.

    HOW TO CONNECT (replaces typing udp:127.0.0.1:14550):
    -------------------------------------------------------
    In QML:   simulator.connectSim()
    In Python: simulator.connectSim()

    That single call:
      1. Marks DroneModel as connected (isConnected → True)
      2. Starts the 20 Hz physics loop
      3. Fires telemetryChanged every 50 ms so every QML panel updates

    HOW TO COMMAND (same slots called by your existing QML buttons):
    ----------------------------------------------------------------
    simulator.takeoff(30.0)          → climb to 30 m
    simulator.land()                 → descend and land
    simulator.set_mode("FORWARD")    → fly forward
    simulator.set_mode("LOITER")     → hover
    simulator.set_mode("RTL")        → return to home
    simulator.set_heading(90.0)      → turn East
    simulator.disconnectSim()        → stop & reset (like disconnect button)
    """

    # ── Signals ───────────────────────────────────────────────────────
    simConnected    = pyqtSignal()          # fired when connectSim() succeeds
    simDisconnected = pyqtSignal()          # fired when disconnectSim() called
    modeChanged     = pyqtSignal(str)       # new mode name string
    telemetryUpdated = pyqtSignal(dict)     # every physics tick

    def __init__(self, drone_model, home_lat=17.4486, home_lon=78.3908, parent=None):
        super().__init__(parent)

        self._dm         = drone_model      # DroneModel reference
        self._home_lat   = home_lat
        self._home_lon   = home_lon

        # ── Physics state ─────────────────────────────────────────────
        self._lat          = home_lat
        self._lon          = home_lon
        self._rel_alt      = 0.0
        self._yaw          = 0.0
        self._target_yaw   = 0.0
        self._groundspeed  = 0.0
        self._target_speed = 0.0
        self._climb_rate   = 0.0
        self._battery      = 100.0
        self._armed        = False
        self._target_alt   = DEFAULT_TAKEOFF_ALT
        self._mode         = SimMode.READY
        self._sim_connected = False

        # ── 20 Hz timer ───────────────────────────────────────────────
        self._timer = QTimer(self)
        self._timer.setInterval(int(DT * 1000))   # 50 ms
        self._timer.timeout.connect(self._tick)

        print(f"[TFlySimulator] Ready — home ({home_lat:.4f}, {home_lon:.4f})")
        print(f"[TFlySimulator] Call simulator.connectSim() to start")

    # ═══════════════════════════════════════════════════════════════════
    # CONNECTION API  ← This is the "address" replacement
    # ═══════════════════════════════════════════════════════════════════

    @pyqtSlot()
    def connectSim(self):
        """
        THE CONNECTION ENTRY POINT — replaces typing udp:127.0.0.1:14550.

        Call this from the "Connect" button in your UI.
        Marks DroneModel as connected and starts the physics loop.
        Everything downstream (HUD, map, telemetry panels) updates
        automatically because we use the exact same DroneModel signals.
        """
        if self._sim_connected:
            print("[TFlySimulator] Already connected — ignoring connectSim()")
            return

        print("[TFlySimulator] ● Connecting simulator...")
        self._sim_connected = True

        # Reset to clean state
        self._reset_state()

        # Tell DroneModel we are "connected" — this fires droneConnectedChanged
        # which unlocks the HUD, map, and all flight control buttons in QML.
        try:
            self._dm._on_sim_connection_success()
        except AttributeError:
            # Fallback if patch hasn't been applied yet
            self._dm._is_connected = True
            self._dm._has_received_gps = True
            self._dm.droneConnectedChanged.emit()
            self._dm.addStatusText("🟢 [SIM] TFlySimulator connected")

        # Start physics
        self._timer.start()
        self.simConnected.emit()
        print("[TFlySimulator] ✅ Simulator connected — physics loop running at 20 Hz")

    @pyqtSlot()
    def disconnectSim(self):
        """
        Stop the simulator and tell DroneModel we are disconnected.
        Mirrors what the real disconnect button does.
        """
        if not self._sim_connected:
            return

        print("[TFlySimulator] ● Disconnecting simulator...")
        self._timer.stop()
        self._sim_connected = False
        self._reset_state()

        # Fire the same cleanup path real disconnection uses
        try:
            self._dm._is_connected = False
            self._dm._has_received_gps = False
            self._dm.droneConnectedChanged.emit()
            self._dm.addStatusText("🔌 [SIM] TFlySimulator disconnected")
        except Exception as e:
            print(f"[TFlySimulator] Disconnect cleanup error: {e}")

        self.simDisconnected.emit()
        print("[TFlySimulator] ✅ Simulator disconnected")

    # ═══════════════════════════════════════════════════════════════════
    # FLIGHT COMMAND API  ← Called by QML buttons
    # ═══════════════════════════════════════════════════════════════════

    @pyqtSlot(float)
    def takeoff(self, target_altitude: float = DEFAULT_TAKEOFF_ALT):
        """Arm and climb to target_altitude metres. Only from READY."""
        if not self._sim_connected:
            print("[TFlySimulator] takeoff() ignored — not connected")
            return
        if self._mode is not SimMode.READY:
            print(f"[TFlySimulator] takeoff() ignored — in {self._mode.name}, not READY")
            return

        self._target_alt   = max(1.0, min(float(target_altitude), MAX_ALTITUDE))
        self._armed        = True
        self._target_speed = 0.0
        self._target_yaw   = self._yaw
        self._set_mode(SimMode.TAKEOFF)
        self._dm.addStatusText(f"🚁 [SIM] Takeoff → {self._target_alt:.0f} m")
        print(f"[TFlySimulator] Takeoff → {self._target_alt:.1f} m")

    @pyqtSlot()
    def land(self):
        """Descend and land from any airborne mode."""
        if not self._sim_connected:
            return
        if self._mode in (SimMode.READY, SimMode.LAND):
            return
        self._target_speed = 0.0
        self._set_mode(SimMode.LAND)
        self._dm.addStatusText("🛬 [SIM] Landing")
        print("[TFlySimulator] Landing initiated")

    @pyqtSlot(str)
    def set_mode(self, mode_name: str):
        """
        Switch flight mode by name.
        Valid:  LOITER | FORWARD | RTL | LAND
        """
        if not self._sim_connected:
            return

        _map = {
            "LOITER":  SimMode.LOITER,
            "FORWARD": SimMode.FORWARD,
            "RTL":     SimMode.RTL,
            "LAND":    SimMode.LAND,
        }
        new_mode = _map.get(mode_name.upper())
        if new_mode is None:
            print(f"[TFlySimulator] Unknown mode '{mode_name}'")
            return
        if self._mode is SimMode.READY:
            print(f"[TFlySimulator] Cannot enter {mode_name} — call takeoff() first")
            return

        if new_mode is SimMode.RTL:
            self._target_yaw   = _bearing(self._lat, self._lon,
                                           self._home_lat, self._home_lon)
            self._target_speed = RTL_TARGET_SPEED
        elif new_mode is SimMode.FORWARD:
            self._target_speed = FORWARD_TARGET_SPEED
        elif new_mode is SimMode.LOITER:
            self._target_speed = 0.0
        elif new_mode is SimMode.LAND:
            self._target_speed = 0.0

        self._set_mode(new_mode)
        self._dm.addStatusText(f"🔄 [SIM] Mode → {mode_name}")

    @pyqtSlot(float)
    def set_heading(self, heading_deg: float):
        """Set target yaw. Drone rotates smoothly toward it."""
        self._target_yaw = float(heading_deg) % 360.0

    @pyqtSlot(float)
    def set_speed(self, speed_ms: float):
        """Override target ground speed (m/s), clamped 0-25."""
        self._target_speed = max(0.0, min(float(speed_ms), 25.0))

    @pyqtSlot()
    def rtl(self):
        """Shortcut for set_mode('RTL') — easier to call from QML."""
        self.set_mode("RTL")

    @pyqtSlot()
    def loiter(self):
        """Shortcut for set_mode('LOITER')."""
        self.set_mode("LOITER")

    @pyqtSlot()
    def flyForward(self):
        """Shortcut for set_mode('FORWARD')."""
        self.set_mode("FORWARD")

    # ═══════════════════════════════════════════════════════════════════
    # QML-READABLE PROPERTIES
    # ═══════════════════════════════════════════════════════════════════

    @pyqtProperty(str, notify=modeChanged)
    def mode(self) -> str:
        return self._mode.name

    @pyqtProperty(bool, notify=simConnected)
    def isConnected(self) -> bool:
        return self._sim_connected

    @pyqtProperty(bool)
    def isArmed(self) -> bool:
        return self._armed

    @pyqtProperty(float)
    def battery(self) -> float:
        return round(self._battery, 1)

    @pyqtProperty(float)
    def altitude(self) -> float:
        return round(self._rel_alt, 1)

    @pyqtProperty(float)
    def groundspeed(self) -> float:
        return round(self._groundspeed, 2)

    @pyqtProperty(float)
    def heading(self) -> float:
        return round(self._yaw, 1)

    # ═══════════════════════════════════════════════════════════════════
    # INTERNAL — STATE MANAGEMENT
    # ═══════════════════════════════════════════════════════════════════

    def _set_mode(self, m: SimMode):
        self._mode = m
        self.modeChanged.emit(m.name)

    def _reset_state(self):
        self._lat          = self._home_lat
        self._lon          = self._home_lon
        self._rel_alt      = 0.0
        self._yaw          = 0.0
        self._target_yaw   = 0.0
        self._groundspeed  = 0.0
        self._target_speed = 0.0
        self._climb_rate   = 0.0
        self._battery      = 100.0
        self._armed        = False
        self._target_alt   = DEFAULT_TAKEOFF_ALT
        self._set_mode(SimMode.READY)

    # ═══════════════════════════════════════════════════════════════════
    # 20 Hz PHYSICS TICK
    # ═══════════════════════════════════════════════════════════════════

    def _tick(self):
        try:
            # Mode dispatch
            {
                SimMode.READY:   self._tick_ready,
                SimMode.TAKEOFF: self._tick_takeoff,
                SimMode.LOITER:  self._tick_loiter,
                SimMode.FORWARD: self._tick_forward,
                SimMode.RTL:     self._tick_rtl,
                SimMode.LAND:    self._tick_land,
            }[self._mode]()

            self._drain_battery()
            self._rel_alt = max(0.0, min(self._rel_alt, MAX_ALTITUDE))

            data = self._build_telemetry()
            self._push(data)
            self.telemetryUpdated.emit(data)

        except Exception as e:
            import traceback
            print(f"[TFlySimulator] Tick error: {e}")
            traceback.print_exc()

    def _tick_ready(self):
        self._groundspeed = 0.0
        self._climb_rate  = 0.0

    def _tick_takeoff(self):
        rem = self._target_alt - self._rel_alt
        if rem > 0.05:
            rise             = min(TAKEOFF_CLIMB_RATE * DT, rem)
            self._rel_alt   += rise
            self._climb_rate = rise / DT
        else:
            self._rel_alt    = self._target_alt
            self._climb_rate = 0.0
            self._set_mode(SimMode.LOITER)
            self._dm.addStatusText(f"✅ [SIM] Takeoff complete — LOITER at {self._rel_alt:.1f} m")
        self._groundspeed = 0.0

    def _tick_loiter(self):
        self._groundspeed = self._ramp(self._groundspeed, 0.0)
        self._climb_rate  = 0.0

    def _tick_forward(self):
        self._yaw         = _smooth_yaw(self._yaw, self._target_yaw, YAW_RATE_DEG_S, DT)
        self._groundspeed = self._ramp(self._groundspeed, self._target_speed)
        if self._groundspeed > 1e-3:
            self._lat, self._lon = _move_latlon(
                self._lat, self._lon, self._yaw, self._groundspeed * DT)
        self._climb_rate = 0.0

    def _tick_rtl(self):
        dist = _haversine(self._lat, self._lon, self._home_lat, self._home_lon)
        if dist > RTL_ARRIVAL_RADIUS_M:
            self._target_yaw  = _bearing(self._lat, self._lon,
                                          self._home_lat, self._home_lon)
            self._yaw         = _smooth_yaw(self._yaw, self._target_yaw, YAW_RATE_DEG_S, DT)
            self._groundspeed = self._ramp(self._groundspeed, RTL_TARGET_SPEED)
            self._lat, self._lon = _move_latlon(
                self._lat, self._lon, self._yaw, self._groundspeed * DT)
        else:
            self._groundspeed = 0.0
            self._lat         = self._home_lat
            self._lon         = self._home_lon
            self._set_mode(SimMode.LAND)
            self._dm.addStatusText("🏠 [SIM] RTL arrived — landing")
        self._climb_rate = 0.0

    def _tick_land(self):
        if self._rel_alt > LAND_THRESHOLD_M:
            drop             = min(LAND_DESCENT_RATE * DT, self._rel_alt)
            self._rel_alt   -= drop
            self._climb_rate = -(drop / DT)
            self._groundspeed = self._ramp(self._groundspeed, 0.0)
        else:
            self._rel_alt     = 0.0
            self._climb_rate  = 0.0
            self._groundspeed = 0.0
            self._armed       = False
            self._set_mode(SimMode.READY)
            self._dm.addStatusText("🟢 [SIM] Landed — READY")

    def _ramp(self, cur, tgt):
        if cur < tgt:
            return min(cur + SPEED_ACCEL * DT, tgt)
        elif cur > tgt:
            return max(cur - SPEED_DECEL * DT, tgt)
        return cur

    def _drain_battery(self):
        drain = {
            SimMode.READY:   BATTERY_DRAIN_IDLE,
            SimMode.LOITER:  BATTERY_DRAIN_HOVER,
            SimMode.FORWARD: BATTERY_DRAIN_CRUISE,
            SimMode.RTL:     BATTERY_DRAIN_CRUISE,
            SimMode.TAKEOFF: BATTERY_DRAIN_CLIMB,
            SimMode.LAND:    BATTERY_DRAIN_CLIMB,
        }.get(self._mode, BATTERY_DRAIN_HOVER)
        self._battery = max(0.0, self._battery - drain * DT)

    def _build_telemetry(self) -> dict:
        return {
            "lat":                round(self._lat, 7),
            "lon":                round(self._lon, 7),
            "alt":                round(500.0 + self._rel_alt, 2),
            "rel_alt":            round(self._rel_alt, 2),
            "roll":               0.0,
            "pitch":              0.0,
            "yaw":                round(self._yaw, 1),
            "heading":            round(self._yaw, 1),
            "groundspeed":        round(self._groundspeed, 2),
            "airspeed":           round(self._groundspeed, 2),
            "climb_rate":         round(self._climb_rate, 2),
            "battery_remaining":  round(self._battery, 1),
            "voltage_battery":    round((self._battery / 100.0) * 12.6, 2),
            "mode":               self._mode.name,
            "armed":              self._armed,
            "safety_armed":       self._armed,
            "gps_status":         3,
            "gps_fix_type":       3,
            "satellites_visible": 14,
            "ekf_ok":             True,
            "vibration_x":        0.0,
            "vibration_y":        0.0,
            "vibration_z":        0.0,
        }

    def _push(self, data: dict):
        try:
            self._dm.updateTelemetry(data)
        except Exception as e:
            print(f"[TFlySimulator] Push error: {e}")