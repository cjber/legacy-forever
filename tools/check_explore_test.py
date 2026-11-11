"""The Explore-versus-Legacy key check, on small generated files."""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_explore

EXPLORE = """\
---@type string, LegacyForeverNamespace
local _, ns = ...

ns.Explore = {
	build = "1.2.3",
	zones = {
		[1439] = {
			width = 6549.9998,
			height = 4366.6665,
			areas = {
				["468:85:256:256"] = { { 0.5, 0.5, 0.6, 0.6, 0.5, 0.6 } },
			},
		},
	},
}
"""

LEGACY = """\
---@type string, LegacyForeverNamespace
local _, ns = ...

ns.Data = {
	completion = {
		[1439] = {
			tileWidth = 256,
			tileHeight = 256,
			areas = {
				{ key = "468:85:256:256", name = "Tower of Althalaxx" },
				{ name = "No overlay", achievement = 500, criteria = 6 },
			},
			taxis = {},
		},
	},
}
"""


def parsed(text):
    return check_explore.luadata.parse_tables(text)[0]


class KeyTests(unittest.TestCase):
    def test_matching_keys_pass(self):
        explore = check_explore.explore_zones(parsed(EXPLORE))
        completion = check_explore.completion_zones(parsed(LEGACY))
        self.assertEqual(check_explore.missing(explore, completion), [])

    def test_a_moved_key_is_named_with_its_zone(self):
        legacy = LEGACY.replace('"468:85:256:256"', '"468:85:256:257"')
        explore = check_explore.explore_zones(parsed(EXPLORE))
        completion = check_explore.completion_zones(parsed(legacy))
        self.assertEqual(check_explore.missing(explore, completion), [(1439, "468:85:256:256")])

    def test_a_zone_without_completion_is_named(self):
        explore = check_explore.explore_zones(parsed(EXPLORE))
        self.assertEqual(check_explore.missing(explore, {}), [(1439, None)])

    def test_an_area_without_a_key_is_not_a_completion_key(self):
        completion = check_explore.completion_zones(parsed(LEGACY))
        self.assertEqual(completion, {1439: {"468:85:256:256"}})

    def test_a_missing_table_is_an_error(self):
        with self.assertRaises(check_explore.luadata.LuaDataError):
            check_explore.explore_zones(parsed("ns.Data = {}\n"))


class MainTests(unittest.TestCase):
    def run_check(self, explore, legacy):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Data").mkdir()
            (root / "Data" / "Explore.lua").write_text(explore, encoding="utf-8")
            (root / "Data" / "Legacy.lua").write_text(legacy, encoding="utf-8")
            output = io.StringIO()
            with mock.patch.object(check_explore, "ROOT", root), contextlib.redirect_stdout(output):
                status = check_explore.main()
            return status, output.getvalue()

    def test_a_consistent_pair_passes(self):
        status, output = self.run_check(EXPLORE, LEGACY)
        self.assertEqual(status, 0)
        self.assertIn("match", output)

    def test_a_moved_key_fails_and_says_how_to_retrace(self):
        status, output = self.run_check(EXPLORE, LEGACY.replace('"468:85:256:256"', '"0:0:1:1"'))
        self.assertEqual(status, 1)
        self.assertIn('zone 1439, area "468:85:256:256"', output)


if __name__ == "__main__":
    unittest.main()
