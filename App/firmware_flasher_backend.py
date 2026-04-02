#!/usr/bin/env python3
"""
Ti-Nari Firmware Flasher Backend
Handles ArduPilot firmware flashing via MAVProxy
"""

import os
import sys
import subprocess
import time
import threading
import serial
from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, QThread


class FirmwareFlasherBackend(QObject):
    """
    Backend for flashing ArduPilot firmware to flight controllers
    Supports CubeOrange and CubeOrange+ with drone-specific firmware
    """
    
    # Qt Signals for communicating with QML
    flashProgress = pyqtSignal(int)  # Progress percentage (0-100)
    flashStatus = pyqtSignal(str)    # Status messages
    flashError = pyqtSignal(str)     # Error messages
    flashCompleted = pyqtSignal(bool, str)  # Success flag and message
    
    def __init__(self, parent=None):
        super().__init__(parent)
        
        # Firmware flashing state
        self.is_flashing = False
        self.should_cancel = False
        self.flash_thread = None
        
        # Firmware directory structure
        self.base_firmware_dir = self._get_firmware_directory()
        
        # Drone name to firmware mapping
        self.drone_firmware_map = {
            "Shadow": {
                "CubeOrange": "Shadow_CubeOrange.apj",
                "CubeOrangePlus": "Shadow_CubeOrangePlus.apj"
            },
            "Spider": {
                "CubeOrange": "Spider_CubeOrange.apj",
                "CubeOrangePlus": "Spider_CubeOrangePlus.apj"
            },
            "Kala": {
                "CubeOrange": "Kala_CubeOrange.apj",
                "CubeOrangePlus": "Kala_CubeOrangePlus.apj"
            },
            "Palyanka": {
                "CubeOrange": "Palyanka_CubeOrange.apj",
                "CubeOrangePlus": "Palyanka_CubeOrangePlus.apj"
            },
            "Chakrayukhan": {
                "CubeOrange": "Chakrayukhan_CubeOrange.apj",
                "CubeOrangePlus": "Chakrayukhan_CubeOrangePlus.apj"
            }
        }
        
        print("✅ FirmwareFlasherBackend initialized")
    
    def _get_firmware_directory(self):
        """Get the firmware directory path"""
        # Try multiple possible locations
        possible_paths = [
            os.path.join(os.path.dirname(__file__), "resources", "firmware"),
            os.path.join(os.path.dirname(__file__), "..", "resources", "firmware"),
            os.path.join(os.path.expanduser("~"), "Videos", "Tfly_V1.0.1", "App", "resources", "firmware"),
            "/home/tihan_012/Videos/Tfly_V1.0.1/App/resources/firmware"
        ]
        
        for path in possible_paths:
            if os.path.exists(path):
                print(f"✅ Found firmware directory: {path}")
                return path
        
        # Default fallback
        fallback = os.path.join(os.path.dirname(__file__), "firmware")
        print(f"⚠️ Firmware directory not found, using fallback: {fallback}")
        os.makedirs(fallback, exist_ok=True)
        return fallback
    
    def _get_firmware_path(self, drone_name, cube_type):
        """Get the full path to the firmware file"""
        if drone_name not in self.drone_firmware_map:
            raise ValueError(f"Unknown drone type: {drone_name}")
        
        if cube_type not in self.drone_firmware_map[drone_name]:
            raise ValueError(f"Unknown cube type: {cube_type}")
        
        firmware_filename = self.drone_firmware_map[drone_name][cube_type]
        firmware_path = os.path.join(self.base_firmware_dir, firmware_filename)
        
        if not os.path.exists(firmware_path):
            raise FileNotFoundError(f"Firmware file not found: {firmware_path}")
        
        return firmware_path
    
    def _check_mavproxy_installed(self):
        """Check if MAVProxy is installed"""
        try:
            result = subprocess.run(
                ["mavproxy.py", "--version"],
                capture_output=True,
                text=True,
                timeout=5
            )
            return result.returncode == 0
        except (subprocess.TimeoutExpired, FileNotFoundError):
            return False
    
    def _put_device_in_bootloader(self, port):
        """Put the device into bootloader mode"""
        self.flashStatus.emit("Entering bootloader mode...")
        
        try:
            # Open serial connection
            ser = serial.Serial(port, 115200, timeout=2)
            time.sleep(0.5)
            
            # Send reboot command
            ser.write(b"reboot\n")
            time.sleep(0.5)
            
            # Close connection
            ser.close()
            
            self.flashStatus.emit("✅ Device rebooting into bootloader mode...")
            time.sleep(3)  # Wait for device to reboot
            
            return True
            
        except Exception as e:
            self.flashStatus.emit(f"⚠️ Could not enter bootloader mode: {str(e)}")
            self.flashStatus.emit("Attempting to flash anyway...")
            return False
    
    def _flash_firmware_process(self, port, firmware_path):
        """
        Internal method that performs the actual firmware flashing
        Runs in a separate thread
        """
        try:
            self.is_flashing = True
            self.should_cancel = False
            
            # Initial status
            self.flashProgress.emit(0)
            self.flashStatus.emit(f"Starting firmware flash on {port}")
            self.flashStatus.emit(f"Firmware file: {os.path.basename(firmware_path)}")
            
            # Check if MAVProxy is installed
            self.flashProgress.emit(5)
            self.flashStatus.emit("Checking MAVProxy installation...")
            
            if not self._check_mavproxy_installed():
                self.flashError.emit("MAVProxy not installed! Please install: pip install MAVProxy")
                self.flashCompleted.emit(False, "MAVProxy not found")
                return
            
            self.flashStatus.emit("✅ MAVProxy found")
            
            # Put device in bootloader mode
            self.flashProgress.emit(10)
            self._put_device_in_bootloader(port)
            
            if self.should_cancel:
                self.flashCompleted.emit(False, "Flash cancelled by user")
                return
            
            # Prepare MAVProxy flash command
            self.flashProgress.emit(20)
            self.flashStatus.emit("Preparing flash command...")
            
            # MAVProxy command to flash firmware
            mavproxy_cmd = [
                "mavproxy.py",
                "--master", port,
                "--baudrate", "115200",
                "--cmd", f"module load firmware; firmware install {firmware_path}"
            ]
            
            self.flashStatus.emit(f"Command: {' '.join(mavproxy_cmd)}")
            self.flashProgress.emit(30)
            self.flashStatus.emit("Connecting to bootloader...")
            
            # Execute MAVProxy flash command
            process = subprocess.Popen(
                mavproxy_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True
            )
            
            # Monitor the flashing process
            flash_stages = {
                "Connecting": 40,
                "Erasing": 50,
                "Programming": 70,
                "Verifying": 85,
                "Rebooting": 95
            }
            
            current_progress = 30
            
            for line in process.stdout:
                if self.should_cancel:
                    process.terminate()
                    self.flashCompleted.emit(False, "Flash cancelled by user")
                    return
                
                line = line.strip()
                if line:
                    self.flashStatus.emit(line)
                    
                    # Update progress based on output
                    for stage, progress in flash_stages.items():
                        if stage.lower() in line.lower():
                            current_progress = progress
                            self.flashProgress.emit(progress)
                            break
                    
                    # Check for success/failure keywords
                    if "success" in line.lower() or "complete" in line.lower():
                        self.flashProgress.emit(100)
                        self.flashStatus.emit("✅ Firmware flashed successfully!")
                    elif "error" in line.lower() or "failed" in line.lower():
                        self.flashError.emit(f"Flash error: {line}")
            
            # Wait for process to complete
            return_code = process.wait(timeout=120)
            
            if return_code == 0:
                self.flashProgress.emit(100)
                self.flashCompleted.emit(True, "Firmware flashed successfully!")
            else:
                self.flashCompleted.emit(False, f"Flash failed with code {return_code}")
            
        except subprocess.TimeoutExpired:
            self.flashError.emit("Flash timeout - process took too long")
            self.flashCompleted.emit(False, "Flash timeout")
            
        except Exception as e:
            error_msg = f"Flash error: {str(e)}"
            self.flashError.emit(error_msg)
            self.flashCompleted.emit(False, error_msg)
            
        finally:
            self.is_flashing = False
            self.should_cancel = False
    
    @pyqtSlot(str, str, str)
    def flashFirmware(self, port, drone_name, cube_type):
        """
        Main method to start firmware flashing
        Called from QML when user clicks INSTALL
        
        Args:
            port: Serial port (e.g., "/dev/ttyUSB0" or "COM3")
            drone_name: Short drone name (e.g., "Shadow", "Spider")
            cube_type: Flight controller type ("CubeOrange" or "CubeOrangePlus")
        """
        print(f"\n{'='*60}")
        print(f"🚀 FIRMWARE FLASH STARTED")
        print(f"{'='*60}")
        print(f"  Port: {port}")
        print(f"  Drone: {drone_name}")
        print(f"  Cube Type: {cube_type}")
        
        # Check if already flashing
        if self.is_flashing:
            self.flashError.emit("A flash operation is already in progress!")
            return
        
        try:
            # Validate inputs
            if not port:
                raise ValueError("No port selected")
            
            if not drone_name:
                raise ValueError("No drone selected")
            
            # Get firmware path
            firmware_path = self._get_firmware_path(drone_name, cube_type)
            print(f"  Firmware: {firmware_path}")
            print(f"{'='*60}\n")
            
            # Start flashing in separate thread
            self.flash_thread = threading.Thread(
                target=self._flash_firmware_process,
                args=(port, firmware_path),
                daemon=True
            )
            self.flash_thread.start()
            
        except Exception as e:
            error_msg = f"Failed to start flash: {str(e)}"
            print(f"❌ {error_msg}")
            self.flashError.emit(error_msg)
            self.flashCompleted.emit(False, error_msg)
    
    @pyqtSlot()
    def cancelFlash(self):
        """Cancel the ongoing flash operation"""
        if self.is_flashing:
            print("🛑 Cancel flash requested")
            self.should_cancel = True
            self.flashStatus.emit("Cancelling flash operation...")
    
    def cleanup(self):
        """Cleanup method for proper shutdown"""
        print("🧹 Cleaning up FirmwareFlasherBackend...")
        if self.is_flashing:
            self.cancelFlash()
            # Wait for thread to finish (with timeout)
            if self.flash_thread and self.flash_thread.is_alive():
                self.flash_thread.join(timeout=5)
        print("✅ FirmwareFlasherBackend cleanup completed")


# Testing code (only runs when executed directly)
if __name__ == "__main__":
    from PyQt5.QtWidgets import QApplication
    
    app = QApplication(sys.argv)
    
    flasher = FirmwareFlasherBackend()
    
    # Connect signals for testing
    flasher.flashProgress.connect(lambda p: print(f"Progress: {p}%"))
    flasher.flashStatus.connect(lambda s: print(f"Status: {s}"))
    flasher.flashError.connect(lambda e: print(f"Error: {e}"))
    flasher.flashCompleted.connect(lambda success, msg: print(f"Completed: {success} - {msg}"))
    
    # Test flash (you'll need to modify these parameters)
    # flasher.flashFirmware("/dev/ttyUSB0", "Shadow", "CubeOrange")
    
    print("Backend test initialized. Add test code above to test flashing.")
    
    sys.exit(app.exec_())
