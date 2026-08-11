#!/usr/bin/env python3
"""Builds the 1024x1024 app icon from the selected concept artwork.

    python3 build_app_icon.py
"""

import os

from PIL import Image

SRC = "../design/app-icon-concepts/concept-04-pop-03-raised-sticker.png"
DST = "../ChizuHakase/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

SIZE = 1024


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    source = os.path.join(here, SRC)
    with Image.open(source) as artwork:
        if artwork.width != artwork.height:
            raise ValueError(f"app icon source must be square: {artwork.size}")
        img = artwork.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)

    out = os.path.join(here, DST)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, optimize=True)
    print(f"wrote {os.path.relpath(out, here)} {SIZE}x{SIZE}")


if __name__ == "__main__":
    main()
