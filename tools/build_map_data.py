#!/usr/bin/env python3
"""GeoJSON -> PrefectureShapes.json (see CLAUDE.md sec.3).

Reads japan_simplified.geojson (mapshaper output) and emits the app's map
resource: screen-space coordinates, top-left origin, y pointing down, width
normalised to 1000.

Run from tools/:
    python3 build_map_data.py
"""

from __future__ import annotations

import heapq
import json
import math
import os
import sys

SRC = "japan_simplified.geojson"
DST = "PrefectureShapes.json"

# Equirectangular projection with a standard parallel through central Honshu.
# Cheap, and over Japan's ~14 deg of latitude the shape error is far below what
# a 5-year-old tapping a prefecture could notice. A conformal projection would
# buy nothing here and would make the coordinates harder to reason about.
LAT0 = 37.0

# --- Island filtering -------------------------------------------------------
# The raw data is geographically complete, which is wrong for this app:
# Tokyo reaches lat 24.75 (Ogasawara) and Okinawa spans 122.9-131.3 deg lon
# (Yonaguni to Daito). Drawn as-is, real prefectures shrink to specks to make
# room for ocean, and the outlying islands are far too small to tap anyway.
# Two neutral rules, applied identically to every prefecture:
MIN_RING_AREA_RATIO = 0.015  # keep rings >= 1.5% of the prefecture's largest
MAX_RING_GAP_DEG = 1.0       # ...and within ~110km of its largest ring's bbox

# Okinawa is moved into an inset box south-west of Kyushu and enlarged, the
# convention every Japanese school map uses. Without this it sits alone in open
# ocean and pushes the rest of the country into the top-right corner.
OKINAWA_CODE = 47
OKINAWA_SCALE = 1.6

OUT_WIDTH = 1000.0
COORD_DECIMALS = 1  # 0.1 / 1000 = 0.01% of map width; well under one pixel

KANA = {
    1: "ほっかいどう", 2: "あおもりけん", 3: "いわてけん", 4: "みやぎけん",
    5: "あきたけん", 6: "やまがたけん", 7: "ふくしまけん", 8: "いばらきけん",
    9: "とちぎけん", 10: "ぐんまけん", 11: "さいたまけん", 12: "ちばけん",
    13: "とうきょうと", 14: "かながわけん", 15: "にいがたけん", 16: "とやまけん",
    17: "いしかわけん", 18: "ふくいけん", 19: "やまなしけん", 20: "ながのけん",
    21: "ぎふけん", 22: "しずおかけん", 23: "あいちけん", 24: "みえけん",
    25: "しがけん", 26: "きょうとふ", 27: "おおさかふ", 28: "ひょうごけん",
    29: "ならけん", 30: "わかやまけん", 31: "とっとりけん", 32: "しまねけん",
    33: "おかやまけん", 34: "ひろしまけん", 35: "やまぐちけん", 36: "とくしまけん",
    37: "かがわけん", 38: "えひめけん", 39: "こうちけん", 40: "ふくおかけん",
    41: "さがけん", 42: "ながさきけん", 43: "くまもとけん", 44: "おおいたけん",
    45: "みやざきけん", 46: "かごしまけん", 47: "おきなわけん",
}


# --- geometry helpers -------------------------------------------------------

def ring_area(ring):
    """Unsigned shoelace area."""
    s = 0.0
    for i in range(len(ring) - 1):
        x1, y1 = ring[i]
        x2, y2 = ring[i + 1]
        s += x1 * y2 - x2 * y1
    return abs(s) * 0.5


def bbox_of(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return [min(xs), min(ys), max(xs), max(ys)]


def bbox_gap(a, b):
    """Shortest distance between two axis-aligned bboxes (0 if they overlap)."""
    dx = max(a[0] - b[2], b[0] - a[2], 0.0)
    dy = max(a[1] - b[3], b[1] - a[3], 0.0)
    return math.hypot(dx, dy)


def point_in_rings(px, py, rings):
    """Even-odd containment, matching Path.contains(_:eoFill: true) on iOS."""
    inside = False
    for ring in rings:
        for i in range(len(ring) - 1):
            x1, y1 = ring[i]
            x2, y2 = ring[i + 1]
            if (y1 > py) != (y2 > py):
                t = (py - y1) / (y2 - y1)
                if px < x1 + t * (x2 - x1):
                    inside = not inside
    return inside


def dist_to_segment_sq(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    if dx == 0.0 and dy == 0.0:
        return (px - x1) ** 2 + (py - y1) ** 2
    t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    ox, oy = x1 + t * dx, y1 + t * dy
    return (px - ox) ** 2 + (py - oy) ** 2


def signed_distance(px, py, rings):
    """Distance to the nearest edge; positive inside, negative outside."""
    best = float("inf")
    for ring in rings:
        for i in range(len(ring) - 1):
            best = min(best, dist_to_segment_sq(px, py, *ring[i], *ring[i + 1]))
    d = math.sqrt(best)
    return d if point_in_rings(px, py, rings) else -d


def pole_of_inaccessibility(rings, precision_ratio=0.002):
    """Interior point furthest from any edge (Mapbox polylabel, quadtree form).

    The area centroid is not usable as a label anchor here: it falls in the sea
    for curved prefectures like Kyoto and outside the landmass entirely for
    multi-island ones like Nagasaki. CLAUDE.md sec.10 requires
    contains(centroid) to hold for all 47, so this has to be a guaranteed
    interior point, not an average.
    """
    x0, y0, x1, y1 = bbox_of([p for r in rings for p in r])
    w, h = x1 - x0, y1 - y0
    cell = min(w, h)
    if cell == 0:
        return (x0, y0)

    precision = max(w, h) * precision_ratio
    half = cell / 2.0

    # max() potential of a cell: centre distance + half its diagonal
    def potential(cx, cy, hh):
        return signed_distance(cx, cy, rings) + hh * math.sqrt(2)

    queue = []
    counter = 0
    best_x = x0 + w / 2.0
    best_y = y0 + h / 2.0
    best_d = signed_distance(best_x, best_y, rings)

    cy = y0 + half
    while cy < y1 + half:
        cx = x0 + half
        while cx < x1 + half:
            d = signed_distance(cx, cy, rings)
            if d > best_d:
                best_d, best_x, best_y = d, cx, cy
            heapq.heappush(queue, (-(d + half * math.sqrt(2)), counter, cx, cy, half))
            counter += 1
            cx += cell
        cy += cell

    while queue:
        neg_pot, _, cx, cy, hh = heapq.heappop(queue)
        if -neg_pot - best_d <= precision:
            break
        hh /= 2.0
        for ox, oy in ((-hh, -hh), (hh, -hh), (-hh, hh), (hh, hh)):
            nx, ny = cx + ox, cy + oy
            d = signed_distance(nx, ny, rings)
            if d > best_d:
                best_d, best_x, best_y = d, nx, ny
            heapq.heappush(queue, (-potential(nx, ny, hh), counter, nx, ny, hh))
            counter += 1

    return (best_x, best_y)


# --- pipeline ---------------------------------------------------------------

def load_features(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    out = {}
    for feat in data["features"]:
        props = feat["properties"]
        geom = feat["geometry"]
        polys = (geom["coordinates"] if geom["type"] == "MultiPolygon"
                 else [geom["coordinates"]])
        rings = []
        for poly in polys:
            for ring in poly:
                # GeoJSON rings are already closed; keep that invariant so the
                # shoelace and crossing tests stay simple.
                r = [(float(x), float(y)) for x, y in ring]
                if r[0] != r[-1]:
                    r.append(r[0])
                if len(r) >= 4:
                    rings.append(r)
        out[int(props["id"])] = {"name": props["nam_ja"], "rings": rings}
    return out


def filter_rings(rings):
    """Drop specks and far-flung archipelagos (see MIN_RING_AREA_RATIO)."""
    scored = sorted(((ring_area(r), r) for r in rings), key=lambda t: -t[0])
    main_area, main_ring = scored[0]
    main_bbox = bbox_of(main_ring)
    kept = [main_ring]
    for area, ring in scored[1:]:
        if area < main_area * MIN_RING_AREA_RATIO:
            continue
        if bbox_gap(bbox_of(ring), main_bbox) > MAX_RING_GAP_DEG:
            continue
        kept.append(ring)
    return kept


def project(rings):
    """lon/lat -> planar, y already flipped so it grows downward like SwiftUI."""
    k = math.cos(math.radians(LAT0))
    return [[(lon * k, -lat) for lon, lat in ring] for ring in rings]


def transform_rings(rings, sx, sy, tx, ty):
    return [[(x * sx + tx, y * sy + ty) for x, y in ring] for ring in rings]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    src = os.path.join(here, SRC)
    if not os.path.exists(src):
        sys.exit(f"missing {SRC} - run the mapshaper step first (CLAUDE.md sec.3)")

    feats = load_features(src)
    missing = sorted(set(range(1, 48)) - set(feats))
    if missing:
        sys.exit(f"source is missing prefecture codes: {missing}")

    shapes = {}
    dropped = 0
    for code, feat in feats.items():
        before = len(feat["rings"])
        kept = filter_rings(feat["rings"])
        dropped += before - len(kept)
        shapes[code] = {"name": feat["name"], "rings": project(kept)}

    # Lay out the mainland first, then drop Okinawa into empty sea so the inset
    # never overlaps a real prefecture.
    main_pts = [p for c, s in shapes.items() if c != OKINAWA_CODE
                for r in s["rings"] for p in r]
    mx0, my0, mx1, my1 = bbox_of(main_pts)
    main_w, main_h = mx1 - mx0, my1 - my0

    ok_rings = shapes[OKINAWA_CODE]["rings"]
    ox0, oy0, ox1, oy1 = bbox_of([p for r in ok_rings for p in r])
    ok_w, ok_h = (ox1 - ox0) * OKINAWA_SCALE, (oy1 - oy0) * OKINAWA_SCALE

    # The inset has to satisfy two things at once.
    #
    # It must sit *inside* the mainland's own box. Parked south-west of Kyushu —
    # where Okinawa actually is — it pushed the map 14% wider than the mainland
    # needs, and since 全国チャレンジ scales the whole country to fit a phone's
    # width, every prefecture was drawn 14% smaller to make room for a box
    # floating in empty water.
    #
    # It must also stay near Kyushu. Moving it to the empty north-west corner
    # fixed the width and broke the 九州・沖縄 stage instead: that stage fits
    # only its own prefectures, so Okinawa at one end and Kyushu at the other
    # turned the map into a tall sliver with the sea in between.
    #
    # The Pacific south-east of Kyushu is the one place that does both. Found by
    # scanning rather than hand-placed, so a change upstream in the
    # simplification cannot silently drop it on top of Shikoku.
    ipad_pre = main_h * 0.012
    step = main_w * 0.005
    band_y0 = my1 - ok_h - ipad_pre
    others = {c: bbox_of([p for r in s["rings"] for p in r])
              for c, s in shapes.items() if c != OKINAWA_CODE}

    def free_at(x0: float, y0: float) -> bool:
        rect = (x0 - ipad_pre, y0 - ipad_pre,
                x0 + ok_w + ipad_pre, y0 + ok_h + ipad_pre)
        if rect[0] < mx0 or rect[2] > mx1 or rect[1] < my0 or rect[3] > my1:
            return False
        return not any(b[0] < rect[2] and b[2] > rect[0]
                       and b[1] < rect[3] and b[3] > rect[1]
                       for b in others.values())

    target = next((x for x in (mx0 + i * step
                               for i in range(int((mx1 - mx0) / step)))
                   if free_at(x, band_y0)), None)
    if target is None:
        raise SystemExit("no free water south-east of Kyushu for the Okinawa inset")

    shapes[OKINAWA_CODE]["rings"] = transform_rings(
        ok_rings, OKINAWA_SCALE, OKINAWA_SCALE,
        target - ox0 * OKINAWA_SCALE,
        band_y0 - oy0 * OKINAWA_SCALE,
    )

    # The dashed inset frame is part of the map's extent, so it has to be in
    # the bbox before normalising - otherwise the frame lands outside 0...1000
    # and clips against the edge of the view.
    ipad = main_h * 0.012
    ok_bb = bbox_of([p for r in shapes[OKINAWA_CODE]["rings"] for p in r])
    inset_rect = [ok_bb[0] - ipad, ok_bb[1] - ipad,
                  ok_bb[2] + ipad, ok_bb[3] + ipad]

    # The corner is only free if nothing is standing in it. Checked rather than
    # assumed: an inset overlapping Honshu would be unreadable, and the
    # simplification step upstream can move a coastline.
    for code, s in shapes.items():
        if code == OKINAWA_CODE:
            continue
        bx0, by0, bx1, by1 = bbox_of([p for r in s["rings"] for p in r])
        if (bx0 < inset_rect[2] and bx1 > inset_rect[0]
                and by0 < inset_rect[3] and by1 > inset_rect[1]):
            raise SystemExit(
                f"okinawa inset {inset_rect} overlaps {s['name']} "
                f"[{bx0:.1f},{by0:.1f},{bx1:.1f},{by1:.1f}]")

    # Normalise the whole assembly to width OUT_WIDTH, origin at (0, 0).
    all_pts = [p for s in shapes.values() for r in s["rings"] for p in r]
    all_pts += [(inset_rect[0], inset_rect[1]), (inset_rect[2], inset_rect[3])]
    gx0, gy0, gx1, gy1 = bbox_of(all_pts)
    scale = OUT_WIDTH / (gx1 - gx0)
    map_h = (gy1 - gy0) * scale
    for s in shapes.values():
        s["rings"] = transform_rings(s["rings"], scale, scale,
                                     -gx0 * scale, -gy0 * scale)
    inset = [round((inset_rect[0] - gx0) * scale, COORD_DECIMALS),
             round((inset_rect[1] - gy0) * scale, COORD_DECIMALS),
             round((inset_rect[2] - gx0) * scale, COORD_DECIMALS),
             round((inset_rect[3] - gy0) * scale, COORD_DECIMALS)]

    prefectures = []
    total_pts = 0
    for code in range(1, 48):
        s = shapes[code]
        rings = s["rings"]
        # Largest ring first: the app draws and labels from rings[0], and
        # centroid search only needs the mainland body.
        rings.sort(key=lambda r: -ring_area(r))
        cx, cy = pole_of_inaccessibility(rings)
        if not point_in_rings(cx, cy, rings):
            sys.exit(f"centroid outside shape for code {code} ({s['name']})")

        rounded = [[[round(x, COORD_DECIMALS), round(y, COORD_DECIMALS)]
                    for x, y in r] for r in rings]
        # Rounding can collapse a coordinate pair; re-close defensively so the
        # Swift side never sees an open ring.
        for r in rounded:
            if r[0] != r[-1]:
                r.append(list(r[0]))
        total_pts += sum(len(r) for r in rounded)

        bx0, by0, bx1, by1 = bbox_of([p for r in rounded for p in r])
        prefectures.append({
            "code": code,
            "name": s["name"],
            "kana": KANA[code],
            "bbox": [round(v, COORD_DECIMALS) for v in (bx0, by0, bx1, by1)],
            "centroid": [round(cx, COORD_DECIMALS), round(cy, COORD_DECIMALS)],
            "rings": rounded,
        })

    out = {
        "mapWidth": OUT_WIDTH,
        "mapHeight": round(map_h, COORD_DECIMALS),
        "okinawaInset": inset,
        "prefectures": prefectures,
    }

    dst = os.path.join(here, DST)
    with open(dst, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(",", ":"))

    size = os.path.getsize(dst)
    print(f"wrote {DST}")
    print(f"  prefectures : {len(prefectures)}")
    print(f"  points      : {total_pts}  (dropped {dropped} outlying rings)")
    print(f"  map         : {OUT_WIDTH} x {round(map_h, 1)}")
    print(f"  okinawaInset: {inset}")
    print(f"  size        : {size / 1024:.1f} KB")


if __name__ == "__main__":
    main()
