#!/usr/bin/env python3
"""Pick a Material 3 accent colour from a wallpaper.

Real Material You pipeline — Google's Material Color Utilities (the same
HCT/CAM16 science matugen uses): Celebi-quantize a downscaled copy, score
the prominent colours (chroma-weighted, so vivid content wins instead of
averaging into mud), and read the accent out of the generated dark
Material 3 scheme. Near-grayscale imagery falls back to the most popular
in-range colour, so a black-and-white wallpaper yields a neutral accent
instead of an unrelated default.

Runs inside its own venv (~/.local/share/quickshell-mcu).
"""
import os
import sys
import warnings

VENV = os.path.expanduser("~/.local/share/quickshell-mcu")
VENV_PY = os.path.join(VENV, "bin", "python")
if sys.prefix != VENV and os.path.exists(VENV_PY):
    os.execv(VENV_PY, [VENV_PY] + sys.argv)

from PIL import Image

from material_color_utilities_python.quantize.quantizer_celebi import QuantizerCelebi
from material_color_utilities_python.score.score import Score
from material_color_utilities_python.scheme.scheme import Scheme
from material_color_utilities_python.utils.theme_utils import Hct, hexFromArgb

# This port's stock cutoff (15) discards everything on muted wallpapers —
# a desert photo scored zero and fell back to Google blue. 5 keeps gentle
# hues while still excluding true grays.
Score.CUTOFF_CHROMA = 5.0


def accent_from(path):
    img = Image.open(path).convert("RGB")
    img.thumbnail((112, 112))
    with warnings.catch_warnings():
        # Pillow 12 deprecates getdata; get_flattened_data is 12+ only.
        warnings.simplefilter("ignore", DeprecationWarning)
        raw = list(img.getdata())
    pixels = [(0xFF << 24) | (r << 16) | (g << 8) | b for r, g, b in raw]
    quantized = QuantizerCelebi.quantize(pixels, 128)

    best = Score.score(quantized)
    if best:
        seed = best[0]
    else:
        # Near-grayscale image: most popular colour with a usable tone, so
        # the accent goes neutral instead of defaulting to blue.
        ranked = sorted(quantized.items(), key=lambda kv: -kv[1])
        seed = next((c for c, n in ranked
                     if 25 <= Hct.fromInt(c).tone <= 85), None)
        if seed is None:
            return None

    # Dark-scheme primary: the canonical Material 3 accent role.
    return hexFromArgb(Scheme.dark(seed).primary).lower()


def main():
    if len(sys.argv) != 2:
        return 1
    try:
        accent = accent_from(sys.argv[1])
    except Exception:
        return 1
    if not accent:
        return 1
    print(accent)
    return 0


if __name__ == "__main__":
    sys.exit(main())
