#!/usr/bin/env python3
"""Telegram music library sync & on-demand audio downloader using Telethon.

Stores config, Telethon session, track index, and downloaded cache in:
  ~/.config/tg_music/
"""
from __future__ import annotations

import argparse
import asyncio
import getpass
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

STATE_DIR = Path.home() / ".config" / "tg_music"
CONFIG_PATH = STATE_DIR / "config.json"
SESSION_PATH = STATE_DIR / "tg_music"
TRACKS_PATH = STATE_DIR / "tracks.json"
CACHE_DIR = STATE_DIR / "cache"
THUMBS_DIR = STATE_DIR / "thumbs"

AUDIO_EXTS = {".mp3", ".m4a", ".flac", ".ogg", ".opus", ".wav", ".aac"}


def atomic_write(path: Path, text: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".tgmusic_", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        if mode is not None:
            os.chmod(tmp_name, mode)
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def load_config() -> dict[str, Any] | None:
    if not CONFIG_PATH.exists():
        return None
    try:
        data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        if isinstance(data, dict) and data.get("api_id") and data.get("api_hash"):
            return data
    except Exception:
        pass
    return None


def find_cached_audio(msg_id: int) -> Path | None:
    if not CACHE_DIR.exists():
        return None
    for ext in AUDIO_EXTS:
        p = CACHE_DIR / f"{msg_id}{ext}"
        if p.exists() and p.stat().st_size > 0:
            return p
    for p in CACHE_DIR.glob(f"{msg_id}.*"):
        if p.is_file() and not p.name.endswith(".part") and p.stat().st_size > 0:
            return p
    return None


def is_audio_message(msg: Any) -> tuple[bool, str, str, int, str]:
    """Return (is_audio, title, artist, duration_sec, ext)."""
    doc = getattr(msg, "document", None)
    if not doc:
        return False, "", "", 0, ""

    from telethon.tl.types import DocumentAttributeAudio, DocumentAttributeFilename

    mime = (getattr(doc, "mime_type", "") or "").lower()
    title = ""
    artist = ""
    duration = 0
    file_name = ""
    has_audio_attr = False

    for attr in getattr(doc, "attributes", []) or []:
        if isinstance(attr, DocumentAttributeAudio):
            if getattr(attr, "voice", False):
                return False, "", "", 0, ""
            has_audio_attr = True
            title = (attr.title or "").strip()
            artist = (attr.performer or "").strip()
            duration = int(attr.duration or 0)
        elif isinstance(attr, DocumentAttributeFilename):
            file_name = (attr.file_name or "").strip()

    ext = Path(file_name).suffix.lower() if file_name else ""
    if not ext:
        if "mpeg" in mime or "mp3" in mime:
            ext = ".mp3"
        elif "mp4" in mime or "m4a" in mime or "aac" in mime:
            ext = ".m4a"
        elif "flac" in mime:
            ext = ".flac"
        elif "ogg" in mime or "opus" in mime:
            ext = ".ogg"

    if not has_audio_attr and not mime.startswith("audio/") and ext not in AUDIO_EXTS:
        return False, "", "", 0, ""

    if not title:
        stem = Path(file_name).stem if file_name else f"Track {msg.id}"
        stem = re.sub(r"^\d+[\s._-]+", "", stem).strip() or stem
        if " - " in stem and not artist:
            parts = stem.split(" - ", 1)
            artist = parts[0].strip()
            title = parts[1].strip()
        else:
            title = stem
    if not artist:
        artist = "Unknown Artist"
    if not ext:
        ext = ".mp3"

    return True, title, artist, duration, ext


async def resolve_chat_entity(client: Any, target: str) -> Any:
    target = (target or "me").strip()
    if target.startswith("@") or target.lstrip("-").isdigit():
        try:
            key = int(target) if target.lstrip("-").isdigit() else target
            return await client.get_entity(key)
        except Exception:
            pass

    lower = target.lower()
    exact = None
    partial = None
    async for dialog in client.iter_dialogs():
        name = (dialog.name or "").strip()
        username = (getattr(dialog.entity, "username", None) or "").strip()
        if name.lower() == lower or (username and username.lower() == lower.lstrip("@")):
            exact = dialog.entity
            break
        if lower in name.lower() and partial is None:
            partial = dialog.entity

    if exact is not None:
        return exact
    if partial is not None:
        return partial
    raise RuntimeError(f"Telegram chat/channel '{target}' not found in your dialogs")


def make_client(cfg: dict[str, Any]) -> Any:
    from telethon import TelegramClient

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    return TelegramClient(
        str(SESSION_PATH),
        int(cfg["api_id"]),
        str(cfg["api_hash"]),
        device_model="MacBook Air",
        system_version="macOS",
        app_version="1.0",
    )


def print_qr_terminal(url: str) -> None:
    import qrcode

    qr = qrcode.QRCode(border=2, box_size=1, error_correction=qrcode.constants.ERROR_CORRECT_L)
    qr.add_data(url)
    qr.make(fit=True)
    matrix = qr.get_matrix()
    # Render 2 vertical modules per row using Unicode half-blocks on white background
    # High contrast: black modules on white paper (spaces = light, blocks = dark)
    # Using ANSI bright-white bg + black fg so Kitty renders a crisp, scannable QR regardless of terminal theme.
    fg_black_bg_white = "\033[30;107m"
    reset = "\033[0m"
    rows = len(matrix)
    print("")
    for y in range(0, rows, 2):
        line = []
        top_row = matrix[y]
        bot_row = matrix[y + 1] if y + 1 < rows else [False] * len(top_row)
        for t, b in zip(top_row, bot_row):
            if t and b:
                line.append("█")
            elif t and not b:
                line.append("▀")
            elif not t and b:
                line.append("▄")
            else:
                line.append(" ")
        print(fg_black_bg_white + "".join(line) + reset)
    print("")


async def qr_login_flow(client: Any) -> None:
    from telethon.errors import SessionPasswordNeededError

    print("\nОткрой Telegram на телефоне:")
    print("  Настройки -> Устройства -> Подключить устройство")
    print("И отсканируй этот QR-код (обновляется автоматически каждые 30 сек):")

    qr_login = await client.qr_login()
    for attempt in range(6):
        print_qr_terminal(qr_login.url)
        try:
            await qr_login.wait(timeout=30)
            return
        except asyncio.TimeoutError:
            if attempt < 5:
                print("[*] QR-код истёк, обновляю...")
                await qr_login.recreate()
            else:
                raise RuntimeError("QR-код не был отсканирован вовремя.")
        except SessionPasswordNeededError:
            pwd = getpass.getpass("Введи облачный пароль Telegram (2FA): ")
            await client.sign_in(password=pwd)
            return


async def phone_login_flow(client: Any) -> None:
    from telethon.errors import SessionPasswordNeededError

    phone = input("Номер телефона (например +79991234567): ").strip().replace(" ", "").replace("-", "")
    if phone.startswith("8") and len(phone) == 11:
        phone = "+7" + phone[1:]
        print(f"[*] Преобразовал номер в международный формат: {phone}")

    sent = await client.send_code_request(phone)
    code_type = type(sent.type).__name__
    print(f"[*] Запрос отправлен (тип доставки: {code_type}).")
    if "App" in code_type:
        print("    -> Ищи код в сервисном чате «Telegram» внутри приложения Telegram.")
    elif "Sms" in code_type:
        print("    -> Код отправлен по SMS.")

    code = input("Введи код: ").strip()
    try:
        await client.sign_in(phone=phone, code=code)
    except SessionPasswordNeededError:
        pwd = getpass.getpass("Введи облачный пароль Telegram (2FA): ")
        await client.sign_in(password=pwd)


async def cmd_status() -> int:
    cfg = load_config()
    tracks_count = 0
    if TRACKS_PATH.exists():
        try:
            tracks_count = len(json.loads(TRACKS_PATH.read_text(encoding="utf-8")).get("tracks", []))
        except Exception:
            pass

    if not cfg:
        print(json.dumps({
            "configured": False,
            "authorized": False,
            "chat": "Telegram Music",
            "track_count": tracks_count,
        }))
        return 0

    authorized = False
    session_file = Path(f"{SESSION_PATH}.session")
    if session_file.exists():
        client = make_client(cfg)
        try:
            await client.connect()
            authorized = await client.is_user_authorized()
        except Exception:
            authorized = False
        finally:
            await client.disconnect()

    print(json.dumps({
        "configured": True,
        "authorized": authorized,
        "chat": cfg.get("chat", "Telegram Music"),
        "track_count": tracks_count,
    }))
    return 0


async def sync_library(cfg: dict[str, Any], limit: int | None = None, download_thumbs: bool = True) -> dict[str, Any]:
    from telethon.errors import FloodWaitError
    from telethon.tl.types import InputMessagesFilterMusic

    client = make_client(cfg)
    await client.connect()
    try:
        if not await client.is_user_authorized():
            raise RuntimeError("Telegram session is not authorized. Run --setup first.")

        chat_name = str(cfg.get("chat") or "me")
        entity = await resolve_chat_entity(client, chat_name)
        resolved_title = getattr(entity, "title", None) or getattr(entity, "first_name", None) or chat_name

        THUMBS_DIR.mkdir(parents=True, exist_ok=True)
        tracks: list[dict[str, Any]] = []
        pending_thumbs: list[tuple[Any, Path, dict[str, Any]]] = []
        msg_limit = limit if (limit and limit > 0) else None

        async for msg in client.iter_messages(entity, limit=msg_limit, filter=InputMessagesFilterMusic()):
            ok, title, artist, duration, ext = is_audio_message(msg)
            if not ok:
                continue

            thumb_path = THUMBS_DIR / f"{msg.id}.jpg"
            has_thumb = thumb_path.exists() and thumb_path.stat().st_size > 0
            cached_path = find_cached_audio(msg.id)
            item = {
                "id": int(msg.id),
                "title": title,
                "artist": artist,
                "duration": duration,
                "ext": ext,
                "size": int(getattr(msg.document, "size", 0) or 0),
                "date": msg.date.isoformat() if msg.date else "",
                "thumb": str(thumb_path) if has_thumb else "",
                "cached": cached_path is not None,
                "cached_path": str(cached_path) if cached_path else "",
            }
            tracks.append(item)
            if download_thumbs and not has_thumb and getattr(msg.document, "thumbs", None):
                pending_thumbs.append((msg, thumb_path, item))

        if pending_thumbs:
            sem = asyncio.Semaphore(4)
            stop_thumbs = False

            async def _fetch_thumb(m: Any, tp: Path, entry: dict[str, Any]) -> None:
                nonlocal stop_thumbs
                if stop_thumbs:
                    return
                async with sem:
                    if stop_thumbs:
                        return
                    try:
                        out = await client.download_media(m, thumb=-1, file=str(tp))
                        if out and Path(out).exists() and Path(out).stat().st_size > 0:
                            entry["thumb"] = str(tp)
                    except FloodWaitError:
                        stop_thumbs = True
                    except Exception:
                        pass

            await asyncio.gather(*(_fetch_thumb(m, tp, entry) for m, tp, entry in pending_thumbs))

        payload = {
            "chat": resolved_title,
            "count": len(tracks),
            "tracks": tracks,
        }
        atomic_write(TRACKS_PATH, json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
        try:
            from classify_playlists import build_playlists
            build_playlists()
        except Exception:
            pass
        return payload
    finally:
        await client.disconnect()


async def cmd_sync(limit: int | None, no_thumbs: bool) -> int:
    cfg = load_config()
    if not cfg:
        print("Error: Telegram API is not configured. Run --setup first.", file=sys.stderr)
        return 1
    payload = await sync_library(cfg, limit=limit, download_thumbs=not no_thumbs)
    print(json.dumps({"ok": True, "chat": payload["chat"], "count": payload["count"]}))
    return 0


async def cmd_fetch(msg_id: int, show_progress: bool = False) -> int:
    existing = find_cached_audio(msg_id)
    if existing is not None:
        print(str(existing))
        return 0

    cfg = load_config()
    if not cfg:
        print("Error: Telegram API is not configured. Run --setup first.", file=sys.stderr)
        return 1

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    client = make_client(cfg)
    await client.connect()
    part_path: Path | None = None
    try:
        if not await client.is_user_authorized():
            print("Error: Telegram session is not authorized. Run --setup first.", file=sys.stderr)
            return 1

        entity = await resolve_chat_entity(client, str(cfg.get("chat") or "me"))
        msg = await client.get_messages(entity, ids=msg_id)
        if not msg:
            print(f"Error: Message {msg_id} not found.", file=sys.stderr)
            return 1

        ok, _, _, _, ext = is_audio_message(msg)
        if not ok:
            print(f"Error: Message {msg_id} does not contain audio.", file=sys.stderr)
            return 1

        final_path = CACHE_DIR / f"{msg_id}{ext}"
        part_path = CACHE_DIR / f".tmp_{msg_id}_{os.getpid()}{ext}"
        total_hint = int(getattr(msg.document, "size", 0) or 0)
        last_emit = [0.0]
        last_pct = [-1]

        def _on_progress(received: int, total: int) -> None:
            if not show_progress:
                return
            tot = total or total_hint
            pct = int((received * 100) / tot) if tot > 0 else 0
            now = time.monotonic()
            if pct != last_pct[0] or (now - last_emit[0]) >= 0.08 or (tot > 0 and received >= tot):
                last_pct[0] = pct
                last_emit[0] = now
                print(f"PROGRESS {received} {tot}", file=sys.stderr, flush=True)

        await client.download_media(
            msg,
            file=str(part_path),
            progress_callback=_on_progress if show_progress else None,
        )
        if not part_path.exists() or part_path.stat().st_size == 0:
            print(f"Error: Failed to download audio for message {msg_id}.", file=sys.stderr)
            return 1

        os.replace(part_path, final_path)

        # Update cached flag in tracks.json if present
        if TRACKS_PATH.exists():
            try:
                data = json.loads(TRACKS_PATH.read_text(encoding="utf-8"))
                for t in data.get("tracks", []):
                    if t.get("id") == msg_id:
                        t["cached"] = True
                        t["cached_path"] = str(final_path)
                        break
                atomic_write(TRACKS_PATH, json.dumps(data, ensure_ascii=False, indent=2) + "\n")
            except Exception:
                pass

        print(str(final_path))
        return 0
    finally:
        if part_path is not None and part_path.exists():
            try:
                part_path.unlink()
            except OSError:
                pass
        await client.disconnect()


async def cmd_setup(force_qr: bool = False) -> int:
    print("=======================================================")
    print("  Telegram Music Player Setup (Telethon)")
    print("=======================================================")
    print("1. Открой https://my.telegram.org -> API development tools")
    print("2. Создай приложение (Platform: Desktop/Other) и скопируй api_id и api_hash.")
    print("")

    existing = load_config() or {}
    default_id = str(existing.get("api_id", ""))
    default_hash = str(existing.get("api_hash", ""))
    default_chat = str(existing.get("chat", ""))

    raw_id = input(f"api_id [{default_id}]: ").strip() or default_id
    raw_hash = input(f"api_hash [{default_hash[:6] + '...' if default_hash else ''}]: ").strip() or default_hash
    chat = input(f"Чат / канал / бот [{default_chat}]: ").strip() or default_chat

    if not raw_id.isdigit() or not raw_hash:
        print("Ошибка: нужны корректные api_id (число) и api_hash.", file=sys.stderr)
        return 1

    cfg = {
        "api_id": int(raw_id),
        "api_hash": raw_hash,
        "chat": chat,
    }
    atomic_write(CONFIG_PATH, json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", mode=0o600)

    client = make_client(cfg)
    await client.connect()
    try:
        if not await client.is_user_authorized():
            if force_qr:
                method = "1"
            else:
                print("\nСпособ входа:")
                print("  [1] QR-код (рекомендуется — работает без SMS и кодов)")
                print("  [2] Номер телефона + код")
                method = input("Выбор [1]: ").strip() or "1"

            if method == "2":
                await phone_login_flow(client)
            else:
                await qr_login_flow(client)

        me = await client.get_me()
        print(f"\n[✓] Авторизован как: {getattr(me, 'first_name', '')} (@{getattr(me, 'username', '')})")
    finally:
        await client.disconnect()

    print(f"[*] Синхронизирую треки из «{chat}»...")
    payload = await sync_library(cfg, limit=None, download_thumbs=True)
    print(f"[✓] Найдено треков: {payload['count']} (чат: {payload['chat']})")
    print("Готово! Можешь закрыть терминал и нажать на иконку плеера на рабочем столе.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Telegram Music sync & fetcher")
    parser.add_argument("--setup", action="store_true", help="Interactive Telegram API login & initial sync")
    parser.add_argument("--qr", action="store_true", help="Use QR code login directly during --setup")
    parser.add_argument("--sync", action="store_true", help="Refresh track list from Telegram")
    parser.add_argument("--limit", type=int, default=0, help="Max tracks to scan (0 = all, default 0)")
    parser.add_argument("--no-thumbs", action="store_true", help="Skip downloading album thumbnails during sync")
    parser.add_argument("--fetch", type=int, metavar="MSG_ID", help="Ensure audio is downloaded and print path")
    parser.add_argument("--progress", action="store_true", help="Emit PROGRESS lines on stderr during --fetch")
    parser.add_argument("--status", action="store_true", help="Print JSON configuration/auth status")
    args = parser.parse_args()

    if args.setup or args.qr:
        return asyncio.run(cmd_setup(force_qr=args.qr))
    if args.sync:
        return asyncio.run(cmd_sync(args.limit or None, args.no_thumbs))
    if args.fetch is not None:
        return asyncio.run(cmd_fetch(args.fetch, show_progress=args.progress))
    if args.status:
        return asyncio.run(cmd_status())

    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
