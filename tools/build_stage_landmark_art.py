#!/usr/bin/env python3
"""Build generated stage-selection landmark stamps.

The 1254px painted originals live in ``assets/stage-landmarks`` and are kept
through Git LFS.  This script produces the 384px, palette-reduced 1x assets
that ship in ``StageSelectArt``.  The explicit source-to-asset tables are also
the contract used by ``Stage.landmarkAssetNames`` and
``WorldStage.landmarkAssetNames``: never infer a region from a filename or a
stage number.

Run from the repository root whenever an original changes:

    python3 tools/build_stage_landmark_art.py
"""

from __future__ import annotations

import json
import os

from PIL import Image


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, "assets", "stage-landmarks")
CATALOG = os.path.join(
    ROOT, "ChizuHakase", "Resources", "Assets.xcassets", "StageSelectArt"
)

SIZE = 384
PALETTE_COLOURS = 192

# Source slug -> asset name for japan stamps replaced after the original seven
# were drawn. The other six still use their existing catalog-only art.
JAPAN_REPLACEMENTS = [
    ("japan-stage-00-ezo-red-fox", "stage-icon-ezo-red-fox"),
]

# Source slug -> asset name, in WorldStage index order (0...18). The last entry
# belongs to the world challenge rather than a regional data stage.
WORLD_LANDMARKS = [
    ("world-stage-00-monarch-butterfly", "stage-icon-world-north-central-america"),
    ("world-stage-01-caribbean-island", "stage-icon-world-caribbean"),
    ("world-stage-02-llama", "stage-icon-world-south-america"),
    ("world-stage-03-aurora", "stage-icon-world-north-europe"),
    ("world-stage-04-half-timbered-house", "stage-icon-world-west-europe"),
    ("world-stage-05-white-stork", "stage-icon-world-east-europe"),
    ("world-stage-06-olive-branch", "stage-icon-world-south-europe"),
    ("world-stage-07-oasis", "stage-icon-world-north-africa"),
    ("world-stage-08-baobab", "stage-icon-world-west-africa"),
    ("world-stage-09-okapi", "stage-icon-world-central-africa"),
    ("world-stage-10-acacia-giraffe", "stage-icon-world-east-africa"),
    ("world-stage-11-gemsbok", "stage-icon-world-south-africa"),
    ("world-stage-12-arabian-oryx", "stage-icon-world-west-asia"),
    ("world-stage-13-yurt", "stage-icon-world-central-asia"),
    ("world-stage-14-indian-elephant", "stage-icon-world-south-asia"),
    ("world-stage-15-red-crowned-crane", "stage-icon-world-east-asia"),
    ("world-stage-16-hornbill", "stage-icon-world-southeast-asia"),
    ("world-stage-17-outrigger-canoe", "stage-icon-world-oceania"),
    ("world-stage-18-world-globe", "stage-icon-world-challenge"),
]


def build_imageset(source_slug: str, asset_name: str) -> int:
    source = os.path.join(SOURCE_DIR, f"{source_slug}-transparent.png")
    if not os.path.isfile(source):
        raise SystemExit(f"missing landmark original: {source}")

    with Image.open(source) as opened:
        image = opened.convert("RGBA")
    if image.width != image.height:
        raise SystemExit(f"{source_slug}: expected square art, got {image.size}")
    if image.getextrema()[3][0] != 0:
        raise SystemExit(f"{source_slug}: expected a transparent background")

    resized = image.resize((SIZE, SIZE), Image.LANCZOS)
    reduced = resized.quantize(colors=PALETTE_COLOURS, method=Image.FASTOCTREE)

    folder = os.path.join(CATALOG, f"{asset_name}.imageset")
    os.makedirs(folder, exist_ok=True)
    filename = f"{asset_name}.png"
    output = os.path.join(folder, filename)

    should_write = True
    if os.path.isfile(output):
        with Image.open(output) as existing:
            should_write = (
                existing.size != reduced.size
                or existing.convert("RGBA").tobytes()
                != reduced.convert("RGBA").tobytes()
            )
    if should_write:
        reduced.save(output, optimize=True)

    contents = {
        "images": [
            {"filename": filename, "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(folder, "Contents.json"), "w") as file:
        json.dump(contents, file, ensure_ascii=False, indent=2)
        file.write("\n")

    return os.path.getsize(output)


def main() -> None:
    if len(WORLD_LANDMARKS) != 19:
        raise SystemExit(
            f"expected 19 world landmarks, got {len(WORLD_LANDMARKS)}"
        )
    landmarks = JAPAN_REPLACEMENTS + WORLD_LANDMARKS
    if len({asset for _, asset in landmarks}) != len(landmarks):
        raise SystemExit("duplicate landmark asset name")

    total = sum(build_imageset(source, asset) for source, asset in landmarks)
    print(f"built {len(landmarks)} stage landmarks ({total // 1024} KB total)")


if __name__ == "__main__":
    main()
