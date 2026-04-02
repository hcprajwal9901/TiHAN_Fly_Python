"""
Port Access Guard - Prevents multiple threads from accessing serial port
"""
import threading
import traceback

class PortAccessGuard:
    """Singleton guard to prevent port access conflicts"""
    _lock = threading.Lock()
    _active_thread = None
    
    @classmethod
    def wrap_connection(cls, connection):
        """Wrap a MAVLink connection to prevent concurrent access"""
        if not hasattr(connection, '_original_recv_match'):
            # Save original method
            connection._original_recv_match = connection.recv_match
            
            def guarded_recv_match(*args, **kwargs):
                current_thread = threading.current_thread()
                
                # Try to acquire lock (non-blocking)
                if not cls._lock.acquire(blocking=False):
                    # Another thread has the lock
                    caller_info = traceback.extract_stack()[-2]
                    print(f"\n{'='*80}")
                    print(f"⚠️ PORT ACCESS CONFLICT DETECTED!")
                    print(f"{'='*80}")
                    print(f"Blocked thread: {current_thread.name}")
                    print(f"Active thread: {cls._active_thread}")
                    print(f"Called from: {caller_info.filename}:{caller_info.lineno} in {caller_info.name}")
                    print(f"{'='*80}\n")
                    
                    # Return None instead of blocking
                    return None
                
                try:
                    cls._active_thread = current_thread.name
                    return connection._original_recv_match(*args, **kwargs)
                finally:
                    cls._active_thread = None
                    cls._lock.release()
            
            # Replace recv_match with guarded version
            connection.recv_match = guarded_recv_match
            print(f"[PortAccessGuard] Wrapped connection {connection}")
        
        return connection
    
    @classmethod
    def is_locked(cls):
        """Check if port is currently locked"""
        return cls._lock.locked()