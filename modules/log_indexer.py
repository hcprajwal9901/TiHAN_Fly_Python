import os
import time
from pathlib import Path
from modules.log_database import LogDatabase
from modules.log_parser import LogParser

class LogIndexer:
    """
    Scans log directory and updates SQLite index.
    Should be run in a separate thread/worker to avoid blocking UI.
    """
    
    def __init__(self, logs_dir, db_path="logs.db"):
        self.logs_dir = Path(logs_dir)
        self.db = LogDatabase(db_path)
        # NOTE: LogParser is NOT stored as self.parser here.
        # scan_and_index() is called from a background thread (LogManager uses
        # threading.Thread). LogParser is a QObject, so it must not be created
        # on the main thread and then called from a worker thread – that
        # violates Qt's object-affinity rules and causes intermittent crashes.
        # A fresh instance is created inside scan_and_index() instead.
        
    def scan_and_index(self):
        """
        Scan directory for new/modified logs and update index.
        Returns list of newly indexed files.
        """
        if not self.logs_dir.exists():
            return []

        # Create LogParser here, on whichever thread calls scan_and_index().
        # LogManager runs this on a daemon thread, so the parser is owned by
        # that thread for its entire lifetime – no cross-thread QObject access.
        parser = LogParser()
        indexed_files = []
        existing_logs = {log['filename']: log for log in self.db.get_all_logs()}
        
        # Scan directory
        for file_path in self.logs_dir.glob("*.[bB][iI][nN]"): # Handle .bin (and .log ideally)
            filename = file_path.name
            file_stat = file_path.stat()
            file_size = file_stat.st_size
            file_mtime = file_stat.st_mtime
            
            # Check if needs update (new or modified)
            needs_update = False
            if filename not in existing_logs:
                needs_update = True
                print(f"Indexing new log: {filename}")
            elif existing_logs[filename]['file_size'] != file_size:
                 # Simple size check, could add mtime
                needs_update = True
                print(f"Re-indexing modified log: {filename}")
            
            if needs_update:
                try:
                    # Parse log to get metadata
                    # Note: Full parse might be slow for huge logs. 
                    # Optimization: LogParser could have a 'header_only' or 'summary_only' mode.
                    # For now, we parse fully but catch errors.
                    parsed_log = parser.parse_log(str(file_path))
                    
                    if parsed_log and parsed_log.flight_summary:
                        summary = parsed_log.flight_summary
                        
                        log_data = {
                            'filename': filename,
                            'filepath': str(file_path),
                            'file_size': file_size,
                            'timestamp': summary.get('start_time', file_mtime), # Fallback to file time
                            'duration': summary.get('duration', 0),
                            'max_altitude': summary.get('max_altitude', 0),
                            'max_speed': summary.get('max_speed', 0),
                            'vehicle_type': 'Unknown', # TODO: Extract from parm/msg
                            'firmware_version': 'Unknown'
                        }
                        
                        self.db.add_log(log_data)
                        indexed_files.append(filename)
                    else:
                        print(f"Failed to extract summary for {filename}")
                        # Add basic info even if parse fails? No, better to retry.
                except Exception as e:
                    print(f"Error indexing {filename}: {e}")
                    
        return indexed_files

if __name__ == "__main__":
    # Test
    indexer = LogIndexer("C:/Users/Tihan 02/Documents/TihanFly/Logs/downloaded")
    new_files = indexer.scan_and_index()
    print(f"Indexed {len(new_files)} new logs.")