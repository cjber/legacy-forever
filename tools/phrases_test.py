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


if __name__ == "__main__":
    unittest.main()
