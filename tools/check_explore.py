#!/usr/bin/env python3
"""Require Data/Explore.lua's zones and area keys to exist in Data/Legacy.lua's completion data (offline).

Data/Explore.lua is traced at its own pinned TERRAIN_BUILD, so a daily data refresh can move the completion
area keys the game reports. The map falls back to the shading for an area without an outline, but a stale key
means the terrain fill quietly misses it: this fails, names each one, and says how to retrace the terrain.
"""

import sys
from pathlib import Path

try:
    from tools.forever_tools import luadata
except ModuleNotFoundError:  # Direct invocation from the tools directory.
    from forever_tools import luadata

ROOT = Path(__file__).resolve().parent.parent


def tables(path: Path) -> dict[str, luadata.Table]:
    """A generated file's top-level tables, read without executing the file."""
    found, _ = luadata.parse_tables(path.read_text(encoding="utf-8"))
    return found


def explore_zones(explore: dict[str, luadata.Table]) -> dict[object, set[str]]:
    """Zone uiMapID -> the completion area keys Data/Explore.lua draws."""
    found = explore.get("ns.Explore")
    if found is None:
        raise luadata.LuaDataError("Data/Explore.lua has no ns.Explore table")
    return {zone: set(entry.keyed["areas"].keyed) for zone, entry in found.keyed["zones"].keyed.items()}


def completion_zones(data: dict[str, luadata.Table]) -> dict[object, set[str]]:
    """Zone uiMapID -> the completion area keys Data/Legacy.lua has, including areas with no key."""
    found = data.get("ns.Data")
    if found is None:
        raise luadata.LuaDataError("Data/Legacy.lua has no ns.Data table")
    zones = {}
    for zone, entry in found.keyed["completion"].keyed.items():
        areas = entry.keyed.get("areas")
        zones[zone] = {area.keyed["key"] for area in (areas.array if areas else ()) if "key" in area.keyed}
    return zones


def missing(explore: dict[object, set[str]], completion: dict[object, set[str]]) -> list[tuple[object, str | None]]:
    """Every zone or area key Explore has that completion does not; the key is None for an unknown zone."""
    problems: list[tuple[object, str | None]] = []
    for zone, keys in explore.items():
        if zone not in completion:
            problems.append((zone, None))
            continue
        problems.extend((zone, key) for key in sorted(keys - completion[zone]))
    return problems


def main() -> int:
    try:
        explore = explore_zones(tables(ROOT / "Data" / "Explore.lua"))
        completion = completion_zones(tables(ROOT / "Data" / "Legacy.lua"))
    except (OSError, luadata.LuaDataError) as error:
        print(f"check_explore: {error}", file=sys.stderr)
        return 1
    problems = missing(explore, completion)
    if not problems:
        print("Explore areas match Legacy's completion data.")
        return 0
    for zone, key in problems:
        if key is None:
            print(f"Data/Explore.lua: zone {zone} is not in Data/Legacy.lua's completion data")
        else:
            print(f'Data/Explore.lua: zone {zone}, area "{key}" is not in Data/Legacy.lua\'s completion data')
    print(
        "Bump TERRAIN_BUILD in tools/gen_explore.py, run python3 tools/gen_explore.py and commit Data/Explore.lua.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
