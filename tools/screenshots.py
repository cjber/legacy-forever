#!/usr/bin/env python3
"""Regenerate docs/screenshots/*.png as mocks drawn from the WoW: Forever client's own art and data.

No game client is involved: map tiles, atlases, fonts and achievement data come from wago.tools via
wowmock (the wow-mock-screenshots skill in cjber/skills). What the addon draws is reproduced here from
its Lua: the zone objectives, the menu, the continent badges, the zone completion corner and tracker section,
and the Legacy tracker, computed from Data/Legacy.lua and the client's achievement tables for one plausible character.

    python3 tools/screenshots.py            # WOWMOCK=/path/to/wow-mock-screenshots to override
"""

import math
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

WOWMOCK = Path(os.environ.get("WOWMOCK", Path.home() / ".claude" / "skills" / "wow-mock-screenshots"))
if not (WOWMOCK / "wowmock.py").exists():
    sys.exit(f"wowmock.py not found in {WOWMOCK}; clone cjber/skills or set WOWMOCK")
sys.path.insert(0, str(WOWMOCK))

from PIL import Image
from wowmock import (
    FONTS,
    MenuButton,
    MenuCheckbox,
    MenuDivider,
    MenuTitle,
    TrackerBlock,
    TrackerModule,
    Ui,
    atlas_markup,
    colored,
    context_menu,
    draw_overlay,
    map_art,
    map_overlays,
    objective_tracker,
    scene,
    world_map_frame,
)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "screenshots"

# --------------------------------------------------------------------------------------------- the data


def parse_lua_table(text):
    """A Lua table constructor (the generated Data/Legacy.lua) as Python: lists for array tables, dicts
    otherwise. Text after the closing brace is ignored."""
    tokens = re.findall(r'--[^\n]*|"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?|[A-Za-z_]\w*|[{}\[\]=,]', text)
    tokens = [t for t in tokens if not t.startswith("--")]
    position = 0

    def value():
        nonlocal position
        token = tokens[position]
        position += 1
        if token == "{":
            return table()
        if token.startswith('"'):
            return token[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        if token in ("true", "false"):
            return token == "true"
        return float(token) if "." in token else int(token)

    def table():
        nonlocal position
        items, keyed = [], {}
        while tokens[position] != "}":
            if tokens[position] == "[":
                key = tokens[position + 1]
                position += 4  # [ key ] =
                keyed[int(key) if key.lstrip("-").isdigit() else key.strip('"')] = value()
            elif tokens[position + 1] == "=":
                key = tokens[position]
                position += 2
                keyed[key] = value()
            else:
                items.append(value())
            if tokens[position] == ",":
                position += 1
        position += 1
        return keyed if keyed else items

    assert tokens[0] == "{", "expected a table constructor"
    position = 1
    return table()


def load_data():
    text = (ROOT / "Data" / "Legacy.lua").read_text()
    return parse_lua_table(text[text.index("{", text.index("ns.Data =")) :])


# --------------------------------------------------------------------------- the character, as Live sees it

ASHENVALE = 1440
KALIMDOR = 1414
# One plausible Alliance character: half of Ashenvale explored, the Astranaar flight path known, Onyxia
# down on the account (the old captures' account had that one done), Blackfathom Deeps not yet cleared.
EXPLORED = {
    "The Zoram Strand",
    "Maestra's Post",
    "Astranaar",
    "Thistlefur Village",
    "Lake Falathim",
    "The Shrine of Aessina",
    "Iris Lake",
    "The Ruins of Stardust",
    "Fire Scar Shrine",
}
FACTION = "Alliance"
KNOWN_TAXIS = {28}
COMPLETED_ACHIEVEMENTS = {684}
# The client shows this character one of Forever's two variant sets (Achievement.Flags).
VARIANT_FLAG = 0x08000000
# In the order they were ticked: Ashenvale's exploration and its dungeon from the map menu (Model.ZoneKey),
# then class levels from "No fixed location" (whole challenges).
TRACKED = ["845", "62032:1440", 62000, 61999, 61994]
EARN_ACHIEVEMENT = 8


@dataclass
class Progress:
    text: str
    completed: bool
    index: int
    type: int | None = None
    asset: int | None = None
    quantity: int = 0
    required: int | None = None


class Live:
    """Live.lua's reads, answered from the client's achievement tables for the character above."""

    def __init__(self, ui, data):
        self.ui, self.data = ui, data
        self.achievements = ui.table("Achievement")
        self.trees = ui.table("CriteriaTree")
        self.criteria_rows = ui.table("Criteria")
        self.categories = ui.table("Achievement_Category")
        self.children = {}
        for row in self.trees.values():
            self.children.setdefault(row["Parent"], []).append(row)
        zone = data["completion"][ASHENVALE]
        self.explored = {area["key"] for area in zone["areas"] if area["name"] in EXPLORED}
        assert len(self.explored) == len(EXPLORED), "an explored area name is not in the data"
        self.done_criteria = {
            entry["criteria"]
            for entry in data["zones"][ASHENVALE]
            if entry["kind"] == "explore" and entry["key"] in self.explored
        }
        self.cache = {}

    def visible(self):
        return {
            achievement
            for achievement in self.data["rewards"]
            if int(self.achievements[str(achievement)]["Flags"]) & VARIANT_FLAG
            and achievement not in COMPLETED_ACHIEVEMENTS
        }

    def name(self, achievement):
        return self.achievements[str(achievement)]["Title_lang"]

    def leaves(self, tree_id):
        """Criteria-bearing CriteriaTree rows under a tree, in the order the client lists them."""
        row = self.trees[tree_id]
        found = [row] if row["CriteriaID"] != "0" else []
        for child in sorted(self.children.get(tree_id, []), key=lambda r: (int(r["OrderIndex"]), int(r["ID"]))):
            found += self.leaves(child["ID"])
        return found

    def located(self, achievement):
        return [
            e["criteria"] for entries in self.data["zones"].values() for e in entries if e["achievement"] == achievement
        ]

    def criteria(self, achievement):
        if achievement not in self.cache:
            self.cache[achievement] = self.read_criteria(achievement)
        return self.cache[achievement]

    def read_criteria(self, achievement):
        row = self.achievements[str(achievement)]
        leaves = self.leaves(row["Criteria_tree"])
        completed = achievement in COMPLETED_ACHIEVEMENTS
        # A single step with no description of its own is the achievement itself: the game reports no
        # criteria, and Live.WholeAchievement files it under the placed criterion, or 0.
        if len(leaves) == 1 and not leaves[0]["Description_lang"]:
            text = row["Description_lang"] or row["Title_lang"]
            return {cid: Progress(text, completed, 1) for cid in self.located(achievement) or [0]}
        result = {}
        for index, leaf in enumerate(leaves, start=1):
            cid = int(leaf["CriteriaID"])
            criteria = self.criteria_rows[leaf["CriteriaID"]]
            kind, asset = int(criteria["Type"]), int(criteria["Asset"])
            done = (
                completed or cid in self.done_criteria or (kind == EARN_ACHIEVEMENT and asset in COMPLETED_ACHIEVEMENTS)
            )
            required = int(leaf["Amount"])
            result[cid] = Progress(
                leaf["Description_lang"], done, index, kind, asset, required if done else 0, required
            )
        return result

    def category(self, achievement):
        """GetCategoryInfo(GetAchievementCategory(id)): name and parent ID."""
        row = self.categories[self.achievements[str(achievement)]["Category"]]
        return row["Name_lang"], int(row["Parent"])

    def category_name(self, category_id):
        return self.categories[str(category_id)]["Name_lang"]

    def refs_done(self, refs):
        state = None
        for achievement, criteria_id in refs:
            progress = (self.criteria(achievement) or {}).get(criteria_id)
            if progress:
                if progress.completed:
                    return True
                state = False
        return state


# ------------------------------------------------------------------------------------- Model.lua, ported


def owning_challenge(data, achievement, visible):
    if achievement in visible:
        return achievement
    return next((reward for reward in data["feeds"].get(achievement, []) if reward in visible), None)


def zone_objectives(data, live, ui_map_id):
    groups, by_achievement = [], {}
    visible = live.visible()
    for entry in data["zones"].get(ui_map_id, []):
        challenge = owning_challenge(data, entry["achievement"], visible)
        progress = challenge and (live.criteria(entry["achievement"]) or {}).get(entry["criteria"])
        if progress and not progress.completed:
            group = by_achievement.get(entry["achievement"])
            if not group:
                group = {
                    "achievement": entry["achievement"],
                    "challenge": challenge,
                    "ui_map": ui_map_id,
                    "objectives": [],
                }
                by_achievement[entry["achievement"]] = group
                groups.append(group)
            group["objectives"].append({"entry": entry, "text": progress.text})
    return groups


def count_objectives(groups):
    return sum(len(group["objectives"]) for group in groups)


def unlocated(data, live):
    located = {entry["criteria"] for entries in data["zones"].values() for entry in entries}

    def open_count(achievement):
        count = 0
        for criteria_id, progress in (live.criteria(achievement) or {}).items():
            if not progress.completed and criteria_id not in located:
                if progress.type == EARN_ACHIEVEMENT and progress.asset in data["feeds"]:
                    count += open_count(progress.asset)
                else:
                    count += 1
        return count

    result = [{"challenge": c, "open": open_count(c)} for c in sorted(live.visible())]
    return [item for item in result if item["open"] > 0]


def step_line(criteria_id, progress, live):
    sub = progress.type == EARN_ACHIEVEMENT and live.criteria(progress.asset)
    if sub:
        detail, seen = f"{sum(step.completed for step in sub.values())}/{len(sub)}", f"a{progress.asset}"
    else:
        counted = progress.required and progress.required > 1
        detail, seen = (f"{progress.quantity}/{progress.required}" if counted else None), f"c{criteria_id}"
    return (f"{detail} {progress.text}" if detail else progress.text), seen


def tracker_lines(live, challenge):
    steps = sorted(
        ((cid, p) for cid, p in live.criteria(challenge).items() if not p.completed), key=lambda s: s[1].index
    )
    return [step_line(cid, progress, live) for cid, progress in steps]


def zone_key(group):
    if group["achievement"] != group["challenge"]:
        return str(group["achievement"])
    return f"{group['challenge']}:{group['ui_map']}"


def zone_lines(data, live, key):
    achievement, _, ui_map = key.partition(":")
    steps = live.criteria(int(achievement))
    if not ui_map:
        done = sum(step.completed for step in steps.values())
        return [] if done == len(steps) else [(f"{done}/{len(steps)} {live.name(int(achievement))}", f"a{achievement}")]
    return [
        step_line(entry["criteria"], steps[entry["criteria"]], live)
        for entry in data["zones"][int(ui_map)]
        if entry["achievement"] == int(achievement) and not steps[entry["criteria"]].completed
    ]


def tracked_blocks(data, live):
    """Model.TrackedBlocks: (challenge, lines) per visible challenge, zone shares first."""
    visible, blocks = live.visible(), {}
    for key in TRACKED:
        whole = isinstance(key, int)
        challenge = (
            (key if key in visible else None) if whole else owning_challenge(data, int(key.split(":")[0]), visible)
        )
        if challenge:
            block = blocks.setdefault(challenge, {"whole": False, "lines": []})
            if whole:
                block["whole"] = True
            else:
                block["lines"] += zone_lines(data, live, key)
    result = []
    for challenge, block in blocks.items():
        seen = {s for _, s in block["lines"]}
        if block["whole"]:
            block["lines"] += [line for line in tracker_lines(live, challenge) if line[1] not in seen]
        if block["whole"] or block["lines"]:
            result.append((challenge, [text for text, _ in block["lines"]]))
    return result


CATEGORIES = ("areas", "taxis", "dungeons", "raids", "legacy", "reputations")
# Completion.lua's COUNTED_BY_DEFAULT: a new player counts only the Legacy categories.
COUNTED = {"areas", "dungeons", "raids", "legacy"}


def completion_category(items, state):
    if not items:
        return None
    category = {"done": 0, "total": 0, "pending": 0}
    for item in items:
        done = state(item)
        if done is None:
            category["pending"] += 1
        else:
            category["total"] += 1
            category["done"] += 1 if done else 0
    category["complete"] = category["done"] == category["total"] and category["pending"] == 0
    return category if category["total"] > 0 or category["pending"] > 0 else None


def zone_completion(live, zone):
    def own(items, key):
        return [i for i in items if i.get(key) in (None, "Neutral", FACTION)]

    def raids(raid):
        return all(live.refs_done(boss["refs"]) for boss in raid["bosses"])

    result = {
        "areas": completion_category(zone["areas"], lambda area: area["key"] in live.explored),
        "taxis": completion_category(own(zone["taxis"], "faction"), lambda taxi: taxi["node"] in KNOWN_TAXIS),
        "dungeons": completion_category(zone["dungeons"], lambda wing: live.refs_done(wing["refs"])),
        "raids": completion_category(zone["raids"], raids),
        "legacy": completion_category(zone["legacy"], lambda objective: live.refs_done(objective["refs"])),
        "reputations": completion_category(own(zone["reputations"], "side"), lambda rep: False),
    }
    for key in CATEGORIES:
        if key not in COUNTED:
            result[key] = None
    counted = [result[key] for key in CATEGORIES if result[key]]
    done, total = sum(c["done"] for c in counted), sum(c["total"] for c in counted)
    complete = done == total and not any(c["pending"] for c in counted)
    percent = math.floor(100 * done / total)
    result.update(done=done, total=total, complete=complete, percent=percent if complete else min(percent, 99))
    return result


# ------------------------------------------------------------------------------ Completion.lua, as text

ICONS = {
    "areas": ("islands-queue-prop-compass", 1),
    "taxis": ("flightmaster", 1),
    "dungeons": ("dungeon", 1),
    "raids": ("raid", 1),
    "legacy": ("UI-Legacy-Points-icon-c60", 50 / 73),
    "reputations": ("Interface\\Icons\\Achievement_Reputation_01", None),
}
LABELS = {
    "areas": "Areas explored",
    "taxis": "Flight paths",
    "dungeons": "Dungeons",
    "raids": "Raids",
    "legacy": "Legacy objectives",
    "reputations": "Reputations (Friendly)",
}
POINTS_ICON = "UI-Legacy-Points-icon-c60"
WHITE = (1, 1, 1)


def icon(key, size):
    name, aspect = ICONS[key]
    if aspect is None:
        return f"|T{name}:{size}:{size}:0:0:64:64:5:59:5:59|t"
    return atlas_markup(name, math.floor(size * aspect + 0.5), size)


def counts_text(ui, result, size):
    green, white = ui.global_color("GREEN_FONT_COLOR"), WHITE
    parts = []
    for key in CATEGORIES:
        category = result[key]
        if category:
            text = f"{category['done']}/{category['total']}"
            parts.append(f"{icon(key, size)} {colored(text, green if category['complete'] else white)}")
    return "   ".join(parts)


# ------------------------------------------------------------------------------------------ the menus


def challenge_text(name, count):
    return f"{name} |cffffffff({count})|r"


def unlocated_tree(live, data):
    """AddUnlocated's grouping: [(top name, [(sub name, items)], items)] in first-appearance order."""
    tops = {}
    for item in unlocated(data, live):
        name, parent = live.category(item["challenge"])
        if parent > 0:
            top = tops.setdefault(live.category_name(parent), {"subs": {}, "items": []})
            top["subs"].setdefault(name, []).append(item)
        else:
            tops.setdefault(name, {"subs": {}, "items": []})["items"].append(item)
    return tops


def main_menu(live, data, hover=None):
    groups = zone_objectives(data, live, ASHENVALE)
    entries = [MenuTitle("Ashenvale")]
    for group in groups:
        explore = group["objectives"][0]["entry"]["kind"] == "explore"
        mark = icon("areas", 14) if explore else atlas_markup(POINTS_ICON, 10, 14)
        text = challenge_text(f"{mark} {live.name(group['achievement'])}", len(group["objectives"]))
        entries.append(MenuCheckbox(text, zone_key(group) in TRACKED))
    open_total = len(unlocated(data, live))
    entries += [
        MenuDivider(),
        MenuCheckbox("Show undiscovered areas", True),
        MenuButton(f"No fixed location |cffffffff({open_total})|r", True, hover == "unlocated"),
        MenuDivider(),
        MenuTitle("Zone completion"),
        MenuCheckbox("In the objective tracker", True),
        MenuCheckbox("On the world map", True),
        MenuButton("What counts", True),
        MenuDivider(),
        MenuButton("Open the Legacy panel"),
    ]
    return entries, groups


# ------------------------------------------------------------------------------------------ the scenes


def world_map(ui, data, live):
    """The world map on Ashenvale with the addon's shading, pin, corner and button drawn in."""
    zone = data["completion"][ASHENVALE]
    art = map_art(ui, ASHENVALE)
    # Blizzard's exploration pin: the explored overlays at full colour.
    for overlay in map_overlays(ui, ASHENVALE):
        if overlay.key in live.explored:
            draw_overlay(ui, art, overlay.offset_x, overlay.offset_y, overlay.width, overlay.height, overlay.tiles)
    # LegacyHereAreaPinMixin: every undiscovered area's tiles, black at AREA_ALPHA.
    for area in zone["areas"]:
        if area["key"] not in live.explored:
            x, y, w, h = (int(n) for n in area["key"].split(":"))
            draw_overlay(ui, art, x, y, w, h, area["tiles"], (0, 0, 0, 0.25), zone["tileWidth"])
    canvas, rects = world_map_frame(ui, art, ("World", "Kalimdor", "Ashenvale"), arrows=("Kalimdor", "Ashenvale"))
    mx, my, mw, mh = rects["map"]
    groups = zone_objectives(data, live, ASHENVALE)
    for group in groups:
        for objective in group["objectives"]:
            entry = objective["entry"]
            if entry["kind"] != "explore" and "x" in entry:
                pin_x, pin_y = mx + entry["x"] * mw, my + entry["y"] * mh
                canvas.draw(ui.atlas(POINTS_ICON), pin_x - 7, pin_y - 10, 14, 20)
    completion_corner(ui, canvas, rects, live, zone)
    button = map_button(ui, canvas, rects, count_objectives(groups))
    return canvas, button


def completion_corner(ui, canvas, rects, live, zone):
    """LegacyHereZoneOverlayTemplate at the canvas container's TOPLEFT (44, -18)."""
    result = zone_completion(live, zone)
    cx, cy, _, _ = rects["container"]
    x, y = cx + 44, cy + 18
    title_font, counts_font = FONTS["GameFontNormalLarge"], FONTS["GameFontHighlight"]
    title = f"Ashenvale  {result['percent']}%"
    counts = counts_text(ui, result, 16)
    width = max(canvas.text_width(title, title_font), canvas.text_width(counts, counts_font), 140)
    height = title_font.height + 4 + 2 + 6 + counts_font.height
    shade = Image.open(ROOT / "media" / "Shade.tga").convert("RGBA")
    canvas.draw(shade, x - 48, y - 22, width + 48 + 64, height + 44, (1, 1, 1, 0.6))
    canvas.text(x, y, title, title_font)
    bar_y = y + title_font.height + 4
    canvas.fill(x, bar_y, width, 2, (0, 0, 0, 0.45))
    canvas.fill(x, bar_y, width * result["percent"] / 100, 2, ui.global_color("NORMAL_FONT_COLOR"))
    canvas.text(x, y + title_font.height + 12, counts, counts_font)


def map_button(ui, canvas, rects, count):
    """LegacyHereMapButtonTemplate at the canvas container's TOPRIGHT (-4, -2): nothing of Blizzard's
    sits in that column on Forever (the tracking options button moves beside the NavBar)."""
    cx, cy, cw, _ = rects["container"]
    x, y = cx + cw - 4 - 32, cy + 2
    canvas.draw(ui.atlas(POINTS_ICON), x + 4, y - 1.5, 24, 35)
    font = FONTS["GameFontNormalSmall" if count >= 100 else "GameFontNormal"]
    canvas.text(x - 4, y + 16 + 3 - font.height / 2, str(count) if count else "", font, justify="CENTER", width=40)
    return x, y, 32, 32


def menu_at(ui, entries, right=None, top=None, left=None):
    """A context menu whose frame (not its shadowed backdrop) has its TOPRIGHT or TOPLEFT at a point."""
    menu, rects = context_menu(ui, entries)
    fx, fy, fw, _ = rects["menu"]
    origin_x = right - fw - fx if right is not None else left - fx
    origin_y = top - fy
    rows = [(origin_x + x, origin_y + y, w, h) for x, y, w, h in rects["rows"]]
    return menu, origin_x, origin_y, rows


def render_map(ui, data, live):
    canvas, button = world_map(ui, data, live)
    bx, by, bw, bh = button
    entries, _ = main_menu(live, data)
    menu, x, y, _ = menu_at(ui, entries, right=bx + bw, top=by + bh)
    return scene(ui, [(canvas, 0, 0), (menu, x, y)])


def render_menu(ui, data, live):
    """The menu's "No fixed location" cascade open down to one skill's challenges, over the map's corner."""
    canvas, button = world_map(ui, data, live)
    bx, by, bw, bh = button
    entries, _ = main_menu(live, data)
    layers = []
    menu, x, y, rows = menu_at(ui, entries, right=bx + bw, top=by + bh)
    layers.append((menu, x, y))
    tops = unlocated_tree(live, data)
    top_name = "Tradeskills"
    sub_name = next(iter(tops[top_name]["subs"]))
    parent_row = rows[
        next(i for i, e in enumerate(entries) if isinstance(e, MenuButton) and e.text.startswith("No fixed"))
    ]
    cascade = [
        [MenuButton(name, True) for name in tops],
        [MenuButton(name, True, name == sub_name) for name in tops[top_name]["subs"]]
        + [
            MenuCheckbox(challenge_text(live.name(i["challenge"]), i["open"]), i["challenge"] in TRACKED)
            for i in tops[top_name]["items"]
        ],
        [
            MenuCheckbox(challenge_text(live.name(i["challenge"]), i["open"]), i["challenge"] in TRACKED)
            for i in tops[top_name]["subs"][sub_name]
        ],
    ]
    opened = [top_name, sub_name]
    for level, entries_at in enumerate(cascade):
        rx, ry, rw, _ = parent_row
        menu, x, y, rows = menu_at(ui, entries_at, left=rx + rw, top=ry)
        layers.append((menu, x, y))
        if level < len(opened):
            parent_row = rows[next(i for i, e in enumerate(entries_at) if e.text == opened[level])]
    # A crop of the map's top-right corner, as a screenshot of that part of the screen would show it.
    crop_left, crop_top = bx - 330, 0
    right = max(x + menu.width for menu, x, _ in layers)
    frame = ui.canvas(canvas.width - crop_left, canvas.height - 150)
    frame.paste(canvas, -crop_left, -crop_top)
    shifted = [(frame, crop_left, crop_top)] + layers
    assert right > crop_left
    return scene(ui, shifted)


def zone_center(ui, zone, continent):
    """The centre of C_Map.GetMapRectOnMap(zone, continent): the zone's world rectangle from its UiMapAssignment,
    projected onto the continent's (world x north, y west, min at the southeast corner)."""

    def assignment(ui_map):
        whole = ("0", "0", "1", "1")
        rows = [
            r
            for r in ui.table("UiMapAssignment").values()
            if r["UiMapID"] == str(ui_map) and (r["UiMin_0"], r["UiMin_1"], r["UiMax_0"], r["UiMax_1"]) == whole
        ]
        row = min(rows, key=lambda r: (int(r["OrderIndex"]), int(r["ID"])))
        return {key: float(value) for key, value in row.items()}

    z, c = assignment(zone), assignment(continent)
    world_x, world_y = (z["Region_0"] + z["Region_3"]) / 2, (z["Region_1"] + z["Region_4"]) / 2
    return (
        (c["Region_4"] - world_y) / (c["Region_4"] - c["Region_1"]),
        (c["Region_3"] - world_x) / (c["Region_3"] - c["Region_0"]),
    )


def continent_zones(ui, data, live, continent):
    """Map.lua's ContinentZones: the centre of each zone with unfinished place-bound objectives, for its badge."""
    parents = ui.table("UiMap")
    zones = []
    for ui_map in data["zones"]:
        if parents[str(ui_map)]["ParentUiMapID"] != str(continent):
            continue
        groups = [g for g in zone_objectives(data, live, ui_map) if g["objectives"][0]["entry"]["kind"] != "explore"]
        if count_objectives(groups):
            zones.append(zone_center(ui, ui_map, continent))
    return zones


def zone_pin(ui, canvas, x, y):
    """LegacyHerePinTemplate centred on (x, y): the bare 14x20 icon; its count is only in the tooltip."""
    canvas.draw(ui.atlas(POINTS_ICON), x - 7, y - 10, 14, 20)


def render_continent(ui, data, live):
    """Kalimdor with a Legacy badge on each zone that still has dungeon objectives. The map button's count
    is 0 here (a continent places nothing itself), so it is drawn desaturated with no number."""
    art = map_art(ui, KALIMDOR)
    canvas, rects = world_map_frame(ui, art, ("World", "Kalimdor"), arrows=("Kalimdor",))
    mx, my, mw, mh = rects["map"]
    for nx, ny in continent_zones(ui, data, live, KALIMDOR):
        zone_pin(ui, canvas, mx + nx * mw, my + ny * mh)
    cx, cy, cw, _ = rects["container"]
    grey = ui.atlas(POINTS_ICON).image.convert("LA").convert("RGBA")
    canvas.draw(grey, cx + cw - 4 - 32 + 6, cy + 2 + 1.5, 20, 29)
    return scene(ui, [(canvas, 0, 0)])


def render_tracker(ui, data, live):
    zone = data["completion"][ASHENVALE]
    result = zone_completion(live, zone)
    legacy = []
    for challenge, lines in tracked_blocks(data, live):
        shown = lines[:5] + ([("...", False)] if len(lines) > 5 else [])
        legacy.append(TrackerBlock(live.name(challenge), shown))
    modules = [
        TrackerModule("Ashenvale", [TrackerBlock(counts_text(ui, result, 14))]),
        TrackerModule("Legacy", legacy),
    ]
    canvas, rects = objective_tracker(ui, modules)
    # The zone section's header: the percent left of the minimize button and a 2 px bar under both.
    hx, hy, hw, hh = rects["modules"][0]
    font = FONTS["ObjectiveTrackerHeaderFont"]
    minimize = ui.atlas("ui-questtrackerbutton-secondary-collapse")
    percent = f"{result['percent']}%"
    percent_right = hx + hw + 1 - minimize.width - 4
    text_top = hy + (hh - font.height) / 2
    canvas.text(percent_right - canvas.text_width(percent, font), text_top, percent, font)
    bar_y, bar_w = hy + hh - 1 - 2, percent_right - (hx + 7)
    canvas.fill(hx + 7, bar_y, bar_w, 2, (0, 0, 0, 0.45))
    canvas.fill(hx + 7, bar_y, bar_w * result["percent"] / 100, 2, ui.global_color("NORMAL_FONT_COLOR"))
    return scene(ui, [(canvas, 0, 0)])


def main():
    ui = Ui(scale=2)
    data = load_data()
    live = Live(ui, data)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, render in (
        ("map", render_map),
        ("menu", render_menu),
        ("continent", render_continent),
        ("tracker", render_tracker),
    ):
        render(ui, data, live).save(OUT / f"{name}.png")
        print(f"wrote {OUT / f'{name}.png'}")


if __name__ == "__main__":
    main()
