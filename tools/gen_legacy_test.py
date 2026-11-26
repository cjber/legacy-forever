"""Focused tests for Legacy rewards and objective metadata."""

import contextlib
import io
import unittest

from gen_legacy import Achievements, reward_achievements


def tables(rows, achievements):
    return {
        "TraitCurrencySource": {i: row for i, row in enumerate(rows)},
        "Achievement": {achievement: {} for achievement in achievements},
    }


class RewardAchievementTests(unittest.TestCase):
    def test_keeps_rows_the_build_defines(self):
        data = tables(
            [
                {"TraitCurrencyID": 4225, "AchievementID": 11},
                {"TraitCurrencyID": 4225, "AchievementID": 12},
                {"TraitCurrencyID": 3820, "AchievementID": 13},
            ],
            [11, 12],
        )
        self.assertEqual(reward_achievements(data), {11, 12})

    def test_drops_a_row_whose_achievement_was_deleted(self):
        data = tables(
            [
                {"TraitCurrencyID": 4225, "AchievementID": 11},
                {"TraitCurrencyID": 4225, "AchievementID": 64283},
            ],
            [11],
        )
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(reward_achievements(data), {11})
        self.assertIn("64283", stderr.getvalue())

    def test_empty_reward_set_is_an_error(self):
        data = tables([{"TraitCurrencyID": 4225, "AchievementID": 64283}], [])
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(ValueError):
            reward_achievements(data)

    def test_zero_reward_is_an_error(self):
        data = tables([{"TraitCurrencyID": 4225, "AchievementID": 0}], [0])
        with self.assertRaises(ValueError):
            reward_achievements(data)


class QuestAlternativeTests(unittest.TestCase):
    def test_unnamed_quest_alternatives_share_the_achievement_description(self):
        root = {"Parent": 0, "CriteriaID": 0, "Operator": 8, "Amount": 1, "Description_lang": "Internal label"}
        leaf = {"Parent": 1, "Operator": 0, "Amount": 1, "Description_lang": ""}
        data = {
            "Achievement": {
                10: {
                    "Criteria_tree": 1,
                    "Shares_criteria": 0,
                    "Description_lang": "Complete the questline.",
                    "Title_lang": "The Questline",
                },
            },
            "Criteria": {4: {"Type": 27, "Asset": 40}, 5: {"Type": 27, "Asset": 50}},
            "CriteriaTree": {1: root, 2: dict(leaf, ID=2, CriteriaID=4), 3: dict(leaf, ID=3, CriteriaID=5)},
        }
        graph = Achievements(data)
        self.assertEqual(graph.objective_details(10, 4), ("Complete the questline.", 1))
        self.assertEqual(graph.objective_details(10, 5), ("Complete the questline.", 1))
        root["Amount"] = 2
        with self.assertRaisesRegex(ValueError, "empty objective name"):
            graph.objective_details(10, 4)


if __name__ == "__main__":
    unittest.main()
