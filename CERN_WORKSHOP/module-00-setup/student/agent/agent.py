import os
import time
import socket
import requests
import subprocess
import glob
import sys

# Configuration
SERVER_URL = os.getenv("DASHBOARD_URL", "http://192.168.1.100:8000/api/report")
INTERVAL = 30  # Seconds
# Default to three levels up from this script if not set
DEFAULT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../"))
WORKSHOP_ROOT = os.getenv("WORKSHOP_ROOT", DEFAULT_ROOT)

def get_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # Doesn't even have to be reachable
        s.connect(('10.255.255.255', 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = '127.0.0.1'
    finally:
        s.close()
    return IP

def check_modules():
    results = {}
    # Find all module directories relative to WORKSHOP_ROOT
    search_path = os.path.join(WORKSHOP_ROOT, "module-*")
    modules = sorted(glob.glob(search_path))
    
    for mod_path in modules:
        mod_name = os.path.basename(mod_path)
        validate_script = os.path.join(mod_path, "validate.sh")
        
        if os.path.isfile(validate_script):
            # Run the validation script
            try:
                rc = subprocess.call(
                    ["/bin/bash", validate_script],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    cwd=mod_path
                )
                if rc == 0:
                    results[mod_name] = "OK"
                elif rc == 100:
                    results[mod_name] = "PENDING"
                elif rc == 101:
                    results[mod_name] = "IN_PROGRESS"
                else:
                    results[mod_name] = "FAIL"
            except Exception:
                results[mod_name] = "ERROR"
        else:
            results[mod_name] = "PENDING"
            
    return results

def main():
    hostname = socket.getfqdn()
    ip_addr = get_ip()
    print(f"Agent started. ID: {hostname}, IP: {ip_addr}")
    print(f"Reporting to: {SERVER_URL}")

    while True:
        try:
            modules_status = check_modules()
            payload = {
                "student_id": hostname,
                "ip_address": ip_addr,
                "modules": modules_status
            }
            
            # Use Basic Auth for the dashboard
            requests.post(SERVER_URL, json=payload, auth=("admin", "kordent2024"))
            print(f"Report sent. Status: {modules_status}")
            
        except Exception as e:
            print(f"Error reporting status: {e}")
        
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
