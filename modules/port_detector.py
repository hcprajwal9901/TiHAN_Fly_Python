"""
Port Detector Backend for Ti-NARI
Detects available serial ports with detailed information
"""

from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot, pyqtProperty, QTimer, QVariant
import serial.tools.list_ports
import platform
from modules.port_scan_lock import PORT_SCAN_LOCK


class PortDetectorBackend(QObject):
    """
    Backend for detecting and managing serial ports
    Compatible with pymavlink and Ti-NARI system
    """
    
    # Signals
    portsChanged = pyqtSignal()
    portCountChanged = pyqtSignal(int)
    scanCompleted = pyqtSignal()
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self._available_ports = []
        self._port_details = []  # Store detailed info
        self._auto_refresh_enabled = False
        self._refresh_timer = QTimer(self)
        self._refresh_timer.timeout.connect(self.scanPorts)
        
        print("✅ PortDetectorBackend initialized")
        
        # Defer via a one-shot timer instead:
        QTimer.singleShot(3000, self.scanPorts)
    
    @pyqtProperty('QVariantList', notify=portsChanged)
    def availablePorts(self):
        """Returns list of available port names (for simple display)"""
        return self._available_ports
    
    @pyqtProperty('QVariantList', notify=portsChanged)
    def portDetails(self):
        """Returns list of detailed port information as dictionaries"""
        return self._port_details
    
    @pyqtProperty(int, notify=portCountChanged)
    def portCount(self):
        """Returns number of available ports"""
        return len(self._available_ports)
    
    @pyqtSlot()
    def scanPorts(self):
        """Scan for available serial ports - Main method"""
        self.refreshPorts()
    
    @pyqtSlot()
    def refreshPorts(self):
        """Scan for available serial ports"""
        try:
            print("🔍 Scanning for available serial ports...")
            
            # Clear old lists
            self._available_ports.clear()
            self._port_details.clear()
            
            # Get all available ports
            with PORT_SCAN_LOCK:
                ports = serial.tools.list_ports.comports()
            
            # Process each port
            for port in ports:
                # Add simple port name to list
                self._available_ports.append(port.device)
                
                # Create detailed info dictionary
                port_dict = {
                    'port': port.device,
                    'description': port.description if port.description else 'Unknown Device',
                    'manufacturer': port.manufacturer if port.manufacturer else 'Unknown',
                    'location': port.device,
                    'vid': port.vid if port.vid else 0,
                    'pid': port.pid if port.pid else 0,
                    'serial': port.serial_number if port.serial_number else 'N/A',
                    'vid_pid': f"0x{port.vid:04X}:0x{port.pid:04X}" if port.vid and port.pid else "Unknown",
                    'is_ardupilot': self._check_if_ardupilot(port)
                }
                self._port_details.append(port_dict)
                
                # Log port details
                print(f"  📍 Found: {port.device}")
                print(f"     Description: {port_dict['description']}")
                print(f"     Manufacturer: {port_dict['manufacturer']}")
                print(f"     VID:PID = {port_dict['vid_pid']}")
            
            new_count = len(self._available_ports)
            print(f"✅ Port scan completed: {new_count} port(s) found")
            
            # Emit signals to update QML
            self.portsChanged.emit()
            self.portCountChanged.emit(new_count)
            self.scanCompleted.emit()
            
        except Exception as e:
            print(f"❌ Error scanning ports: {e}")
            import traceback
            traceback.print_exc()
    
    def _check_if_ardupilot(self, port):
        """Check if port is likely an ArduPilot/Pixhawk device"""
        # Common ArduPilot VID values
        ardupilot_vids = [0x26AC, 0x2DAE, 0x0483, 0x16D0]
        
        if port.vid in ardupilot_vids:
            return True
        
        # Check description
        if port.description:
            desc_lower = port.description.lower()
            keywords = ['pixhawk', 'ardupilot', 'px4', 'cube', 'flight controller']
            if any(keyword in desc_lower for keyword in keywords):
                return True
        
        return False
    
    @pyqtSlot(str, result=bool)
    def isPortAvailable(self, port_name):
        """Check if a specific port is available"""
        return port_name in self._available_ports
    
    @pyqtSlot(str, result='QVariant')
    def getPortInfo(self, port_name):
        """Get detailed information about a specific port"""
        for port_info in self._port_details:
            if port_info['port'] == port_name:
                return port_info
        return None
    
    @pyqtSlot(result='QVariantList')
    def getPortNames(self):
        """Get list of port names only"""
        return self._available_ports
    
    @pyqtSlot(result='QVariantList')
    def getArduPilotPorts(self):
        """Get ports that are likely ArduPilot/Pixhawk devices"""
        ardupilot_ports = []
        for port_info in self._port_details:
            if port_info['is_ardupilot']:
                ardupilot_ports.append(port_info)
        return ardupilot_ports
    
    @pyqtSlot(bool)
    def setAutoRefresh(self, enabled):
        """Enable/disable automatic port refresh"""
        self._auto_refresh_enabled = enabled
        
        if enabled:
            # Refresh every 3 seconds
            self._refresh_timer.start(3000)
            print("✅ Auto-refresh enabled (3s interval)")
        else:
            self._refresh_timer.stop()
            print("⏸️ Auto-refresh disabled")
    
    @pyqtProperty(bool)
    def autoRefreshEnabled(self):
        return self._auto_refresh_enabled
    
    @pyqtSlot(result=str)
    def getSystemInfo(self):
        """Get system information"""
        return f"{platform.system()} {platform.release()}"
    
    @pyqtSlot(str, result=bool)
    def testPortConnection(self, port_name):
        """Test if a port can be opened"""
        try:
            import serial
            ser = serial.Serial(port_name, 57600, timeout=1)
            ser.close()
            print(f"✅ Port {port_name} test: SUCCESS")
            return True
        except Exception as e:
            print(f"❌ Port {port_name} test: FAILED - {e}")
            return False
    
    def cleanup(self):
        """Cleanup resources"""
        print("  - Cleaning up PortDetectorBackend...")
        self._refresh_timer.stop()
        self._available_ports.clear()
        self._port_details.clear()
        print("✅ PortDetectorBackend cleanup completed")


# Standalone test function
def test_port_detector():
    """Test the port detector"""
    print("=" * 80)
    print("Testing Port Detector Backend")
    print("=" * 80)
    
    from PyQt5.QtWidgets import QApplication
    import sys
    
    app = QApplication(sys.argv)
    detector = PortDetectorBackend()
    
    print(f"\nTotal ports found: {detector.portCount}")
    print("\nPort Details:")
    print("-" * 80)
    
    for port_info in detector.portDetails:
        print(f"Port: {port_info['port']}")
        print(f"  Description: {port_info['description']}")
        print(f"  Manufacturer: {port_info['manufacturer']}")
        print(f"  VID:PID: {port_info['vid_pid']}")
        print(f"  Serial: {port_info['serial']}")
        print(f"  Is ArduPilot: {port_info['is_ardupilot']}")
        print("-" * 80)
    
    print("\nArduPilot/Pixhawk Ports:")
    ardupilot_ports = detector.getArduPilotPorts()
    if ardupilot_ports:
        for port in ardupilot_ports:
            print(f"  - {port['port']}: {port['description']}")
    else:
        print("  No ArduPilot/Pixhawk devices detected")
    
    print("\n" + "=" * 80)
    detector.cleanup()


if __name__ == "__main__":
    test_port_detector()