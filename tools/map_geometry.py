"""日本版・世界版のビルドスクリプトが共有する幾何の純関数。

build_map_data.py (平面正規化後の座標) と build_world_map_data.py (緯度経度)
の両方から使う。座標系には依存しない。挙動を変えるときは両スクリプトの
出力を再生成し、意図しない差分が無いことを確認すること。
"""

from __future__ import annotations

import heapq
import math


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
    """内部で最も縁から遠い点 (Mapbox polylabel の quadtree 版)。

    面積重心と違い、凹形状・群島でも必ず形の内部に落ちることを保証する。
    どの形で重心が使えないかの根拠は各ビルドスクリプトの呼び出し側にある。
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
