import unittest
from map_detail import refine_rings, validate_detail


class MapDetailTests(unittest.TestCase):
    def test_refinement_keeps_only_existing_islands(self):
        coarse = [(0, 0), (4, 0), (4, 4), (0, 0)]
        detail = [(0, 0), (2, -1), (4, 0), (4, 4), (0, 0)]
        other = [(8, 8), (9, 8), (9, 9), (8, 8)]
        self.assertEqual(refine_rings([coarse], [other, detail]), [detail])

    def test_unrelated_source_is_rejected(self):
        with self.assertRaises(ValueError):
            refine_rings([[(0, 0), (4, 0), (4, 4), (0, 0)]],
                         [[(8, 8), (9, 8), (9, 9), (8, 8)]])

    def test_duplicate_or_open_detail_is_rejected(self):
        ring = [[0, 0], [4, 0], [4, 4], [0, 0]]
        with self.assertRaises(AssertionError):
            validate_detail([{'code': 1, 'rings': [ring, ring], 'detailedRings': [ring, ring]}])
        with self.assertRaises(AssertionError):
            validate_detail([{'code': 1, 'rings': [ring], 'detailedRings': [ring[:-1]]}])

    def test_old_data_needs_no_detail(self):
        validate_detail([{'code': 1, 'rings': []}])
