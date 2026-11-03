"""reward_achievements keeps only TraitCurrencySource 4225 rows the Achievement table defines."""

import contextlib
import io
import unittest

from gen_legacy import reward_achievements


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


if __name__ == "__main__":
    unittest.main()
