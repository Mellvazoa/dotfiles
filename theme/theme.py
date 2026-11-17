#!/usr/bin/env python3
"""Unified template-driven theme engine for macOS dotfiles.

Supports both curated TOML presets (Catppuccin, Tokyo Night, Nord, etc.)
and dynamic wallpaper-extracted palettes from wallpaper_gallery.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path
from typing import Any

THEME_DIR = Path(__file__).resolve().parent
REPO_DIR = THEME_DIR.parent
TARGETS_PATH = THEME_DIR / "targets.toml"
TEMPLATES_DIR = THEME_DIR / "templates"
PRESETS_DIR = THEME_DIR / "presets"

CONFIG_THEME_DIR = Path.home() / ".config" / "theme"
STATE_PATH = CONFIG_THEME_DIR / "state.json"

DEFAULT_COLORS = {
    "bg": "#14172f",
    "bg_panel": "#1c203f",
    "bg_card": "#292e59",
    "fg": "#f0edfc",
    "fg_soft": "#d8d3f5",
    "fg_muted": "#8a8eb5",
    "accent": "#c8b4fa",
    "highlight": "#928dfb",
    "danger": "#fc5d7c",
    "urgent": "#fca07a",
    "ok": "#a3e49b",
    "yellow": "#f6df94",
    "blue": "#9ccdfb",
    "cyan": "#8ae1e8",
}


def norm_hex(value: str, fallback: str = "#ffffff") -> str:
    s = (value or "").strip().lstrip("#")
    if len(s) == 6 and all(c in "0123456789abcdefABCDEF" for c in s):
        return "#" + s.lower()
    return fallback.lower()


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    s = norm_hex(h)[1:]
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


def rgb_to_hex(r: int, g: int, b: int) -> str:
    return f"#{max(0, min(255, r)):02x}{max(0, min(255, g)):02x}{max(0, min(255, b)):02x}"


def blend(h1: str, h2: str, t: float) -> str:
    r1, g1, b1 = hex_to_rgb(h1)
    r2, g2, b2 = hex_to_rgb(h2)
    return rgb_to_hex(
        round(r1 + (r2 - r1) * t),
        round(g1 + (g2 - g1) * t),
        round(b1 + (b2 - b1) * t),
    )


def load_state() -> dict[str, Any]:
    if STATE_PATH.exists():
        try:
            data = json.loads(STATE_PATH.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return data
        except Exception:
            pass
    return {"mode": "wallpaper", "preset": "arona-lavender", "locked": False}


def save_state(state: dict[str, Any]) -> None:
    CONFIG_THEME_DIR.mkdir(parents=True, exist_ok=True)
    atomic_write(STATE_PATH, json.dumps(state, indent=2) + "\n")


def atomic_write(path: Path, content: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".theme_", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        if mode is not None:
            os.chmod(tmp_name, mode)
        elif path.exists():
            os.chmod(tmp_name, path.stat().st_mode & 0o777)
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def expand_path(raw: str) -> Path:
    return Path(raw.replace("{repo}", str(REPO_DIR))).expanduser()


def build_tokens(colors: dict[str, str], label: str, appearance: str = "dark") -> dict[str, str]:
    c = {k: norm_hex(v) for k, v in colors.items() if isinstance(v, str) and v.startswith("#")}

    island = c.get("bg", DEFAULT_COLORS["bg"])
    is_light = appearance == "light"
    bg1 = c.get("bg_panel") or blend(island, "#000000" if is_light else "#ffffff", 0.05)
    bg2 = c.get("bg_card") or blend(island, "#000000" if is_light else "#ffffff", 0.12)
    fg = c.get("fg", DEFAULT_COLORS["fg"])
    fg_soft = c.get("fg_soft") or blend(fg, island, 0.15)
    fg_muted = c.get("fg_muted") or blend(fg, island, 0.45)

    accent = c.get("accent", DEFAULT_COLORS["accent"])
    accent_light = c.get("accent_light") or blend(accent, fg, 0.35)
    accent_dim = c.get("accent_dim") or blend(accent, island, 0.25)
    lilac = c.get("highlight") or c.get("lilac") or blend(accent, c.get("term5", accent), 0.5)

    red = c.get("danger") or c.get("term9") or c.get("term1") or DEFAULT_COLORS["danger"]
    green = c.get("ok") or c.get("term10") or c.get("term2") or DEFAULT_COLORS["ok"]
    blue = c.get("blue") or c.get("term12") or c.get("term4") or DEFAULT_COLORS["blue"]
    yellow = c.get("yellow") or c.get("term11") or c.get("term3") or DEFAULT_COLORS["yellow"]
    orange = c.get("urgent") or blend(red, yellow, 0.45)
    cyan = c.get("cyan") or c.get("term14") or c.get("term6") or DEFAULT_COLORS["cyan"]

    cursor = c.get("cursor", accent_light)
    selection_bg = c.get("selection_bg", accent)
    selection_fg = c.get("selection_fg", island)
    tab_bar_bg = c.get("tab_bar_bg") or blend(island, "#000000", 0.15 if not is_light else 0.05)
    inactive_tab_fg = c.get("fg_faint") or fg_muted
    inactive_tab_bg = bg1
    bell_border = c.get("bell_border") or orange

    defaults_term = {
        0: bg1,
        1: red,
        2: green,
        3: yellow,
        4: blue,
        5: accent,
        6: lilac,
        7: fg_soft,
        8: bg2,
        9: blend(red, "#ffffff", 0.18),
        10: blend(green, "#ffffff", 0.18),
        11: blend(yellow, "#ffffff", 0.18),
        12: blend(blue, "#ffffff", 0.18),
        13: accent_light,
        14: blend(cyan, "#ffffff", 0.18),
        15: fg,
    }

    tokens: dict[str, str] = {
        "theme_label": label,
        "appearance": appearance,
        "telegram_parent": "day" if is_light else "nightAccent",
        "island": island,
        "bg1": bg1,
        "bg2": bg2,
        "fg": fg,
        "fg_soft": fg_soft,
        "fg_muted": fg_muted,
        "accent": accent,
        "accent_light": accent_light,
        "accent_dim": accent_dim,
        "lilac": lilac,
        "red": red,
        "green": green,
        "blue": blue,
        "yellow": yellow,
        "orange": orange,
        "cyan": cyan,
        "cursor": cursor,
        "selection_bg": selection_bg,
        "selection_fg": selection_fg,
        "tab_bar_bg": tab_bar_bg,
        "inactive_tab_fg": inactive_tab_fg,
        "inactive_tab_bg": inactive_tab_bg,
        "bell_border": bell_border,
    }

    for i in range(16):
        tokens[f"term{i}"] = c.get(f"term{i}", defaults_term[i])

    # Add bare hex variants (`*_hex`) without leading '#'
    for key, val in list(tokens.items()):
        if isinstance(val, str) and val.startswith("#") and len(val) == 7:
            tokens[f"{key}_hex"] = val[1:]

    return tokens


def render_template(template_text: str, tokens: dict[str, str]) -> str:
    def repl(match: re.Match[str]) -> str:
        key = match.group(1)
        return tokens.get(key, match.group(0))

    return re.sub(r"\{\{([A-Za-z0-9_]+)\}\}", repl, template_text)


def sync_yabai(accent_hex: str) -> None:
    yabai_files = [
        Path.home() / ".config" / "yabai" / "yabairc",
        REPO_DIR / "yabai" / "yabairc",
    ]
    seen_real: set[Path] = set()
    for path in yabai_files:
        if not path.exists():
            continue
        real = path.resolve()
        if real in seen_real:
            continue
        seen_real.add(real)
        try:
            text = path.read_text(encoding="utf-8")
            updated = re.sub(
                r"insert_feedback_color\s+0xff[0-9a-fA-F]+",
                f"insert_feedback_color      0xff{accent_hex}",
                text,
            )
            if updated != text:
                atomic_write(path, updated)
        except Exception:
            pass

    if shutil.which("yabai"):
        subprocess.run(
            ["yabai", "-m", "config", "insert_feedback_color", f"0xff{accent_hex}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def sync_lockscreen_json(tokens: dict[str, str]) -> None:
    lock_json = Path.home() / ".config" / "lockscreen" / "current_theme.json"
    data: dict[str, Any] = {}
    if lock_json.exists():
        try:
            loaded = json.loads(lock_json.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                data = loaded
        except Exception:
            pass
    data["accentHex"] = tokens["accent_hex"]
    data["islandHex"] = tokens["island_hex"]
    data["textWhiteHex"] = tokens["fg_hex"]
    atomic_write(lock_json, json.dumps(data, indent=2))


def ensure_btop_config() -> None:
    btop_conf = Path.home() / ".config" / "btop" / "btop.conf"
    if not btop_conf.exists():
        if not shutil.which("btop"):
            return
        res = subprocess.run(
            ["btop", "--default-config"],
            capture_output=True,
            text=True,
        )
        if res.returncode != 0 or not res.stdout:
            return
        text = res.stdout
    else:
        text = btop_conf.read_text(encoding="utf-8")

    updated = re.sub(
        r'^#?\s*color_theme\s*=.*$',
        'color_theme = "dynamic"',
        text,
        count=1,
        flags=re.MULTILINE,
    )
    updated = re.sub(
        r'^#?\s*theme_background\s*=.*$',
        'theme_background = false',
        updated,
        count=1,
        flags=re.MULTILINE,
    )
    if updated != text or not btop_conf.exists():
        atomic_write(btop_conf, updated)


def ensure_cava_config() -> None:
    cava_conf = Path.home() / ".config" / "cava" / "config"
    if not cava_conf.exists():
        return
    text = cava_conf.read_text(encoding="utf-8")
    updated = re.sub(
        r"^;\s*theme\s*=\s*['\"].*?['\"]$",
        "theme = 'dynamic'",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if updated == text:
        updated = re.sub(
            r"^theme\s*=\s*['\"].*?['\"]$",
            "theme = 'dynamic'",
            text,
            count=1,
            flags=re.MULTILINE,
        )
    if updated != text:
        atomic_write(cava_conf, updated)


def sync_wallpaper_gallery(tokens: dict[str, str]) -> None:
    candidates = [
        Path.home() / ".local" / "bin" / "wallpaper_gallery",
        REPO_DIR / "wallpaper_gallery" / "bin" / "wallpaper_gallery",
    ]
    for bin_path in candidates:
        if bin_path.exists() and os.access(bin_path, os.X_OK):
            subprocess.run(
                [
                    str(bin_path),
                    "--theme",
                    tokens["accent_hex"],
                    tokens["island_hex"],
                    tokens["fg_hex"],
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            break


def apply_tokens(tokens: dict[str, str], reload_targets: bool = True, notify_gallery: bool = True) -> None:
    targets = tomllib.loads(TARGETS_PATH.read_text(encoding="utf-8"))

    ensure_btop_config()
    ensure_cava_config()

    reload_cmds: list[list[str]] = []
    seen_real_outputs: set[Path] = set()

    for name, cfg in targets.items():
        if not isinstance(cfg, dict):
            continue
        tpl_file = TEMPLATES_DIR / cfg["input"]
        if not tpl_file.exists():
            continue
        rendered = render_template(tpl_file.read_text(encoding="utf-8"), tokens)
        file_mode = cfg.get("mode")

        for raw_out in cfg.get("outputs", []):
            out_path = expand_path(raw_out)
            real = out_path.resolve()
            if real in seen_real_outputs:
                continue
            seen_real_outputs.add(real)
            atomic_write(out_path, rendered, mode=file_mode)

        if reload_targets and "reload" in cfg:
            reload_cmds.append([os.path.expanduser(arg) for arg in cfg["reload"]])

    sync_yabai(tokens["accent_hex"])
    sync_lockscreen_json(tokens)

    tg_music_bin = Path.home() / ".local" / "bin" / "tg_music"
    if tg_music_bin.exists() and os.access(tg_music_bin, os.X_OK):
        subprocess.run(
            [str(tg_music_bin), "--reload-theme"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    if reload_targets:
        for cmd in reload_cmds:
            try:
                subprocess.Popen(
                    cmd,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except OSError:
                pass

    if notify_gallery:
        sync_wallpaper_gallery(tokens)


def load_preset(preset_id: str) -> tuple[dict[str, str], str, str]:
    path = PRESETS_DIR / f"{preset_id}.toml"
    if not path.exists():
        raise FileNotFoundError(f"Preset '{preset_id}' not found in {PRESETS_DIR}")
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    label = str(data.get("name") or preset_id)
    appearance = str(data.get("appearance") or "dark")
    colors = data.get("colors", {})
    if not isinstance(colors, dict):
        colors = {}
    return colors, label, appearance


def list_presets() -> list[dict[str, str]]:
    items: list[dict[str, str]] = []
    if not PRESETS_DIR.exists():
        return items
    for path in sorted(PRESETS_DIR.glob("*.toml")):
        try:
            data = tomllib.loads(path.read_text(encoding="utf-8"))
            colors = data.get("colors", {})
            items.append({
                "id": path.stem,
                "name": str(data.get("name") or path.stem),
                "appearance": str(data.get("appearance") or "dark"),
                "description": str(data.get("description") or ""),
                "accent": norm_hex(str(colors.get("accent", "#c8b4fa"))),
                "bg": norm_hex(str(colors.get("bg", "#14172f"))),
            })
        except Exception:
            continue
    return items


def dynamic_payload_to_colors(payload: dict[str, Any]) -> tuple[dict[str, str], str]:
    is_arona = bool(payload.get("isArona", False))
    if is_arona:
        colors, label, _ = load_preset("arona-lavender")
        return colors, label

    accent = norm_hex(payload.get("accentHex", "c8b4fa"))
    accent_light = norm_hex(payload.get("accentLightHex", "e4d2fd"))
    accent_dim = norm_hex(payload.get("accentDimHex", "aba0f5"))
    lilac = norm_hex(payload.get("lilacHex", "928dfb"))
    island = norm_hex(payload.get("islandHex", "14172f"))
    fg = norm_hex(payload.get("textWhiteHex", "f0edfc"))
    bg1 = norm_hex(payload.get("bg1Hex", "1c203f"))
    bg2 = norm_hex(payload.get("bg2Hex", "292e59"))
    name = str(payload.get("wallpaperName") or "Wallpaper Dynamic")

    colors = {
        "bg": island,
        "bg_panel": bg1,
        "bg_card": bg2,
        "fg": fg,
        "fg_soft": blend(fg, island, 0.12),
        "fg_muted": accent_dim,
        "accent": accent,
        "accent_light": accent_light,
        "accent_dim": accent_dim,
        "highlight": lilac,
        "danger": "#fc5d7c",
        "urgent": "#fca07a",
        "ok": "#a3e49b",
        "yellow": "#f6df94",
        "blue": "#9ccdfb",
        "cyan": lilac,
        "cursor": accent_light,
        "selection_bg": accent,
        "selection_fg": island,
        "bell_border": accent_light,
    }
    return colors, name


def main() -> int:
    parser = argparse.ArgumentParser(description="Unified theme engine for dotfiles")
    parser.add_argument("--list", action="store_true", help="List available preset themes")
    parser.add_argument("--json", action="store_true", help="Output JSON (with --list or --status)")
    parser.add_argument("--status", action="store_true", help="Show current theme state")
    parser.add_argument("--preset", metavar="ID", help="Apply a preset theme by id")
    parser.add_argument("--lock", action="store_true", help="Lock preset so wallpaper changes keep it")
    parser.add_argument("--unlock", action="store_true", help="Unlock preset so wallpaper changes adapt theme")
    parser.add_argument("--toggle-lock", action="store_true", help="Toggle wallpaper lock state")
    parser.add_argument("--auto", action="store_true", help="Unlock and reapply dynamic theme from current wallpaper")
    parser.add_argument("--apply-dynamic", metavar="JSON_OR_PATH", help="Apply dynamic palette JSON from wallpaper_gallery")
    parser.add_argument("--force", action="store_true", help="Ignore preset lock when applying dynamic theme")
    parser.add_argument("--no-reload", action="store_true", help="Write files without reloading services")
    args = parser.parse_args()

    state = load_state()

    if args.list:
        presets = list_presets()
        if args.json:
            print(json.dumps({"state": state, "presets": presets}, indent=2))
        else:
            for p in presets:
                mark = "*" if (state.get("mode") == "preset" and state.get("preset") == p["id"]) else " "
                print(f"{mark} {p['id']:20s} {p['accent']}  {p['name']} ({p['appearance']})")
        return 0

    if args.status:
        if args.json:
            print(json.dumps(state, indent=2))
        else:
            print(f"mode: {state.get('mode', 'wallpaper')}")
            print(f"preset: {state.get('preset', '')}")
            print(f"locked: {bool(state.get('locked', False))}")
        return 0

    if args.toggle_lock:
        state["locked"] = not bool(state.get("locked", False))
        save_state(state)
        print(f"locked={state['locked']}")
        return 0

    if args.auto:
        state["mode"] = "wallpaper"
        state["locked"] = False
        save_state(state)
        dyn = state.get("last_dynamic")
        if isinstance(dyn, dict) and dyn:
            colors, label = dynamic_payload_to_colors(dyn)
            tokens = build_tokens(colors, label, "dark")
        else:
            colors, label, app = load_preset("arona-lavender")
            tokens = build_tokens(colors, label, app)
        apply_tokens(tokens, reload_targets=not args.no_reload, notify_gallery=True)
        print(f"Applied wallpaper theme: {tokens['theme_label']}")
        return 0

    if args.preset:
        colors, label, appearance = load_preset(args.preset)
        tokens = build_tokens(colors, label, appearance)
        state["mode"] = "preset"
        state["preset"] = args.preset
        if args.lock:
            state["locked"] = True
        elif args.unlock:
            state["locked"] = False
        save_state(state)
        apply_tokens(tokens, reload_targets=not args.no_reload, notify_gallery=True)
        print(f"Applied preset: {args.preset} (locked={state.get('locked', False)})")
        return 0

    if args.apply_dynamic:
        raw = args.apply_dynamic
        if os.path.exists(raw):
            payload = json.loads(Path(raw).read_text(encoding="utf-8"))
        else:
            payload = json.loads(raw)

        state["last_dynamic"] = payload
        if state.get("locked", False) and not args.force and state.get("preset"):
            colors, label, appearance = load_preset(str(state["preset"]))
            tokens = build_tokens(colors, label, appearance)
            save_state(state)
            apply_tokens(tokens, reload_targets=not args.no_reload, notify_gallery=True)
            print(f"Kept locked preset: {state['preset']}")
            return 0

        state["mode"] = "wallpaper"
        save_state(state)
        colors, label = dynamic_payload_to_colors(payload)
        tokens = build_tokens(colors, label, "dark")
        # wallpaper_gallery already updates its own pill/webview UI right away
        apply_tokens(tokens, reload_targets=not args.no_reload, notify_gallery=False)
        print(f"Applied dynamic wallpaper theme: {label}")
        return 0

    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
