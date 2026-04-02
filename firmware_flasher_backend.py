#!/usr/bin/env python3
"""
Add this code to your main.py file to support the Ti-NARI window
"""

from PyQt5.QtCore import QObject, pyqtSlot, QUrl
from PyQt5.QtQml import QQmlApplicationEngine
from PyQt5.QtWidgets import QMessageBox

# ============================================================
# TI-NARI WINDOW OPENER
# ============================================================

def create_tinari_window_opener(qml_base_path, port_detector, message_logger, app_mgr):
    """Create Ti-NARI firmware flash window opener"""
    
    @pyqtSlot()
    def openTiNariWindow():
        try:
            print("🔧 Opening Ti-NARI firmware flash window...")
            
            # Create new QML engine for Ti-NARI window
            tinari_engine = QQmlApplicationEngine()
            app_mgr.register_engine(tinari_engine)
            
            # Set context properties
            tinari_engine.rootContext().setContextProperty("portDetector", port_detector)
            tinari_engine.rootContext().setContextProperty("messageLogger", message_logger)
            
            # Load the Ti-NARI QML file
            tinari_qml = qml_base_path / "TiNariWindow.qml"
            
            if not tinari_qml.exists():
                QMessageBox.critical(
                    None, 
                    "File Error", 
                    f"Ti-NARI window file not found:\n{tinari_qml}"
                )
                return
            
            tinari_engine.load(QUrl.fromLocalFile(str(tinari_qml)))
            
            if tinari_engine.rootObjects():
                print("✅ Ti-NARI window opened successfully")
                message_logger.logMessage("🔧 Ti-NARI firmware flash tool opened", "info")
            else:
                QMessageBox.critical(
                    None, 
                    "Error", 
                    "Failed to load Ti-NARI window"
                )
                print("❌ Failed to load Ti-NARI window")
                
        except Exception as e:
            print(f"❌ Error opening Ti-NARI window: {e}")
            QMessageBox.critical(
                None, 
                "Error", 
                f"Failed to open Ti-NARI window:\n{str(e)}"
            )
    
    return openTiNariWindow


# ============================================================
# ADD TO YOUR main() FUNCTION
# ============================================================

# Add this code in your main() function after initializing port_detector
# and before "# Expose models to QML" section:

"""
# Ti-NARI window opener
print("🔧 Setting up Ti-NARI window opener...")
tinari_opener = create_tinari_window_opener(
    qml_base_path, 
    port_detector, 
    message_logger, 
    app_manager
)
"""

# Then add this line in the "# Expose models to QML" section:
"""
ctx.setContextProperty("tinariWindowOpener", tinari_opener)
"""

# ============================================================
# ALTERNATIVE: USE QML-ONLY APPROACH (RECOMMENDED)
# ============================================================

# If you prefer to keep it simple, you don't need Python integration.
# Just ensure these are already exposed to QML (which they are in your code):
# - portDetector
# - messageLogger

# Then use the QML button handler code provided in the other artifact.
# The window will be created entirely in QML using Qt.createComponent()