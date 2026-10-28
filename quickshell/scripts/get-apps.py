#!/usr/bin/env python3
"""Scan .desktop entries for the app launcher.

Prints a JSON array of {name, exec, icon, terminal} to stdout and mirrors it
to ~/.cache/quickshell_apps.json so LauncherPanel has a list before the first
scan finishes. Ported for the quickshell config (dynamic-island-hyprland used
a personal ~/.scripts/get-apps.py).
"""
import json
import os
import re
import sys
from pathlib import Path

CACHE = Path(os.path.expanduser("~/.cache/quickshell_apps.json"))
# Desktop-entry Exec field codes to strip (%f, %u, %i, ...)
FIELD_CODES = re.compile(r"\s*%[fFuUdDnNickvmt]")

ESCAPES = {"\\s": " ", "\\n": "\n", "\\t": "\t", "\\\\": "\\", "\\r": "\r"}


def unescape(value):
    for src, dst in ESCAPES.items():
        value = value.replace(src, dst)
    return value


def parse_desktop(path):
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    entry = {}
    section = None
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            section = line.strip("[]")
            continue
        if section != "Desktop Entry" or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = unescape(value.strip())
        if key == "Type":
            entry["type"] = value
        elif key == "Name":
            entry.setdefault("name", value)
        elif key == "Exec":
            entry.setdefault("exec", FIELD_CODES.sub("", value).strip())
        elif key == "Icon":
            entry.setdefault("icon", value)
        elif key == "Terminal":
            entry["terminal"] = value.lower() == "true"
        elif key in ("Hidden", "NoDisplay"):
            if value.lower() == "true":
                entry["hidden"] = True
    return entry


def main():
    apps = []
    seen = {}
    data_home = Path(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"))
    data_dirs = [
        data_home / "applications",
        *(Path(d) / "applications" for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")),
    ]

    for base in data_dirs:
        if not base.is_dir():
            continue
        # Later dirs are higher priority; process in reverse and keep first wins
        for file in sorted(base.rglob("*.desktop")):
            entry = parse_desktop(file)
            if not entry or entry.get("hidden") or entry.get("type", "Application") != "Application":
                continue
            if not entry.get("name") or not entry.get("exec"):
                continue
            app_id = file.stem
            if app_id in seen:
                continue
            seen[app_id] = True
            apps.append({
                "name": entry["name"],
                "exec": entry["exec"],
                "icon": entry.get("icon", ""),
                "terminal": bool(entry.get("terminal")),
            })

    apps.sort(key=lambda app: app["name"].lower())
    payload = json.dumps(apps, ensure_ascii=False)
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(payload, encoding="utf-8")
    except OSError as error:
        print(f"[get-apps] cache write failed: {error}", file=sys.stderr)
    print(payload)


if __name__ == "__main__":
    main()
