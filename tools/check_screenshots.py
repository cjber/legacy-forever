#!/usr/bin/env python3
"""Fail when a screenshot is older than what it shows (WFA-9, forever_tools.screens).

tools/screenshots.py draws every scene from wowmock and asks the addon's Core/Model.lua
(tools/screenshots_model.lua) what to show, porting the completion corner, map badges and tracker lines from UI/.
Each image's dump is those files' hashes, so a change to any of them needs a fresh render. Generated `Data/` and
`Locales/` are left out: the daily data refresh moves them and cannot render, and the release re-renders every image
(the release skill). docs/screenshots/scenes.sha256 holds each image's hash beside its dump's; tools/screenshots.py
rewrites it after a render.

    python3 tools/check_screenshots.py           # CI: fail on a stale image
    python3 tools/check_screenshots.py --record  # after a render, if tools/screenshots.py did not
"""

import functools
import sys
from pathlib import Path

try:
    from tools.forever_tools import screens
except ModuleNotFoundError:
    from forever_tools import screens

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/screenshots"
SOURCES = (
    "tools/screenshots.py",
    "tools/screenshots_model.lua",
    "Core/Model.lua",
    "UI/Completion.lua",
    "UI/MapContents.lua",
    "UI/Tracker.lua",
    "media/Shade.tga",
)
SCENES = {
    path.name: functools.partial(screens.files, ROOT, SOURCES)
    for pattern in screens.IMAGES
    for path in sorted(OUT.glob(pattern))
}


if __name__ == "__main__":
    sys.exit(screens.main(OUT, SCENES))
