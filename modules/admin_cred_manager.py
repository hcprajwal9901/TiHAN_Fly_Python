
from PyQt5.QtWidgets import QDialog, QVBoxLayout, QLabel, QLineEdit, QPushButton, QMessageBox, QTabWidget, QWidget, QFormLayout, QCheckBox
from PyQt5.QtCore import Qt
from PyQt5.QtGui import QFont


class AdminCredentialsDialog(QDialog):
    """Admin dialog for changing credentials"""
    
    def __init__(self, credentials_manager, parent=None):
        super().__init__(parent)
        self.credentials_manager = credentials_manager
        self.setWindowTitle("Admin - Credential Management")
        self.setFixedSize(500, 600)
        self.setWindowFlags(Qt.Dialog | Qt.WindowSystemMenuHint | Qt.WindowTitleHint)
        self.setup_ui()
    
    def setup_ui(self):
        """Setup the admin UI"""
        layout = QVBoxLayout()
        
        # Title
        title_label = QLabel("🔐 Admin Credential Management")
        title_label.setAlignment(Qt.AlignCenter)
        title_font = QFont()
        title_font.setPointSize(16)
        title_font.setBold(True)
        title_label.setFont(title_font)
        layout.addWidget(title_label)
        
        # Tab widget
        tab_widget = QTabWidget()
        
        # Admin Login Tab
        login_tab = QWidget()
        login_layout = QVBoxLayout()
        
        # Admin credentials section
        admin_group = QLabel("Admin Authentication")
        admin_group.setStyleSheet("font-weight: bold; font-size: 14px; color: #333;")
        login_layout.addWidget(admin_group)
        
        admin_form = QFormLayout()
        self.admin_username = QLineEdit()
        self.admin_username.setPlaceholderText("Enter admin username")
        self.admin_password = QLineEdit()
        self.admin_password.setPlaceholderText("Enter admin password")
        self.admin_password.setEchoMode(QLineEdit.Password)
        
        admin_form.addRow("Admin Username:", self.admin_username)
        admin_form.addRow("Admin Password:", self.admin_password)
        login_layout.addLayout(admin_form)
        
        # Verify button
        verify_button = QPushButton("🔓 Verify Admin Access")
        verify_button.setStyleSheet("""
            QPushButton {
                background-color: #2196F3;
                color: white;
                border: none;
                padding: 10px;
                border-radius: 5px;
                font-weight: bold;
            }
            QPushButton:hover { background-color: #1976D2; }
        """)
        verify_button.clicked.connect(self.verify_admin)
        login_layout.addWidget(verify_button)
        
        login_tab.setLayout(login_layout)
        tab_widget.addTab(login_tab, "🔐 Admin Login")
        
        # Credential Management Tab
        self.manage_tab = QWidget()
        manage_layout = QVBoxLayout()
        
        # Current credentials info
        info_label = QLabel("📊 Current Credentials Information")
        info_label.setStyleSheet("font-weight: bold; font-size: 14px; color: #333;")
        manage_layout.addWidget(info_label)
        
        self.info_display = QLabel("Please verify admin access first")
        self.info_display.setStyleSheet("""
            background-color: #f5f5f5;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-family: monospace;
        """)
        manage_layout.addWidget(self.info_display)
        
        # New credentials section
        new_cred_label = QLabel("🔄 Update Credentials")
        new_cred_label.setStyleSheet("font-weight: bold; font-size: 14px; color: #333;")
        manage_layout.addWidget(new_cred_label)
        
        cred_form = QFormLayout()
        self.new_username = QLineEdit()
        self.new_username.setPlaceholderText("Enter new username")
        self.new_password = QLineEdit()
        self.new_password.setPlaceholderText("Enter new password")
        self.show_password = QCheckBox("Show password")
        self.show_password.toggled.connect(self.toggle_password_visibility)
        
        cred_form.addRow("New Username:", self.new_username)
        cred_form.addRow("New Password:", self.new_password)
        cred_form.addRow("", self.show_password)
        manage_layout.addLayout(cred_form)
        
        # Update button
        self.update_button = QPushButton("💾 Update Credentials")
        self.update_button.setStyleSheet("""
            QPushButton {
                background-color: #4CAF50;
                color: white;
                border: none;
                padding: 10px;
                border-radius: 5px;
                font-weight: bold;
            }
            QPushButton:hover { background-color: #45a049; }
            QPushButton:disabled {
                background-color: #cccccc;
                color: #666666;
            }
        """)
        self.update_button.clicked.connect(self.update_credentials)
        self.update_button.setEnabled(False)
        manage_layout.addWidget(self.update_button)
        
        # Warning
        warning_label = QLabel("⚠️ Warning: Updating credentials will reset the trial status!\nNew credentials will be valid for one 1-minute trial session.")
        warning_label.setStyleSheet("color: #ff6b35; font-size: 11px; font-weight: bold;")
        warning_label.setWordWrap(True)
        manage_layout.addWidget(warning_label)
        
        self.manage_tab.setLayout(manage_layout)
        tab_widget.addTab(self.manage_tab, "⚙️ Manage Credentials")
        
        # Initially disable manage tab
        tab_widget.setTabEnabled(1, False)
        self.tab_widget = tab_widget
        
        layout.addWidget(tab_widget)
        
        # Close button
        close_button = QPushButton("Close")
        close_button.clicked.connect(self.accept)
        layout.addWidget(close_button)
        
        self.setLayout(layout)
        
        self.admin_verified = False
    
    def toggle_password_visibility(self, checked):
        """Toggle password visibility"""
        if checked:
            self.new_password.setEchoMode(QLineEdit.Normal)
        else:
            self.new_password.setEchoMode(QLineEdit.Password)
    
    def verify_admin(self):
        """Verify admin credentials"""
        username = self.admin_username.text().strip()
        password = self.admin_password.text().strip()
        
        if self.credentials_manager.verify_admin_credentials(username, password):
            self.admin_verified = True
            self.tab_widget.setTabEnabled(1, True)
            self.tab_widget.setCurrentIndex(1)
            self.update_button.setEnabled(True)
            self.update_credentials_info()
            
            QMessageBox.information(
                self,
                "✅ Admin Verified",
                "Admin access granted!\nYou can now manage credentials."
            )
        else:
            QMessageBox.critical(
                self,
                "❌ Admin Verification Failed",
                "Invalid admin credentials!\nAccess denied."
            )
            self.admin_password.clear()
    
    def update_credentials_info(self):
        """Update the credentials information display"""
        info = self.credentials_manager.get_credentials_info()
        if info:
            info_text = f"""
Current Username: {info['username']}
Created: {info['created_at']}
Created By: {info['created_by']}
Usage Count: {info['usage_count']}
Last Used: {info['last_used']}
Total Changes: {info['change_count']}
            """.strip()
            self.info_display.setText(info_text)
        else:
            self.info_display.setText("Could not load credentials information")
    
    def update_credentials(self):
        """Update credentials with validation"""
        if not self.admin_verified:
            QMessageBox.warning(self, "Access Denied", "Admin verification required!")
            return
        
        new_username = self.new_username.text().strip()
        new_password = self.new_password.text().strip()
        
        # Validation
        if not new_username or not new_password:
            QMessageBox.warning(
                self,
                "Invalid Input",
                "Both username and password are required!"
            )
            return
        
        if len(new_username) < 3:
            QMessageBox.warning(
                self,
                "Invalid Username",
                "Username must be at least 3 characters long!"
            )
            return
        
        if len(new_password) < 6:
            QMessageBox.warning(
                self,
                "Invalid Password",
                "Password must be at least 6 characters long!"
            )
            return
        
        # Confirmation
        reply = QMessageBox.question(
            self,
            "Confirm Update",
            f"Update credentials to:\nUsername: {new_username}\nPassword: {new_password}\n\n"
            "This will reset the trial status and allow one new 1-minute trial session.\n\n"
            "Are you sure?",
            QMessageBox.Yes | QMessageBox.No
        )
        
        if reply == QMessageBox.Yes:
            admin_user = self.admin_username.text().strip()
            if self.credentials_manager.update_credentials(new_username, new_password, admin_user):
                QMessageBox.information(
                    self,
                    "✅ Success",
                    "Credentials updated successfully!\n\n"
                    "The trial status has been reset.\n"
                    "New credentials are now valid for one 1-minute trial."
                )
                self.update_credentials_info()
                self.new_username.clear()
                self.new_password.clear()
            else:
                QMessageBox.critical(
                    self,
                    "❌ Error",
                    "Failed to update credentials!\nCheck console for details."
                )
