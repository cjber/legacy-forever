"""completion_wings places Spelunker wings whose step names a creature or a reviewed DungeonEncounter."""

import unittest
from collections import Counter, defaultdict

from db2 import CRITERIA_DUNGEON_ENCOUNTER, CRITERIA_KILL_CREATURE
from gen_legacy import SPELUNKER, completion_wings

ACHIEVEMENT = SPELUNKER[0]


class Graph:
    def __init__(self, steps):
        self.steps = steps

    def walk(self, root, active):
        return self.steps if root == ACHIEVEMENT else []


def run(criteria, wings):
    tables = {
        "Achievement": {achievement: {"Criteria_tree": achievement} for achievement in SPELUNKER},
        "Criteria": {cid: {"Type": kind, "Asset": asset} for cid, (kind, asset) in criteria.items()},
    }
    steps = [{"CriteriaID": cid, "Amount": 1, "Description_lang": f"Wing {cid}"} for cid in criteria]
    curated = {"dungeonWings": wings}
    completion = defaultdict(lambda: {"dungeons": []})
    unplaced = completion_wings(tables, Graph(steps), curated, {}, completion, Counter())
    return completion, unplaced


class CompletionWingTests(unittest.TestCase):
    def test_encounter_step_uses_the_reviewed_wing(self):
        completion, unplaced = run(
            {1: (CRITERIA_KILL_CREATURE, 10), 2: (CRITERIA_DUNGEON_ENCOUNTER, 478)},
            {10: {"uiMap": 100, "name": "Wing 1"}, 20: {"uiMap": 100, "name": "Wing 2", "encounter": 478}},
        )
        self.assertEqual(unplaced, [])
        self.assertEqual(
            completion[100]["dungeons"],
            [{"name": "Wing 1", "refs": [(ACHIEVEMENT, 1)]}, {"name": "Wing 2", "refs": [(ACHIEVEMENT, 2)]}],
        )

    def test_unreviewed_encounter_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "DungeonEncounter 478 has no reviewed wing"):
            run({2: (CRITERIA_DUNGEON_ENCOUNTER, 478)}, {})

    def test_reviewed_encounter_no_longer_used_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "encounters no longer in Spelunker"):
            run({1: (CRITERIA_KILL_CREATURE, 20)}, {20: {"uiMap": 100, "name": "Wing 1", "encounter": 478}})

    def test_other_step_types_are_an_error(self):
        with self.assertRaisesRegex(ValueError, "expected a single-boss kill or encounter step"):
            run({1: (27, 5)}, {})


if __name__ == "__main__":
    unittest.main()
