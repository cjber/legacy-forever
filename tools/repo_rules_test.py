"""The repository rules over the cases that have mattered: growth, a new file, a rename, a shrink, a marker, and a
workflow naming a file that is gone."""

import unittest

from tools.repo_rules import LIMIT, missing_hashfiles, oversize_growth

BIG = b"x\n" * (LIMIT + 1)
BIGGER = BIG + b"x\n"


def check(rows, head, base):
    return oversize_growth(rows, head.get, base.get)


class FileSizeTest(unittest.TestCase):
    def test_growing_a_large_file_fails(self):
        self.assertEqual(len(check([("M", "a.lua", "a.lua")], {"a.lua": BIGGER}, {"a.lua": BIG})), 1)

    def test_a_new_large_file_fails_unless_excluded(self):
        rows = [
            ("A", "a.lua", "a.lua"),
            ("A", "deps.lock", "deps.lock"),
            ("A", "tools/forever_sim/w.lua", "tools/forever_sim/w.lua"),
        ]
        head = {"a.lua": BIG, "deps.lock": BIG, "tools/forever_sim/w.lua": BIG}
        self.assertEqual([hit.split(":")[0] for hit in check(rows, head, {})], ["a.lua"])

    def test_a_rename_compares_with_the_old_path(self):
        self.assertEqual(len(check([("R", "old.lua", "new.lua")], {"new.lua": BIGGER}, {"old.lua": BIG})), 1)
        self.assertEqual(check([("R", "old.lua", "new.lua")], {"new.lua": BIG}, {"old.lua": BIG}), [])

    def test_shrinking_a_large_file_passes(self):
        self.assertEqual(check([("M", "a.lua", "a.lua")], {"a.lua": BIG}, {"a.lua": BIGGER}), [])

    def test_a_marker_needs_a_reason(self):
        marked = b"; rule-ignore: file-size-no-growth - one lookup table, generated and reviewed\n" + BIG
        bare = b"; rule-ignore: file-size-no-growth - ok\n" + BIG
        self.assertEqual(check([("A", "t.ini", "t.ini")], {"t.ini": marked}, {}), [])
        self.assertEqual(len(check([("A", "t.ini", "t.ini")], {"t.ini": bare}, {})), 1)


class HashFilesTest(unittest.TestCase):
    def test_a_missing_literal_path_fails_and_a_glob_passes(self):
        text = "key: k-${{ hashFiles('tools/a.txt', 'tools/gone.txt', 'tools/gen_*.txt') }}"
        hits = missing_hashfiles("ci.yml", text, {"tools/a.txt"}.__contains__)
        self.assertEqual(
            hits, ["ci.yml:1: workflow-hashfiles-path: hashFiles names 'tools/gone.txt', which does not exist"]
        )


if __name__ == "__main__":
    unittest.main()
