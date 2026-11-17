#!/usr/bin/env python3
import sys
import json
import subprocess
import os
import signal

event_name = sys.argv[1] if len(sys.argv) > 1 else "temp_update"
interval = sys.argv[2] if len(sys.argv) > 2 else "2500"

# Register event with Sketchybar
subprocess.run(["sketchybar", "--add", "event", event_name], check=False)

macmon_path = "/opt/homebrew/bin/macmon"
if not os.path.exists(macmon_path):
    macmon_path = "macmon"

cmd = [macmon_path, "pipe", "-i", str(interval)]

proc = None

def cleanup(sig=None, frame=None):
    global proc
    if proc and proc.poll() is None:
        try:
            proc.terminate()
            proc.wait(timeout=0.5)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
    sys.exit(0)

signal.signal(signal.SIGTERM, cleanup)
signal.signal(signal.SIGINT, cleanup)

try:
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            temp = data.get("temp", {})
            cpu_t = round(temp.get("cpu_temp_avg", 0))
            gpu_t = round(temp.get("gpu_temp_avg", 0))
            pwr = round(data.get("sys_power", 0), 1)

            if cpu_t > 0:
                subprocess.run([
                    "sketchybar",
                    "--trigger", event_name,
                    f"cpu_temp={cpu_t}",
                    f"gpu_temp={gpu_t}",
                    f"sys_power={pwr}"
                ], check=False)
        except Exception:
            continue
except Exception:
    pass
finally:
    cleanup()
