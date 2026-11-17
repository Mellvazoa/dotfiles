#!/usr/bin/env python3
"""Minimize the focused window (macOS yellow button analog) or restore the last minimized window."""

import json
import os
import subprocess
import sys

STACK_PATH = "/tmp/yabai_min_stack.json"
MAX_STACK = 50


def run_yabai(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["yabai", "-m", *args], capture_output=True, text=True)


def query_json(*args: str):
    res = run_yabai(*args)
    if res.returncode != 0 or not res.stdout.strip():
        return None
    try:
        return json.loads(res.stdout)
    except json.JSONDecodeError:
        return None


def load_stack() -> list[int]:
    try:
        with open(STACK_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            return [int(x) for x in data if isinstance(x, (int, float, str))]
    except Exception:
        pass
    return []


def save_stack(stack: list[int]) -> None:
    try:
        with open(STACK_PATH, "w", encoding="utf-8") as f:
            json.dump(stack[-MAX_STACK:], f)
    except Exception:
        pass


def minimize_focused() -> int:
    win = query_json("query", "--windows", "--window")
    if not isinstance(win, dict) or "id" not in win:
        return 1

    wid = int(win["id"])
    res = run_yabai("window", str(wid), "--minimize")
    if res.returncode != 0:
        # Fallback to clicking standard macOS Minimize shortcut on frontmost app
        subprocess.run(
            ["osascript", "-e", 'tell application "System Events" to keystroke "m" using command down'],
            capture_output=True,
        )

    stack = [x for x in load_stack() if x != wid]
    stack.append(wid)
    save_stack(stack)
    return 0


def restore_last_minimized() -> int:
    windows = query_json("query", "--windows")
    if not isinstance(windows, list):
        return 1

    space = query_json("query", "--spaces", "--space")
    cur_space_idx = space.get("index") if isinstance(space, dict) else None

    minimized = {int(w["id"]): w for w in windows if w.get("is-minimized")}
    if not minimized:
        return 0

    stack = load_stack()
    target_id = None

    # 1. Most recently minimized window still minimized (prefer current space first)
    for wid in reversed(stack):
        w = minimized.get(wid)
        if w and (cur_space_idx is None or w.get("space") == cur_space_idx):
            target_id = wid
            break

    # 2. Any stacked minimized window across spaces
    if target_id is None:
        for wid in reversed(stack):
            if wid in minimized:
                target_id = wid
                break

    # 3. Fallback: any minimized window (e.g. minimized via yellow button with mouse)
    if target_id is None:
        on_space = [wid for wid, w in minimized.items() if cur_space_idx is None or w.get("space") == cur_space_idx]
        target_id = on_space[0] if on_space else next(iter(minimized.keys()))

    save_stack([x for x in stack if x != target_id])
    run_yabai("window", str(target_id), "--deminimize")
    run_yabai("window", str(target_id), "--focus")
    return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--restore":
        return restore_last_minimized()
    return minimize_focused()


if __name__ == "__main__":
    raise SystemExit(main())
