#!/usr/bin/env python3
"""Print a translation template: every phrase the shipped Lua translates, as a Locales/<locale>.lua file (stdlib only).

A phrase is the English text in `L["..."]`; the addon uses it as the key and falls back to it. The output is
committed as Locales/phrases.txt for translators to copy, and tests/locale_spec.lua fails when the two disagree.
Translation files themselves (Locales/) are not read, so a phrase the code no longer uses drops out.

    python3 tools/phrases.py > Locales/phrases.txt
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOC = ROOT / "LegacyForever.toc"
PHRASE = re.compile(r'\bL\["((?:\\.|[^"\\])*)"\]')
HEADER = """\
-- A translation template for Legacy Forever. Save a copy as Locales/deDE.lua (or your locale), change "deDE" below,
-- translate the right-hand side of each line and delete the lines you leave in English. Keep %s, %d and |4...;
-- as they are. Then add Locales\\deDE.lua to LegacyForever.toc, right after Locales\\enUS.lua.
local _, ns = ...
if GetLocale() ~= "deDE" then
\treturn
end
local L = ns.L
"""


def shipped():
    """The Lua files the TOC loads, in load order, outside Locales/."""
    for line in TOC.read_text().splitlines():
        line = line.strip()
        if line.endswith(".lua") and not line.startswith(("#", "Locales")):
            yield ROOT / line.replace("\\", "/")


def phrases():
    found = set()
    for path in shipped():
        found.update(PHRASE.findall(path.read_text()))
    return sorted(found)


if __name__ == "__main__":
    print(HEADER)
    for phrase in phrases():
        line = f'L["{phrase}"] = "{phrase}"'
        # StyLua's wrap at 120 columns, so a copy passes `stylua --check` before it is translated.
        print(line if len(line) <= 120 else f'L["{phrase}"] =\n\t"{phrase}"')
