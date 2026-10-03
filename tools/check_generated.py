#!/usr/bin/env python3
"""Regenerate committed data twice and require a fresh, byte-stable result."""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Data" / "Legacy.lua"


def input_cache() -> Path:
    """The main checkout's tools/.cache, so every git worktree of the repository shares one set of inputs."""
    common = subprocess.check_output(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=ROOT, text=True
    ).strip()
    return Path(common).parent / "tools" / ".cache"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    command = ["tools/gen_legacy.py"] + (["--offline"] if args.offline else [])
    original = OUTPUT.read_bytes()
    with tempfile.TemporaryDirectory() as directory:
        scratch = Path(directory) / ROOT.name
        scratch.mkdir()
        tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
        for name in tracked.decode().split("\0"):
            if not name:
                continue
            source = ROOT / name
            target = scratch / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        cache = input_cache()
        if cache.is_dir():
            shutil.copytree(cache, scratch / "tools" / ".cache")
        (scratch / OUTPUT.relative_to(ROOT)).unlink()
        subprocess.run([sys.executable, *command], cwd=scratch, check=True)
        if not args.offline:
            shutil.copytree(scratch / "tools" / ".cache", cache, dirs_exist_ok=True)
        first = (scratch / OUTPUT.relative_to(ROOT)).read_bytes()
        if first != original:
            raise SystemExit("generated output is stale: Data/Legacy.lua")
        (scratch / OUTPUT.relative_to(ROOT)).unlink()
        subprocess.run([sys.executable, "tools/gen_legacy.py", "--offline"], cwd=scratch, check=True)
        if (scratch / OUTPUT.relative_to(ROOT)).read_bytes() != first:
            raise SystemExit("generator is not byte-stable: Data/Legacy.lua")


if __name__ == "__main__":
    main()
