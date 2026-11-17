#!/usr/bin/env python3
"""Classify Telegram music library tracks into curated playlists."""

import json
import os
import re
import tempfile
import unicodedata
from pathlib import Path
from typing import Any

STATE_DIR = Path.home() / ".config" / "tg_music"
TRACKS_PATH = STATE_DIR / "tracks.json"
PLAYLISTS_PATH = STATE_DIR / "playlists.json"

PLAYLIST_DEFS = [
    {
        "id": "death_metal",
        "name": "Death Metal",
        "icon": "flame.fill",
        "subtitle": "Melodeath • Deathcore • Extreme",
    },
    {
        "id": "gothic",
        "name": "Gothic & Doom",
        "icon": "moon.stars.fill",
        "subtitle": "Gothic • Doom • Darkwave",
    },
    {
        "id": "prog_rock",
        "name": "Prog Rock & Metal",
        "icon": "guitars.fill",
        "subtitle": "Prog • Power • Heavy & Alt",
    },
    {
        "id": "phonk",
        "name": "Phonk & Hardtekk",
        "icon": "bolt.fill",
        "subtitle": "Phonk • Funk • Hardtekk",
    },
    {
        "id": "anime_ost",
        "name": "Anime & Game OST",
        "icon": "sparkles",
        "subtitle": "Anime OST • Games • Covers",
    },
    {
        "id": "other",
        "name": "Other",
        "icon": "music.note.list",
        "subtitle": "Electronic • Misc • Remixes",
    },
]

# Rules checked in priority order so band names inside AMV uploads or slowed edits
# go to the actual genre rather than getting misclassified as anime/phonk.

DEATH_METAL_KEYWORDS = [
    "insomnium", "arch enemy", "wintersun", "amon amarth", "dark tranquillity",
    "be'lakor", "belakor", "amorphis", "in flames", "edge of sanity",
    "gates of ishtar", "disinterment", "ceremonium", "shylmagoghnar",
    "lorna shore", "thy art is murder", "make them suffer", "makethemsuffer",
    "as i lay dying", "the unguided", "unguided", "aeternus", "sylosis",
    "trivium", "currents", "imperial circus dead decadence", "ad nauseam",
    "grenadier", "ensiferum", "deathcore", "melodeath", "бездна анального угнетения",
    "semargl", "misstiq",
]

GOTHIC_DOOM_KEYWORDS = [
    "draconian", "theatre of tragedy", "darkher", "candlemass", "mortal love",
    "alcest", "agalloch", "empyrium", "frayle", "within temptation",
    "evanescence", "bring me to life", "nightwish", "the birthday massacre", "the lust",
    "kmfdm", "cold in may", "mental discipline", "sangre de muerdago",
    "twin tribes", "pastel ghost", "pastel ghos", "him – join me", "him - join me",
    "ghost angel", "unlucky morpheus", "gothic", "dark classical academia",
    "antlers", "invadable harmony", "vessel - red sex", "red sex",
]

PROG_POWER_ROCK_KEYWORDS = [
    "opeth", "ne obliviscaris", "tool", "king crimson - epitaph",
    "king crimson - the court", "king crimson", "edguy", "rhapsody of fire",
    "rhapsody", "luca turilli", "stratovarius", "galneryus", "holyhell",
    "helloween", "hammerfall", "iced earth", "iron maiden", "dream evil",
    "firewind", "primal fear", "alter bridge", "pantera", "metallica",
    "exodus", "machine head", "slipknot", "disturbed", "system of a down",
    "system of down", "deftones", "breaking benjamin", "chevelle",
    "shinedown", "soundgarden", "audioslave", "nirvana", "radiohead",
    "rammstein", "linkin park", "in the end", "seether", "rise against", "three days grace",
    "drowning pool", "crossfade", "hurt - topic", "hurt ", "red - topic",
    "red - breathe", "paramore", "guns n' roses", "gunsnroses", "scorpions",
    "skid row", "ac/dc", "ozzy osbourne", "black label society", "zakk wylde",
    "demon hunter", "avenged sevenfold", "while she sleeps", "bring me the horizon",
    "asking alexandria", "bullet for my valentine", "bulletvalentine",
    "limp bizkit", "sum 41", "better than ezra", "parkwood", "silver end",
    "fun mode", "sektor gaza", "сектор газа", "ария", "aria - topic",
    "электрослабость", "nautilus pompilius", "би-2", "билборды", "creed",
    "breaking point", "trust company", "trustcompany", "papercut massacre",
    "our last night", "cult to follow", "autopilot off", "alien ant farm",
    "for all those sleeping", "i see stars", "thousand foot krutch",
    "decyfer down", "ghost atlas", "haji's kitchen", "gravity pool",
    "widek", "fraxriel", "for the taking", "late night savior",
    "martin kesici", "meytal", "fades away", "avril lavigne",
    "w.a.s.p.", "rock privet", "alex terrible", "first to eleven",
    "smells like teen spirit", "runnin' down a dream", "blsofficial",
    "white comic", "paul udarov", "dreamstate feat. elize", "elize ryd",
    "heavy metal instrumental", "dexter and the moonrocks",
    "skars", "neon blade [rock version]", "rock version", "rock in hd",
    "s.o.d. stormtroopers of death", "sturm", "haughty", "my first story",
    "amaranthe", "frog leap", "through fire", "cold - topic", "prophecy of light",
    "sundazer", "sven karlsson", "violent vira", "vira - topic", "vira — god complex", "god complex",
    "toismic", "bon jovi", "three da", "duel in the mist", "[metal",
]

PHONK_HARDTEKK_KEYWORDS = [
    "phonk", "funk", "montagem", "automotivo", "hardtekk", "hardstyle",
    "hardstylish", "kordhell", "shadxwbxrn", "eternxlkz", "dudeplaya",
    "dj anemia", "dj fku", "hensonn", "onimxru", "ogryzek", "vøj", "voj",
    "narvent", "akiaura", "lonown", "ilyhiryu", "lagoyo", "eiby",
    "lumisoun", "nxxkz", "vukeine", "isq", "mupp", "$uicideboy$",
    "night lovell", "shahmen", "skorn", "miguel angeles", "sxrvvani",
    "plenka", "vlcnrsh", "kxrd", "stakillaz", "krezus", "by!nurs",
    "chuddnelius", "craspore", "kute", "udiennx", "drollxd", "smashed",
    "sma$her", "bxkq", "luz roja", "tuca donka", "cursedevil", "death is no more",
    "memory reboot", "sleepwalker", "icewhore", "murder in my", "sahara",
    "dark aura", "red aura", "light aura", "hell aura", "remnant aura",
    "remnant funk", "pulsebreaker", "pulse breaker", "villain tekk",
    "tekkmaxx", "decapi", "mxteng", "slxughter", "jumpstorm", "jumpstyle",
    "tundramane", "omenxiii", "svlient", "y1kmtx", "vapad", "mshtcore",
    "chey", "kyszenn", "moestro", "tron austin", "zrxio", "chxpped",
    "murflauer", "rweloac", "4cyzon", "6skii", "andonis", "beneath my shade",
    "decapitekk", "torturertekk", "aura", "monolith", "acelerada", "vai sentar",
    "malvado", "templar", "arcturus", "al1en_jump", "hypnotic", "static",
    "dr4in", "smezir", "bevlynous", "grok", "gano", "upast", "factrum",
    "nefer", "fartania", "slaughter", "killaz", "master skills", "siren",
    "cry wolf", "neon blade", "scraizis", "turning maniax",
    "we go jim", "seikatsu", "ichiro", "otvphonk", "euphxria", "lxminal",
    "godlike", "bibi phonk", "clandestina", "diedlonely", "énoume", "antent",
    "øneheart", "oneheart", "xxxtentacion", "yeat", "triple6og", "hoodtrap",
    "fangs", "saibotaje", "dionnysuss", "elven dior", "pomoc", "bones -",
    "voce na mira", "slowed", "slow ", "hardst", "tekk", "volt vision", "krushed",
    "cold gaze", "velora", "lxaws", "lxews", "shadow dance", "senhor das trevas",
    "mtg ", "nakama", "strlght", "taktstörer", "schneeschieber", "planeta desconhecido",
    "torturertek", "himxn", "l.p. rhythm", "versatile",
]

ANIME_GAME_KEYWORDS = [
    "yuki kajiura", "梶浦由記", "keita haga", "hiroyuki sawano", "kohta yamamoto",
    "fate", "fgo", "saber alter", "morgan's theme", "goetia", "u-olga", "archer - absolute",
    "jujutsu kaisen", "gojo", "sukuna", "mahoraga", "itadori",
    "dragon ball", "dragonball", "dbz", "goku", "vegeta", "gohan", "broly", "frieza",
    "faulconer", "friedrich habetler", "saiyan enigma", "paul owen", "i.o.n", "i o n",
    "bleach", "aizen", "treachery", "kenpachi", "unohana",
    "naruto", "sasuke", "madara", "mugen tsukuyomi", "itachi", "reaper death seal",
    "jojo", "jjba", "yoshikage kira", "diavolo", "golden wind", "giorno",
    "time skip", "jesus christus",
    "attack on titan", "shingeki", "overlord", "fairy tail", "mirajane",
    "guilty crown", "death note", "eighty-six", "claymore", "черный мечник", "guts",
    "elden ring", "malenia", "mohg", "godfrey", "godskin", "tsukasa saitoh",
    "shoi miyazawa", "tai tomisawa", "may chaos take the world",
    "doom", "mick gordon", "andrew hulshult", "at doom",
    "c418", "minecraft", "aria math", "terraria", "kirbyrocket", "richaadeb",
    "kamakeen", "aaron daniel", "cyberpunk 2077", "p.t. adamczyk", "rebel path",
    "metal gear rising", "a stranger i remain", "shadow fight", "buckshot roulette",
    "genshin", "hoyo-mix", "ronova", "rwby", "falkkone", "samuel kim",
    "vincent moretto", "celestial fury", "antti martikainen", "veigar margeirsson",
    "thomas bergersen", "legio symphonica", "stalker ost", "shadow of chernobyl",
    "anime", "amv", "mmv", "nightcore", "ost", "soundtrack", "boss",
    "chikoi the maid", "butter-fly", "dimrain47", "speed of light", "sakupen",
    "tragicfx", "crystilo music", "mosh bits", "질풍가도", "goukisan", "betrayal of f",
    "the war still rages", "fire inside", "thunderclap", "demon hunte",
]


def classify_track(track: dict[str, Any]) -> str:
    artist = unicodedata.normalize("NFKC", (track.get("artist") or "")).strip().lower()
    title = unicodedata.normalize("NFKC", (track.get("title") or "")).strip().lower()
    text = f"{artist} — {title}"

    # 1. Special disambiguations:
    # JoJo King Crimson memes/edits belong to anime_ost, while actual King Crimson prog goes to prog_rock
    if "king crimson" in text and any(w in text for w in ("jjba", "diavolo", "giorno", "time skip", "edit", "sound effect", "jojo")):
        return "anime_ost"
    if "metallica" in text and "slowed" not in text and "phonk" not in text:
        return "prog_rock"

    # 2. Death / Extreme Metal (takes priority over Silence AMV channel or slowed edits)
    if any(k in text for k in DEATH_METAL_KEYWORDS):
        return "death_metal"

    # 3. Gothic / Doom / Darkwave
    if any(k in text for k in GOTHIC_DOOM_KEYWORDS):
        return "gothic"

    # 4. Prog / Power / Heavy / Alt Metal & Rock
    if any(k in text for k in PROG_POWER_ROCK_KEYWORDS):
        return "prog_rock"

    # 5. Phonk / Hardtekk / Funk / Slowed Dark Edits
    if any(k in text for k in PHONK_HARDTEKK_KEYWORDS):
        return "phonk"
    if any(w in text for w in ("ultra slowed", "super slowed", "slowed + reverb", "slowed & reverb")):
        return "phonk"

    # 6. Anime & Game OST / Covers / Nightcore
    if any(k in text for k in ANIME_GAME_KEYWORDS):
        return "anime_ost"

    # 7. Everything else
    return "other"


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".tgmusic_pl_", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp_name, path)
    except Exception:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)
        raise


def build_playlists() -> dict[str, Any]:
    if not TRACKS_PATH.exists():
        return {"playlists": []}

    lib = json.loads(TRACKS_PATH.read_text(encoding="utf-8"))
    tracks = lib.get("tracks", [])

    # Preserve optional manual overrides if present
    manual_overrides: dict[int, str] = {}
    if PLAYLISTS_PATH.exists():
        try:
            old = json.loads(PLAYLISTS_PATH.read_text(encoding="utf-8"))
            for tid_str, pid in (old.get("overrides") or {}).items():
                manual_overrides[int(tid_str)] = str(pid)
        except Exception:
            pass

    buckets: dict[str, list[int]] = {p["id"]: [] for p in PLAYLIST_DEFS}
    for t in tracks:
        tid = int(t["id"])
        pid = manual_overrides.get(tid) or classify_track(t)
        if pid not in buckets:
            pid = "other"
        buckets[pid].append(tid)

    playlists = []
    for pdef in PLAYLIST_DEFS:
        playlists.append({
            "id": pdef["id"],
            "name": pdef["name"],
            "icon": pdef["icon"],
            "subtitle": pdef["subtitle"],
            "track_ids": buckets[pdef["id"]],
        })

    payload: dict[str, Any] = {"playlists": playlists}
    if manual_overrides:
        payload["overrides"] = {str(k): v for k, v in manual_overrides.items()}

    atomic_write(PLAYLISTS_PATH, json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    return payload


if __name__ == "__main__":
    res = build_playlists()
    for p in res.get("playlists", []):
        print(f"{p['name']:20s}: {len(p['track_ids'])} tracks")
