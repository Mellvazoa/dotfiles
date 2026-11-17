"""Run Homebrew `choose` cleanly above floating/zoomed yabai windows."""
import json
import os
import pwd
import socket
import struct
import subprocess

USER = os.environ.get("USER") or pwd.getpwuid(os.getuid()).pw_name
SOCK_PATH = f"/tmp/yabai_{USER}.socket"


def _y(*args):
    str_args = [str(a) for a in args]
    try:
        payload = ("\x00".join(str_args) + "\x00\x00").encode("utf-8")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.3)
            s.connect(SOCK_PATH)
            s.sendall(struct.pack("<I", len(payload)) + payload)
            s.shutdown(socket.SHUT_WR)
            chunks = []
            while True:
                chunk = s.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
        raw = b"".join(chunks)
        if raw.startswith(b"\x07"):
            return ""
        return raw.decode("utf-8", errors="replace").strip()
    except OSError:
        return ""


def run_choose(choose_cmd, input_data):
    """Temporarily lower `sub-layer=above` windows on the space so `choose` renders on top."""
    lowered_ids = []
    raw_wins = _y("query", "--windows", "--space")
    if raw_wins:
        try:
            for w in json.loads(raw_wins):
                if (
                    w.get("sub-layer") == "above"
                    and w.get("is-visible")
                    and not w.get("is-minimized")
                    and w.get("app") != "wallpaper_gallery"
                ):
                    wid = w["id"]
                    _y("window", wid, "--sub-layer", "normal")
                    lowered_ids.append(wid)
        except ValueError:
            pass

    try:
        proc = subprocess.Popen(
            choose_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        selected, _ = proc.communicate(input=input_data)
        return selected.strip()
    finally:
        for wid in lowered_ids:
            _y("window", wid, "--sub-layer", "above")

