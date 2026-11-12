"""The outline tracer, the chunk grid and the generated Lua's shape, on synthetic terrain."""

import struct
import unittest

from gen_explore import (
    CHUNK,
    TILE,
    boundary_rings,
    chaikin,
    chunk_cells,
    clip_ring,
    grid,
    number,
    ring_lines,
    simplify,
    tiles_for,
    uv,
    wdt_tiles,
)


def chunk(tag, body):
    return tag[::-1] + struct.pack("<I", len(body)) + body


class TraceTests(unittest.TestCase):
    def test_one_chunk_is_one_ring(self):
        rings = boundary_rings({(0, 0)})
        self.assertEqual(rings, [[(-1, -1), (0, -1), (0, 0), (-1, 0)]])

    def test_a_hole_stays_a_separate_ring(self):
        cells = {(x, y) for x in range(3) for y in range(3)} - {(1, 1)}
        rings = boundary_rings(cells)
        self.assertEqual(len(rings), 2)
        self.assertIn([(0, 0), (0, 1), (1, 1), (1, 0)], rings)

    def test_diagonal_cells_are_two_rings_not_one(self):
        rings = boundary_rings({(0, 0), (1, 1)})
        self.assertEqual(len(rings), 2)
        self.assertIn([(-1, -1), (0, -1), (0, 0), (-1, 0)], rings)

    def test_a_straight_edge_keeps_no_middle_points(self):
        rings = boundary_rings({(x, 0) for x in range(4)})
        self.assertEqual(rings, [[(-1, -1), (3, -1), (3, 0), (-1, 0)]])


class SmoothTests(unittest.TestCase):
    def test_chaikin_doubles_a_ring(self):
        points = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        self.assertEqual(len(chaikin(points, 1)), 8)
        self.assertEqual(len(chaikin(points, 2)), 16)

    def test_simplify_drops_a_straight_run(self):
        points = [(0.0, 0.0), (0.25, 0.0), (0.5, 0.0), (0.75, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        kept = simplify(points, 0.002)
        self.assertEqual(kept, [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)])

    def test_simplify_keeps_a_corner(self):
        points = [(0.0, 0.0), (1.0, 0.0), (1.5, 0.5), (1.0, 1.0), (0.0, 1.0)]
        self.assertIn((1.5, 0.5), simplify(points, 0.002))


class CoordinateTests(unittest.TestCase):
    @staticmethod
    def polygon_area(points):
        return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(points, points[1:] + points[:1], strict=False))) / 2

    def test_ring_is_clipped_at_map_edges_before_projection(self):
        rectangle = (0.0, 100.0 * CHUNK, 0.0, 100.0 * CHUNK)
        ring = [(-50.0, 25.0), (50.0, 150.0), (150.0, 25.0), (50.0, -50.0)]
        clipped = clip_ring(ring, rectangle)
        self.assertTrue(all(0 <= x <= 100 and 0 <= y <= 100 for x, y in clipped))
        self.assertEqual(len(clipped), 6)
        self.assertEqual(self.polygon_area(clipped), 9875)
        self.assertIn((0.0, 87.5), clipped)
        self.assertIn((100.0, 87.5), clipped)

        # The previous per-vertex UV clamp loses the edge intersections and changes the fill area.
        clamped = [(min(100.0, max(0.0, x)), min(100.0, max(0.0, y))) for x, y in ring]
        self.assertNotEqual(self.polygon_area(clamped), self.polygon_area(clipped))

    def test_concave_ring_keeps_unique_vertices_within_map(self):
        rectangle = (0.0, 100.0 * CHUNK, 0.0, 100.0 * CHUNK)
        ring = [
            (-20.0, 10.0),
            (20.0, 10.0),
            (20.0, 80.0),
            (80.0, 80.0),
            (80.0, 10.0),
            (120.0, 10.0),
            (120.0, 90.0),
            (-20.0, 90.0),
        ]
        clipped = clip_ring(ring, rectangle)
        self.assertEqual(len(clipped), len(set(clipped)))
        self.assertGreater(self.polygon_area(clipped), 0)
        self.assertTrue(all(0 <= x <= 100 and 0 <= y <= 100 for x, y in clipped))

    def test_the_map_rectangle_edges_map_to_the_map_edges(self):
        rectangle = (100.0, 500.0, -200.0, 600.0)
        for point, expected in (
            ((grid(100.0), grid(600.0)), (0.0, 1.0)),
            ((grid(500.0), grid(-200.0)), (1.0, 0.0)),
        ):
            found = uv(point, rectangle)
            self.assertAlmostEqual(found[0], expected[0], places=6)
            self.assertAlmostEqual(found[1], expected[1], places=6)

    def test_a_point_outside_the_map_is_clipped(self):
        rectangle = (0.0, 100.0, 0.0, 100.0)
        self.assertEqual(uv((grid(200.0), grid(200.0)), rectangle), (0.0, 0.0))

    def test_a_position_off_the_chunk_grid_is_an_error(self):
        with self.assertRaises(ValueError):
            grid(10.0)

    def test_a_rectangle_touches_the_tiles_around_it(self):
        # Tile 31 covers (0, TILE] on both axes: the world origin is its south-west corner.
        tiles = {(x, y): x * 100 + y for x in range(64) for y in range(64)}
        found = tiles_for((0.0, TILE, 0.0, TILE), tiles)
        self.assertEqual(found, {(31, 31): 3131})


class FileTests(unittest.TestCase):
    def test_the_wdt_names_each_present_tile(self):
        main = bytearray(64 * 64 * 8)
        maid = bytearray(64 * 64 * 32)
        struct.pack_into("<I", main, (18 * 64 + 33) * 8, 1)
        struct.pack_into("<I", maid, (18 * 64 + 33) * 32, 785040)
        data = chunk(b"MVER", struct.pack("<I", 4)) + chunk(b"MAIN", bytes(main)) + chunk(b"MAID", bytes(maid))
        self.assertEqual(wdt_tiles(data), {(33, 18): 785040})

    def test_a_wdt_without_a_maid_chunk_is_an_error(self):
        main = bytearray(64 * 64 * 8)
        data = chunk(b"MAIN", bytes(main))
        with self.assertRaises(ValueError):
            wdt_tiles(data)

    def test_an_adt_yields_its_chunk_areas(self):
        body = bytearray(0x80)
        struct.pack_into("<I", body, 0x34, 444)
        struct.pack_into("<ff", body, 0x68, 33.3333, -33.3333)
        terrain = b"".join(chunk(b"MCNK", bytes(body)) for _ in range(256))
        found = chunk_cells(chunk(b"MVER", struct.pack("<I", 4)) + terrain)
        self.assertEqual(len(found), 256)
        self.assertEqual(found[0], (444, 1, -1))

    def test_a_chunk_off_the_grid_is_an_error(self):
        body = bytearray(0x80)
        struct.pack_into("<I", body, 0x34, 444)
        struct.pack_into("<ff", body, 0x68, 10.0, 10.0)
        terrain = b"".join(chunk(b"MCNK", bytes(body)) for _ in range(256))
        with self.assertRaises(ValueError):
            chunk_cells(chunk(b"MVER", struct.pack("<I", 4)) + terrain)


class FormatTests(unittest.TestCase):
    def test_numbers_keep_four_decimals_without_padding(self):
        self.assertEqual(number(0.5), "0.5")
        self.assertEqual(number(0.12345), "0.1235")
        self.assertEqual(number(1.0), "1")
        self.assertEqual(number(0.0), "0")

    def test_a_short_ring_is_one_line(self):
        self.assertEqual(ring_lines([0.5, 0.25, 0.75, 0.5], "\t"), ["{ 0.5, 0.25, 0.75, 0.5 },"])

    def test_a_long_ring_wraps_and_stays_closed(self):
        points = [index / 100 for index in range(100)]
        lines = ring_lines(points, "\t\t")
        self.assertGreater(len(lines), 1)
        self.assertTrue(lines[0].startswith("{"))
        self.assertTrue(lines[-1].endswith(" },"))
        self.assertIn("99", lines[-1])
        self.assertNotIn("100", " ".join(lines))

    def test_the_chunk_size_is_an_adt_tile_sixteenth(self):
        self.assertAlmostEqual(CHUNK, TILE / 16)


if __name__ == "__main__":
    unittest.main()
