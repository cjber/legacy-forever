#!/usr/bin/env python3
"""Fail closed on every diagnostic in a LuaLS --check_format=json report."""

import json
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse


def check(path: Path) -> int:
    try:
        report = json.loads(path.read_text())
        # LuaLS serializes the empty report as [], and nonempty reports as URI -> diagnostics.
        if report == []:
            report = {}
        if not isinstance(report, dict):
            raise ValueError("expected a diagnostic map")
        count = 0
        for uri, diagnostics in sorted(report.items()):
            if not isinstance(diagnostics, list):
                raise ValueError("expected a diagnostic list")
            filename = Path(unquote(urlparse(uri).path))
            filename = filename.relative_to(Path.cwd()) if filename.is_relative_to(Path.cwd()) else filename
            for diagnostic in diagnostics:
                line = diagnostic["range"]["start"]["line"] + 1
                message = " ".join(diagnostic["message"].splitlines())
                print(f"{filename}:{line}: {diagnostic['code']}: {message}")
                count += 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"typecheck: invalid or missing LuaLS report: {error}", file=sys.stderr)
        return 1
    print(f"LuaLS: {count} diagnostics")
    return int(count != 0)


if __name__ == "__main__":
    raise SystemExit(check(Path(sys.argv[1])))
