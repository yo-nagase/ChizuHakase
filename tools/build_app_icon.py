#!/usr/bin/env python3
"""Renders the 1024x1024 app icon from the same shapes the app draws.

Keeping the icon generated from PrefectureShapes.json means it cannot drift
away from the map inside the app.

    python3 build_app_icon.py
"""

import json
import os

from PIL import Image, ImageDraw

SRC = "../WakuwakuChizu/Resources/PrefectureShapes.json"
DST = "../WakuwakuChizu/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

SIZE = 1024
SUPERSAMPLE = 4  # draw big, downscale: gives clean edges without any AA library

BACKGROUND_TOP = (255, 226, 168)
BACKGROUND_BOTTOM = (255, 247, 232)
LAND = (255, 159, 28)
LAND_EDGE = (255, 255, 255)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, SRC), encoding="utf-8") as fh:
        data = json.load(fh)

    s = SIZE * SUPERSAMPLE
    img = Image.new("RGB", (s, s), BACKGROUND_BOTTOM)
    draw = ImageDraw.Draw(img)

    # Vertical warm gradient
    for y in range(s):
        t = y / s
        draw.line(
            [(0, y), (s, y)],
            fill=tuple(
                int(BACKGROUND_TOP[i] + (BACKGROUND_BOTTOM[i] - BACKGROUND_TOP[i]) * t)
                for i in range(3)
            ),
        )

    # Fit the mainland into the safe area. Okinawa's inset is dropped: at icon
    # size the dashed frame is illegible and the gap just shrinks Honshu.
    prefs = [p for p in data["prefectures"] if p["code"] != 47]
    x0 = min(p["bbox"][0] for p in prefs)
    y0 = min(p["bbox"][1] for p in prefs)
    x1 = max(p["bbox"][2] for p in prefs)
    y1 = max(p["bbox"][3] for p in prefs)

    margin = s * 0.14
    scale = min((s - margin * 2) / (x1 - x0), (s - margin * 2) / (y1 - y0))
    dx = (s - (x1 - x0) * scale) / 2 - x0 * scale
    dy = (s - (y1 - y0) * scale) / 2 - y0 * scale

    for pref in prefs:
        for ring in pref["rings"]:
            pts = [(px * scale + dx, py * scale + dy) for px, py in ring]
            if len(pts) >= 3:
                draw.polygon(pts, fill=LAND, outline=LAND_EDGE, width=SUPERSAMPLE)

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    out = os.path.join(here, DST)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print(f"wrote {os.path.relpath(out, here)} {SIZE}x{SIZE}")


if __name__ == "__main__":
    main()
