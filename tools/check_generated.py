#!/usr/bin/env python3
"""Regenerate committed data twice and require a fresh, byte-stable result."""

import argparse
import subprocess
import sys
from pathlib import Path

from forever_tools import generated

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Data" / "Legacy.lua"


def outputs(root: Path) -> dict[str, bytes]:
    return {"Data/Legacy.lua": (root / "Data" / "Legacy.lua").read_bytes()}


def regenerate(scratch: Path, offline: bool) -> None:
    (scratch / OUTPUT.relative_to(ROOT)).unlink()
    subprocess.run(
        [sys.executable, "tools/gen_legacy.py", *(["--offline"] if offline else [])], cwd=scratch, check=True
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true")
    generated.check_generated(
        ROOT,
        outputs=outputs,
        regenerate=regenerate,
        offline=parser.parse_args().offline,
        success="Generated data is fresh and byte-stable.",
    )


if __name__ == "__main__":
    main()
