"""Check that screenshot UI chrome uses the shared retail art build pin."""

import ast
import unittest
from pathlib import Path

SOURCE = Path(__file__).with_name("screenshots.py")


class RendererBuildTests(unittest.TestCase):
    def test_ui_uses_shared_art_build(self):
        tree = ast.parse(SOURCE.read_text(encoding="utf-8"))
        builds = [
            keyword.value
            for node in ast.walk(tree)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "Ui"
            for keyword in node.keywords
            if keyword.arg == "build"
        ]
        self.assertEqual(len(builds), 2)
        self.assertTrue(all(isinstance(value, ast.Name) and value.id == "UI_ART_BUILD" for value in builds))
        self.assertIn('UI_ART_BUILD = "1.60.1.70124"', SOURCE.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
