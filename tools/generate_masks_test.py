"""Terrain masks keep one distance field around corners and separate islands."""

import hashlib
import math
import subprocess
import tempfile
import unittest
from pathlib import Path

from generate_masks_all import ROOT, alpha_mask, generate, read_rings
from PIL import Image


class MaskGeneratorTests(unittest.TestCase):
    def sample(self, image, left, top, x, y):
        return image.getpixel((x - left, y - top))[3]

    def test_corner_distance_and_winding(self):
        ring = [(100, 100), (200, 100), (200, 200), (100, 200)]
        image, left, top = alpha_mask([ring])

        def at(x, y):
            return self.sample(image, left, top, x, y)

        self.assertEqual(at(150, 150), 255)
        self.assertEqual(at(150, 60), int((1 - 39.5 / 40) * 255))
        self.assertEqual(at(60, 60), 0)
        self.assertEqual(at(80, 80), int((1 - math.hypot(19.5, 19.5) / 40) * 255))
        reversed_image, _, _ = alpha_mask([list(reversed(ring))])
        self.assertEqual(image.tobytes(), reversed_image.tobytes())

    def test_concave_notch_uses_nearest_edge_once(self):
        ring = [(0, 0), (200, 0), (200, 80), (80, 80), (80, 200), (0, 200)]
        image, left, top = alpha_mask([ring])
        self.assertEqual(self.sample(image, left, top, 100, 100), int((1 - 20.5 / 40) * 255))
        self.assertEqual(self.sample(image, left, top, 140, 140), 0)
        self.assertEqual(self.sample(image, left, top, 40, 140), 255)

    def test_multiple_terrain_islands_are_a_union(self):
        rings = [[(0, 0), (40, 0), (40, 40), (0, 40)], [(80, 0), (120, 0), (120, 40), (80, 40)]]
        image, left, top = alpha_mask(rings)
        self.assertEqual(self.sample(image, left, top, 20, 20), 255)
        self.assertEqual(self.sample(image, left, top, 100, 20), 255)
        self.assertEqual(self.sample(image, left, top, 60, 20), int((1 - 19.5 / 40) * 255))

    def test_output_contract_determinism_and_stale_cleanup(self):
        scratch = Path.home() / ".cache/agent-scratch"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="legacy-mask-test-", dir=scratch) as directory:
            output = Path(directory) / "masks"
            manifest = Path(directory) / "ShadingMasks.lua"
            groups = {
                (1433, "same:key"): [[(0, 0), (20, 0), (20, 20)]],
                (1429, "same:key"): [[(0, 0), (40, 0), (40, 40)]],
            }
            paths = generate(groups, output, manifest)
            first = {p.name: hashlib.sha256(p.read_bytes()).digest() for p in paths}
            first_manifest = manifest.read_bytes()
            (output / "Mask999.tga").write_bytes(b"stale")
            (output / "Other.tga").write_bytes(b"unrelated")
            second = generate(dict(reversed(list(groups.items()))), output, manifest)
            self.assertEqual(first, {p.name: hashlib.sha256(p.read_bytes()).digest() for p in second})
            self.assertEqual(first_manifest, manifest.read_bytes())
            self.assertFalse((output / "Mask999.tga").exists())
            self.assertEqual((output / "Other.tga").read_bytes(), b"unrelated")
            for path in second:
                with Image.open(path) as image:
                    self.assertEqual(image.mode, "RGBA")
                    self.assertEqual(image.width & (image.width - 1), 0)
                    self.assertEqual(image.height & (image.height - 1), 0)

    def test_committed_manifest_covers_every_real_area(self):
        text = subprocess.check_output(
            ["luajit", str(ROOT / "tools/export_shading_rings.lua"), str(ROOT / "Data/Explore.lua")], text=True
        )
        groups = read_rings(text)
        output = subprocess.check_output(
            ["luajit", str(ROOT / "tools/export_shading_masks.lua"), str(ROOT / "Data/ShadingMasks.lua")], text=True
        )
        manifests = {(int(row[0]), row[1]): row[6] for row in (line.split("\t") for line in output.splitlines())}
        self.assertEqual(set(groups), set(manifests))
        for basename in manifests.values():
            self.assertTrue((ROOT / "media/legacy-masks" / f"{basename.split(chr(92))[-1]}.tga").is_file())


if __name__ == "__main__":
    unittest.main()
