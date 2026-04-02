from PyQt5.QtCore import QObject, pyqtSignal, pyqtSlot

class TrialManager(QObject):
    """Stub for TrialManager to prevent NameError"""
    def __init__(self, parent=None):
        super().__init__(parent)
        print("⚠️ [STUB] TrialManager initialized (Not Implemented)")

class DirectionalPadController(QObject):
    """Stub for DirectionalPadController to prevent NameError"""
    statusChanged = pyqtSignal(str, str)
    
    def __init__(self, drone_model, parent=None):
        super().__init__(parent)
        print("⚠️ [STUB] DirectionalPadController initialized (Not Implemented)")
    
    @pyqtSlot()
    def stopMovement(self):
        print("⚠️ [STUB] DirectionalPadController.stopMovement called")

class EmailSender(QObject):
    """Stub for EmailSender to prevent NameError"""
    emailSent = pyqtSignal(bool, str)
    
    def __init__(self, parent=None):
        super().__init__(parent)
        print("⚠️ [STUB] EmailSender initialized (Not Implemented)")
