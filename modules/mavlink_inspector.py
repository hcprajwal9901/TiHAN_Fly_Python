from PyQt5.QtCore import QAbstractItemModel, QModelIndex, Qt, QTimer, pyqtSlot, pyqtSignal, pyqtProperty
import time
import collections
import threading


class MavlinkMessageNode:
    """Node for the hierarchical tree structure"""
    def __init__(self, name, node_type, parent=None, msg_id=None):
        self.name = name
        self.node_type = node_type  # 'Vehicle', 'Component', 'Message', 'Field'
        self.parent = parent
        self.children = []
        self.msg_id = msg_id

        # Message-level stats
        self.count = 0
        self.bytes = 0
        self.rate = 0.0
        self.bandwidth = 0.0
        self.last_count = 0
        self.last_bytes = 0

        # Field-level data
        self.field_value = None
        self.field_type = ""
        self.is_dirty = False

        if parent:
            parent.children.append(self)

    def row(self):
        if self.parent:
            return self.parent.children.index(self)
        return 0


class MavlinkMessageRateModel(QAbstractItemModel):
    """
    QAbstractItemModel for displaying MAVLink message rates in a tree view.
    Hierarchy: Vehicle ID -> Component ID -> Message Name -> Fields

    Thread safety: process_message() may be called from any thread.
    It enqueues data into a deque (lock-free for single-writer). A 200ms
    QTimer drains the queue on the main thread where all Qt model mutations
    are safe.
    """

    # Custom Roles
    NameRole      = Qt.UserRole + 1
    FrequencyRole = Qt.UserRole + 2
    MessageIdRole = Qt.UserRole + 3
    BandwidthRole = Qt.UserRole + 4

    showGcsChanged = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._root_node    = MavlinkMessageNode("Root", "Root")
        self._vehicles     = {}   # sysid -> Node
        self._components   = {}   # (sysid, compid) -> Node
        self._messages     = {}   # (sysid, compid, msgid) -> Node
        self._fields       = {}   # (sysid, compid, msgid, field_name) -> Node

        self._last_update_time = time.time()
        self._show_gcs = True

        # ── Thread-safe message queue ──────────────────────────────────────────
        # Keyed dict so we only keep the LATEST data per (sysid, compid, msgid).
        # Written from MAVLink thread, drained on the main thread.
        self._pending_lock    = threading.Lock()
        self._pending_msgs    = {}   # (sysid,compid,msgid) -> dict snapshot
        self._pending_counts  = {}   # (sysid,compid,msgid) -> int  (total arrivals)
        self._pending_bytes   = {}   # (sysid,compid,msgid) -> int

        # 200ms timer drains the queue and updates the tree
        self._drain_timer = QTimer(self)
        self._drain_timer.timeout.connect(self._drain_queue)
        self._drain_timer.start(200)

        # 1 Hz timer refreshes Hz / bandwidth figures
        self._rate_timer = QTimer(self)
        self._rate_timer.timeout.connect(self._update_rates)
        self._rate_timer.start(1000)

    # ─── showGcs property ──────────────────────────────────────────────────────

    @pyqtProperty(bool, notify=showGcsChanged)
    def showGcs(self):
        return self._show_gcs

    @showGcs.setter
    def showGcs(self, value):
        if self._show_gcs != value:
            self._show_gcs = value
            self.showGcsChanged.emit()
            self.layoutChanged.emit()

    # ─── Visibility helpers ────────────────────────────────────────────────────

    def _is_visible(self, node):
        if node.node_type == 'Vehicle' and not self._show_gcs:
            if node.name == '255':
                return False
        return True

    def _get_visible_children(self, parent_node):
        return [c for c in parent_node.children if self._is_visible(c)]

    # ─── QAbstractItemModel interface ──────────────────────────────────────────

    def rowCount(self, parent=QModelIndex()):
        if not parent.isValid():
            return len(self._get_visible_children(self._root_node))
        node = parent.internalPointer()
        return len(self._get_visible_children(node))

    def columnCount(self, parent=QModelIndex()):
        return 4  # Name | Hz/Value | Msg ID / Type | Bandwidth

    def index(self, row, column, parent=QModelIndex()):
        if not self.hasIndex(row, column, parent):
            return QModelIndex()

        parent_node = self._root_node if not parent.isValid() else parent.internalPointer()
        visible = self._get_visible_children(parent_node)
        if row < len(visible):
            return self.createIndex(row, column, visible[row])
        return QModelIndex()

    def parent(self, index):
        if not index.isValid():
            return QModelIndex()

        node        = index.internalPointer()
        parent_node = node.parent

        if parent_node is None or parent_node == self._root_node:
            return QModelIndex()

        grandparent = parent_node.parent
        if grandparent:
            visible_siblings = self._get_visible_children(grandparent)
            if parent_node in visible_siblings:
                return self.createIndex(visible_siblings.index(parent_node), 0, parent_node)

        return QModelIndex()

    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid():
            return None

        node = index.internalPointer()

        if role == Qt.DisplayRole:
            if node.node_type == 'Vehicle':
                return f"Vehicle {node.name}"
            elif node.node_type == 'Component':
                return f"Component {node.name}"
            else:
                return node.name

        elif role == self.NameRole:
            if node.node_type == 'Vehicle':
                return f"Vehicle {node.name}"
            elif node.node_type == 'Component':
                return f"Component {node.name}"
            else:
                return node.name

        elif role == self.FrequencyRole:
            if node.node_type == 'Message':
                return f"{node.rate:.1f} Hz"
            elif node.node_type == 'Field':
                return _format_field_value(node.field_value)
            return None

        elif role == self.MessageIdRole:
            if node.node_type == 'Message':
                return str(node.msg_id) if node.msg_id is not None else ""
            elif node.node_type == 'Field':
                return node.field_type
            return None

        elif role == self.BandwidthRole:
            if node.node_type == 'Message':
                bw = node.bandwidth
                if bw >= 1024:
                    return f"{bw / 1024:.1f} KB/s"
                return f"{bw:.0f} B/s"
            return None

        return None

    def roleNames(self):
        return {
            self.NameRole:      b"messageName",
            self.FrequencyRole: b"frequency",
            self.MessageIdRole: b"messageId",
            self.BandwidthRole: b"bandwidth",
        }

    # ─── Message ingestion (called from MAVLink background thread) ─────────────

    @pyqtSlot(object)
    def process_message(self, msg):
        """
        Thread-safe ingestion. Just extracts minimal data and stores it in
        the pending dict — no Qt model calls here.
        """
        try:
            sys_id   = msg.get_srcSystem()
            comp_id  = msg.get_srcComponent()
            msg_id   = msg.get_msgId()
            msg_len  = len(msg.get_msgbuf())

            try:
                msg_dict = msg.to_dict()
            except Exception:
                msg_dict = {}

            snapshot = {
                'sys_id':   sys_id,
                'comp_id':  comp_id,
                'msg_id':   msg_id,
                'msg_name': msg.get_type(),
                'msg_len':  msg_len,
                'fields':   {k: v for k, v in msg_dict.items() if k != 'mavpackettype'},
            }

            key = (sys_id, comp_id, msg_id)
            with self._pending_lock:
                self._pending_msgs[key] = snapshot
                self._pending_counts[key] = self._pending_counts.get(key, 0) + 1
                self._pending_bytes[key]  = self._pending_bytes.get(key, 0) + msg_len

        except Exception:
            pass  # Never block the MAVLink thread

    # ─── Drain queue on main thread (200 ms) ──────────────────────────────────

    def _drain_queue(self):
        """Called on the main thread every 200ms. Applies pending snapshots."""
        with self._pending_lock:
            if not self._pending_msgs:
                return
            msgs   = self._pending_msgs.copy()
            counts = self._pending_counts.copy()
            byt    = self._pending_bytes.copy()
            self._pending_msgs.clear()
            self._pending_counts.clear()
            self._pending_bytes.clear()

        for key, snap in msgs.items():
            try:
                self._apply_snapshot(snap, counts[key], byt[key])
            except Exception as e:
                print(f"[MavlinkInspector] Error applying snapshot: {e}")

    def _apply_snapshot(self, snap, count_delta, bytes_delta):
        """Apply a single message snapshot. Must be called on the main thread."""
        sys_id   = snap['sys_id']
        comp_id  = snap['comp_id']
        msg_id   = snap['msg_id']
        msg_name = snap['msg_name']

        # ── Vehicle node ──────────────────────────────────────────────────────
        if sys_id not in self._vehicles:
            pos = len(self._root_node.children)
            self.beginInsertRows(QModelIndex(), pos, pos)
            vehicle_node = MavlinkMessageNode(str(sys_id), 'Vehicle', self._root_node)
            self._vehicles[sys_id] = vehicle_node
            self.endInsertRows()
        else:
            vehicle_node = self._vehicles[sys_id]

        # ── Component node ────────────────────────────────────────────────────
        comp_key = (sys_id, comp_id)
        if comp_key not in self._components:
            parent_idx = self.createIndex(vehicle_node.row(), 0, vehicle_node)
            pos        = len(vehicle_node.children)
            self.beginInsertRows(parent_idx, pos, pos)
            comp_node = MavlinkMessageNode(str(comp_id), 'Component', vehicle_node)
            self._components[comp_key] = comp_node
            self.endInsertRows()
        else:
            comp_node = self._components[comp_key]

        # ── Message node ──────────────────────────────────────────────────────
        msg_key = (sys_id, comp_id, msg_id)
        if msg_key not in self._messages:
            parent_idx = self.createIndex(comp_node.row(), 0, comp_node)
            pos        = len(comp_node.children)
            self.beginInsertRows(parent_idx, pos, pos)
            msg_node = MavlinkMessageNode(msg_name, 'Message', comp_node, msg_id)
            self._messages[msg_key] = msg_node
            self.endInsertRows()
        else:
            msg_node = self._messages[msg_key]

        # ── Update message counters ───────────────────────────────────────────
        msg_node.count += count_delta
        msg_node.bytes += bytes_delta

        # ── Field nodes ───────────────────────────────────────────────────────
        for field_name, field_value in snap['fields'].items():
            field_key = (sys_id, comp_id, msg_id, field_name)

            if field_key not in self._fields:
                parent_idx = self.createIndex(msg_node.row(), 0, msg_node)
                pos        = len(msg_node.children)
                self.beginInsertRows(parent_idx, pos, pos)
                field_node = MavlinkMessageNode(field_name, 'Field', msg_node)
                field_node.field_value = field_value
                field_node.field_type  = _type_label(field_value)
                self._fields[field_key] = field_node
                self.endInsertRows()
            else:
                field_node = self._fields[field_key]
                if field_node.field_value != field_value:
                    field_node.field_value = field_value
                    field_node.field_type  = _type_label(field_value)
                    field_node.is_dirty    = True

    # ─── Rate / bandwidth update (1 Hz) ───────────────────────────────────────

    def _update_rates(self):
        current_time = time.time()
        dt = current_time - self._last_update_time
        if dt <= 0:
            return
        self._last_update_time = current_time

        def update_node(node):
            if node.node_type == 'Message':
                count_diff = node.count - node.last_count
                bytes_diff = node.bytes - node.last_bytes
                new_rate   = count_diff / dt
                new_bw     = bytes_diff / dt

                if abs(new_rate - node.rate) > 0.05 or abs(new_bw - node.bandwidth) > 1.0:
                    node.rate      = new_rate
                    node.bandwidth = new_bw
                    tl = self.createIndex(node.row(), 0, node)
                    br = self.createIndex(node.row(), 3, node)
                    self.dataChanged.emit(tl, br, [Qt.DisplayRole, self.FrequencyRole, self.BandwidthRole])

                node.last_count = node.count
                node.last_bytes = node.bytes

            elif node.node_type == 'Field':
                if getattr(node, 'is_dirty', False):
                    tl = self.createIndex(node.row(), 0, node)
                    br = self.createIndex(node.row(), 3, node)
                    self.dataChanged.emit(tl, br, [Qt.DisplayRole, self.FrequencyRole, self.MessageIdRole])
                    node.is_dirty = False

            for child in node.children:
                update_node(child)

        update_node(self._root_node)


# ─── Helpers ───────────────────────────────────────────────────────────────────

def _format_field_value(value):
    """Return a compact, readable string for a field value."""
    if value is None:
        return ""
    if isinstance(value, (bytes, bytearray)):
        preview = ','.join(str(b) for b in value[:16])
        if len(value) > 16:
            preview += f"… (+{len(value)-16})"
        return preview
    if isinstance(value, (list, tuple)):
        items = [str(v) for v in value[:16]]
        suffix = f"… (+{len(value)-16})" if len(value) > 16 else ""
        return ','.join(items) + suffix
    if isinstance(value, float):
        return f"{value:.4f}"
    return str(value)


def _type_label(value):
    """Return a short type label string."""
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "float"
    if isinstance(value, str):
        return "str"
    if isinstance(value, (bytes, bytearray)):
        return f"bytes[{len(value)}]"
    if isinstance(value, (list, tuple)):
        return f"array[{len(value)}]"
    return type(value).__name__
