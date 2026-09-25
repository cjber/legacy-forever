#!/usr/bin/env python3
"""Print every phrase the shipped Lua translates, for CurseForge's Import localization page (stdlib only).

A phrase is the English text in `L["..."]`; the addon uses it as the key and falls back to it. The output is
committed as Locales/phrases.txt so the maintainer can paste it, and tests/locale_spec.lua fails when the two
disagree.

    python3 tools/phrases.py > Locales/phrases.txt
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOC = ROOT / "LegacyForever.toc"
PHRASE = re.compile(r'\bL\["((?:\\.|[^"\\])*)"\]')


def shipped():
    """The Lua files the TOC loads, in load order."""
    for line in TOC.read_text().splitlines():
        line = line.strip()
        if line.endswith(".lua") and not line.startswith("#"):
            yield ROOT / line.replace("\\", "/")


def phrases():
    found = set()
    for path in shipped():
        found.update(PHRASE.findall(path.read_text()))
    return sorted(found)


if __name__ == "__main__":
    for phrase in phrases():
        print(f'L["{phrase}"] = true')
