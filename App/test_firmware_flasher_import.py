#!/usr/bin/env python3
"""
Diagnostic script to test FirmwareFlasherBackend import and functionality
Run this before running the main application
"""

import sys
import os

print("="*80)
print("🔍 FIRMWARE FLASHER BACKEND DIAGNOSTIC")
print("="*80)

# Add current directory to path
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)
print(f"✅ Added to sys.path: {current_dir}")

# Check if file exists
backend_file = os.path.join(current_dir, "firmware_flasher_backend.py")
print(f"\n📄 Checking file: {backend_file}")
if os.path.exists(backend_file):
    print(f"✅ File exists")
    print(f"   Size: {os.path.getsize(backend_file)} bytes")
else:
    print(f"❌ File NOT found!")
    sys.exit(1)

# Try to import
print("\n📦 Attempting import...")
try:
    from firmware_flasher_backend import FirmwareFlasherBackend
    print("✅ Import successful!")
except ImportError as e:
    print(f"❌ Import failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Try to create instance
print("\n🔧 Creating instance...")
try:
    flasher = FirmwareFlasherBackend()
    print(f"✅ Instance created: {flasher}")
    print(f"   Type: {type(flasher)}")
except Exception as e:
    print(f"❌ Instance creation failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Check methods
print("\n🔍 Checking methods...")
methods = ['flashFirmware', 'cancelFlash', 'cleanup']
for method in methods:
    if hasattr(flasher, method):
        print(f"✅ Method exists: {method}")
    else:
        print(f"❌ Method missing: {method}")

# Check signals
print("\n📡 Checking signals...")
signals = ['flashProgress', 'flashStatus', 'flashError', 'flashCompleted']
for signal in signals:
    if hasattr(flasher, signal):
        print(f"✅ Signal exists: {signal}")
    else:
        print(f"❌ Signal missing: {signal}")

# Check PyQt5 imports
print("\n🔍 Checking PyQt5 dependencies...")
try:
    from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot
    print("✅ PyQt5.QtCore imports OK")
except ImportError as e:
    print(f"❌ PyQt5.QtCore import failed: {e}")

try:
    import serial
    print("✅ pyserial import OK")
except ImportError as e:
    print(f"⚠️  pyserial import failed: {e}")
    print("   Install with: pip install pyserial")

# Check MAVProxy
print("\n🔍 Checking MAVProxy...")
import subprocess
try:
    result = subprocess.run(
        ["mavproxy.py", "--version"],
        capture_output=True,
        text=True,
        timeout=5
    )
    if result.returncode == 0:
        print("✅ MAVProxy is installed")
    else:
        print("⚠️  MAVProxy command failed")
except (subprocess.TimeoutExpired, FileNotFoundError) as e:
    print(f"⚠️  MAVProxy not found: {e}")
    print("   Install with: pip install MAVProxy")

print("\n" + "="*80)
print("✅ DIAGNOSTIC COMPLETE - Backend is ready!")
print("="*80)
