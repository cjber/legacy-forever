"""LuaLS can exit zero with an Information diagnostic; the JSON report is authoritative."""

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from tools.check_diagnostics import check


class DiagnosticsTests(unittest.TestCase):
    def run_report(self, contents):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "diagnostics.json"
            report.write_text(contents)
            output = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                status = check(report)
            return status, output.getvalue()

    def test_empty_reports(self):
        for contents in ["[]", "{}"]:
            self.assertEqual(self.run_report(contents)[0], 0)

    def test_every_severity_fails_with_a_location(self):
        for severity in range(1, 5):
            report = {
                "file:///tmp/addon%20name.lua": [
                    {
                        "severity": severity,
                        "code": "unused-local",
                        "message": "Unused local `value`.",
                        "range": {"start": {"line": 4}},
                    }
                ]
            }
            status, output = self.run_report(json.dumps(report))
            self.assertEqual(status, 1)
            self.assertIn("/tmp/addon name.lua:5: unused-local: Unused local `value`.", output)

    def test_bad_report_fails_closed(self):
        for contents in ["", "garbage", "null", "[1]", '{"file:///tmp/a.lua": [{}]}', '{"file:///tmp/a.lua": {}}']:
            with self.subTest(contents=contents):
                self.assertEqual(self.run_report(contents)[0], 1)


if __name__ == "__main__":
    unittest.main()
