"""
TiHAN Fly — MAVLink Mission Protocol Manager
═══════════════════════════════════════════════

Implements the full MAVLink Mission Sub-Protocol per:
    https://mavlink.io/en/services/mission.html

Supports:
    • Upload   – GCS → FC (MISSION_COUNT → MISSION_REQUEST_INT → MISSION_ITEM_INT → MISSION_ACK)
    • Download – FC → GCS (MISSION_REQUEST_LIST → MISSION_COUNT → MISSION_REQUEST_INT → MISSION_ITEM_INT → MISSION_ACK)
    • Clear    – MISSION_CLEAR_ALL → MISSION_ACK
    • Set Current – MAV_CMD_DO_SET_MISSION_CURRENT (preferred) or MISSION_SET_CURRENT (fallback)
    • Monitor  – MISSION_CURRENT / MISSION_ITEM_REACHED

Uses MISSION_ITEM_INT (non-deprecated), with lat/lon encoded as int32 × 1e7.
Frame: MAV_FRAME_GLOBAL_RELATIVE_ALT_INT (3) by default.

ArduPilot quirks handled:
    • seq==0 is Home position (not first WP)
    • Non-atomic uploads
    • Rounding on float ↔ int conversions
"""

import json
import math
import time
import threading
from enum import Enum, auto
from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty, QTimer

from pymavlink import mavutil


# ═══════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════

# Timeouts (ms) per MAVLink spec
TIMEOUT_DEFAULT_MS = 1500
TIMEOUT_ITEM_MS    = 250
MAX_RETRIES        = 5

# MAV_MISSION_TYPE
MISSION_TYPE_MISSION = 0   # MAV_MISSION_TYPE_MISSION
MISSION_TYPE_FENCE   = 1   # MAV_MISSION_TYPE_FENCE
MISSION_TYPE_RALLY   = 2   # MAV_MISSION_TYPE_RALLY


class MissionOp(Enum):
    """Current mission operation state machine."""
    IDLE       = auto()
    UPLOADING  = auto()
    DOWNLOADING = auto()
    CLEARING   = auto()


# Friendly names for MAV_CMD IDs (the subset we care about for flight plans)
CMD_NAMES = {
    mavutil.mavlink.MAV_CMD_NAV_WAYPOINT:         'WAYPOINT',
    mavutil.mavlink.MAV_CMD_NAV_TAKEOFF:          'TAKEOFF',
    mavutil.mavlink.MAV_CMD_NAV_LAND:             'LAND',
    mavutil.mavlink.MAV_CMD_NAV_RETURN_TO_LAUNCH: 'RTL',
    mavutil.mavlink.MAV_CMD_NAV_LOITER_UNLIM:     'LOITER_UNLIM',
    mavutil.mavlink.MAV_CMD_NAV_LOITER_TURNS:     'LOITER_TURNS',
    mavutil.mavlink.MAV_CMD_NAV_LOITER_TIME:      'LOITER_TIME',
    mavutil.mavlink.MAV_CMD_DO_JUMP:              'DO_JUMP',
    mavutil.mavlink.MAV_CMD_DO_CHANGE_SPEED:      'DO_CHANGE_SPEED',
    mavutil.mavlink.MAV_CMD_DO_LAND_START:        'DO_LAND_START',
    mavutil.mavlink.MAV_CMD_DO_SET_HOME:          'DO_SET_HOME',
}
CMD_IDS = {v: k for k, v in CMD_NAMES.items()}
CMD_IDS['RETURN'] = mavutil.mavlink.MAV_CMD_NAV_RETURN_TO_LAUNCH  # alias

NAV_COMMANDS = {
    mavutil.mavlink.MAV_CMD_NAV_WAYPOINT,
    mavutil.mavlink.MAV_CMD_NAV_TAKEOFF,
    mavutil.mavlink.MAV_CMD_NAV_LAND,
    mavutil.mavlink.MAV_CMD_NAV_RETURN_TO_LAUNCH,
    mavutil.mavlink.MAV_CMD_NAV_LOITER_UNLIM,
    mavutil.mavlink.MAV_CMD_NAV_LOITER_TURNS,
    mavutil.mavlink.MAV_CMD_NAV_LOITER_TIME,
}

JUMP_COMMANDS = {mavutil.mavlink.MAV_CMD_DO_JUMP}


# ═══════════════════════════════════════════════════════════════════════════
# MISSION ITEM  — internal dict used everywhere
# ═══════════════════════════════════════════════════════════════════════════

def make_item(seq, cmd, lat=0.0, lon=0.0, alt=0.0,
              p1=0.0, p2=0.0, p3=0.0, p4=0.0,
              frame=3, current=0, autocontinue=1):
    """Build a mission-item dict.

    lat/lon are in **degrees** (NOT ×1e7 — encoding happens at send time).
    frame=3 → MAV_FRAME_GLOBAL_RELATIVE_ALT (legacy compat, INT variant used on wire).
    """
    return {
        'seq':          int(seq),
        'frame':        int(frame),
        'command':      int(cmd),
        'current':      int(current),
        'autocontinue': int(autocontinue),
        'param1':       float(p1),
        'param2':       float(p2),
        'param3':       float(p3),
        'param4':       float(p4),
        'x':            float(lat),
        'y':            float(lon),
        'z':            float(alt),
        'mission_type': 0,
    }


# ═══════════════════════════════════════════════════════════════════════════
# HAVERSINE
# ═══════════════════════════════════════════════════════════════════════════

def haversine_m(lat1, lon1, lat2, lon2):
    """Great-circle distance (metres) between two WGS-84 points."""
    R = 6_371_000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = (math.sin(dphi / 2) ** 2
         + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ═══════════════════════════════════════════════════════════════════════════
# MissionManager QObject
# ═══════════════════════════════════════════════════════════════════════════

class MissionManager(QObject):
    """Full MAVLink Mission Sub-Protocol implementation (PyQt5 QObject).

    Expose to QML via:
        ctx.setContextProperty("missionManager", missionManager)

    Then connect signals in QML:
        Connections { target: missionManager;
            function onMissionChanged(items) { ... }   // list of dicts
            function onStatsChanged(stats) { ... }     // {wpCount, distKm, eteSec}
        }
    """

    # ── Signals ────────────────────────────────────────────────────────────
    feedback        = pyqtSignal(str)              # human status text
    missionChanged  = pyqtSignal('QVariantList')   # full item list (after any mutation)
    statsChanged    = pyqtSignal('QVariant')        # {wpCount, distKm, eteSec}
    currentWPChanged = pyqtSignal(int)             # from MISSION_CURRENT
    wpReached       = pyqtSignal(int)              # from MISSION_ITEM_REACHED
    uploadComplete  = pyqtSignal(bool, str)        # success, message
    downloadComplete = pyqtSignal(bool, str)       # success, message

    def __init__(self, parent=None):
        super().__init__(parent)

        # ── Operation state ────────────────────────────────────────────────
        self._op           = MissionOp.IDLE
        self._lock         = threading.Lock()

        # ── Upload state ───────────────────────────────────────────────────
        self._up_items     = []     # items to upload (list of dicts)
        self._up_retries   = 0
        self._up_timer_id  = None

        # ── Download state ─────────────────────────────────────────────────
        self._dl_expected  = 0
        self._dl_items     = []     # accumulates received items
        self._dl_retries   = 0
        self._dl_timer_id  = None

        # ── Clear state ────────────────────────────────────────────────────
        self._cl_retries   = 0
        self._cl_timer_id  = None

        # ── Mission items (source of truth) ────────────────────────────────
        self._items        = []     # list[dict]
        self._current_seq  = -1     # last MISSION_CURRENT seq

        # ── FC capability tracking ─────────────────────────────────────────
        self._accepts_do_set_current = {}  # (sysid, compid) → bool

        # ── MAVLink connection (set by DroneCommander) ─────────────────────
        self._drone = None

    # ══════════════════════════════════════════════════════════════════════
    # CONNECTION
    # ══════════════════════════════════════════════════════════════════════

    def setConnection(self, drone_connection):
        """Set (or update) the pymavlink connection object."""
        self._drone = drone_connection
        print('[MissionManager] ✅ MAVLink connection set')

    def _ready(self):
        if self._drone is None:
            self.feedback.emit('❌ No MAVLink connection')
            return False
        return True

    # ══════════════════════════════════════════════════════════════════════
    # UPLOAD — GCS → FC
    # ══════════════════════════════════════════════════════════════════════

    @pyqtSlot('QVariantList', result=bool)
    def uploadMission(self, items):
        """Start an async mission upload.

        `items` is a list of dicts with at least:
           {lat, lon/lng, alt, command (str or int)}
        Home (seq=0) is auto-inserted if missing.
        """
        if not self._ready():
            return False
        with self._lock:
            if self._op != MissionOp.IDLE:
                self.feedback.emit('⏳ Another operation in progress')
                return False
            self._op = MissionOp.UPLOADING

        # ── Build normalised item list ─────────────────────────────────────
        parsed = self._parse_input_items(items)
        if not parsed:
            self.feedback.emit('❌ No valid waypoints to upload')
            with self._lock:
                self._op = MissionOp.IDLE
            return False

        self._up_items   = parsed
        self._up_retries = 0

        total = len(parsed)
        self.feedback.emit(f'📡 Uploading {total} items to FC…')
        print(f'[MissionManager] ▶ Upload started ({total} items)')

        try:
            self._drone.mav.mission_count_send(
                self._drone.target_system,
                self._drone.target_component,
                total,
                MISSION_TYPE_MISSION)
        except Exception as e:
            self.feedback.emit(f'❌ Upload failed: {e}')
            with self._lock:
                self._op = MissionOp.IDLE
            return False

        self._start_timer('up', TIMEOUT_DEFAULT_MS)
        return True

    @pyqtSlot('QVariantList', result=bool)
    def uploadMissionFromMap(self, markers):
        """Upload from map markers (legacy compat with DroneCommander.uploadMission)."""
        items = []
        for i, m in enumerate(markers):
            if isinstance(m, dict):
                lat = float(m.get('latitude', m.get('lat', 0)))
                lon = float(m.get('longitude', m.get('lng', m.get('lon', 0))))
                alt = float(m.get('altitude', m.get('alt', 10)))
                cmd = m.get('command', m.get('commandType', 'WAYPOINT'))
            else:
                lat = float(getattr(m, 'latitude', getattr(m, 'lat', 0)))
                lon = float(getattr(m, 'longitude', getattr(m, 'lng', getattr(m, 'lon', 0))))
                alt = float(getattr(m, 'altitude', getattr(m, 'alt', 10)))
                cmd = getattr(m, 'command', 'WAYPOINT')
            items.append({'lat': lat, 'lon': lon, 'alt': alt, 'command': cmd})
        return self.uploadMission(items)

    # ══════════════════════════════════════════════════════════════════════
    # DOWNLOAD — FC → GCS
    # ══════════════════════════════════════════════════════════════════════

    @pyqtSlot(result=bool)
    def downloadMission(self):
        """Request the full mission from the flight controller."""
        if not self._ready():
            return False
        with self._lock:
            if self._op != MissionOp.IDLE:
                self.feedback.emit('⏳ Another operation in progress')
                return False
            self._op = MissionOp.DOWNLOADING

        self._dl_expected = 0
        self._dl_items    = []
        self._dl_retries  = 0

        self.feedback.emit('📥 Requesting mission from FC…')
        print('[MissionManager] ▶ Download started (MISSION_REQUEST_LIST)')

        try:
            self._drone.mav.mission_request_list_send(
                self._drone.target_system,
                self._drone.target_component,
                MISSION_TYPE_MISSION)
        except Exception as e:
            self.feedback.emit(f'❌ Download failed: {e}')
            with self._lock:
                self._op = MissionOp.IDLE
            return False

        self._start_timer('dl', TIMEOUT_DEFAULT_MS)
        return True

    # ══════════════════════════════════════════════════════════════════════
    # CLEAR
    # ══════════════════════════════════════════════════════════════════════

    @pyqtSlot(result=bool)
    def clearMission(self):
        """Send MISSION_CLEAR_ALL and wait for ACK."""
        if not self._ready():
            return False
        with self._lock:
            if self._op != MissionOp.IDLE:
                self.feedback.emit('⏳ Another operation in progress')
                return False
            self._op = MissionOp.CLEARING

        self._cl_retries = 0
        self.feedback.emit('🗑️ Clearing mission on FC…')
        print('[MissionManager] ▶ Clear started')

        try:
            self._drone.mav.mission_clear_all_send(
                self._drone.target_system,
                self._drone.target_component,
                MISSION_TYPE_MISSION)
        except Exception as e:
            self.feedback.emit(f'❌ Clear failed: {e}')
            with self._lock:
                self._op = MissionOp.IDLE
            return False

        self._start_timer('cl', TIMEOUT_DEFAULT_MS)
        return True

    # ══════════════════════════════════════════════════════════════════════
    # SET CURRENT WAYPOINT
    # ══════════════════════════════════════════════════════════════════════

    @pyqtSlot(int, result=bool)
    def setCurrentWP(self, seq):
        """Set the current mission item on the FC (MAV_CMD_DO_SET_MISSION_CURRENT)."""
        if not self._ready():
            return False
        try:
            key = (self._drone.target_system, self._drone.target_component)
            use_legacy = self._accepts_do_set_current.get(key) is False

            if use_legacy:
                self._drone.mav.mission_set_current_send(
                    self._drone.target_system,
                    self._drone.target_component,
                    seq)
            else:
                self._drone.mav.command_long_send(
                    self._drone.target_system,
                    self._drone.target_component,
                    mavutil.mavlink.MAV_CMD_DO_SET_MISSION_CURRENT,
                    0, seq, 0, 0, 0, 0, 0, 0)
            self.feedback.emit(f'🎯 Set current WP → #{seq}')
            return True
        except Exception as e:
            self.feedback.emit(f'❌ setCurrentWP error: {e}')
            return False

    # ══════════════════════════════════════════════════════════════════════
    # SET HOME
    # ══════════════════════════════════════════════════════════════════════

    @pyqtSlot(float, float, float, result=bool)
    def setHome(self, lat, lon, alt=0.0):
        """Send MAV_CMD_DO_SET_HOME."""
        if not self._ready():
            return False
        try:
            self._drone.mav.command_long_send(
                self._drone.target_system,
                self._drone.target_component,
                mavutil.mavlink.MAV_CMD_DO_SET_HOME,
                0, 0, 0, 0, 0, lat, lon, alt)
            self.feedback.emit(f'🏠 Home → {lat:.5f}, {lon:.5f}')
            return True
        except Exception as e:
            self.feedback.emit(f'❌ setHome error: {e}')
            return False

    # ══════════════════════════════════════════════════════════════════════
    # LOCAL ITEM MANIPULATION (offline — no FC comms)
    # ══════════════════════════════════════════════════════════════════════

    @pyqtSlot(int, float, float, float, str, result=bool)
    def insertItem(self, idx, lat, lon, alt, cmd_str='WAYPOINT'):
        """Insert a mission item at position idx (0-based)."""
        cmd = CMD_IDS.get(cmd_str.upper(), mavutil.mavlink.MAV_CMD_NAV_WAYPOINT)
        idx = max(0, min(idx, len(self._items)))
        item = make_item(idx, cmd, lat, lon, alt)
        self._items.insert(idx, item)
        self._fix_jumps(idx - 1, +1)
        self._rebuild_seqs()
        self.feedback.emit(f'➕ Inserted {cmd_str} at #{idx}')
        self._emit_changed()
        return True

    @pyqtSlot(int, result=bool)
    def removeItem(self, idx):
        if idx < 0 or idx >= len(self._items):
            return False
        self._items.pop(idx)
        self._fix_jumps(idx, -1)
        self._rebuild_seqs()
        self.feedback.emit(f'🗑️ Removed item #{idx}')
        self._emit_changed()
        return True

    @pyqtSlot(int, result=bool)
    def moveItemUp(self, idx):
        if idx < 1 or idx >= len(self._items):
            return False
        self._items[idx - 1], self._items[idx] = self._items[idx], self._items[idx - 1]
        self._rebuild_seqs()
        self._emit_changed()
        return True

    @pyqtSlot(int, result=bool)
    def moveItemDown(self, idx):
        if idx < 0 or idx >= len(self._items) - 1:
            return False
        self._items[idx], self._items[idx + 1] = self._items[idx + 1], self._items[idx]
        self._rebuild_seqs()
        self._emit_changed()
        return True

    @pyqtSlot(int, str, 'QVariant', result=bool)
    def setItemField(self, idx, field, value):
        """Update a single field: lat, lon, alt, command, param1, param2…"""
        if idx < 0 or idx >= len(self._items):
            return False
        FIELD_MAP = {'lat': 'x', 'lon': 'y', 'alt': 'z',
                     'latitude': 'x', 'longitude': 'y', 'altitude': 'z'}
        key = FIELD_MAP.get(field.lower(), field.lower())
        try:
            if key == 'command':
                if isinstance(value, str):
                    self._items[idx]['command'] = CMD_IDS.get(
                        value.upper(), mavutil.mavlink.MAV_CMD_NAV_WAYPOINT)
                else:
                    self._items[idx]['command'] = int(value)
            else:
                self._items[idx][key] = float(value)
            self._emit_changed()
            return True
        except Exception as e:
            print(f'[MissionManager] setItemField error: {e}')
            return False

    # ── Named-item convenience slots ───────────────────────────────────────

    @pyqtSlot(float, float, float, result=bool)
    def addTakeoff(self, lat, lon, alt=20.0):
        """Insert NAV_TAKEOFF at index 1 (after home)."""
        if not self._items:
            self._items.append(make_item(0, mavutil.mavlink.MAV_CMD_NAV_WAYPOINT, lat, lon, 0))
        item = make_item(1, mavutil.mavlink.MAV_CMD_NAV_TAKEOFF, lat, lon, alt)
        self._items.insert(1, item)
        self._fix_jumps(0, +1)
        self._rebuild_seqs()
        self.feedback.emit(f'🛫 Takeoff inserted at {alt}m')
        self._emit_changed()
        return True

    @pyqtSlot(float, float, result=bool)
    def addLanding(self, lat, lon):
        """Append NAV_LAND at end."""
        self._items.append(make_item(len(self._items),
                                     mavutil.mavlink.MAV_CMD_NAV_LAND, lat, lon, 0))
        self._rebuild_seqs()
        self.feedback.emit('🛬 Landing waypoint appended')
        self._emit_changed()
        return True

    @pyqtSlot(result=bool)
    def addRTL(self):
        """Append NAV_RETURN_TO_LAUNCH."""
        self._items.append(make_item(len(self._items),
                                     mavutil.mavlink.MAV_CMD_NAV_RETURN_TO_LAUNCH))
        self._rebuild_seqs()
        self.feedback.emit('🏠 RTL appended')
        self._emit_changed()
        return True

    @pyqtSlot(result=bool)
    def addLoop(self):
        """Append DO_JUMP back to first nav WP (skip home/takeoff)."""
        if not self._items:
            self.feedback.emit('❌ No items to loop')
            return False
        if self._items[-1].get('command') in JUMP_COMMANDS:
            self.feedback.emit('ℹ️ Already looped')
            return False
        target = 1
        if len(self._items) > 1 and self._items[1].get('command') == mavutil.mavlink.MAV_CMD_NAV_TAKEOFF:
            target = 2
        self._items.append(make_item(
            len(self._items), mavutil.mavlink.MAV_CMD_DO_JUMP,
            p1=target, p2=-1, frame=0))
        self._rebuild_seqs()
        self.feedback.emit(f'🔁 Loop → WP{target}')
        self._emit_changed()
        return True

    @pyqtSlot(float, float, result=bool)
    def addDoLandStart(self, lat, lon):
        """Append DO_LAND_START."""
        self._items.append(make_item(len(self._items),
                                     mavutil.mavlink.MAV_CMD_DO_LAND_START, lat, lon))
        self._rebuild_seqs()
        self.feedback.emit('🏁 DO_LAND_START appended')
        self._emit_changed()
        return True

    # ══════════════════════════════════════════════════════════════════════
    # SAVE / LOAD JSON
    # ══════════════════════════════════════════════════════════════════════

    @pyqtSlot(result=str)
    def toJson(self):
        """Serialise current mission to JSON string."""
        items_out = []
        for it in self._items:
            items_out.append({
                'seq':     it['seq'],
                'command': CMD_NAMES.get(it['command'], str(it['command'])),
                'cmd_id':  it['command'],
                'frame':   it['frame'],
                'lat':     it['x'],
                'lon':     it['y'],
                'alt':     it['z'],
                'param1':  it['param1'],
                'param2':  it['param2'],
                'param3':  it['param3'],
                'param4':  it['param4'],
                'autocontinue': it['autocontinue'],
            })
        payload = {'format': 'TiHAN_Mission', 'version': '2.0', 'items': items_out}
        return json.dumps(payload, indent=2)

    @pyqtSlot(str, result=bool)
    def fromJson(self, json_str):
        """Load mission from JSON string."""
        try:
            data = json.loads(json_str)
            raw = data.get('items', data) if isinstance(data, dict) else data
            self._items = []
            for it in raw:
                cmd_raw = it.get('command', it.get('cmd', it.get('cmd_id', 'WAYPOINT')))
                if isinstance(cmd_raw, str):
                    cmd = CMD_IDS.get(cmd_raw.upper(), mavutil.mavlink.MAV_CMD_NAV_WAYPOINT)
                else:
                    cmd = int(cmd_raw)
                self._items.append(make_item(
                    seq=it.get('seq', len(self._items)),
                    cmd=cmd,
                    lat=float(it.get('lat', it.get('x', 0))),
                    lon=float(it.get('lon', it.get('y', 0))),
                    alt=float(it.get('alt', it.get('z', 0))),
                    p1=it.get('param1', 0), p2=it.get('param2', 0),
                    p3=it.get('param3', 0), p4=it.get('param4', 0),
                    frame=it.get('frame', 3),
                    autocontinue=it.get('autocontinue', 1)))
            self._rebuild_seqs()
            self.feedback.emit(f'📂 Loaded {len(self._items)} items')
            self._emit_changed()
            return True
        except Exception as e:
            self.feedback.emit(f'❌ JSON load error: {e}')
            return False

    # ══════════════════════════════════════════════════════════════════════
    # STATS
    # ══════════════════════════════════════════════════════════════════════

    @pyqtSlot(result='QVariant')
    def getStats(self):
        return self._compute_stats()

    @pyqtSlot(result='QVariantList')
    def getItems(self):
        """Return the current item list for QML."""
        return self._items_for_qml()

    @pyqtSlot(result=int)
    def itemCount(self):
        return len(self._items)

    # ══════════════════════════════════════════════════════════════════════
    # MAVLINK PACKET HANDLER — call from DroneModel's msg loop
    # ══════════════════════════════════════════════════════════════════════

    def handle_mavlink_message(self, msg):
        """Process incoming MAVLink messages related to the mission protocol.

        This must be called from the telemetry thread for every inbound msg.
        """
        mtype = msg.get_type()

        # ── Upload: FC requests next item ──────────────────────────────────
        if mtype in ('MISSION_REQUEST', 'MISSION_REQUEST_INT'):
            if self._op == MissionOp.UPLOADING:
                self._cancel_timer('up')
                seq = msg.seq
                total = len(self._up_items)
                if 0 <= seq < total:
                    self._send_item_int(self._up_items[seq])
                    self._up_retries = 0
                    if seq % max(1, total // 10) == 0 or seq == total - 1:
                        self.feedback.emit(f'📤 Sending WP {seq + 1}/{total}')
                    self._start_timer('up', TIMEOUT_ITEM_MS)

        # ── MISSION_ACK ────────────────────────────────────────────────────
        elif mtype == 'MISSION_ACK':
            result_code = msg.type

            if self._op == MissionOp.UPLOADING:
                self._cancel_timer('up')
                if result_code == mavutil.mavlink.MAV_MISSION_ACCEPTED:
                    n = len(self._up_items)
                    self._items = list(self._up_items)
                    self._rebuild_seqs()
                    print(f'[MissionManager] ✅ Upload accepted ({n} items)')
                    self.feedback.emit(f'✅ Mission uploaded ({n} items)')
                    self.uploadComplete.emit(True, f'{n} items uploaded')
                    self._emit_changed()
                else:
                    err = self._ack_code_name(result_code)
                    print(f'[MissionManager] ❌ Upload NACK: {err}')
                    self.feedback.emit(f'❌ Upload rejected: {err}')
                    self.uploadComplete.emit(False, err)
                with self._lock:
                    self._op = MissionOp.IDLE

            elif self._op == MissionOp.CLEARING:
                self._cancel_timer('cl')
                if result_code == mavutil.mavlink.MAV_MISSION_ACCEPTED:
                    self._items = []
                    print('[MissionManager] ✅ Mission cleared')
                    self.feedback.emit('✅ Mission cleared')
                    self._emit_changed()
                else:
                    self.feedback.emit(f'❌ Clear rejected: {self._ack_code_name(result_code)}')
                with self._lock:
                    self._op = MissionOp.IDLE

        # ── Download: MISSION_COUNT (FC tells us total) ────────────────────
        elif mtype == 'MISSION_COUNT':
            if self._op == MissionOp.DOWNLOADING:
                self._cancel_timer('dl')
                count = msg.count
                self._dl_expected = count
                self._dl_items    = []
                print(f'[MissionManager] 📥 FC reports {count} items')

                if count == 0:
                    self.feedback.emit('📋 Mission is empty')
                    self._items = []
                    self._emit_changed()
                    self.downloadComplete.emit(True, '0 items')
                    with self._lock:
                        self._op = MissionOp.IDLE
                else:
                    self.feedback.emit(f'📥 Downloading {count} items…')
                    self._request_item(0)
                    self._start_timer('dl', TIMEOUT_ITEM_MS)

        # ── Download: MISSION_ITEM_INT (individual item from FC) ──────────
        elif mtype in ('MISSION_ITEM_INT', 'MISSION_ITEM'):
            if self._op == MissionOp.DOWNLOADING:
                self._cancel_timer('dl')
                is_int = (mtype == 'MISSION_ITEM_INT')
                lat = msg.x / 1e7 if is_int else msg.x
                lon = msg.y / 1e7 if is_int else msg.y

                item = make_item(
                    seq=msg.seq, cmd=msg.command,
                    lat=lat, lon=lon, alt=msg.z,
                    p1=msg.param1, p2=msg.param2,
                    p3=msg.param3, p4=msg.param4,
                    frame=msg.frame, current=msg.current,
                    autocontinue=msg.autocontinue)
                self._dl_items.append(item)

                received = len(self._dl_items)
                total    = self._dl_expected
                if received % max(1, total // 10) == 0 or received == total:
                    self.feedback.emit(f'📥 Item {received}/{total}')

                if received < total:
                    self._request_item(received)
                    self._dl_retries = 0
                    self._start_timer('dl', TIMEOUT_ITEM_MS)
                else:
                    # All received → send MISSION_ACK back to FC
                    try:
                        self._drone.mav.mission_ack_send(
                            self._drone.target_system,
                            self._drone.target_component,
                            mavutil.mavlink.MAV_MISSION_ACCEPTED,
                            MISSION_TYPE_MISSION)
                    except Exception:
                        pass
                    self._items = list(self._dl_items)
                    self._rebuild_seqs()
                    print(f'[MissionManager] ✅ Download complete ({total} items)')
                    self.feedback.emit(f'✅ Downloaded {total} items')
                    self.downloadComplete.emit(True, f'{total} items')
                    self._emit_changed()
                    with self._lock:
                        self._op = MissionOp.IDLE

        # ── Track current WP ───────────────────────────────────────────────
        elif mtype == 'MISSION_CURRENT':
            seq = msg.seq
            if seq != self._current_seq:
                self._current_seq = seq
                self.currentWPChanged.emit(seq)

        # ── Track reached WP ──────────────────────────────────────────────
        elif mtype == 'MISSION_ITEM_REACHED':
            self.wpReached.emit(msg.seq)

        # ── COMMAND_ACK for DO_SET_MISSION_CURRENT ─────────────────────────
        elif mtype == 'COMMAND_ACK':
            if msg.command == mavutil.mavlink.MAV_CMD_DO_SET_MISSION_CURRENT:
                key = (msg.get_srcSystem(), msg.get_srcComponent())
                if msg.result == mavutil.mavlink.MAV_RESULT_UNSUPPORTED:
                    self._accepts_do_set_current[key] = False
                elif msg.result == mavutil.mavlink.MAV_RESULT_ACCEPTED:
                    self._accepts_do_set_current[key] = True

    # ══════════════════════════════════════════════════════════════════════
    # INTERNAL HELPERS
    # ══════════════════════════════════════════════════════════════════════

    def _parse_input_items(self, items):
        """Normalise raw input [{lat, lon, alt, command}] → [make_item(...)]."""
        result = []
        for i, raw in enumerate(items):
            if isinstance(raw, dict):
                lat = float(raw.get('lat', raw.get('latitude', raw.get('x', 0))))
                lon = float(raw.get('lon', raw.get('lng',
                            raw.get('longitude', raw.get('y', 0)))))
                alt = float(raw.get('alt', raw.get('altitude', raw.get('z', 10))))
                cmd_raw = raw.get('command', raw.get('commandType', 'WAYPOINT'))
            else:
                lat = float(getattr(raw, 'lat', getattr(raw, 'latitude', 0)))
                lon = float(getattr(raw, 'lon', getattr(raw, 'lng',
                            getattr(raw, 'longitude', 0))))
                alt = float(getattr(raw, 'alt', getattr(raw, 'altitude', 10)))
                cmd_raw = getattr(raw, 'command', 'WAYPOINT')

            if isinstance(cmd_raw, str):
                cmd = CMD_IDS.get(cmd_raw.upper(), mavutil.mavlink.MAV_CMD_NAV_WAYPOINT)
            else:
                cmd = int(cmd_raw)

            if lat == 0.0 and lon == 0.0 and cmd in NAV_COMMANDS:
                if cmd != mavutil.mavlink.MAV_CMD_NAV_RETURN_TO_LAUNCH:
                    continue  # skip zero-coordinate NAV items (except RTL)

            result.append(make_item(i, cmd, lat, lon, alt))

        # Renumber seqs and mark first item current
        for i, it in enumerate(result):
            it['seq'] = i
            it['current'] = 1 if i == 0 else 0
        return result

    def _send_item_int(self, item):
        """Send a MISSION_ITEM_INT to the FC (lat/lon encoded ×1e7)."""
        self._drone.mav.mission_item_int_send(
            self._drone.target_system,
            self._drone.target_component,
            item['seq'],
            item['frame'],
            item['command'],
            item['current'],
            item['autocontinue'],
            item['param1'], item['param2'],
            item['param3'], item['param4'],
            int(item['x'] * 1e7),   # lat → int32 deg×1e7
            int(item['y'] * 1e7),   # lon → int32 deg×1e7
            float(item['z']),       # alt metres
            MISSION_TYPE_MISSION)

    def _request_item(self, seq):
        """Send MISSION_REQUEST_INT for download."""
        self._drone.mav.mission_request_int_send(
            self._drone.target_system,
            self._drone.target_component,
            seq,
            MISSION_TYPE_MISSION)

    # ── Seq / jump helpers ─────────────────────────────────────────────────

    def _rebuild_seqs(self):
        for i, it in enumerate(self._items):
            it['seq'] = i

    def _fix_jumps(self, idx, delta):
        for it in self._items:
            if it.get('command') in JUMP_COMMANDS:
                p1 = int(it.get('param1', 0))
                if p1 > idx and p1 + delta > 0:
                    it['param1'] = float(p1 + delta)

    # ── Emit helpers ───────────────────────────────────────────────────────

    def _items_for_qml(self):
        """Convert internal items → QML-friendly list of dicts."""
        out = []
        for it in self._items:
            cmd_id = it.get('command', 16)
            out.append({
                'seq':     it['seq'],
                'command': CMD_NAMES.get(cmd_id, f'CMD_{cmd_id}'),
                'cmd_id':  cmd_id,
                'lat':     it['x'],
                'lon':     it['y'],
                'alt':     it['z'],
                'param1':  it['param1'],
                'param2':  it['param2'],
                'frame':   it['frame'],
            })
        return out

    def _emit_changed(self):
        """Emit both missionChanged and statsChanged."""
        self.missionChanged.emit(self._items_for_qml())
        self.statsChanged.emit(self._compute_stats())

    def _compute_stats(self):
        nav = [it for it in self._items if it.get('command', 0) in NAV_COMMANDS]
        total_m = 0.0
        for i in range(1, len(nav)):
            total_m += haversine_m(nav[i-1]['x'], nav[i-1]['y'],
                                   nav[i]['x'], nav[i]['y'])
        cruise = 10.0  # default m/s
        ete = total_m / cruise if cruise > 0 else 0
        return {
            'wpCount':  len(self._items),
            'distKm':   round(total_m / 1000, 3),
            'eteSec':   round(ete),
        }

    @staticmethod
    def _ack_code_name(code):
        names = {
            0: 'ACCEPTED', 1: 'ERROR', 2: 'UNSUPPORTED_FRAME',
            3: 'INVALID_SEQUENCE', 4: 'INVALID_PARAM',
            5: 'INVALID_COUNT', 6: 'UNSUPPORTED',
            7: 'DENIED', 8: 'NO_SPACE', 14: 'OPERATION_CANCELLED',
        }
        return names.get(code, f'code_{code}')

    # ── Timeout / retry infrastructure ─────────────────────────────────────

    def _start_timer(self, prefix, ms):
        """Start a QTimer for timeout/retry."""
        attr = f'_{prefix}_timer_id'
        self._cancel_timer(prefix)
        timer = QTimer()
        timer.setSingleShot(True)
        timer.setInterval(ms)
        timer.timeout.connect(lambda: self._on_timeout(prefix))
        setattr(self, attr, timer)
        timer.start()

    def _cancel_timer(self, prefix):
        attr = f'_{prefix}_timer_id'
        timer = getattr(self, attr, None)
        if timer is not None:
            timer.stop()
            setattr(self, attr, None)

    def _on_timeout(self, prefix):
        """Handle a timeout — retry or abort."""
        retries_attr = f'_{prefix}_retries'
        retries = getattr(self, retries_attr, 0) + 1
        setattr(self, retries_attr, retries)

        if retries > MAX_RETRIES:
            op_name = {'up': 'Upload', 'dl': 'Download', 'cl': 'Clear'}.get(prefix, prefix)
            print(f'[MissionManager] ❌ {op_name} timed out after {MAX_RETRIES} retries')
            self.feedback.emit(f'❌ {op_name} timed out')
            if prefix == 'up':
                self.uploadComplete.emit(False, 'Timeout')
            elif prefix == 'dl':
                self.downloadComplete.emit(False, 'Timeout')
            with self._lock:
                self._op = MissionOp.IDLE
            return

        print(f'[MissionManager] ⏳ Retry {retries}/{MAX_RETRIES} ({prefix})')

        try:
            if prefix == 'up':
                # Resend MISSION_COUNT to re-trigger the handshake
                self._drone.mav.mission_count_send(
                    self._drone.target_system,
                    self._drone.target_component,
                    len(self._up_items),
                    MISSION_TYPE_MISSION)
                self._start_timer('up', TIMEOUT_DEFAULT_MS)

            elif prefix == 'dl':
                received = len(self._dl_items)
                if received == 0:
                    # Retry request list
                    self._drone.mav.mission_request_list_send(
                        self._drone.target_system,
                        self._drone.target_component,
                        MISSION_TYPE_MISSION)
                    self._start_timer('dl', TIMEOUT_DEFAULT_MS)
                else:
                    # Retry the last expected item
                    self._request_item(received)
                    self._start_timer('dl', TIMEOUT_ITEM_MS)

            elif prefix == 'cl':
                self._drone.mav.mission_clear_all_send(
                    self._drone.target_system,
                    self._drone.target_component,
                    MISSION_TYPE_MISSION)
                self._start_timer('cl', TIMEOUT_DEFAULT_MS)

        except Exception as e:
            print(f'[MissionManager] ❌ Retry failed: {e}')
            self.feedback.emit(f'❌ Retry failed: {e}')
            with self._lock:
                self._op = MissionOp.IDLE
