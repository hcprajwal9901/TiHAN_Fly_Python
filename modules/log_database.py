import sqlite3
import os
from datetime import datetime
from pathlib import Path

class LogDatabase:
    """
    Manages SQLite database for log metadata.
    Stores summary information to allow fast searching/filtering without re-parsing files.
    """
    
    def __init__(self, db_path="logs.db"):
        self.db_path = db_path
        self._init_db()

    def _init_db(self):
        """Initialize database schema"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create logs table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS logs (
                filename TEXT PRIMARY KEY,
                filepath TEXT,
                file_size INTEGER,
                timestamp INTEGER, -- Unix timestamp of log start
                duration REAL,     -- Flight duration in seconds
                max_altitude REAL,
                max_speed REAL,
                vehicle_type TEXT,
                firmware_version TEXT,
                date_added TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        conn.commit()
        conn.close()

    def add_log(self, log_data):
        """
        Add or update a log entry.
        log_data: dict containing 'filename', 'filepath', 'file_size', etc.
        """
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        query = '''
            INSERT OR REPLACE INTO logs (
                filename, filepath, file_size, timestamp, duration, 
                max_altitude, max_speed, vehicle_type, firmware_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        '''
        
        values = (
            log_data.get('filename'),
            log_data.get('filepath'),
            log_data.get('file_size', 0),
            log_data.get('timestamp', 0),
            log_data.get('duration', 0.0),
            log_data.get('max_altitude', 0.0),
            log_data.get('max_speed', 0.0),
            log_data.get('vehicle_type', 'Unknown'),
            log_data.get('firmware_version', 'Unknown')
        )
        
        cursor.execute(query, values)
        conn.commit()
        conn.close()

    def get_all_logs(self):
        """Retrieve all logs ordered by timestamp desc"""
        try:
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            
            cursor.execute('SELECT * FROM logs ORDER BY timestamp DESC')
            rows = [dict(row) for row in cursor.fetchall()]
            
            conn.close()
            return rows
        except Exception as e:
            print(f"Error fetching logs: {e}")
            return []

    def get_log(self, filename):
        """Get single log by filename"""
        try:
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            
            cursor.execute('SELECT * FROM logs WHERE filename = ?', (filename,))
            row = cursor.fetchone()
            
            conn.close()
            return dict(row) if row else None
        except Exception:
            return None


    def delete_log(self, filename):
        """Remove log from index"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('DELETE FROM logs WHERE filename = ?', (filename,))
        conn.commit()
        conn.close()
