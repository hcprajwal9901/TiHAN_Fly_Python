import threading
from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty, QAbstractListModel, Qt, QModelIndex
from modules.log_database import LogDatabase
from modules.log_indexer import LogIndexer
from pathlib import Path

class LogListModel(QAbstractListModel):
    """
    Qt ListModel for displaying logs from SQLite database
    """
    TitleRole = Qt.UserRole + 1
    DateRole = Qt.UserRole + 2
    SizeRole = Qt.UserRole + 3
    DurationRole = Qt.UserRole + 4
    PathRole = Qt.UserRole + 5
    
    def __init__(self, logs=None, parent=None):
        super().__init__(parent)
        self._logs = logs or []
        
    def rowCount(self, parent=QModelIndex()):
        return len(self._logs)
        
    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid() or index.row() >= len(self._logs):
            return None
            
        log = self._logs[index.row()]
        
        if role == self.TitleRole:
            return log['filename']
        elif role == self.DateRole:
            # Format timestamp
            import datetime
            ts = log['timestamp']
            return datetime.datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M')
        elif role == self.SizeRole:
            # Format size
            size = log['file_size']
            if size > 1024 * 1024:
                return f"{size / (1024*1024):.2f} MB"
            return f"{size / 1024:.2f} KB"
        elif role == self.DurationRole:
            duration = log['duration']
            if duration:
                 m, s = divmod(duration, 60)
                 return f"{int(m)}m {int(s)}s"
            return "N/A"
        elif role == self.PathRole:
            return log['filepath']
            
        return None

    def roleNames(self):
        return {
            self.TitleRole: b'filename',
            self.DateRole: b'date',
            self.SizeRole: b'size',
            self.DurationRole: b'duration',
            self.PathRole: b'filepath'
        }
        
    def update_logs(self, new_logs):
        self.beginResetModel()
        self._logs = new_logs
        self.endResetModel()


class LogManager(QObject):
    """
    QML Backend for managing local log library.
    """
    logsUpdated = pyqtSignal()
    indexingStarted = pyqtSignal()
    indexingFinished = pyqtSignal()
    _internalIndexFinished = pyqtSignal() # Internal signal for thread safety
    
    def __init__(self):
        super().__init__()
        
        # Paths
        self.logs_dir = Path.home() / "Documents" / "TihanFly" / "Logs" / "downloaded"
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        
        self.db_path = self.logs_dir.parent / "logs.db"
        
        self.db = LogDatabase(str(self.db_path))
        self.indexer = LogIndexer(self.logs_dir, str(self.db_path))
        
        # Initial logs
        self._log_model = LogListModel(self.db.get_all_logs())
        
        # Connect internal signal
        self._internalIndexFinished.connect(self._on_indexing_finished_internal)
        
        # Initial scan on background thread
        self.refreshLogs()

    @pyqtProperty(QObject, notify=logsUpdated)
    def logModel(self):
        return self._log_model

    @pyqtSlot()
    def refreshLogs(self):
        """Start background indexing"""
        self.indexingStarted.emit()
        threading.Thread(target=self._run_indexer, daemon=True).start()
        
    def _run_indexer(self):
        try:
            self.indexer.scan_and_index()
        except Exception as e:
            print(f"Indexing error: {e}")
        finally:
            self._internalIndexFinished.emit()
            
    @pyqtSlot() 
    def _on_indexing_finished_internal(self):
        """Called on main thread after indexing"""
        logs = self.db.get_all_logs()
        self._log_model.update_logs(logs)
        self.indexingFinished.emit()
        self.logsUpdated.emit()

