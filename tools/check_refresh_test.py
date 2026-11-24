#!/usr/bin/env python3
"""Run from the repository root: python3 tools/check_refresh_test.py"""

import unittest

import check_refresh


def data(records):
    """check_refresh.dump's groupings for the given legacy_dump records."""
    return check_refresh.group(iter(records))


REWARDS = [{"kind": "reward", "id": 684}]
FEEDS = [{"kind": "feed", "id": 700, "targets": [684]}]
EXPLORE = [
    {
        "kind": "objective",
        "zone": 1426,
        "achievement": 627,
        "criteria": 502,
        "obj": "explore",
        "key": "295:385:256:128",
        "x": 0.349,
        "y": 0.681,
    }
]
INSTANCE = [
    {
        "kind": "objective",
        "zone": 1445,
        "achievement": 684,
        "criteria": 3271,
        "obj": "instance",
        "instance": 249,
        "x": 0.529,
        "y": 0.777,
    }
]
AREA = [{"kind": "area", "zone": 1411, "name": "Orgrimmar", "key": "244:0:512:256", "tiles": 2}]
WING = [{"kind": "wing", "zone": 1411, "name": "Bazzalan", "refs": [[62031, 19213]]}]
BOSS = [{"kind": "boss", "zone": 1445, "raid": "Onyxia's Lair", "name": "Onyxia", "refs": [[684, 3271]]}]
LEGACY = [{"kind": "legacy", "zone": 1411, "name": "Ragefire Chasm or Hall of Thanes", "refs": [[62031, 19213]]}]
REP = [{"kind": "reputation", "zone": 1411, "faction": 21, "name": "Orgrimmar"}]


def regressions_lines(regressions):
    return [line for _, line in regressions]


class Compare(unittest.TestCase):
    def test_identical_data_reports_nothing(self):
        for records in (REWARDS, FEEDS, EXPLORE, INSTANCE, AREA, WING, BOSS, LEGACY, REP):
            regressions, reports = check_refresh.compare(data(records), data(records))
            self.assertEqual(regressions, [])
            self.assertEqual(reports, [])

    def test_an_objective_that_lost_its_pin_is_a_regression(self):
        moved = [dict(EXPLORE[0], x=0.5, y=0.5)]
        regressions, reports = check_refresh.compare(data(EXPLORE), data(moved))
        self.assertEqual(regressions, [])
        self.assertEqual(reports, ["objective 627/502 in zone 1426: moved its pin from 0.349, 0.681 to 0.5, 0.5"])
        unpinned = [{key: value for key, value in EXPLORE[0].items() if key not in ("x", "y")}]
        regressions, _ = check_refresh.compare(data(EXPLORE), data(unpinned))
        self.assertEqual(regressions_lines(regressions), ["objective 627/502 in zone 1426: lost its pin"])

    def test_an_explore_objective_that_lost_its_key_is_a_regression(self):
        unkeyed = [{key: value for key, value in EXPLORE[0].items() if key != "key"}]
        regressions, reports = check_refresh.compare(data(EXPLORE), data(unkeyed))
        self.assertEqual(
            regressions_lines(regressions), ["objective 627/502 in zone 1426: lost its drawn key (295:385:256:128)"]
        )
        self.assertEqual(reports, [])

    def test_an_objective_that_lost_every_zone_while_its_reward_stays_is_a_regression(self):
        regressions, reports = check_refresh.compare(
            data(EXPLORE + [{"kind": "reward", "id": 627}]), data([{"kind": "reward", "id": 627}])
        )
        self.assertEqual(
            regressions_lines(regressions),
            ["objective 627/502: lost every zone it had (the achievement is still a reward or feed)"],
        )
        self.assertEqual(reports, [])
        regressions, reports = check_refresh.compare(data(EXPLORE), data([]))
        self.assertEqual(regressions, [])
        self.assertEqual(reports, ["objective 627/502 is gone"])

    def test_a_moved_objective_and_a_new_one_are_reports(self):
        moved = [dict(INSTANCE[0], zone=1454, x=0.530, y=0.489)]
        regressions, reports = check_refresh.compare(data(INSTANCE), data(moved))
        self.assertEqual(regressions, [])
        self.assertEqual(
            reports, ["objective 684/3271: no longer in zone 1445", "objective 684/3271: now also in zone 1454"]
        )

    def test_a_feed_that_dropped_a_link_is_a_regression(self):
        mutated = [{"kind": "feed", "id": 700, "targets": []}]
        regressions, reports = check_refresh.compare(data(FEEDS), data(mutated))
        self.assertEqual(regressions_lines(regressions), ["feed 700: dropped its link to reward 684"])
        self.assertEqual(reports, [])

    def test_an_area_that_lost_its_tiles_or_its_key_is_a_regression(self):
        regressions, _ = check_refresh.compare(data(AREA), data([dict(AREA[0], tiles=0)]))
        self.assertEqual(regressions_lines(regressions), ["area Orgrimmar (zone 1411): lost its tiles (2 -> none)"])
        regressions, _ = check_refresh.compare(
            data(AREA), data([{key: value for key, value in AREA[0].items() if key != "key"}])
        )
        self.assertEqual(
            regressions_lines(regressions), ["area Orgrimmar (zone 1411): lost its drawn key (244:0:512:256)"]
        )

    def test_a_wing_boss_or_legacy_entry_that_dropped_a_ref_is_a_regression(self):
        for records in (WING, BOSS, LEGACY):
            with self.subTest(records[0]["kind"]):
                ref = records[0]["refs"][0]
                mutated = [{key: value for key, value in records[0].items() if key != "refs"}]
                regressions, reports = check_refresh.compare(data(records), data(mutated))
                self.assertEqual(reports, [])
                self.assertEqual(len(regressions), 1)
                self.assertIn(f"dropped ref {ref[0]}/{ref[1]}", regressions_lines(regressions)[0])

    def test_drops_gains_and_moves_of_whole_entries_are_reports(self):
        regressions, reports = check_refresh.compare(data(REP), data([dict(REP[0], zone=1454, side="Horde")]))
        self.assertEqual(regressions, [])
        self.assertEqual(
            reports,
            ["reputation 21: moved from zone 1411 to zone 1454", "reputation 21: changed its side from None to Horde"],
        )


if __name__ == "__main__":
    unittest.main()
