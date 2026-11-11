"""Phrase extraction follows the same TOC/XML runtime graph as type checking."""

import tempfile
import unittest
from pathlib import Path

from tools.phrases import phrases


class PhraseRuntimeTest(unittest.TestCase):
    def test_xml_script_is_scanned(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Addon.toc").write_text("Frames.xml\n")
            (root / "Frames.xml").write_text('<Ui><Script file="UI.lua"/></Ui>')
            (root / "UI.lua").write_text('local label = L["XML-only phrase"]')

            self.assertIn("XML-only phrase", phrases(root))

    def test_a_bracket_choice_adds_every_phrase(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Addon.toc").write_text("UI.lua\n")
            (root / "UI.lua").write_text('local label = L[count == 1 and "board" or "boards"]')

            found = phrases(root)
            self.assertIn("board", found)
            self.assertIn("boards", found)

    def test_a_phrase_from_a_local_list_is_found(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Addon.toc").write_text("UI.lua\n")
            (root / "UI.lua").write_text(
                'local ORDINALS = { "1st", "2nd" }\nlocal phrase = ORDINALS[rank]\nlocal text = L[phrase]\n'
            )

            found = phrases(root)
            self.assertIn("1st", found)
            self.assertIn("2nd", found)

    def test_a_shared_files_phrase_helper_is_found(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Addon.toc").write_text("ForeverRequire.lua\n")
            (root / "ForeverRequire.lua").write_text(
                "local function phrase(key, ...)\n"
                "\treturn string.format((ns.L or {})[key] or key, ...)\n"
                "end\n"
                'text = phrase("%s is out of date. Update it to fix this.", name)\n'
            )

            self.assertIn("%s is out of date. Update it to fix this.", phrases(root))


if __name__ == "__main__":
    unittest.main()
