#!/bin/bash
# Fixed PyInstaller command for TiHAN Drone System with QtWebEngine support

VENV_PATH="/home/tihan_012/Videos/Tfly Final Pyversion/myenv"
PYQT5_PATH="$VENV_PATH/lib/python3.10/site-packages/PyQt5"

pyinstaller --onefile \
    --add-data "$PYQT5_PATH/Qt5/plugins/platforms:PyQt5/Qt5/plugins/platforms" \
    --add-data "$PYQT5_PATH/Qt5/plugins/imageformats:PyQt5/Qt5/plugins/imageformats" \
    --add-data "$PYQT5_PATH/Qt5/plugins/geoservices:PyQt5/Qt5/plugins/geoservices" \
    --add-data "$PYQT5_PATH/Qt5/plugins/platformthemes:PyQt5/Qt5/plugins/platformthemes" \
    --add-data "$PYQT5_PATH/Qt5/plugins/xcbglintegrations:PyQt5/Qt5/plugins/xcbglintegrations" \
    --add-data "$PYQT5_PATH/Qt5/resources:PyQt5/Qt5/resources" \
    --add-data "$PYQT5_PATH/Qt5/translations/qtwebengine_locales:PyQt5/Qt5/translations/qtwebengine_locales" \
    --add-data "App/qml:App/qml" \
    --add-data "App/resources:App/resources" \
    --add-data "App/images:App/images" \
    --add-data "App/tihan1.ico:App" \
    --add-data "App/tihan.png:App" \
    --add-data "App/qml/translations_ta.qm:App" \
    --add-binary "$PYQT5_PATH/Qt5/libexec/QtWebEngineProcess:PyQt5/Qt5/libexec" \
    --add-binary "$PYQT5_PATH/Qt5/lib/*.so*:PyQt5/Qt5/lib" \
    --add-binary "/usr/lib/x86_64-linux-gnu/libQt5Location.so.5:." \
    --hidden-import=PyQt5.QtWebEngine \
    --hidden-import=PyQt5.QtWebEngineCore \
    --hidden-import=PyQt5.QtWebEngineWidgets \
    --hidden-import=PyQt5.QtWebChannel \
    --hidden-import=PyQt5.QtCore \
    --hidden-import=PyQt5.QtGui \
    --hidden-import=PyQt5.QtWidgets \
    --hidden-import=PyQt5.QtQml \
    --hidden-import=PyQt5.QtQuick \
    --hidden-import=PyQt5.QtLocation \
    --hidden-import=PyQt5.QtPositioning \
    --hidden-import=PyQt5.QtNetwork \
    --hidden-import=PyQt5.QtPrintSupport \
    main.py

echo ""
echo "Build complete! Executable is in the dist/ folder"
