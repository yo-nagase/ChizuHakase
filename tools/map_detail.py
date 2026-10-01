"""Match nested mapshaper resolutions without adding islands or changing layout."""
from collections import defaultdict


def refine_rings(rings, candidates):
    """Preserve the coarse ring set; restore vertices from the same source rings.

    mapshaper simplifies shared arcs together, so using its detailed output
    also preserves country/prefecture borders. Never fit each ring separately:
    that would move the border and create gaps between neighbours.
    """
    index = defaultdict(set)
    for i, ring in enumerate(candidates):
        for point in ring:
            index[tuple(point)].add(i)
    result = []
    for ring in rings:
        votes = defaultdict(int)
        for point in set(map(tuple, ring)):
            for i in index[point]:
                votes[i] += 1
        if not votes:
            raise ValueError('Detailed source does not match the coarse map; regenerate both from the same source')
        best = max(votes, key=votes.get)
        if votes[best] < 3:
            raise ValueError('Not enough shared vertices to identify a detailed ring')
        result.append(candidates[best] if len(candidates[best]) > len(ring) else ring)
    return result


# Separate budgets keep the normal-resolution data from silently growing just
# because detail was added. Measured world detail: 1,366 KiB / 75,687 points.
DETAIL_SIZE_BUDGET = 1600 * 1024


def detail_size(entries):
    import json
    return sum(len(json.dumps(c.get('detailedRings', []), separators=(',', ':')).encode())
               for c in entries if 'detailedRings' in c)


def validate_detail(entries):
    import math
    for entry in entries:
        detail = entry.get('detailedRings')
        if detail is None:
            continue
        assert len(detail) == len(entry['rings']), (entry['code'], 'detail changes island/hole count')
        assert sum(map(len, detail)) >= sum(map(len, entry['rings'])), (entry['code'], 'detail loses vertices')
        for ring in detail:
            assert len(ring) >= 4 and ring[0] == ring[-1], (entry['code'], 'open detail ring')
            assert all(len(p) == 2 and all(math.isfinite(v) for v in p) for p in ring)
        assert len({tuple(map(tuple, r)) for r in detail}) == len(detail), (entry['code'], 'duplicate detail ring')
