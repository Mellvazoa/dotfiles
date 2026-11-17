#!/usr/bin/env python3
import subprocess
import re
import sys

def main():
    iface = sys.argv[1] if len(sys.argv) > 1 else "en0"
    ssid = "N/A"
    lan_ip = "N/A"
    try:
        out = subprocess.check_output(["ipconfig", "getsummary", iface], text=True)
        m = re.search(r'\bSSID\s*:\s*(.+)', out)
        if m:
            ssid = m.group(1).strip()
        m_ip = re.search(r'Addresses\s*:\s*<array>\s*\{\s*0\s*:\s*([0-9.]+)', out)
        if m_ip:
            lan_ip = m_ip.group(1).strip()
    except Exception:
        pass

    direct_ip = "N/A"
    try:
        direct_ip = subprocess.check_output(
            ["curl", "--interface", iface, "-s", "--max-time", "2", "https://api.ipify.org"],
            text=True
        ).strip()
    except Exception:
        pass

    routed_ip = "N/A"
    try:
        routed_ip = subprocess.check_output(
            ["curl", "-s", "--max-time", "2", "https://api.ipify.org"],
            text=True
        ).strip()
    except Exception:
        pass

    vpn_ip = "Disconnected"
    pub_ip = direct_ip if direct_ip != "N/A" else routed_ip

    if routed_ip and direct_ip and routed_ip != "N/A" and direct_ip != "N/A":
        if routed_ip != direct_ip:
            pub_ip = direct_ip
            vpn_ip = routed_ip
        else:
            pub_ip = routed_ip
            vpn_ip = "Disconnected"
    elif routed_ip and routed_ip != "N/A":
        pub_ip = routed_ip
        vpn_ip = "Disconnected"

    print(f"{ssid}|{lan_ip}|{pub_ip}|{vpn_ip}")

if __name__ == "__main__":
    main()

