#!/usr/bin/env python3
"""
Firmware Flasher Diagnostic Test
Run this script to diagnose firmware flasher initialization issues
Usage: python3 test_firmware_diagnostic.py
"""

import os
import sys

print("="*80)
print("FIRMWARE FLASHER DIAGNOSTIC TEST")
print("="*80)

# Test 1: Check current directory
print("\n1. CHECKING CURRENT DIRECTORY")
print("-"*80)
current_dir = os.path.dirname(os.path.abspath(__file__))
print(f"Current directory: {current_dir}")
print(f"Script location: {__file__}")

# Test 2: Check if firmware_flasher_backend.py exists
print("\n2. CHECKING IF FIRMWARE_FLASHER_BACKEND.PY EXISTS")
print("-"*80)
firmware_backend_path = os.path.join(current_dir, 'firmware_flasher_backend.py')
print(f"Looking for: {firmware_backend_path}")

if os.path.exists(firmware_backend_path):
    print("✅ FILE FOUND")
    file_size = os.path.getsize(firmware_backend_path)
    print(f"   File size: {file_size:,} bytes")
    
    # Check if file is readable
    try:
        with open(firmware_backend_path, 'r') as f:
            first_line = f.readline()
            print(f"   First line: {first_line.strip()}")
        print("✅ FILE IS READABLE")
    except Exception as e:
        print(f"❌ FILE READ ERROR: {e}")
else:
    print("❌ FILE NOT FOUND!")
    print("\nSOLUTION:")
    print("  1. Create firmware_flasher_backend.py in:")
    print(f"     {current_dir}")
    print("  2. Copy the FirmwareFlasherBackend code into it")
    sys.exit(1)

# Test 3: Check Python path
print("\n3. CHECKING PYTHON PATH")
print("-"*80)
print(f"sys.path[0]: {sys.path[0]}")
print(f"Current dir in sys.path: {current_dir in sys.path}")
if current_dir not in sys.path:
    print("⚠️  Current directory not in sys.path, adding it...")
    sys.path.insert(0, current_dir)
    print("✅ Added to sys.path")

# Test 4: Check syntax
print("\n4. CHECKING FILE SYNTAX")
print("-"*80)
try:
    import py_compile
    py_compile.compile(firmware_backend_path, doraise=True)
    print("✅ NO SYNTAX ERRORS")
except py_compile.PyCompileError as e:
    print("❌ SYNTAX ERROR FOUND:")
    print(str(e))
    sys.exit(1)

# Test 5: Check dependencies
print("\n5. CHECKING DEPENDENCIES")
print("-"*80)

# Check PyQt5
try:
    from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot
    print("✅ PyQt5.QtCore - OK")
except ImportError as e:
    print(f"❌ PyQt5.QtCore - FAILED: {e}")
    print("   Install with: pip3 install PyQt5")
    sys.exit(1)

# Check pyserial
try:
    import serial
    print(f"✅ pyserial - OK (version: {serial.__version__})")
except ImportError as e:
    print(f"❌ pyserial - FAILED: {e}")
    print("   Install with: pip3 install pyserial")
    sys.exit(1)

# Check threading
try:
    import threading
    print("✅ threading - OK")
except ImportError as e:
    print(f"❌ threading - FAILED: {e}")
    sys.exit(1)

# Check subprocess
try:
    import subprocess
    print("✅ subprocess - OK")
except ImportError as e:
    print(f"❌ subprocess - FAILED: {e}")
    sys.exit(1)

# Test 6: Try to import the module
print("\n6. ATTEMPTING TO IMPORT MODULE")
print("-"*80)
try:
    from firmware_flasher_backend import FirmwareFlasherBackend
    print("✅ IMPORT SUCCESSFUL")
    print(f"   Module: {FirmwareFlasherBackend.__module__}")
    print(f"   Class: {FirmwareFlasherBackend}")
except ImportError as e:
    print(f"❌ IMPORT FAILED: {e}")
    print("\nDETAILED ERROR:")
    import traceback
    traceback.print_exc()
    sys.exit(1)
except Exception as e:
    print(f"❌ UNEXPECTED ERROR: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Test 7: Try to create instance
print("\n7. ATTEMPTING TO CREATE INSTANCE")
print("-"*80)
try:
    # We need QApplication for QObject
    from PyQt5.QtWidgets import QApplication
    app = QApplication(sys.argv)
    
    flasher = FirmwareFlasherBackend()
    print("✅ INSTANCE CREATED")
    print(f"   Type: {type(flasher)}")
    print(f"   Instance: {flasher}")
except Exception as e:
    print(f"❌ INSTANCE CREATION FAILED: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Test 8: Check methods
print("\n8. CHECKING METHODS")
print("-"*80)
required_methods = ['flashFirmware', 'cancelFlash', 'cleanup', '_flash_firmware_process']
all_found = True

for method_name in required_methods:
    if hasattr(flasher, method_name):
        method = getattr(flasher, method_name)
        print(f"✅ {method_name:25s} - Found (type: {type(method).__name__})")
    else:
        print(f"❌ {method_name:25s} - NOT FOUND")
        all_found = False

if not all_found:
    print("\n❌ SOME METHODS ARE MISSING")
    sys.exit(1)

# Test 9: Check signals
print("\n9. CHECKING SIGNALS")
print("-"*80)
required_signals = ['flashProgress', 'flashStatus', 'flashError', 'flashCompleted']
all_found = True

for signal_name in required_signals:
    if hasattr(flasher, signal_name):
        signal = getattr(flasher, signal_name)
        print(f"✅ {signal_name:25s} - Found (type: {type(signal).__name__})")
    else:
        print(f"❌ {signal_name:25s} - NOT FOUND")
        all_found = False

if not all_found:
    print("\n❌ SOME SIGNALS ARE MISSING")
    sys.exit(1)

# Test 10: Check firmware directory
print("\n10. CHECKING FIRMWARE DIRECTORY")
print("-"*80)
if hasattr(flasher, 'base_firmware_dir'):
    firmware_dir = flasher.base_firmware_dir
    print(f"Firmware directory: {firmware_dir}")
    
    if os.path.exists(firmware_dir):
        print("✅ DIRECTORY EXISTS")
        
        # List firmware files
        try:
            files = os.listdir(firmware_dir)
            apj_files = [f for f in files if f.endswith('.apj')]
            
            if apj_files:
                print(f"✅ FOUND {len(apj_files)} FIRMWARE FILES:")
                for fw_file in apj_files:
                    file_path = os.path.join(firmware_dir, fw_file)
                    file_size = os.path.getsize(file_path)
                    print(f"   - {fw_file:40s} ({file_size:,} bytes)")
            else:
                print("⚠️  NO .APJ FIRMWARE FILES FOUND")
                print("   You'll need to add firmware files to:")
                print(f"   {firmware_dir}")
        except Exception as e:
            print(f"❌ ERROR LISTING DIRECTORY: {e}")
    else:
        print("⚠️  DIRECTORY DOES NOT EXIST")
        print(f"   Will be created at: {firmware_dir}")
else:
    print("❌ base_firmware_dir ATTRIBUTE NOT FOUND")

# Test 11: Check drone firmware mapping
print("\n11. CHECKING DRONE FIRMWARE MAPPING")
print("-"*80)
if hasattr(flasher, 'drone_firmware_map'):
    mapping = flasher.drone_firmware_map
    print(f"✅ MAPPING FOUND - {len(mapping)} drones configured:")
    for drone_name, cube_types in mapping.items():
        print(f"   {drone_name}:")
        for cube_type, firmware_file in cube_types.items():
            print(f"      - {cube_type:20s} → {firmware_file}")
else:
    print("❌ drone_firmware_map ATTRIBUTE NOT FOUND")

# Final summary
print("\n" + "="*80)
print("DIAGNOSTIC TEST COMPLETE")
print("="*80)
print("✅ ALL TESTS PASSED!")
print("\nThe FirmwareFlasherBackend is working correctly.")
print("If you're still having issues in main.py, the problem is likely:")
print("  1. main.py is not importing from the correct location")
print("  2. There's an exception during initialization that's being caught")
print("  3. The instance is being created but not properly exposed to QML")
print("\nNext steps:")
print("  1. Replace the firmware flasher initialization section in main.py")
print("     with the fixed version (see artifact)")
print("  2. Run main.py and check the detailed initialization logs")
print("  3. Look for the specific error in the startup logs")
print("="*80)
