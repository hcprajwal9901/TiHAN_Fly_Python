#!/usr/bin/env python3
"""
TiHAN Drone System - Main Application with Splash Screen
Version: 2.1.0
Features: Splash Screen First, then Main Application Load
"""

import faulthandler
faulthandler.enable()

import os
import sys
import signal
import atexit
import traceback as _tb
from PyQt5.QtGui import QIcon

def resource_path(relative_path):
    try:
        base_path = sys._MEIPASS  # PyInstaller temp folder
    except Exception:
        base_path = os.path.abspath(".")
    return os.path.join(base_path, relative_path)


from pathlib import Path

# MAVLink Inspector
from modules.mavlink_inspector import MavlinkMessageRateModel

# ── Global exception hook ──────────────────────────────────────────────────
# ✅ MERGED from Doc 6: PyQt5 prints "Unhandled Python exception" but swallows
# the traceback. This hook makes the full traceback visible in the terminal.
def _excepthook(exc_type, exc_value, exc_tb):
    print("\n" + "="*60)
    print("[CRASH] Unhandled Python exception:")
    _tb.print_exception(exc_type, exc_value, exc_tb)
    print("="*60 + "\n")

sys.excepthook = _excepthook

# Force add current directory to Python path
current_dir = Path(__file__).parent.absolute()
if str(current_dir) not in sys.path:
    sys.path.insert(0, str(current_dir))
print(f"📂 Added to sys.path: {current_dir}")

from PyQt5 import QtCore
from PyQt5.QtCore import (
    QUrl, QTranslator, QCoreApplication, QTimer, QObject, pyqtSignal, pyqtSlot
)
from PyQt5.QtQml import QQmlApplicationEngine, qmlRegisterType
# Try to import QtWebEngine - make it optional
try:
    from PyQt5.QtWebEngine import QtWebEngine
    QTWEBENGINE_AVAILABLE = True
    # Initialize WebEngine before creating QApplication
    QtWebEngine.initialize()
except ImportError as e:
    QTWEBENGINE_AVAILABLE = False
    print(f"⚠️ QtWebEngine not available: {e}")
    print("   Web features will be disabled")
from PyQt5.QtWidgets import QApplication, QMessageBox

# ✅ MERGED from Doc 6: Qt rendering — use OpenGL (GPU) so map tile textures
# live in VRAM, not system RAM. Software backend keeps every decoded tile in
# CPU RAM which fills gigabytes when zooming into satellite imagery.
# QT_QUICK_BACKEND and QT_OPENGL are intentionally NOT set to "software".
os.environ["QT_LOGGING_RULES"]          = "qt.qml.connections.debug=false"
os.environ["QT_QUICK_CONTROLS_STYLE"]   = "Basic"

# ── GPU / Render-loop throttling ────────────────────────────────────────────
# The default Qt Quick render loop drives repaints at monitor vsync (~60 fps)
# EVEN when nothing is moving.  On a GPU this wastes 40-50% of GPU capacity
# just to redraw a static map.
#
# QSG_RENDER_LOOP=windows  → Windows-native loop, redraws only when dirty.
# QSG_RENDER_LOOP=basic    → Single-threaded fallback, also event-driven.
#
# "windows" is a Windows-only value — on Linux it is invalid and can cause the
# renderer to crash or lock up when map/GPS activity starts. Use "basic" on
# non-Windows platforms (cross-platform, event-driven, stable).
if sys.platform == "win32":
    os.environ.setdefault("QSG_RENDER_LOOP", "windows")
else:
    os.environ.setdefault("QSG_RENDER_LOOP", "basic")

# ✅ MERGED from Doc 6: Fix QtMultimedia QML plugin DLL resolution on Windows.
# Python 3.8+ restricts the DLL search path; declarative_multimedia.dll needs
# Qt5Multimedia.dll which lives in PyQt5/Qt5/bin. Use PyQt5.__file__ to get
# the correct path regardless of venv structure.
if sys.platform == "win32":
    try:
        import PyQt5 as _pyqt5_mod
        _qt5_bin = Path(_pyqt5_mod.__file__).parent / "Qt5" / "bin"
        if _qt5_bin.exists():
            os.environ["PATH"] = str(_qt5_bin) + os.pathsep + os.environ.get("PATH", "")
            if hasattr(os, "add_dll_directory"):
                os.add_dll_directory(str(_qt5_bin))
            print(f"  ✅ Added Qt5/bin to DLL search path: {_qt5_bin}")
        else:
            print(f"  ⚠️ Qt5/bin not found at: {_qt5_bin}")
    except Exception as _e:
        print(f"  ⚠️ Could not set Qt5/bin DLL path: {_e}")

# Configure QtLocation tile cache (2GB persistent cache) - Qt 5.15
cache_dir = Path.home() / ".tihanfly" / "map_cache"
cache_dir.mkdir(parents=True, exist_ok=True)
os.environ["QT_LOCATION_TILECACHE_DIRECTORY"] = str(cache_dir)
os.environ["QT_LOCATION_TILECACHE_SIZE"]      = "2147483648"  # 2GB disk cache
print(f"📍 Map tile cache configured: {cache_dir} (disk=2GB, GPU-rendered)")


# ============================================================
# IMPORT MODULES WITH ERROR HANDLING
# ============================================================

# Try to import Qt Location and Positioning
try:
    from PyQt5 import QtLocation, QtPositioning
    from PyQt5.QtLocation import QGeoServiceProvider, QGeoMapType
    from PyQt5.QtPositioning import QGeoCoordinate, QGeoAddress
    QT_LOCATION_AVAILABLE = True
    print("✅ Qt Location and Positioning modules available")
except ImportError as e:
    QT_LOCATION_AVAILABLE = False
    print(f"⚠️ Qt Location/Positioning not available: {e}")

# Import core modules
try:
    from port_scanner_backend import PortScannerBackend
    from modules.port_detector import PortDetectorBackend
    from modules.port_manager import PortManager
    from modules.drone_module import DroneModel
    from modules.drone_commander import DroneCommander
    from modules.mission_manager import MissionManager              # ✅ Mission Protocol Manager
    from modules.nfz_manager import NFZManager                      # ✅ NFZ Manager
    from modules.camera_model import CameraModel                    # ✅ Camera Model
    from modules.rtsp_frame_provider import RtspFrameProvider       # ✅ MERGED from Doc 6: OpenCV RTSP frame provider
    from modules.drone_calibration import CalibrationModel

    # ── MERGED from Doc 6: Camera / Gimbal / GStreamer Streaming modules ────
    try:
        from modules.CameraManager import CameraManager
        from modules.GimbalManager import GimbalManager
        from modules.VideoStreamManager import VideoStreamManager as GstVideoStreamManager
        _CAMERA_MODULES_AVAILABLE = True
        print("✅ CameraManager / GimbalManager / GstVideoStreamManager imported")
    except ImportError as _cam_err:
        _CAMERA_MODULES_AVAILABLE = False
        print(f"⚠️ Camera/Gimbal/GStreamer modules not available: {_cam_err}")
        CameraManager        = None
        GimbalManager        = None
        GstVideoStreamManager = None

    from modules.compass_calibration import MissionPlannerCompassCalibration as CompassCalibrationModel
    from modules.radio_calibration import RadioCalibrationModel
    from modules.esc_calibration import ESCCalibrationModel
    
    # ✅ NEW: LogBrowser Backend
    from modules.log_browser_backend import LogBrowserBackend
    from modules.log_downloader import LogDownloader
    from modules.log_manager import LogManager
    from message_logger import MessageLogger
    from firmware_flasher_qml import FirmwareFlasher
    from modules.stubs import TrialManager, DirectionalPadController, EmailSender

    print("✅ All core modules imported successfully")
except ImportError as e:
    print(f"❌ Critical error importing modules: {e}")
    sys.exit(1)

# ============================================================
# GLOBAL APPLICATION STATE
# ============================================================

app_instance = None
app_manager  = None
main_engine  = None  # Store main engine globally

# ============================================================
# APPLICATION MANAGER CLASS
# ============================================================

class ApplicationManager(QObject):
    """Centralized application manager for proper cleanup and lifecycle management"""
    
    def __init__(self):
        super().__init__()
        self.cleanup_completed = False
        self.engines = []
        self.models  = {}
        
    def register_engine(self, engine):
        """Register QML engines for cleanup"""
        self.engines.append(engine)
        print(f"  📝 Registered engine: {type(engine).__name__}")
        
    def register_model(self, name, model):
        """Register models for cleanup"""
        if model is not None:
            self.models[name] = model
            print(f"  📝 Registered model: {name}")
        
    def cleanup_all(self):
        """Comprehensive cleanup of all resources"""
        if self.cleanup_completed:
            return
            
        print("\n" + "="*80)
        print("🧹 STARTING COMPREHENSIVE CLEANUP")
        print("="*80)
        
        # 1. Stop firmware flasher first
        self._cleanup_component('firmware_flasher',
            lambda m: (m.cancel_flashing() if hasattr(m, 'cancel_flashing') else None,
                       m.cleanup()         if hasattr(m, 'cleanup')         else None),
            "Firmware Flasher")
        
        # 2. Stop message logger capture
        self._cleanup_component('message_logger', 
            lambda m: m.stop_capture() if hasattr(m, 'stop_capture') else None,
            "Message Logger")
        
        # 3. Stop directional pad controller
        self._cleanup_component('directional_pad_controller',
            lambda m: m.stopMovement() if hasattr(m, 'stopMovement') else None,
            "Directional Pad Controller")
        
        # 4. Stop all calibrations
        self._stop_all_calibrations()
        
        # 5. Cleanup command executor
        self._cleanup_component('command_executor',
            lambda m: m.cleanup() if hasattr(m, 'cleanup') else None,
            "Command Executor")
        
        # 6. Cleanup port detector
        self._cleanup_component('port_detector',
            lambda m: m.cleanup() if hasattr(m, 'cleanup') else None,
            "Port Detector")
        
        # 7. Cleanup all registered models
        self._cleanup_all_models()
        
        # 8. Clear QML engines
        self._cleanup_engines()
        
        self.cleanup_completed = True
        print("="*80)
        print("✅ CLEANUP COMPLETED SUCCESSFULLY")
        print("="*80 + "\n")
    
    def _cleanup_component(self, name, cleanup_func, display_name):
        """Helper to cleanup individual component"""
        try:
            if name in self.models:
                print(f"  🔧 Cleaning up {display_name}...")
                cleanup_func(self.models[name])
                print(f"    ✅ {display_name} cleaned up")
        except Exception as e:
            print(f"    ⚠️ Error during {display_name} cleanup: {e}")
    
    def _stop_all_calibrations(self):
        """Stop all active calibrations"""
        print("  🔧 Stopping calibrations...")
        
        calibration_configs = [
            ('calibration_model',        ['isCalibrating',      'stopLevelCalibration', 'stopAccelCalibration'], 'Accel/Level'),
            ('compass_calibration_model', ['calibrationStarted', 'stopCalibration'],                             'Compass'),
            ('radio_calibration_model',  ['calibrationActive',  'stopCalibration'],                             'Radio'),
            ('esc_calibration_model',    ['isCalibrating',      'resetCalibrationStatus'],                      'ESC'),
        ]
        
        for model_name, methods, display_name in calibration_configs:
            try:
                if model_name in self.models:
                    model = self.models[model_name]
                    check_attr, *stop_methods = methods
                    
                    if hasattr(model, check_attr):
                        is_active = getattr(model, check_attr)
                        if callable(is_active):
                            is_active = is_active()
                        
                        if is_active:
                            print(f"    ⚙️ Stopping {display_name} calibration...")
                            for method in stop_methods:
                                if hasattr(model, method):
                                    getattr(model, method)()
            except Exception as e:
                print(f"    ⚠️ Error stopping {display_name} calibration: {e}")
    
    def _cleanup_all_models(self):
        """Cleanup all registered models"""
        print("  🔧 Cleaning up models...")
        for name, model in list(self.models.items()):
            try:
                if hasattr(model, 'cleanup'):
                    print(f"    ⚙️ Cleaning up {name}...")
                    model.cleanup()
                elif hasattr(model, 'deleteLater'):
                    model.deleteLater()
            except Exception as e:
                print(f"    ⚠️ Error cleaning up {name}: {e}")
        
        self.models.clear()
    
    def _cleanup_engines(self):
        """Cleanup QML engines"""
        print("  🔧 Cleaning up QML engines...")
        for engine in self.engines:
            try:
                if engine and hasattr(engine, 'deleteLater'):
                    engine.deleteLater()
            except Exception as e:
                print(f"    ⚠️ Error cleaning up engine: {e}")
        
        self.engines.clear()

# ============================================================
# SPLASH SCREEN MANAGER
# ============================================================

class SplashScreenManager(QObject):
    """Manages splash screen lifecycle and main window loading"""

    splashCompleted = pyqtSignal()

    def __init__(self, qml_base_path, app_mgr):
        super().__init__()
        self.qml_base_path = qml_base_path
        self.app_mgr       = app_mgr
        self.splash_engine = None
        self.splash_window = None
        self.check_timer   = None

        # ── Double-invocation guard ───────────────────────────────────────────
        # _on_splash_complete() can be reached via two independent paths:
        #   1. check_timer polling (every 100 ms) detects splashComplete == True
        #   2. 7-second fallback QTimer.singleShot in _connect_splash_signals
        #  AND via the exception handlers in _check_splash_complete.
        # Without this guard, both paths can fire in the same run, calling
        # load_main_window() twice → duplicate models → crash.
        self._transition_started = False

    def show_splash(self):
        """Show splash screen"""
        print("\n" + "="*80)
        print("🎬 LOADING SPLASH SCREEN")
        print("="*80)

        try:
            self.splash_engine = QQmlApplicationEngine()
            self.app_mgr.register_engine(self.splash_engine)

            splash_qml = self.qml_base_path / "SplashScreen.qml"

            if not splash_qml.exists():
                print(f"⚠️ Splash screen file not found: {splash_qml}")
                print("   Proceeding to main window...")
                self.splashCompleted.emit()
                return

            print(f"📄 Loading splash screen: {splash_qml}")
            self.splash_engine.load(QUrl.fromLocalFile(str(splash_qml)))

            if not self.splash_engine.rootObjects():
                print("⚠️ Failed to load splash screen")
                print("   Proceeding to main window...")
                self.splashCompleted.emit()
                return

            self.splash_window = self.splash_engine.rootObjects()[0]
            print("✅ Splash screen loaded successfully")

            self._connect_splash_signals()

        except Exception as e:
            print(f"❌ Error loading splash screen: {e}")
            print("   Proceeding to main window...")
            self.splashCompleted.emit()

    def _connect_splash_signals(self):
        """Connect to splash window signals"""
        try:
            # Verify the property exists before starting the poll timer
            self.splash_window.property("splashComplete")

            self.check_timer = QTimer()
            self.check_timer.timeout.connect(self._check_splash_complete)
            self.check_timer.start(100)

            print("🔗 Monitoring splash screen completion...")

        except Exception as e:
            print(f"⚠️ Error connecting splash signals: {e}")
            # Fallback: force transition after 7 s regardless.
            # The _transition_started guard ensures this can't double-fire
            # with the check_timer path (even if check_timer was started
            # before the exception).
            QTimer.singleShot(7000, self._on_splash_complete)

    def _check_splash_complete(self):
        """Check if splash screen is complete"""
        try:
            if self.splash_window:
                splash_complete = self.splash_window.property("splashComplete")
                if splash_complete:
                    print("✅ Splash screen completed")
                    self.check_timer.stop()
                    self._on_splash_complete()
        except Exception as e:
            print(f"⚠️ Error checking splash completion: {e}")
            if self.check_timer:
                self.check_timer.stop()
            self._on_splash_complete()

    def _on_splash_complete(self):
        """Handle splash screen completion — called at most ONCE."""
        # ── Double-invocation guard ───────────────────────────────────────────
        # This method is reachable from both the 100 ms check_timer path and
        # the 7 s fallback singleShot.  Without this guard, load_main_window()
        # would be called twice, duplicating all backend models → crash.
        if self._transition_started:
            print("🚀 (splash transition already in progress — ignoring duplicate call)")
            return
        self._transition_started = True

        print("🚀 Transitioning to main application...")

        try:
            if self.splash_window:
                # Use hide() rather than close().
                #
                # close() fires Qt's lastWindowClosed signal when no other
                # visible windows exist yet (the main window is still being
                # built).  Even with setQuitOnLastWindowClosed(False) this
                # is semantically wrong — we don't want the splash destroyed
                # immediately; we just want it invisible.
                #
                # hide() makes the window invisible without triggering any
                # close/destroy signals.  The actual C++ destruction happens
                # when the splash QML engine is deleted 2 s below.
                self.splash_window.hide()
                self.splash_window = None

            if self.splash_engine:
                # 2-second delay: gives the main QML engine time to load,
                # render its first frame, and become visible before we
                # destroy the splash engine's C++ objects.
                QTimer.singleShot(2000, self._cleanup_splash_engine)

        except Exception as e:
            print(f"⚠️ Error hiding splash: {e}")

        # Emit AFTER hiding — this triggers load_main_window()
        self.splashCompleted.emit()

    def _cleanup_splash_engine(self):
        """Cleanup splash engine after delay (called 2 s after hide)."""
        try:
            if self.splash_engine:
                # Remove from app_mgr.engines first to prevent double-deletion
                # during app shutdown cleanup (app_mgr._cleanup_engines would call
                # deleteLater on an already-deleted C++ object → crash)
                try:
                    self.app_mgr.engines.remove(self.splash_engine)
                except ValueError:
                    pass
                self.splash_engine.deleteLater()
                self.splash_engine = None
        except Exception as e:
            print(f"⚠️ Error cleaning up splash engine: {e}")



# ============================================================
# WAYPOINTS SAVER/LOADER
# ============================================================

class WaypointsSaver(QObject):
    """Handle saving and loading waypoints files"""
    
    @pyqtSlot(str, str, result=bool)
    def save_file(self, path, data):
        """Save waypoints data to file"""
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write(data)
            print(f"✅ Waypoints saved: {path}")
            return True
        except Exception as e:
            print(f"❌ Error saving waypoints: {e}")
            return False

    @pyqtSlot(str, result=str)
    def load_file(self, file_path):
        """Load waypoints from file"""
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
            print(f"✅ Waypoints loaded: {file_path}")
            return content
        except Exception as e:
            print(f"❌ Error loading waypoints: {e}")
            return ""

# ============================================================
# MAP COMMUNICATION BRIDGE
# ============================================================

class MapCommunicationBridge(QObject):
    """Bridge for communication between QML and Google Maps WebEngine"""
    
    mapClicked    = pyqtSignal(float, float)
    markerClicked = pyqtSignal(int, float, float, float, float)
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.markers   = []
        self._destroyed = False
    
    @pyqtSlot(str)
    def processWebMessage(self, message):
        """Legacy WebEngine message handler - now stubbed for QML Map"""
        pass

    @pyqtSlot(float, float, float, float, result=int)
    def addMarker(self, lat, lng, altitude, speed):
        """Add a marker to the map"""
        if self._destroyed:
            return -1
        try:
            marker_data = {
                'lat': lat, 'lng': lng,
                'altitude': altitude, 'speed': speed,
                'index': len(self.markers)
            }
            self.markers.append(marker_data)
            return len(self.markers) - 1
        except Exception as e:
            print(f"❌ Error adding marker: {e}")
            return -1
    
    @pyqtSlot(int)
    def deleteMarker(self, index):
        """Delete a marker from the map"""
        if self._destroyed:
            return
        try:
            if 0 <= index < len(self.markers):
                self.markers.pop(index)
                for i, marker in enumerate(self.markers):
                    marker['index'] = i
        except Exception as e:
            print(f"❌ Error deleting marker: {e}")
    
    @pyqtSlot(result=str)
    def getMarkersJson(self):
        """Get all markers as JSON string"""
        if self._destroyed:
            return "[]"
        try:
            import json
            return json.dumps(self.markers)
        except Exception as e:
            print(f"❌ Error getting markers JSON: {e}")
            return "[]"
            
    def cleanup(self):
        """Clean up the bridge"""
        self._destroyed = True
        self.markers.clear()

# ============================================================
# SIGNAL HANDLERS
# ============================================================

def setup_signal_handlers(app):
    """Setup signal handlers for graceful shutdown"""
    def signal_handler(signum, frame):
        print(f"\n🛑 Received signal {signum}, initiating shutdown...")
        if app:
            QTimer.singleShot(0, app.quit)
    
    signal.signal(signal.SIGINT,  signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    if hasattr(signal, 'SIGBREAK'):
        signal.signal(signal.SIGBREAK, signal_handler)

# ============================================================
# QT PATHS SETUP
# ============================================================

def setup_qt_paths():
    """Setup Qt paths for plugins and QML"""
    try:
        if getattr(sys, 'frozen', False):
            base_path = Path(sys._MEIPASS)
            qml_path  = base_path / "App" / "qml"

            QCoreApplication.setLibraryPaths([])
            
            plugin_dirs = [
                'platforms', 'position', 'geoservices', 'imageformats',
                'bearer', 'tls', 'iconengines', 'generic'
            ]
            
            for plugin_dir in plugin_dirs:
                full_path = base_path / plugin_dir
                if full_path.exists():
                    QCoreApplication.addLibraryPath(str(full_path))

            qml_dirs = [
                qml_path,
                base_path / 'qml',
                base_path / 'QtLocation',
                base_path / 'QtPositioning'
            ]
            
            existing_dirs = [str(d) for d in qml_dirs if d.exists()]
            if existing_dirs:
                os.environ['QML2_IMPORT_PATH'] = os.pathsep.join(existing_dirs)
                os.environ['QML_IMPORT_PATH']  = os.environ['QML2_IMPORT_PATH']
            
            os.environ['QT_PLUGIN_PATH'] = str(base_path)
            return qml_path
        else:
            pyqt5_plugins = Path(sys.executable).parent.parent / "Lib" / "site-packages" / "PyQt5" / "Qt5" / "plugins"
            if pyqt5_plugins.exists():
                QCoreApplication.addLibraryPath(str(pyqt5_plugins))
                print(f"  ✅ PyQt5 plugins path added: {pyqt5_plugins}")
            
            return current_dir / "App" / "qml"
            
    except Exception as e:
        print(f"⚠️ Error setting up Qt paths: {e}")
        return current_dir / "App" / "qml"

# ============================================================
# WINDOW OPENERS
# ============================================================

def create_calibration_window_opener(qml_base_path, calibration_model, drone_model, drone_commander, app_mgr):
    """Create calibration window opener"""
    @pyqtSlot()
    def openCalibrationWindow():
        try:
            if not drone_model.isConnected:
                QMessageBox.warning(None, "Connection Required", 
                                   "Please connect to the drone before opening calibration.")
                return
            
            print("🔧 Opening calibration window...")
            calibration_engine = QQmlApplicationEngine()
            app_mgr.register_engine(calibration_engine)
            
            calibration_engine.rootContext().setContextProperty("calibrationModel",  calibration_model)
            calibration_engine.rootContext().setContextProperty("droneModel",         drone_model)
            calibration_engine.rootContext().setContextProperty("droneCommander",     drone_commander)
            
            calibration_qml = qml_base_path / "AccelCalibration.qml"
            if calibration_qml.exists():
                calibration_engine.load(QUrl.fromLocalFile(str(calibration_qml)))
                if calibration_engine.rootObjects():
                    print("✅ Calibration window opened")
                else:
                    QMessageBox.critical(None, "Error", "Failed to load calibration window")
            else:
                QMessageBox.critical(None, "File Error", f"Calibration file not found:\n{calibration_qml}")
        except Exception as e:
            print(f"❌ Error opening calibration window: {e}")
            QMessageBox.critical(None, "Error", f"Failed to open calibration window:\n{str(e)}")
    
    return openCalibrationWindow


def create_tinari_window_opener(qml_base_path, firmware_flasher, port_detector, app_mgr):
    """Create Ti-NARI firmware flashing window opener"""
    @pyqtSlot()
    def openTinariWindow():
        try:
            print("⚡ Opening Ti-NARI Firmware Flasher...")
            tinari_engine = QQmlApplicationEngine()
            app_mgr.register_engine(tinari_engine)
            
            tinari_engine.rootContext().setContextProperty("firmwareFlasher", firmware_flasher)
            tinari_engine.rootContext().setContextProperty("portDetector",    port_detector)
            
            tinari_qml = qml_base_path / "TinariWindow.qml"
            if tinari_qml.exists():
                tinari_engine.load(QUrl.fromLocalFile(str(tinari_qml)))
                if tinari_engine.rootObjects():
                    print("✅ Ti-NARI window opened")
                else:
                    QMessageBox.critical(None, "Error", "Failed to load Ti-NARI window")
            else:
                QMessageBox.critical(None, "File Error", f"Ti-NARI file not found:\n{tinari_qml}")
        except Exception as e:
            print(f"❌ Error opening Ti-NARI window: {e}")
            QMessageBox.critical(None, "Error", f"Failed to open Ti-NARI window:\n{str(e)}")
    
    return openTinariWindow


def create_mavlink_inspector_window_opener(qml_base_path, mavlink_inspector_model, app_mgr):
    """Create MAVLink Inspector window opener with model injected into its own engine"""
    @pyqtSlot()
    def openMavlinkInspectorWindow():
        try:
            print("🔍 Opening MAVLink Inspector...")
            inspector_engine = QQmlApplicationEngine()
            app_mgr.register_engine(inspector_engine)

            # ← THIS is the critical line the window needs
            inspector_engine.rootContext().setContextProperty(
                "mavlinkInspectorModel", mavlink_inspector_model
            )

            inspector_qml = qml_base_path / "MavlinkInspectorWindow.qml"
            if inspector_qml.exists():
                inspector_engine.load(QUrl.fromLocalFile(str(inspector_qml)))
                root_objects = inspector_engine.rootObjects()
                if root_objects:
                    root_objects[0].setProperty("visible", True)
                    print("✅ MAVLink Inspector window opened")
                else:
                    QMessageBox.critical(None, "Error", "Failed to load MAVLink Inspector window")
            else:
                QMessageBox.critical(None, "File Error",
                                     f"MAVLink Inspector QML not found:\n{inspector_qml}")
        except Exception as e:
            print(f"❌ Error opening MAVLink Inspector: {e}")
            QMessageBox.critical(None, "Error",
                                 f"Failed to open MAVLink Inspector:\n{str(e)}")

    return openMavlinkInspectorWindow

# ============================================================
# MAIN WINDOW LOADING
# ============================================================

def load_main_window(qml_base_path, app_mgr):
    """Load the main application window after splash"""
    global main_engine, _main_window_loaded

    # ── Double-invocation guard ───────────────────────────────────────────────
    # splashCompleted can fire synchronously inside show_splash() (splash QML
    # fails to load fast) AND then again when the check_timer polls 100 ms
    # after exec_() starts.  The second invocation gets an already-used engine
    # with empty rootObjects() → returns False → app_instance.quit() → crash.
    if _main_window_loaded:
        print("⚠️ load_main_window() called again — ignoring duplicate call")
        return True
    _main_window_loaded = True

    print("\n" + "="*80)
    print("🚁 LOADING MAIN APPLICATION")
    print("="*80 + "\n")

    try:
        # Initialize trial manager
        print("⏱️ Initializing trial manager...")
        try:
            trial_manager = TrialManager()
        except Exception as e:
            print(f"⚠️ Trial manager initialization failed: {e}")
            trial_manager = None
        
        # Setup translation
        print("🌐 Setting up translations...")
        translator     = QTranslator()
        translation_path = qml_base_path.parent / "translations_ta.qm"
        if translation_path.exists() and translator.load(str(translation_path)):
            app_instance.installTranslator(translator)
            print("✅ Translation loaded")
        
        # Initialize main QML engine
        print("🎨 Initializing main QML engine...")
        main_engine = QQmlApplicationEngine()
        app_mgr.register_engine(main_engine)
        
        # Initialize Map Communication Bridge
        print("🌐 Initializing Map Communication Bridge...")
        map_bridge = MapCommunicationBridge()
        app_mgr.register_model('map_bridge', map_bridge)
        
        # Initialize backend models
        print("🔧 Initializing backend models...")
        
        # Message Logger
        print("  📨 Message Logger...")
        message_logger = MessageLogger()
        app_mgr.register_model('message_logger', message_logger)
        
        # Drone models
        drone_model = DroneModel()
        app_mgr.register_model('drone_model', drone_model)
        
        drone_commander = DroneCommander(drone_model)
        app_mgr.register_model('drone_commander', drone_commander)

        # ✅ Mission Manager — spec-compliant MAVLink mission protocol
        mission_manager = MissionManager()
        app_mgr.register_model('mission_manager', mission_manager)

        # ✅ Camera Model - handles stream, recording, zoom, camera switching
        print("  📷 Camera Model...")
        camera_model = CameraModel(drone_commander)
        app_mgr.register_model('camera_model', camera_model)
        print("    ✅ Camera Model initialized")

        # ✅ MERGED from Doc 6: RTSP Frame Provider - OpenCV-based stream for QML Image
        # on_stream_failed is called from the worker thread when OpenCV cannot
        # open the URL — use QTimer.singleShot to safely invoke on main thread
        def _on_stream_failed():
            QTimer.singleShot(0, camera_model.disconnectStream)

        rtsp_provider = RtspFrameProvider(on_stream_failed=_on_stream_failed)
        # Register with QML engine so Image { source: "image://rtspframes/frame" } works
        main_engine.addImageProvider("rtspframes", rtsp_provider)
        print("    ✅ RTSP Frame Provider registered")

        # ── MERGED from Doc 6: GStreamer-based multi-camera managers ─────────
        camera_manager    = None
        gimbal_manager    = None
        gst_video_manager = None

        if _CAMERA_MODULES_AVAILABLE:
            print("  📷 CameraManager (MAVLink)...")
            try:
                camera_manager = CameraManager(drone_commander=drone_commander)
                app_mgr.register_model('camera_manager', camera_manager)
                print("    ✅ CameraManager initialized")
            except Exception as _e:
                print(f"    ⚠️ CameraManager failed (non-fatal): {_e}")

            print("  🎯 GimbalManager (MAVLink)...")
            try:
                gimbal_manager = GimbalManager(drone_commander=drone_commander)
                app_mgr.register_model('gimbal_manager', gimbal_manager)
                print("    ✅ GimbalManager initialized")
            except Exception as _e:
                print(f"    ⚠️ GimbalManager failed (non-fatal): {_e}")

            print("  📡 GstVideoStreamManager (GStreamer)...")
            try:
                import faulthandler; faulthandler.enable()  # shows C-level crash tracebacks
                gst_video_manager = GstVideoStreamManager()
                app_mgr.register_model('gst_video_manager', gst_video_manager)
                print("    ✅ GstVideoStreamManager initialized")
            except Exception as _e:
                print(f"    ⚠️ GstVideoStreamManager failed (non-fatal): {_e}")
                print("    ℹ️  Video streaming will be unavailable this session")
        else:
            print("  ⚠️ Skipping Camera/Gimbal/GStreamer managers (modules unavailable)")

        # ✅ NFZ Manager - create without loading yet (loading happens AFTER QML is ready)
        # Do NOT pass geojson_path here — NFZManager.__init__ would call loadNFZFromFile()
        # synchronously, blocking the Qt event loop for ~1-2 s while parsing the 13 MB JSON,
        # and then main.py line ~1151 would call it again (double-parse / crash risk).
        print("  🚫 NFZ Manager...")
        geojson_path = str(current_dir / "export.geojson")
        nfz_manager  = NFZManager()   # ← no path: load deferred until after QML load
        app_mgr.register_model('nfz_manager', nfz_manager)
        print("    ✅ NFZ Manager initialized")

        # ✅ MERGED from Doc 5: Wire NFZ manager into drone_commander for backend takeoff guard
        drone_commander.nfz_manager = nfz_manager
        print("    ✅ NFZ Manager wired into DroneCommander (takeoff block active)")

        # Firmware Flasher
        firmware_flasher = FirmwareFlasher()
        app_mgr.register_model('firmware_flasher', firmware_flasher)
        
        # Directional Pad Controller
        print("  🎮 Directional Pad Controller...")
        try:
            directional_pad_controller = DirectionalPadController(drone_model)
            app_mgr.register_model('directional_pad_controller', directional_pad_controller)
            directional_pad_controller.statusChanged.connect(
                lambda msg, sev: message_logger.logMessage(msg, sev)
            )
            print("    ✅ Directional Pad Controller initialized")
        except Exception as e:
            print(f"    ❌ Error: {e}")
            directional_pad_controller = None
        
        # Port Manager
        port_manager = PortManager()
        app_mgr.register_model('port_manager', port_manager)
        
        # Port Detector
        print("  🔌 Port Detector...")
        try:
            port_detector = PortDetectorBackend()
            app_mgr.register_model('port_detector', port_detector)
            print("    ✅ Port Detector initialized")
        except Exception as e:
            print(f"    ❌ Error: {e}")
            port_detector = None
        
        # Email Sender
        print("  📧 Email Sender...")
        try:
            email_sender = EmailSender()
            app_mgr.register_model('email_sender', email_sender)
            print("    ✅ Email Sender initialized")
        except Exception as e:
            print(f"    ❌ Error: {e}")
            email_sender = None
            
        # MAVLink Inspector Model
        print("  🔍 MAVLink Inspector Model...")
        try:
            mavlink_inspector_model = MavlinkMessageRateModel()
            app_mgr.register_model('mavlink_inspector_model', mavlink_inspector_model)
            
            # NOTE: Do NOT use the cross-thread mavlinkMessageReceived signal here.
            # That signal was emitted ~100×/sec from the MAVLink thread, building
            # an unbounded Qt event queue that consumed all RAM on Ubuntu.
            # Instead, we wire process_message as a direct Python callback AFTER
            # the drone connects — see _wire_mavlink_callbacks_on_connect() below.
            print("    ✅ MAVLink Inspector Model initialized (will wire on connect)")
        except Exception as e:
            print(f"    ❌ Error: {e}")
            mavlink_inspector_model = None

        # Log Browser Backend
        print("  📊 Log Browser Backend...")
        try:
            log_browser_backend = LogBrowserBackend()
            app_mgr.register_model('log_browser_backend', log_browser_backend)
            print("    ✅ Log Browser Backend initialized")
        except Exception as e:
            print(f"    ❌ Error: {e}")
            log_browser_backend = None
            
        # Log Downloader & Manager
        print("  📥 Log Downloader & Manager...")
        try:
            log_downloader = LogDownloader(drone_model)
            app_mgr.register_model('log_downloader', log_downloader)
            
            log_manager = LogManager()
            app_mgr.register_model('log_manager', log_manager)
            print("    ✅ Log Downloader & Manager initialized")
        except Exception as e:
            print(f"    ❌ Error initializing Log System: {e}")
            log_downloader = None
            log_manager = None
        
        # Calibration models
        # NOTE: drone_model._drone is None at startup (no drone connected yet).
        # CalibrationModel stores mav=None; actual mav object is assigned later
        # inside DroneModel._on_connection_success via
        # self._calibration_model.mav = self._drone
        calibration_model = CalibrationModel(None)   # ← pass None explicitly; mav set on connect
        app_mgr.register_model('calibration_model', calibration_model)
        drone_model.setCalibrationModel(calibration_model)
        
        compass_calibration_model = CompassCalibrationModel(drone_model)
        app_mgr.register_model('compass_calibration_model', compass_calibration_model)
        
        radio_calibration_model = RadioCalibrationModel(drone_model)
        app_mgr.register_model('radio_calibration_model', radio_calibration_model)
        
        esc_calibration_model = ESCCalibrationModel(drone_model)
        app_mgr.register_model('esc_calibration_model', esc_calibration_model)
      
        print("✅ All models initialized successfully\n")
        
        # Register QML types
        print("📋 Registering QML types...")
        try:
            qmlRegisterType(CalibrationModel,         "TiHAN.Calibration", 1, 0, "CalibrationModel")
            qmlRegisterType(CompassCalibrationModel,  "TiHAN.Compass",     1, 0, "CompassCalibrationModel")
            qmlRegisterType(RadioCalibrationModel,    "TiHAN.Radio",       1, 0, "RadioCalibrationModel")
            qmlRegisterType(ESCCalibrationModel,      "TiHAN.ESC",         1, 0, "ESCCalibrationModel")
            print("✅ QML types registered\n")
        except Exception as e:
            print(f"⚠️ QML type registration warning: {e}\n")
        
        # ── Signal connections ───────────────────────────────────────────────
        print("🔗 Setting up signal connections...")
        
        # Map bridge handlers
        def handle_map_click(lat, lng):
            message_logger.logMessage(f"Map clicked: {lat:.6f}, {lng:.6f}", "info")
            
        def handle_marker_click(index, lat, lng, altitude, speed):
            message_logger.logMessage(f"Marker {index} clicked: {lat:.6f}, {lng:.6f}", "info")
            
        map_bridge.mapClicked.connect(handle_map_click)
        map_bridge.markerClicked.connect(handle_marker_click)
        
        # ✅ NFZ breach logging - connect to message logger
        def on_nfz_breach(zone_name):
            message_logger.logMessage(f"🚨 NFZ BREACH DETECTED: {zone_name}", "error")
            print(f"🚨 DRONE ENTERED NO-FLY ZONE: {zone_name}")

        def on_nfz_exit():
            message_logger.logMessage("✅ Drone exited restricted airspace", "success")
            print("✅ Drone exited NFZ")

        nfz_manager.droneInNFZ.connect(on_nfz_breach)
        nfz_manager.droneExitedNFZ.connect(on_nfz_exit)

        # Drone connection handlers
        def on_drone_disconnected():
            message_logger.logMessage("⚠️ Drone disconnected - stopping operations", "warning")
            if directional_pad_controller:
                directional_pad_controller.stopMovement()
            app_mgr._stop_all_calibrations()
            # Resume COM-port scanning now that the drone is gone
            port_manager.clearActivePort()

        def on_drone_connected():
            if drone_model.isConnected:
                message_logger.logMessage("✅ Drone connected successfully", "success")

                # ✅ Stop the port scanner from probing COM ports while the flight
                # controller is active — avoids competing with the MAVLink socket.
                # Use a placeholder key so _active_port is non-None.
                port_manager.setActivePort("__drone_connected__")

                if drone_model._drone_commander:
                    print("📡 Updating droneCommander in QML context...")
                    main_engine.rootContext().setContextProperty("droneCommander", drone_model._drone_commander)
                    print("✅ droneCommander available to QML")

                if esc_calibration_model:
                    QTimer.singleShot(2000, esc_calibration_model.testBuzzer)
        
        drone_model.droneConnectedChanged.connect(
            lambda: on_drone_disconnected() if not drone_model.isConnected else on_drone_connected()
        )

        # ✅ NFZ periodic check - check drone position against NFZ every 5 seconds
        # Uses checkDronePosition() which fires droneNearNFZ / droneInNFZ /
        # droneExitedNFZ / droneExitedProximity signals with full state-machine logic.
        # 5 s is adequate for safety and avoids log spam / CPU churn from the
        # proximity re-emit path.
        nfz_check_timer = QTimer()
        nfz_check_timer.setInterval(5000)

        def _check_nfz_position():
            if drone_model.isConnected and drone_model.telemetry:
                tel = drone_model.telemetry
                lat = tel.get("lat", 0.0) if isinstance(tel, dict) else getattr(tel, "lat", 0.0)
                lon = tel.get("lon", 0.0) if isinstance(tel, dict) else getattr(tel, "lon", 0.0)
                if lat != 0.0 and lon != 0.0:
                    nfz_manager.checkDronePosition(lat, lon)  # fires all NFZ signals

        # Proximity warning → message logger
        def on_nfz_near(zone_name, dist_m):
            message_logger.logMessage(
                f"⚠️ Approaching NFZ: {zone_name}  (dist={dist_m:.0f} m)", "warning"
            )
            print(f"⚠️ DRONE NEAR NFZ: {zone_name}  dist={dist_m:.0f} m")

        def on_nfz_proximity_cleared():
            message_logger.logMessage("✅ Cleared NFZ proximity zone", "info")

        nfz_manager.droneNearNFZ.connect(on_nfz_near)
        nfz_manager.droneExitedProximity.connect(on_nfz_proximity_cleared)

        nfz_check_timer.timeout.connect(_check_nfz_position)
        nfz_check_timer.start()
        # Keep reference so it doesn't get garbage collected
        app_mgr.models['nfz_check_timer'] = nfz_check_timer
        
        # Camera model status → message logger
        camera_model.statusMessage.connect(
            lambda msg: message_logger.logMessage(msg, "info")
        )

        # ✅ MERGED from Doc 6: Wire stream signals — use OpenCV rtsp_frame_provider
        # (stable on Windows). GStreamer crashes at the C level on this Windows
        # installation even with the software decodebin profile.
        def _on_streaming_changed():
            try:
                if camera_model.isStreaming:
                    rtsp_provider.start(camera_model.rtspUrl)
                else:
                    rtsp_provider.stop()
            except Exception as _e:
                import traceback
                print(f"[Stream] Error in streaming handler: {_e}")
                traceback.print_exc()

        camera_model.isStreamingChanged.connect(_on_streaming_changed)

        # ── Route MAVLink messages to camera/gimbal managers AND inspector ──────
        # All wiring uses register_msg_callback() — direct Python calls inside the
        # MAVLink thread with zero Qt event-queue overhead.
        # Replaces the old current_msg signal (removed) and the cross-thread
        # mavlinkMessageReceived signal (which caused unbounded RAM growth).

        def _wire_mavlink_callbacks_on_connect():
            """Wire direct Python callbacks after drone connects."""
            if not drone_model.isConnected or not drone_model._thread:
                return
            thread = drone_model._thread

            # Inspector — already has its own thread-safe queue drained every 200 ms
            if mavlink_inspector_model is not None:
                thread.register_msg_callback(mavlink_inspector_model.process_message)
                print("[Main] ✅ MAVLink Inspector wired via register_msg_callback")

            # Wire compass calibration message queue (fixes WiFi calibration)
            if compass_calibration_model is not None:
                thread.register_msg_callback(compass_calibration_model.push_mavlink_msg)
                print("[Main] ✅ Compass Calibration wired via register_msg_callback")

            # Wire radio calibration — delivers RC_CHANNELS directly from MAVLinkThread
            # with zero latency (no polling, no shared-socket competition).
            if radio_calibration_model is not None:
                def _rc_msg_dispatcher(msg):
                    msg_type = msg.get_type()
                    if msg_type == 'RC_CHANNELS':
                        radio_calibration_model.on_rc_channels_message(msg)
                    elif msg_type == 'RC_CHANNELS_RAW':
                        radio_calibration_model.on_rc_channels_raw_message(msg)
                thread.register_msg_callback(_rc_msg_dispatcher)
                print("[Main] ✅ Radio Calibration wired via register_msg_callback (zero-latency RC)")

            # Log Downloader — needs LOG_ENTRY and LOG_DATA messages
            if log_downloader is not None:
                thread.register_msg_callback(log_downloader._process_mavlink_message)
                print("[Main] ✅ LogDownloader wired via register_msg_callback")

            # Camera / Gimbal managers
            if camera_manager or gimbal_manager:
                def _route_mavlink_to_camera_gimbal(msg):
                    try:
                        if camera_manager:
                            camera_manager.handleMAVLinkMessage(msg)
                        if gimbal_manager:
                            gimbal_manager.handleMAVLinkMessage(msg)
                    except Exception:
                        pass  # Silently ignore — do not disrupt existing telemetry

                thread.register_msg_callback(_route_mavlink_to_camera_gimbal)
                print("[Main] ✅ Camera/Gimbal managers wired via register_msg_callback")

            # Mission Manager — route mission protocol messages
            if mission_manager is not None:
                mission_manager.setConnection(drone_model.drone_connection)
                thread.register_msg_callback(mission_manager.handle_mavlink_message)
                print("[Main] ✅ MissionManager wired via register_msg_callback")

        drone_model.droneConnectedChanged.connect(
            lambda: _wire_mavlink_callbacks_on_connect() if drone_model.isConnected else None
        )

        # ── MERGED from Doc 6: Log GStreamer hardware profile ────────────────
        if gst_video_manager:
            gst_profile = gst_video_manager.hardwareProfile
            message_logger.logMessage(
                f"📡 GStreamer video decoder profile: {gst_profile}", "info"
            )
            print(f"[Main] GStreamer profile: {gst_profile}")

        # Email sender connections
        if email_sender:
            email_sender.emailSent.connect(
                lambda success, msg: message_logger.logMessage(f"📧 {msg}", "success" if success else "error")
            )
        
        print("✅ Signal connections established\n")
        
        # ── Expose models to QML ─────────────────────────────────────────────
        print("🔗 Exposing models to QML...")
        ctx = main_engine.rootContext()
        
        # Core models
        ctx.setContextProperty("droneModel",      drone_model)
        ctx.setContextProperty("droneCommander",  drone_commander)
        ctx.setContextProperty("missionManager",  mission_manager)
        ctx.setContextProperty("cameraModel",     camera_model)      # ✅ Camera Model
        ctx.setContextProperty("nfzManager",      nfz_manager)       # ✅ NFZ Manager
        ctx.setContextProperty("portManager",     port_manager)
        ctx.setContextProperty("messageLogger",   message_logger)
        if 'firmware_flasher' in locals() and firmware_flasher is not None:
            ctx.setContextProperty("firmwareFlasher", firmware_flasher)
        
        if mavlink_inspector_model is not None:
            print("🔗 Exposing mavlinkInspectorModel context property...")
            ctx.setContextProperty("mavlinkInspectorModel", mavlink_inspector_model)
        else:
            print("⚠️ mavlink_inspector_model is None, not exposing to QML.")
        
        # Optional models
        ctx.setContextProperty("portDetector",             port_detector)
        ctx.setContextProperty("emailSender",              email_sender)
        ctx.setContextProperty("directionalPadController", directional_pad_controller)
        
        # Calibration models
        ctx.setContextProperty("calibrationModel",        calibration_model)
        ctx.setContextProperty("compassCalibrationModel", compass_calibration_model)
        ctx.setContextProperty("radioCalibrationModel",   radio_calibration_model)
        ctx.setContextProperty("escCalibrationModel",     esc_calibration_model)
        
        if 'log_browser_backend' in locals() and log_browser_backend is not None:
             ctx.setContextProperty("logBrowser", log_browser_backend)
             
        if 'log_downloader' in locals() and log_downloader is not None:
             ctx.setContextProperty("logDownloader", log_downloader)
             
        if 'log_manager' in locals() and log_manager is not None:
             ctx.setContextProperty("logManager", log_manager)
        
        # Utility objects
        ctx.setContextProperty("mapBridge",         map_bridge)
        waypoints_saver = WaypointsSaver()
        app_mgr.register_model('waypoints_saver', waypoints_saver)
        ctx.setContextProperty("waypointsSaver",    waypoints_saver)
        ctx.setContextProperty("googleMapsApiKey",  "AIzaSyDnBjIddcNnhfndEEJHi8puawYx3cPspWI")

        # ── MERGED from Doc 6: Camera / Gimbal / GStreamer managers ──────────
        ctx.setContextProperty("cameraManager",      camera_manager)      # MAVLink camera ctrl
        ctx.setContextProperty("gimbalManager",      gimbal_manager)      # MAVLink gimbal ctrl
        ctx.setContextProperty("videoStreamManager", gst_video_manager)   # GStreamer RTSP
        
        # Window openers — must be registered via app_mgr to prevent GC during QML load
        tinari_opener = create_tinari_window_opener(qml_base_path, firmware_flasher, port_detector, app_mgr)
        app_mgr.register_model('tinari_opener', tinari_opener)
        ctx.setContextProperty("tinariWindowOpener", tinari_opener)

        calibration_opener = create_calibration_window_opener(
            qml_base_path, calibration_model, drone_model, drone_commander, app_mgr
        )
        app_mgr.register_model('calibration_opener', calibration_opener)
        ctx.setContextProperty("calibrationWindowOpener", calibration_opener)

        mavlink_inspector_opener = create_mavlink_inspector_window_opener(
            qml_base_path, mavlink_inspector_model, app_mgr
        )
        app_mgr.register_model('mavlink_inspector_opener', mavlink_inspector_opener)
        ctx.setContextProperty("mavlinkInspectorWindowOpener", mavlink_inspector_opener)
        
        print("✅ Models exposed to QML successfully\n")
        
        # Load main QML file
        qml_file = qml_base_path / "Main.qml"
        print(f"📄 Loading main QML file: {qml_file}")
        
        if not qml_file.exists():
            print(f"❌ Main QML file not found: {qml_file}")
            QMessageBox.critical(None, "File Error", f"Main QML file not found:\n{qml_file}")
            return False
        
        try:
            main_engine.load(QUrl.fromLocalFile(str(qml_file)))
            if not main_engine.rootObjects():
                print("❌ Failed to load main QML file")
                QMessageBox.critical(None, "QML Error", "Failed to load the main QML file")
                return False
            print("✅ Main QML file loaded successfully\n")

            # ✅ CRITICAL: Load NFZ data AFTER QML engine is ready
            # geojson_path was captured earlier in this function.
            print("🚫 Loading NFZ data from GeoJSON...")
            try:
                nfz_manager.loadNFZFromFile(geojson_path)
                print(f"✅ NFZ data loaded: {nfz_manager.nfzCount} zones")
            except Exception as nfz_err:
                print(f"⚠️ NFZ load failed (non-fatal): {nfz_err}")

        except Exception as e:
            print(f"❌ Exception loading main QML: {e}")
            import traceback
            traceback.print_exc()
            QMessageBox.critical(None, "QML Error", f"Exception loading main QML file:\n{str(e)}")
            return False
        
        # Start message logger capture
        print("📨 Starting message logger capture...")
        message_logger.start_capture()
        message_logger.logMessage("🚀 TiHAN Drone System initialized successfully", "success")
        message_logger.logMessage(f"🚫 NFZ System active: {nfz_manager.nfzCount} no-fly zones loaded", "info")
        
        if email_sender:
            message_logger.logMessage("📧 Feedback system ready - multiple delivery methods active", "info")
        
        if directional_pad_controller:
            message_logger.logMessage("🎮 Directional Pad Controller ready for flight control", "info")
        
        # Setup trial manager
        if trial_manager:
            try:
                def handle_trial_expired():
                    msg = QMessageBox()
                    msg.setIcon(QMessageBox.Information)
                    msg.setText("Trial period expired")
                    msg.setStandardButtons(QMessageBox.Ok)
                    msg.exec_()
                    app_instance.quit()
                
                trial_manager.trial_expired.connect(handle_trial_expired)
                trial_manager.start_trial()
            except Exception as e:
                print(f"⚠️ Trial manager setup warning: {e}")
        
        print_system_status(directional_pad_controller, email_sender, firmware_flasher)
        
        return True
        
    except Exception as e:
        print(f"❌ Error loading main window: {e}")
        import traceback
        traceback.print_exc()
        QMessageBox.critical(None, "Error", f"Failed to load main application:\n{str(e)}")
        return False

# ============================================================
# MAIN APPLICATION
# ============================================================

# Guard: prevents load_main_window() from running more than once.
# This can happen when splashCompleted emits synchronously during show_splash()
# (splash QML fails fast) AND then again via the check_timer — the second
# call gets an empty rootObjects() → returns False → app_instance.quit().
_main_window_loaded = False

def main():
    """Main application entry point"""
    global app_instance, app_manager

    try:
        print("\n" + "="*80)
        print("🚁 TiHAN DRONE SYSTEM - v2.1.0")
        print("="*80 + "\n")
        
        app_manager    = ApplicationManager()
        qml_base_path  = setup_qt_paths()
        
        app_instance = QApplication(sys.argv)

        icon_path = resource_path("App/tihan1.ico")
        app_instance.setWindowIcon(QIcon(icon_path))
        app_instance.setApplicationName("TihanFly")
        app_instance.setApplicationVersion("v2.1.0")
        app_instance.setOrganizationName("TiHAN")

        # NOTE: A processEvents() keepalive QTimer that was present in an earlier
        # revision caused dangerous re-entrancy in Qt's event loop and triggered
        # "Unhandled Python exception" crashes. It has been intentionally removed.
        
        setup_signal_handlers(app_instance)

        # ── Cleanup handler ──────────────────────────────────────────────────
        def cleanup_application():
            print("\n🧹 Application cleanup initiated...")
            try:
                if 'firmware_flasher' in app_manager.models:
                    print("  🔧 Stopping firmware flasher...")
                    try:
                        fw_flasher = app_manager.models['firmware_flasher']
                        if hasattr(fw_flasher, 'cancel_flashing'):
                            fw_flasher.cancel_flashing()
                        if hasattr(fw_flasher, 'cleanup'):
                            fw_flasher.cleanup()
                    except Exception as e:
                        print(f"    ⚠️ Error cleaning firmware flasher: {e}")

                # Stop NFZ check timer
                if 'nfz_check_timer' in app_manager.models:
                    try:
                        app_manager.models['nfz_check_timer'].stop()
                    except Exception:
                        pass

                app_manager.cleanup_all()

                # Force-kill the process after 3 s in a daemon thread.
                # QTimer.singleShot cannot fire after exec_() returns, so
                # non-daemon QThreads (e.g. PnpWatcher) would keep Python
                # alive indefinitely — requiring the user to press Ctrl+C.
                import threading as _threading
                def _force_exit():
                    import time as _time
                    _time.sleep(3.0)
                    os._exit(0)
                _t = _threading.Thread(target=_force_exit, daemon=True)
                _t.start()

            except Exception as e:
                print(f"❌ Error during cleanup: {e}")
                os._exit(1)

        app_instance.aboutToQuit.connect(cleanup_application)
        atexit.register(lambda: app_manager.cleanup_all() if not app_manager.cleanup_completed else None)

        # ── Protect the loading phase from spurious quit ────────────────────
        # main_engine.load() internally processes Qt events. If any QML
        # component briefly creates/destroys a window, or if PnpWatcher/WMI
        # causes signal activity, Qt's default lastWindowClosed → quit()
        # fires and sets the quit flag. exec_() then returns immediately.
        # Disable during load, re-enable once the event loop is running.
        app_instance.setQuitOnLastWindowClosed(False)

        success = load_main_window(qml_base_path, app_manager)
        if not success:
            print("❌ Failed to load main window, exiting...")
            return 1

        # Re-enable after a single event-loop iteration so the main window
        # is fully visible and closing it will properly quit the app.
        def _restore_quit_on_close():
            app_instance.setQuitOnLastWindowClosed(True)
            print("✅ quitOnLastWindowClosed re-enabled")
        QTimer.singleShot(0, _restore_quit_on_close)

        # Start FirmwareFlasher port scanner only after all other port activity settles.
        if 'firmware_flasher' in app_manager.models:
            QTimer.singleShot(
                12000,
                app_manager.models['firmware_flasher'].start_port_scanner
            )
            print("⏱️  FirmwareFlasher port scanner scheduled in 12 s")

        exit_code = app_instance.exec_()
        print(f"\n👋 Application exited with code: {exit_code}")
        return exit_code
        
    except KeyboardInterrupt:
        print("\n👋 Application interrupted by user")
        return 0
        
    except Exception as e:
        print(f"\n❌ FATAL ERROR: {e}")
        import traceback
        traceback.print_exc()
        
        try:
            if app_instance is None:
                app_instance = QApplication(sys.argv)
            QMessageBox.critical(None, "Fatal Error", 
                f"An unexpected error occurred:\n\n{str(e)}\n\nCheck console for details.")
        except:
            pass
        
        return 1
        
    finally:
        try:
            if app_manager and not app_manager.cleanup_completed:
                app_manager.cleanup_all()
        except:
            pass

# ============================================================
# SYSTEM STATUS DISPLAY
# ============================================================

def print_system_status(directional_pad, email_sender, firmware_flasher=None):
    """Print comprehensive system status"""
    print("\n" + "="*80)
    print("🚁 TiHAN DRONE SYSTEM - READY")
    print("="*80)
    print("✅ System initialization completed successfully")
    print("\n🔧 Core Features:")
    print("    • Enhanced error handling and recovery")
    print("    • Comprehensive resource cleanup")
    print("    • Signal handler for proper shutdown")
    print("    • Memory leak prevention")
    print("    • QML engine lifecycle management")
    print("    • Model reference tracking")
    print("    • WebEngine stability improvements")
    print("    • Command executor integration")
    print("    • Ti-NARI Port Detector with real-time scanning")
    print("    • Message Logger with terminal capture")
    print("    • Splash screen with smooth transition")
    print("    • 🚫 No-Fly Zone (NFZ) system with GeoJSON support")
    print("    • 🚫 Real-time NFZ breach detection & alerts")
    print("    • 📷 OpenCV RTSP frame provider (stable on Windows)")
    print("    • 🎯 MAVLink Camera / Gimbal managers")
    print("    • 📡 GStreamer multi-stream video manager")

    if firmware_flasher:
        print("\n⚡ Ti-NARI Firmware Flasher Features:")
        print("    • APM Planner 2-style firmware flashing")
        print("    • Automatic bootloader detection")
        print("    • Reboot-then-flash workflow")
        print("    • Support for .apj, .px4, .bin files")
        print("    • Password-protected drone selection")
        print("    • Multi-drone support (5 drone types)")
        print("    • Real-time progress tracking")
        print("    • Comprehensive error handling")
        print("    • Automatic port monitoring")
        print("    • Safe flash cancellation")
    
    if directional_pad:
        print("\n🎮 Directional Pad Controller Features:")
        print("    • Keyboard arrow key control (↑ ↓ ← →)")
        print("    • Center button for ARM & TAKEOFF")
        print("    • Automatic STOP on key release")
        print("    • Configurable takeoff altitude (default: 5m)")
        print("    • Emergency stop functionality")
        print("    • Real-time status feedback")
        print("    • Integrated with message logger")
    
    if email_sender:
        print("\n📧 Feedback System Features:")
        print("    • Multi-method email delivery (FormSubmit + SMTP)")
        print("    • No configuration required for basic operation")
        print("    • Automatic fallback to file backup")
        print("    • Background thread processing (non-blocking UI)")
        print("    • Integrated with message logger")
        print("    • Feedback saved to: feedback_submissions/")
    
    print("\n" + "="*80)
    print("🚀 System is ready for operation")
    print("="*80 + "\n")

# ============================================================
# APPLICATION ENTRY POINT
# ============================================================

if __name__ == "__main__":
    # ✅ MERGED from Doc 6: required on Windows for spawned processes
    import multiprocessing
    multiprocessing.freeze_support()
    sys.exit(main())