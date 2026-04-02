"""Test QtLocation plugin loading"""
import sys
from pathlib import Path

# Add current directory to path
current_dir = Path(__file__).parent.absolute()
sys.path.insert(0, str(current_dir))

from PyQt5.QtWidgets import QApplication
from PyQt5.QtCore import QCoreApplication
from PyQt5.QtLocation import QGeoServiceProvider

# Add PyQt5 plugin paths
pyqt5_plugins = Path(sys.executable).parent.parent / "Lib" / "site-packages" / "PyQt5" / "Qt5" / "plugins"
if pyqt5_plugins.exists():
    QCoreApplication.addLibraryPath(str(pyqt5_plugins))
    print(f"✅ Added plugin path: {pyqt5_plugins}")

app = QApplication(sys.argv)

print("\n=== TESTING GOOGLE GEOSERVICES PLUGIN ===")
provider = QGeoServiceProvider("google")

if provider.error() == QGeoServiceProvider.NoError:
    print("✅ Google plugin loaded successfully")
    print(f"   Mapping features: {provider.mappingFeatures()}")
    print(f"   Geocoding features: {provider.geocodingFeatures()}")
    print(f"   Routing features: {provider.routingFeatures()}")
else:
    print(f"❌ Plugin load failed: {provider.errorString()}")
    print(f"   Error code: {provider.error()}")

print("\n=== AVAILABLE PLUGINS ===")
print(f"Library paths: {QCoreApplication.libraryPaths()}")

sys.exit(0)
