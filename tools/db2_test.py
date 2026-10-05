import tempfile
import unittest
from pathlib import Path

import db2


class Db2Test(unittest.TestCase):
    def rows(self, text, columns=("Value",), **options):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            (cache / "T-1.csv").write_text(text, encoding="utf-8")
            return db2.db2("T", columns, "1", cache, offline=True, **options)

    def test_valid_rows_are_keyed_by_id_and_typed(self):
        rows = self.rows("ID,Value,Name_lang,Region_X\n1,2,a,0.5\n", ("Value", "Name_lang", "Region_X"))
        self.assertEqual(rows, {1: {"ID": 1, "Value": 2, "Name_lang": "a", "Region_X": 0.5}})

    def test_rejects_duplicate_columns_ids_and_malformed_rows(self):
        for text, message in (
            ("ID,Value,Value\n1,2,3\n", "duplicate columns"),
            ("ID,Value\n1,2\n1,3\n", "duplicate ID"),
            ("ID,Value\n1\n", "malformed CSV row"),
            ("ID,Value\n1,2.5\n", "invalid integer"),
            ("ID,Value\n-1,2\n", "negative/duplicate ID"),
            ("ID,Value\n", "empty export"),
        ):
            with self.subTest(text=text), self.assertRaisesRegex(ValueError, message):
                self.rows(text)

    def test_atomic_write_replaces_without_leaving_temporaries(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "out" / "x.lua"
            db2.atomic_write(path, b"one")
            db2.atomic_write(path, b"two")
            self.assertEqual(path.read_bytes(), b"two")
            self.assertEqual([p.name for p in path.parent.iterdir()], ["x.lua"])


if __name__ == "__main__":
    unittest.main()
