#!/usr/bin/env python3
"""Trace exploration area outlines from the client's terrain chunks (stdlib only).

Every ADT terrain chunk names its AreaTable area. The exploration areas of a zone are the areas (and
their child areas) of the zone's map overlays, the same join tools/gen_legacy.py makes for completion
areas. This generator groups the chunks of each area into rings, smooths and simplifies them, and
writes Data/Explore.lua in that zone's map coordinates. Tiles are fetched from wago.tools and cached
by FileDataID and TERRAIN_BUILD, so a rerun downloads nothing.

TERRAIN_BUILD is pinned here, apart from tools/gen_legacy.py's BUILD: the daily data refresh moves area
keys and must not download every terrain tile again. tools/check_explore.py fails when the committed
exploration keys no longer match Data/Legacy.lua, and the fix is to bump TERRAIN_BUILD, run this locally
and commit the result.
"""

import argparse
import json
import math
import struct
import sys
import time
import urllib.error
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import gen_legacy as legacy
from db2 import db2
from forever_tools import wago
from forever_tools.fsio import atomic_write

# The client build the terrain and the DB2 rows that name its areas are read at. Bump it by hand when
# tools/check_explore.py names keys Data/Legacy.lua no longer has, then rerun this generator.
TERRAIN_BUILD = "1.60.1.70888"
ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache" / "adt"
OUTPUT = ROOT / "Data" / "Explore.lua"
CASC = "https://wago.tools/api/casc/{fdid}?version={build}"
# wago.tools answers Python's default User-Agent with 403 on the CASC endpoint.
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) LegacyForever/1.0"
DB2_USER_AGENT = "LegacyForever/1.0"
TILE = 533.3333
CHUNK = TILE / 16
# Map units. Two Chaikin passes round the chunk steps, then Douglas-Peucker keeps the shape readable
# at map scale: about 8 yards on a zone map 4000 yards across.
SIMPLIFY = 0.002
SMOOTH_PASSES = 2
ATTEMPTS = 4
# A WDT's MAIN chunk is a 64 by 64 grid; each entry is 8 bytes, the present flag first.
GRID = 64
PRESENT = 1
# The server refuses a request now and then; these downloads are the slow part, so retry rather than lose an hour.
TIMEOUT = 120


class Source:
    """wago.tools downloads, cached under tools/.cache/adt by build; a cached file is never fetched again."""

    def __init__(self, offline=False):
        self.offline = offline
        self.downloaded = 0

    def path(self, name):
        return CACHE / TERRAIN_BUILD / name

    def read(self, name):
        path = self.path(name)
        return path.read_bytes() if path.exists() else None

    def url(self, url):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        attempt = 0
        while True:
            try:
                with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
                    return response.read()
            except (OSError, urllib.error.HTTPError) as error:
                attempt += 1
                transient = not isinstance(error, urllib.error.HTTPError) or (error.code == 429 or error.code >= 500)
                if attempt >= ATTEMPTS or not transient:
                    raise
                time.sleep(2**attempt)

    def fetch(self, name, url, validate):
        data = self.read(name)
        if data is not None:
            validate(data)
            return data
        if self.offline:
            raise ValueError(f"Missing cached tile {name}; run without --offline to download it")
        data = self.url(url)
        validate(data)
        atomic_write(self.path(name), data)
        self.downloaded += 1
        return data

    def downloads(self, tasks, workers):
        """Run `tasks` (name, url, validate) at once; each writes its own cache file."""
        if not tasks:
            return
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(self.fetch, *task): task[0] for task in tasks}
            for done, future in enumerate(as_completed(futures), 1):
                future.result()
                if done % 20 == 0 and done < len(tasks):
                    print(f"  {done}/{len(tasks)} tiles cached", file=sys.stderr, flush=True)


def wdt_tiles(data):
    """A WDT's present tiles as (x, y) -> the root ADT FileDataID, from its MAIN and MAID chunks.

    MAIN is a 64 by 64 grid of 8-byte entries, the present flag first. MAID holds eight FileDataIDs per
    tile in the same order, the root ADT first.
    """
    chunks = {}
    position = 0
    while position < len(data) - 8:
        tag = data[position : position + 4][::-1]
        size = struct.unpack_from("<I", data, position + 4)[0]
        chunks[tag] = data[position + 8 : position + 8 + size]
        position += 8 + size
    main, maid = chunks.get(b"MAIN"), chunks.get(b"MAID")
    if main is None or maid is None or len(main) < GRID * GRID * 8 or len(maid) < GRID * GRID * 8 * 4:
        raise ValueError("WDT has no usable MAIN and MAID chunks")
    tiles = {}
    for y in range(GRID):
        for x in range(GRID):
            index = y * GRID + x
            if not struct.unpack_from("<I", main, index * 8)[0] & PRESENT:
                continue
            fdid = struct.unpack_from("<I", maid, index * 8 * 4)[0]
            if not fdid:
                raise ValueError(f"WDT tile {x}, {y} is present with no file")
            tiles[x, y] = fdid
    return tiles


def chunk_cells(data):
    """Every terrain chunk as (AreaID, cell x, cell y); a cell is CHUNK yards square."""
    if data[:4] != b"REVM":
        raise ValueError("not an ADT file")
    cells = []
    position = 0
    while position < len(data) - 8:
        tag = data[position : position + 4][::-1]
        size = struct.unpack_from("<I", data, position + 4)[0]
        if tag == b"MCNK":
            header = position + 8
            area = struct.unpack_from("<I", data, header + 0x34)[0]
            x, y = struct.unpack_from("<ff", data, header + 0x68)
            # The header's position is the chunk corner with the largest X and Y.
            cells.append((area, grid(x), grid(y)))
        position += 8 + size
    if len(cells) != 256:
        raise ValueError(f"expected 256 terrain chunks, found {len(cells)}")
    return cells


def grid(value):
    """A world position as a grid index, refusing a file whose chunk layout is not the one read here."""
    index = math.floor(value / CHUNK + 0.5)
    if abs(value - index * CHUNK) > CHUNK / 100:
        raise ValueError(f"chunk position {value} is not on the {CHUNK}-yard grid")
    return index


def tiles_for(rectangle, tiles):
    """The present tiles a world rectangle touches: tile index i covers (32 - i - 1, 32 - i] tiles."""
    xmin, xmax, ymin, ymax = rectangle
    found = {}
    for (x, y), fdid in tiles.items():
        if (32 - y) * TILE > xmin and (31 - y) * TILE < xmax and (32 - x) * TILE > ymin and (31 - x) * TILE < ymax:
            found[x, y] = fdid
    return found


def boundary_rings(cells):
    """Marching squares over the chunk grid: the rings around the union of `cells`.

    A cell (x, y) covers [x - 1, x] by [y - 1, y]; every cell edge against an empty neighbour is one
    contour segment, oriented with the filled side on its left. Segments are stitched into closed
    rings; at a corner where two rings touch, the leftmost turn keeps them apart.
    """
    ends = defaultdict(list)
    for x, y in cells:
        if (x, y + 1) not in cells:
            ends[(x, y)].append((x - 1, y))
        if (x, y - 1) not in cells:
            ends[(x - 1, y - 1)].append((x, y - 1))
        if (x - 1, y) not in cells:
            ends[(x - 1, y)].append((x - 1, y - 1))
        if (x + 1, y) not in cells:
            ends[(x, y - 1)].append((x, y))
    starts = {start: list(goals) for start, goals in ends.items()}
    rings = []
    while starts:
        start = min(starts)
        ring = [start]
        current = start
        while True:
            goals = starts[current]
            if len(goals) == 1:
                following = goals[0]
                del starts[current]
            else:
                # Two rings meeting at one corner: take the leftmost turn, which keeps them apart.
                back = ring[-2] if len(ring) > 1 else None
                direction = (current[0] - back[0], current[1] - back[1]) if back else None
                following = min(goals, key=lambda goal: turn(direction, (goal[0] - current[0], goal[1] - current[1])))
                goals.remove(following)
            current = following
            if current == start:
                break
            ring.append(current)
        ring = collinear(ring)
        if len(ring) >= 3:
            rings.append(ring)
    return rings


def turn(direction, step):
    """A counter-clockwise turn from `direction` to `step`, in (0, 2 pi]."""
    if direction is None:
        return 0.0
    cross = direction[0] * step[1] - direction[1] * step[0]
    dot = direction[0] * step[0] + direction[1] * step[1]
    angle = math.atan2(cross, dot)
    return angle if angle > 0 else angle + 2 * math.pi


def collinear(points):
    """The ring without a point that lies on the straight line between its neighbours."""
    kept = []
    count = len(points)
    for index, point in enumerate(points):
        before, after = points[index - 1], points[(index + 1) % count]
        cross = (point[0] - before[0]) * (after[1] - point[1]) - (point[1] - before[1]) * (after[0] - point[0])
        if cross != 0:
            kept.append(point)
    return kept


def chaikin(points, passes=SMOOTH_PASSES):
    """Chaikin corner cutting on a closed ring: each pass replaces every corner with two."""
    for _ in range(passes):
        smoothed = []
        count = len(points)
        for index in range(count):
            ax, ay = points[index]
            bx, by = points[(index + 1) % count]
            smoothed.append((0.75 * ax + 0.25 * bx, 0.75 * ay + 0.25 * by))
            smoothed.append((0.25 * ax + 0.75 * bx, 0.25 * ay + 0.75 * by))
        points = smoothed
    return points


def apart(point, start, end):
    """A point's distance from the line through `start` and `end`."""
    ex, ey = end[0] - start[0], end[1] - start[1]
    length = math.hypot(ex, ey)
    if length == 0:
        return math.hypot(point[0] - start[0], point[1] - start[1])
    return abs(ex * (start[1] - point[1]) - (start[0] - point[0]) * ey) / length


def simplify(points, tolerance=SIMPLIFY):
    """Douglas-Peucker on a closed ring, split at its point farthest from the first."""
    if len(points) <= 3:
        return points
    far = max(
        range(1, len(points)),
        key=lambda index: math.hypot(points[index][0] - points[0][0], points[index][1] - points[0][1]),
    )
    chains = (points[: far + 1], points[far:] + points[:1])
    kept = []
    for chain in chains:
        stack = [(0, len(chain) - 1)]
        inside = [False] * len(chain)
        inside[0] = inside[-1] = True
        while stack:
            start, end = stack.pop()
            if end <= start + 1:
                continue
            worst, index = -1.0, start
            for point in range(start + 1, end):
                distance = apart(chain[point], chain[start], chain[end])
                if distance > worst:
                    worst, index = distance, point
            if worst > tolerance:
                inside[index] = True
                stack.extend(((start, index), (index, end)))
        kept.append([chain[index] for index, keep in enumerate(inside) if keep][:-1])
    return kept[0] + kept[1]


def uv(point, rectangle):
    """A grid corner in the zone's map coordinates, clipped to the map's own rectangle."""
    xmin, xmax, ymin, ymax = rectangle
    x, y = point[0] * CHUNK, point[1] * CHUNK
    return (
        min(1.0, max(0.0, (ymax - y) / (ymax - ymin))),
        min(1.0, max(0.0, (xmax - x) / (xmax - xmin))),
    )


def clip_ring(points, rectangle):
    """Clip a terrain-grid ring to the map rectangle before projecting it to UVs."""
    xmin, xmax, ymin, ymax = (value / CHUNK for value in rectangle)
    result = list(points)
    for axis, low, high in ((0, xmin, xmax), (1, ymin, ymax)):
        for bound, keep_low in ((low, True), (high, False)):
            if not result:
                return []
            clipped = []
            previous = result[-1]
            previous_inside = previous[axis] >= bound if keep_low else previous[axis] <= bound
            for current in result:
                current_inside = current[axis] >= bound if keep_low else current[axis] <= bound
                if current_inside != previous_inside:
                    fraction = (bound - previous[axis]) / (current[axis] - previous[axis])
                    clipped.append(
                        tuple(previous[index] + fraction * (current[index] - previous[index]) for index in (0, 1))
                    )
                if current_inside:
                    clipped.append(current)
                previous, previous_inside = current, current_inside
            result = clipped
    return result


def number(value):
    """Four decimals, without the trailing zeros Lua would only pad back."""
    text = f"{value:.4f}".rstrip("0").rstrip(".")
    return "0" if text in ("", "-0") else text


def ring_lines(points, indent):
    """One Lua ring, a flat list of coordinates, wrapped to the repository's 120-column style."""
    parts = [number(coordinate) for coordinate in points]
    rows, current = [], []
    for index, part in enumerate(parts):
        piece = part + ("," if index < len(parts) - 1 else "")
        if current and len(indent) + len(" ".join(current)) + 2 + len(piece) > 118:
            rows.append(" ".join(current))
            current = [piece]
        else:
            current.append(piece)
    rows.append(" ".join(current))
    if len(rows) == 1:
        return ["{ " + rows[0] + " },"]
    return ["{" + rows[0], *(f"\t{row}" for row in rows[1:-1]), f"\t{rows[-1]} }},"]


def render(zones):
    lines = [
        f"-- Generated by tools/gen_explore.py from WoW: Forever build {TERRAIN_BUILD}. Do not edit by hand.",
        "-- Terrain chunk areas from the client's ADT files at that build; bump TERRAIN_BUILD to retrace them.",
        "---@type string, LegacyForeverNamespace",
        "local _, ns = ...",
        "",
        # The rings are written by the generator's own wrapper; let StyLua keep them as they are.
        "-- stylua: ignore start",
        "ns.Explore = {",
        f'\tbuild = "{TERRAIN_BUILD}",',
        "\t-- Per zone uiMapID: its rectangle in yards and each exploration area's outline rings, keyed",
        "\t-- like Legacy's completion areas. A ring is a flat list of u, v pairs.",
        "\tzones = {",
    ]
    for zone, data in sorted(zones.items()):
        lines.append(f"\t\t[{zone}] = {{")
        lines.append(f"\t\t\twidth = {number(data['width'])},")
        lines.append(f"\t\t\theight = {number(data['height'])},")
        lines.append("\t\t\tareas = {")
        for key, rings in sorted(data["areas"].items()):
            lines.append(f"\t\t\t\t[{json.dumps(key)}] = {{")
            for ring in rings:
                lines.extend("\t\t\t\t\t" + line for line in ring_lines(ring, "\t\t\t\t\t"))
            lines.append("\t\t\t\t},")
        lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines.extend(["\t},", "}", "-- stylua: ignore end", ""])
    return "\n".join(lines)


def ancestry(tables):
    """AreaTable ID -> every ancestor including itself, validating the parent chain."""
    table = tables["AreaTable"]
    known = {}

    def chain(area):
        if area not in known:
            seen, walk, found = set(), area, {area}
            while table[walk]["ParentAreaID"]:
                walk = table[walk]["ParentAreaID"]
                if walk in seen or walk not in table:
                    raise ValueError(f"AreaTable {area}: broken parent chain")
                seen.add(walk)
                found.add(walk)
            known[area] = found
        return known[area]

    return chain


def zone_areas(tables, geography, completion):
    """Per zone, each completion area's overlay and the AreaTable IDs it owns."""
    by_zone_key = {}
    for overlay in tables["WorldMapOverlay"].values():
        if not (overlay["TextureWidth"] and overlay["TextureHeight"]):
            continue
        key = legacy.overlay_key(overlay)
        for zone in geography.by_art[overlay["UiMapArtID"]] - legacy.BATTLEGROUNDS - {2521}:
            if (zone, key) in by_zone_key:
                raise ValueError(f"WorldMapOverlay {overlay['ID']}: duplicate completion key {key} in UiMap {zone}")
            by_zone_key[zone, key] = overlay
    areas = {}
    for zone, categories in completion.items():
        entries = {}
        for area in categories["areas"]:
            key = area.get("key")
            if key is None:
                continue
            overlay = by_zone_key.get((zone, key))
            if overlay is None:
                raise ValueError(f"UiMap {zone}: completion area {key} has no current-art overlay")
            entries[key] = legacy.overlay_areas(overlay)
        areas[zone] = entries
    return areas


def regions(tables, zones):
    """Each zone's world rectangle (min X, max X, min Y, max Y) from its UiMapAssignment rows."""
    found = {}
    for row in tables["UiMapAssignment"].values():
        if row["WMODoodadPlacementID"] or row["WMOGroupID"] or row["UiMapID"] not in zones:
            continue
        rectangle = (row["Region_0"], row["Region_3"], row["Region_1"], row["Region_4"])
        xmin, xmax, ymin, ymax = rectangle
        if xmax <= xmin or ymax <= ymin:
            raise ValueError(f"UiMapAssignment {row['ID']}: inverted world rectangle")
        zone = row["UiMapID"]
        if zone in found and found[zone] != rectangle:
            raise ValueError(f"UiMap {zone}: conflicting map rectangles")
        found[zone] = rectangle
    missing = set(zones) - found.keys()
    if missing:
        raise ValueError(f"UiMap {sorted(missing)}: no world rectangle")
    return found


def map_rows(offline):
    """Map ID -> (directory, WDT FileDataID), which tools/db2.py cannot keep because Directory is a string."""
    rows = wago.db2_rows(
        "Map",
        TERRAIN_BUILD,
        ROOT / "tools" / ".cache",
        user_agent=DB2_USER_AGENT,
        ints=("ID", "WdtFileDataID"),
        required=("ID", "Directory", "MapName_lang", "WdtFileDataID"),
        offline=offline,
    )
    maps = {}
    for row in rows:
        if row["ID"] < 0:
            raise ValueError(f"Map {row['ID']}: negative ID")
        if row["Directory"] and row["WdtFileDataID"]:
            maps[row["ID"]] = (row["Directory"], row["WdtFileDataID"])
    return maps


def zone_maps(tables, zones):
    """Each zone's Map ID, requiring the zone's assignment rows to agree."""
    maps = {}
    for zone in zones:
        found = {
            row["MapID"]
            for row in tables["UiMapAssignment"].values()
            if row["UiMapID"] == zone and not (row["WMODoodadPlacementID"] or row["WMOGroupID"])
        }
        if len(found) != 1:
            raise ValueError(f"UiMap {zone}: ambiguous map {sorted(found)}")
        maps[zone] = next(iter(found))
    return maps


def outlines(tables, completion, source, workers):
    """Per zone, the map rectangle and every area's outline rings, downloading the tiles they need."""
    geography = legacy.Geography(tables)
    areas = zone_areas(tables, geography, completion)
    rectangles = regions(tables, areas)
    maps = map_rows(source.offline)
    chain = ancestry(tables)
    zone_map = zone_maps(tables, areas)

    # One WDT per map, then the tiles those zones' rectangles touch. The WDT names each tile's ADT, so
    # there is no file-list request and no file list to cap.
    maps_wdt = {}
    tiles = {}
    for map_id in sorted(set(zone_map.values())):
        if map_id not in maps:
            raise ValueError(f"Map {map_id}: no directory in the Map table")
        fdid = maps[map_id][1]
        maps_wdt[map_id] = wdt_tiles(
            source.fetch(f"{fdid}.wdt", CASC.format(fdid=fdid, build=TERRAIN_BUILD), wdt_tiles)
        )
    for zone, rectangle in sorted(rectangles.items()):
        if zone not in areas:
            continue
        map_id = zone_map[zone]
        for (x, y), fdid in tiles_for(rectangle, maps_wdt[map_id]).items():
            tiles[map_id, x, y] = fdid
    tasks = [
        (f"{fdid}.adt", CASC.format(fdid=fdid, build=TERRAIN_BUILD), chunk_cells)
        for (map_id, x, y), fdid in sorted(tiles.items())
    ]
    print(f"  {len(tasks)} terrain tiles for {len(areas)} zones", file=sys.stderr, flush=True)
    source.downloads(tasks, workers)

    # The chunk cells of every area, from every downloaded tile.
    cells_by_area = defaultdict(set)
    for fdid in sorted(tiles.values()):
        for area, cell_x, cell_y in chunk_cells(source.read(f"{fdid}.adt")):
            if area:
                cells_by_area[area].add((cell_x, cell_y))

    zones = {}
    counts = defaultdict(int)
    for zone, entries in sorted(areas.items()):
        xmin, xmax, ymin, ymax = rectangles[zone]
        drawn = {}
        for key, area_ids in sorted(entries.items()):
            cells = set()
            for area, area_cells in cells_by_area.items():
                if chain(area) & area_ids:
                    cells |= area_cells
            if not cells:
                counts["areas without terrain"] += 1
                print(f"  No terrain: UiMap {zone}, area {key}", file=sys.stderr)
                continue
            rings = []
            for ring in boundary_rings(cells):
                clipped = clip_ring(ring, rectangles[zone])
                if len(clipped) < 3:
                    continue
                points = simplify(chaikin([uv(point, rectangles[zone]) for point in clipped]))
                rounded = []
                for point in points:
                    corner = (round4(point[0]), round4(point[1]))
                    if not rounded or corner != rounded[-1]:
                        rounded.append(corner)
                if len(rounded) >= 3:
                    rings.append([coordinate for point in rounded for coordinate in point])
            if not rings:
                counts["areas without outline"] += 1
                print(f"  No outline on this map: UiMap {zone}, area {key}", file=sys.stderr)
                continue
            drawn[key] = rings
            counts["areas"] += 1
            counts["rings"] += len(rings)
            counts["points"] += sum(len(ring) // 2 for ring in rings)
        if drawn:
            zones[zone] = {"width": ymax - ymin, "height": xmax - xmin, "areas": drawn}
            counts["zones"] += 1
    return zones, counts


def round4(value):
    return math.floor(value * 10000 + 0.5) / 10000


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true", help="use the cached tiles only")
    parser.add_argument("--workers", type=int, default=12, help="tiles downloaded at once")
    args = parser.parse_args()
    tables = {
        name: db2(name, columns, TERRAIN_BUILD, ROOT / "tools" / ".cache", offline=args.offline)
        for name, columns in legacy.SCHEMAS.items()
    }
    _, _, _, completion, _, _, _ = legacy.generate(tables)
    source = Source(offline=args.offline)
    zones, counts = outlines(tables, completion, source, max(1, args.workers))
    atomic_write(OUTPUT, render(zones).encode("utf-8"))
    print(f"Terrain build {TERRAIN_BUILD}: {source.downloaded} files downloaded", file=sys.stderr)
    for key in ("zones", "areas", "rings", "points", "areas without terrain", "areas without outline"):
        print(f"  {key}: {counts[key]}", file=sys.stderr)
    print(f"Wrote {OUTPUT.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, struct.error) as error:
        sys.exit(f"error: {error}")
