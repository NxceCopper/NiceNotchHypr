#!/usr/bin/env python3
"""Wallpaper scanner + thumbnail cache for the quickshell control centre.

Walks the given directories (max depth 3, capped at 300 images) and prints one
JSON record per wallpaper on stdout, then keeps the 640x360 JPEG thumbnail
cache up to date and prints a "ready" record for each thumb it regenerates.

Protocol (one JSON object per line):
  {"path": ..., "thumb": ...}   phase A, list a wallpaper (thumb may be "")
  {"ready": ..., "thumb": ...}  phase B, thumbnail just became available

Scan/thumbnail-hash logic adapted from dynamic-island-hyprland
(c) St0rmosu, MIT — see LICENSE-dynamic-island-hyprland.txt
"""
import hashlib
import json
import os
import subprocess
import sys

CACHE_DIR = sys.argv[1]
DIRS = sys.argv[2:]
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif", ".tiff", ".bmp"}
TW, TH, QUALITY = 640, 360, 86
MAX_FILES = 300


def collect():
    """Sorted image list, find -maxdepth 3 equivalent, capped."""
    found = []
    for d in DIRS:
        d = os.path.expanduser(d)
        if not os.path.isdir(d):
            continue
        for root, subdirs, names in os.walk(d):
            rel = os.path.relpath(root, d)
            depth = 0 if rel == "." else rel.count(os.sep) + 1
            if depth >= 3:
                subdirs[:] = []
                continue
            for name in names:
                if os.path.splitext(name)[1].lower() in EXTS:
                    found.append(os.path.join(root, name))
    return sorted(set(found))[:MAX_FILES]


def thumb_path(path):
    """Cache key includes mtime/size so edits regenerate the thumb."""
    st = os.stat(path)
    key = "{}|{}|{}|{}x{}|q{}".format(
        path, st.st_mtime_ns, st.st_size, TW, TH, QUALITY)
    digest = hashlib.sha1(
        key.encode("utf-8", "surrogateescape")).hexdigest()[:24]
    return os.path.join(CACHE_DIR, "wallpaper-" + digest + ".jpg")


def emit(obj):
    print(json.dumps(obj, separators=(",", ":")), flush=True)


def ensure_thumb(path, dest):
    if os.path.isfile(dest):
        return True
    os.makedirs(CACHE_DIR, exist_ok=True)
    tmp = "{}.tmp.{}.jpg".format(dest, os.getpid())
    try:
        subprocess.run(
            ["magick", path, "-auto-orient",
             "-resize", "{}x{}^".format(TW, TH),
             "-gravity", "center", "-extent", "{}x{}".format(TW, TH),
             "-quality", str(QUALITY), tmp],
            check=True, capture_output=True, timeout=30)
        os.replace(tmp, dest)
        return True
    except Exception:
        try:
            os.remove(tmp)
        except OSError:
            pass
        return False


def main():
    files = collect()
    pending = []
    for path in files:
        try:
            dest = thumb_path(path)
        except OSError:
            emit({"path": path, "thumb": ""})
            continue
        if os.path.isfile(dest):
            emit({"path": path, "thumb": dest})
        else:
            emit({"path": path, "thumb": ""})
            pending.append((path, dest))

    # Phase B: generate the missing thumbs, announce each when ready so the
    # carousel can swap from the full-size image to the cached thumbnail.
    for path, dest in pending:
        if ensure_thumb(path, dest):
            emit({"ready": path, "thumb": dest})


if __name__ == "__main__":
    main()
