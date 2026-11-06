#!/usr/bin/env python3
"""Regenerate docs/screenshots/*.png and demo.gif as mocks drawn from the WoW: Forever client's own art and data.

No game client is involved: map tiles, atlases, fonts and achievement data come from wago.tools via
wowmock (the forever-core shared renderer). What the addon draws is reproduced here from
its Lua: the zone objectives, the menu, the continent badges, an unvisited zone, the zone completion corner and
tracker section, and the Legacy tracker, computed from Data/Legacy.lua and the client's achievement tables for one
plausible character.

    python3 tools/screenshots.py            # FOREVER_CORE=/path/to/forever-core to override
"""

import io
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

FOREVER_CORE = Path(os.environ.get("FOREVER_CORE", Path(__file__).resolve().parents[2] / "forever-core")).expanduser()
WOWMOCK = FOREVER_CORE / "tools" / "wowmock"
if not (WOWMOCK / "wowmock.py").is_file():
    sys.exit(f"wowmock.py not found in {WOWMOCK}; set FOREVER_CORE to the forever-core checkout")
sys.path.insert(0, str(WOWMOCK))

from legacy_render import COMPLETION_CATEGORIES, lua_string, lua_unquote
from PIL import Image
from wowmock import (
    FONTS,
    FRIZQT,
    Font,
    MenuButton,
    MenuCheckbox,
    MenuDivider,
    MenuTitle,
    TooltipLine,
    TrackerBlock,
    TrackerModule,
    Ui,
    Wago,
    atlas_markup,
    backdrop,
    colored,
    context_menu,
    draw_overlay,
    map_art,
    map_overlays,
    objective_tracker,
    scene,
    tooltip,
    world_map_frame,
)

UI_ART_BUILD = "1.60.1.70124"
ART_DB2 = frozenset(
    {"UiCanvas", "UiTextureAtlas", "UiTextureAtlasElement", "UiTextureAtlasElementSliceData", "UiTextureAtlasMember"}
)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "screenshots"


class SplitWago:
    """Keep generated data on its build while pinning UI art to the reviewed Forever art build."""

    def __init__(self, data, art):
        self.data = data
        self.art = art

    def db2(self, table):
        return (self.art if table in ART_DB2 else self.data).db2(table)

    def fdid(self, path):
        return self.art.fdid(path)

    def file(self, fdid):
        return self.art.file(fdid)


def make_ui(scale):
    data_build = re.search(r"build ([0-9.]+)", (ROOT / "Data" / "Legacy.lua").read_text()).group(1).rstrip(".")
    content = Ui(build=data_build, scale=scale)
    ui = Ui(build=data_build, scale=scale)
    ui.wago = SplitWago(ui.wago, Wago(UI_ART_BUILD))
    ui.content = content
    return ui


# GameFontNormalTiny: SystemFont_Tiny (Friz 9, no shadow) in gold; wowmock has no entry for it.
TINY = Font(FRIZQT, 9, FONTS["GameFontNormal"].color, None)

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
            return lua_unquote(token)
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
                keyed[int(key) if key.lstrip("-").isdigit() else lua_unquote(key)] = value()
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
FELWOOD = 1448
KALIMDOR = 1414
# One plausible Alliance character: half of Ashenvale explored, the Astranaar flight path known, Onyxia
# down on the account, Blackfathom Deeps not yet cleared.
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
    """Core/Live.lua's reads, answered from the client's achievement tables for the character above."""

    def __init__(self, ui, data, explored=EXPLORED):
        self.data = data
        self.achievements = ui.table("Achievement")
        self.trees = ui.table("CriteriaTree")
        self.criteria_rows = ui.table("Criteria")
        self.categories = ui.table("Achievement_Category")
        self.children = {}
        for row in self.trees.values():
            self.children.setdefault(row["Parent"], []).append(row)
        zone = data["completion"][ASHENVALE]
        self.explored = {area["key"] for area in zone["areas"] if area["name"] in explored}
        assert len(self.explored) == len(explored), "an explored area name is not in the data"
        self.done_criteria = {
            entry["criteria"]
            for entry in data["zones"][ASHENVALE]
            if entry["kind"] == "explore" and entry["key"] in self.explored
        }
        self.cache = {}
        self._model = None

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

    @property
    def model(self):
        if self._model is None:
            self._model = Model(self.data, self)
        return self._model


# --------------------------------------------------------------------------------- Core/Model.lua, run for real

# Core/Saved.lua's DEFAULTS.zoneCompletion count_* keys: a new player counts only the Legacy categories.
COUNTED = {"areas", "dungeons", "raids", "legacy"}


def lua_literal(value):
    """A Python value as a Lua table constructor: dicts keyed by int or str, lists as arrays."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, dict):
        items = (f"[{lua_literal(k)}] = {lua_literal(v)}" for k, v in value.items() if v is not None)
        return "{ " + ", ".join(items) + " }"
    return "{ " + ", ".join(lua_literal(v) for v in value) + " }"


class Model:
    """What Core/Model.lua makes of this character: tools/screenshots_model.lua loads the addon's Data/Legacy.lua and
    Core/Model.lua under LuaJIT and answers the scenes' questions, keeping the pictures tied to addon logic."""

    def __init__(self, data, live):
        achievements = set(data["rewards"]) | set(data["feeds"])
        achievements |= {entry["achievement"] for entries in data["zones"].values() for entry in entries}
        zones = [ASHENVALE, FELWOOD]
        achievements |= {
            ref[0]
            for ui_map in zones
            for category in ("dungeons", "legacy")
            for item in data["completion"][ui_map][category]
            for ref in item["refs"]
        }
        achievements |= {
            ref[0]
            for ui_map in zones
            for raid in data["completion"][ui_map]["raids"]
            for boss in raid["bosses"]
            for ref in boss["refs"]
        }
        criteria, pending = {}, sorted(achievements)
        while pending:
            achievement = pending.pop()
            if achievement in criteria or str(achievement) not in live.achievements:
                continue
            criteria[achievement] = {cid: vars(progress) for cid, progress in live.criteria(achievement).items()}
            pending += [p.asset for p in live.criteria(achievement).values() if p.type == EARN_ACHIEVEMENT]
        taxis = {taxi["node"]: taxi["node"] in KNOWN_TAXIS for z in zones for taxi in data["completion"][z]["taxis"]}
        character = {
            "visible": {achievement: True for achievement in live.visible()},
            "criteria": criteria,
            "names": {achievement: live.name(achievement) for achievement in criteria},
            "tracked": TRACKED,
            "zones": sorted(data["zones"]),
            "completion": zones,
            "explored": {key: True for key in live.explored},
            "taxis": taxis,
            "faction": FACTION,
            "counted": {key: True for key in COUNTED},
        }
        with tempfile.NamedTemporaryFile("w", suffix=".lua", encoding="utf-8") as source:
            source.write("return " + lua_literal(character) + "\n")
            source.flush()
            output = subprocess.run(
                ["luajit", str(ROOT / "tools" / "screenshots_model.lua"), source.name],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        answers = json.loads(output)
        self.objectives = {item["uiMapID"]: item for item in answers["objectives"]}
        self.completion = {item["uiMapID"]: item["result"] for item in answers["completion"]}
        self.unlocated = answers["unlocated"]
        self.tracked = answers["tracked"]

    def zone_objectives(self, ui_map):
        return self.objectives[ui_map]["groups"]

    def count(self, ui_map):
        return self.objectives[ui_map]["count"]


# ------------------------------------------------------------------------------ UI/Completion.lua, as text

ICONS = {
    "areas": "islands-queue-prop-compass",
    "taxis": "flightmaster",
    "dungeons": "dungeon",
    "raids": "raid",
    "legacy": "UI-Legacy-Points-icon-c60",
    "reputations": "Interface\\Icons\\Achievement_Reputation_01",
}
TEXTURES = {"reputations"}
POINTS_ICON = "UI-Legacy-Points-icon-c60"
WHITE = (1, 1, 1)


def fitted_markup(ui, name, size):
    """ns.Art.Markup: whole pixels keeping the atlas's shape within 2%, up to two pixels under `size`."""
    atlas = ui.atlas(name)
    aspect = atlas.width / atlas.height
    shape = min(aspect, 1 / aspect)
    long, short, best = size, size, math.inf
    for side in range(size, max(1, size - 2) - 1, -1):
        other = max(1, math.floor(side * shape + 0.5))
        off = abs(other / side / shape - 1)
        if off < best:
            long, short, best = side, other, off
        if off <= 0.02:
            break
    return atlas_markup(name, short, long) if aspect < 1 else atlas_markup(name, long, short)


def icon(ui, key, size):
    name = ICONS[key]
    if key in TEXTURES:
        return f"|T{name}:{size}:{size}:0:0:64:64:5:59:5:59|t"
    return fitted_markup(ui, name, size)


def counts_text(ui, result, size):
    green, white = ui.global_color("GREEN_FONT_COLOR"), WHITE
    parts = []
    for key in COMPLETION_CATEGORIES:
        category = result.get(key)
        if category:
            text = f"{category['done']}/{category['total']}"
            parts.append(f"{icon(ui, key, size)} {colored(text, green if category['complete'] else white)}")
    return "   ".join(parts)


# ------------------------------------------------------------------------------------------ the menus


def challenge_text(name, count):
    return f"{name} |cffffffff({count})|r"


def unlocated_tree(live):
    """AddUnlocated's grouping: {top name: {"subs": {sub name: items}, "items": items}} in first-appearance order."""
    tops = {}
    for item in live.model.unlocated:
        name, parent = live.category(item["challenge"])
        if parent > 0:
            top = tops.setdefault(live.category_name(parent), {"subs": {}, "items": []})
            top["subs"].setdefault(name, []).append(item)
        else:
            tops.setdefault(name, {"subs": {}, "items": []})["items"].append(item)
    return tops


def main_menu(ui, live):
    groups = live.model.zone_objectives(ASHENVALE)
    entries = [MenuTitle("Ashenvale")]
    for group in groups:
        explore = group["objectives"][0]["entry"]["kind"] == "explore"
        mark = icon(ui, "areas", 14) if explore else icon(ui, "legacy", 14)
        text = challenge_text(f"{mark} {live.name(group['achievement'])}", len(group["objectives"]))
        entries.append(MenuCheckbox(text, group["zoneKey"] in TRACKED))
    open_total = len(live.model.unlocated)
    entries += [
        MenuDivider(),
        MenuCheckbox("Show undiscovered areas", True),
        MenuCheckbox("Show dungeon and raid entrances", True),
        MenuButton(f"No fixed location |cffffffff({open_total})|r", True),
        MenuDivider(),
        MenuTitle("Zone completion"),
        MenuCheckbox("In the objective tracker", True),
        MenuCheckbox("On the world map", True),
        MenuButton("What counts", True),
        MenuDivider(),
        MenuButton("Flight-path leaderboard"),
        MenuCheckbox("Share flight-path totals with guild and group", True),
        MenuDivider(),
        MenuButton("Open the Legacy panel"),
        MenuDivider(),
        MenuCheckbox("What's new after an update", True),
        MenuCheckbox("Suggest my other Forever addons", True),
    ]
    return entries


# ------------------------------------------------------------------------------------------ the scenes


def world_map(ui, data, live, ui_map=ASHENVALE, collapsed=False, entrance=False):
    """The world map on a Kalimdor zone with the addon's shading, pins, corner and button drawn in."""
    zone = data["completion"][ui_map]
    name = ui.table("UiMap")[str(ui_map)]["Name_lang"]
    content = ui.content
    art = map_art(content, ui_map)
    # Blizzard's exploration pin: the explored overlays at full colour.
    for overlay in map_overlays(content, ui_map):
        if overlay.key in live.explored:
            draw_overlay(content, art, overlay.offset_x, overlay.offset_y, overlay.width, overlay.height, overlay.tiles)
    # AreaPin (UI/Map.lua): every undiscovered area's tiles, black at AREA_ALPHA.
    for area in zone["areas"]:
        if area["key"] not in live.explored:
            x, y, w, h = (int(n) for n in area["key"].split(":"))
            draw_overlay(content, art, x, y, w, h, area["tiles"], (0, 0, 0, 0.25), zone["tileWidth"])
    canvas, rects = world_map_frame(ui, art, ("World", "Kalimdor", name), arrows=("Kalimdor", name))
    mx, my, mw, mh = rects["map"]
    groups = live.model.zone_objectives(ui_map)
    for group in groups:
        for objective in group["objectives"]:
            entry = objective["entry"]
            if entry["kind"] != "explore" and "x" in entry:
                portal = ("Raid" if entry.get("raid") else "Dungeon") if "instance" in entry else None
                zone_pin(ui, canvas, mx + entry["x"] * mw, my + entry["y"] * mh, portal)
    completion_corner(ui, canvas, rects, live.model.completion[ui_map], name, collapsed)
    button = map_button(ui, canvas, rects, live.model.count(ui_map))
    if entrance:
        # AtlasLootClassic_DungeonsAndRaids' BFD fixture: entry level 15, recommended levels 24-32.
        # The companion owns the dataset; this one preview fixture is not shipped as runtime data.
        group, objective = next(
            (group, objective)
            for group in groups
            for objective in group["objectives"]
            if objective["entry"].get("instance") == 48
        )
        reward = next(
            int(row["Amount"])
            for row in ui.wago.db2("TraitCurrencySource")
            if row["TraitCurrencyID"] == "4225" and int(row["AchievementID"]) == group["challenge"]
        )
        panel = tooltip(
            ui,
            [
                TooltipLine(live.name(group["challenge"])),
                TooltipLine(f"Dungeon or raid: {objective['text']}"),
                # Level-24 preview: the lower end sets the whole range colour, using QuestDifficultyColors.
                TooltipLine(
                    f"Recommended levels: {colored('24-32', (1, 0.82, 0))} (AtlasLoot)",
                    ui.global_color("NORMAL_FONT_COLOR"),
                ),
                TooltipLine(
                    f"{fitted_markup(ui, POINTS_ICON, 14)} {reward} Legacy {'point' if reward == 1 else 'points'}",
                    ui.global_color("NORMAL_FONT_COLOR"),
                ),
                TooltipLine("Click to set a waypoint here.", ui.global_color("GREEN_FONT_COLOR")),
            ],
        )
        entry = objective["entry"]
        canvas.paste(panel, mx + entry["x"] * mw + 16, my + entry["y"] * mh)
    return canvas, button


def legacy_bar(ui, canvas, x, y, width, percent, color):
    """The Legacy panel's own bar (LegacyProgressBarTemplate at the reward track's sizes): a 12 recess, a 9 fill,
    and the frame's 26, which hangs 8 outside each end and 7 above and 10 below the fill. The frame and recess are
    nine-sliced, as the client sizes them; the fill is the status bar's texture, cropped to the percent."""
    canvas.draw(ui.atlas("Legacy-Progressbar-BG"), x + 8, y + 7, width - 16, 12)
    if percent > 0 and width > 16:
        fill = ui.canvas(width - 16, 9)
        fill.draw(ui.atlas("Legacy-Progressbar-Fill"), 0, 0, width - 16, 9, color)
        cropped = fill.image.crop((0, 0, canvas.px((width - 16) * percent / 100), fill.image.height))
        canvas.composite(cropped, canvas.px(x + 8), canvas.px(y + 7))
    canvas.draw(ui.atlas("Legacy-Progressbar-Frame"), x, y, width, 26)


def completion_corner(ui, canvas, rects, result, name, collapsed=False):
    """LegacyForeverZoneOverlayTemplate at the canvas container's TOPLEFT (44, -18); a click collapses it to the
    title and bar."""
    cx, cy, _, _ = rects["container"]
    x, y = cx + 44, cy + 18
    title_font, counts_font = FONTS["GameFontNormalLarge"], FONTS["GameFontHighlight"]
    title = f"{name}  {result['percent']}%"
    counts = counts_text(ui, result, 16)
    width = max(canvas.text_width(title, title_font), 140)
    height = title_font.height + 4 + 26
    if not collapsed:
        width = max(width, canvas.text_width(counts, counts_font))
        height += 6 + counts_font.height
    canvas.text(x, y, title, title_font)
    bar_y = y + title_font.height + 4
    color = ui.global_color("GREEN_FONT_COLOR" if result["complete"] else "NORMAL_FONT_COLOR")
    legacy_bar(ui, canvas, x, bar_y, width, result["percent"], color)
    if not collapsed:
        canvas.text(x, y + title_font.height + 4 + 26 + 6, counts, counts_font)


def map_button(ui, canvas, rects, count):
    """LegacyForeverMapButtonTemplate at the canvas container's TOPRIGHT (-4, -2): nothing of Blizzard's
    sits in that column on Forever (the tracking options button moves beside the NavBar)."""
    cx, cy, cw, _ = rects["container"]
    x, y = cx + cw - 4 - 32, cy + 2
    canvas.draw(ui.atlas(POINTS_ICON), x + 1, y, 30, 44)
    font = TINY if count >= 100 else FONTS["GameFontNormalSmall" if count >= 10 else "GameFontNormal"]
    canvas.text(x - 4, y + 22 + 4 - font.height / 2, str(count) if count else "", font, justify="CENTER", width=40)
    return x, y, 32, 44


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
    entries = main_menu(ui, live)
    menu, x, y, _ = menu_at(ui, entries, right=bx + bw, top=by + bh)
    return scene(ui, [(canvas, 0, 0), (menu, x, y)])


def render_entrance(ui, data, live):
    canvas, _ = world_map(ui, data, live, entrance=True)
    return scene(ui, [(canvas, 0, 0)])


def render_menu(ui, data, live):
    """The menu's "No fixed location" cascade open down to one skill's challenges, over the map's corner."""
    canvas, button = world_map(ui, data, live)
    bx, by, bw, bh = button
    entries = main_menu(ui, live)
    layers = []
    menu, x, y, rows = menu_at(ui, entries, right=bx + bw, top=by + bh)
    layers.append((menu, x, y))
    tops = unlocated_tree(live)
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
    # The whole frame: cropping into it sliced the frame's centred title mid-word, which no capture shows.
    crop_left, crop_top = 0, 0
    # Tall enough that the map, not the backdrop, sits behind the whole main menu.
    menu_bottom = layers[0][2] + layers[0][0].height
    frame = ui.canvas(canvas.width - crop_left, min(canvas.height, max(canvas.height - 150, menu_bottom + 40)))
    frame.paste(canvas, -crop_left, -crop_top)
    shifted = [(frame, crop_left, crop_top)] + layers
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
    """UI/MapContents.lua's badges: the centre of each zone with unfinished place-bound objectives, for its badge."""
    parents = ui.table("UiMap")
    zones = []
    for ui_map in data["zones"]:
        if parents[str(ui_map)]["ParentUiMapID"] != str(continent):
            continue
        groups = live.model.zone_objectives(ui_map)
        if any(g["objectives"][0]["entry"]["kind"] != "explore" for g in groups):
            zones.append(zone_center(ui, ui_map, continent))
    return zones


def zone_pin(ui, canvas, x, y, portal=None):
    """ObjectivePin:Layout (UI/Map.lua) centred on (x, y): the bare icon fitted in 14x20, or at an entrance the 32x32
    portal atlas with the icon fitted in 12x17 at its BOTTOMRIGHT offset (2, -2). A count is only ever in the tooltip.
    ns.Art.Fit keeps the 50x73 shield's shape, so the full height sets the width."""
    shield = ui.atlas(POINTS_ICON)
    if portal is None:
        w = 20 * shield.width / shield.height
        canvas.draw(shield, x - w / 2, y - 10, w, 20)
        return
    canvas.draw(ui.atlas(portal), x - 16, y - 16, 32, 32)
    w = 17 * shield.width / shield.height
    canvas.draw(shield, x + 18 - w, y + 18 - 17, w, 17)


def render_unvisited(ui, data, live):
    """Felwood, where this character has never been: every area shaded and the corner at 0%, its bar empty."""
    canvas, _ = world_map(ui, data, live, FELWOOD)
    return scene(ui, [(canvas, 0, 0)])


def render_continent(ui, data, live):
    """Kalimdor with a Legacy badge on each zone that still has dungeon objectives. The map button's count
    is 0 here (a continent places nothing itself), so it is drawn desaturated with no number."""
    art = map_art(ui.content, KALIMDOR)
    canvas, rects = world_map_frame(ui, art, ("World", "Kalimdor"), arrows=("Kalimdor",))
    mx, my, mw, mh = rects["map"]
    for nx, ny in continent_zones(ui, data, live, KALIMDOR):
        zone_pin(ui, canvas, mx + nx * mw, my + ny * mh)
    cx, cy, cw, _ = rects["container"]
    grey = ui.atlas(POINTS_ICON).image.convert("LA").convert("RGBA")
    canvas.draw(grey, cx + cw - 4 - 32 + 6, cy + 2 + 1.5, 20, 29)
    return scene(ui, [(canvas, 0, 0)])


def render_tracker(ui, data, live):
    """The shared column as the host lays it out: the game's All Objectives header, then Ashenvale's
    completion and the tracked challenges. The quests below are the native frame's own and are not part
    of this crop."""
    result = live.model.completion[ASHENVALE]
    legacy = []
    for block in live.model.tracked:
        # UI/Tracker.lua's line: the progress, then the step.
        lines = [f"{line['detail']} {line['text']}" if "detail" in line else line["text"] for line in block["lines"]]
        shown = lines[:5] + ([("...", False)] if len(lines) > 5 else [])
        legacy.append(TrackerBlock(live.name(block["challenge"]), shown))
    # The zone section's header on a canvas of its own: the Legacy bar and the counts sit in the row
    # UI/Completion.lua reserves below the header, so the tracked challenges start after that row.
    canvas, rects = objective_tracker(ui, [TrackerModule("Ashenvale", [])], container=True)
    hx, hy, hw, hh = rects["modules"][0]
    font, line_font = FONTS["ObjectiveTrackerHeaderFont"], FONTS["ObjectiveTrackerLineFont"]
    minimize = ui.atlas("ui-questtrackerbutton-secondary-collapse")
    percent = f"{result['percent']}%"
    percent_right = hx + hw + 1 - minimize.width - 4
    canvas.text(percent_right - canvas.text_width(percent, font), hy + (hh - font.height) / 2, percent, font)
    bar_canvas = ui.canvas(hw, 26)
    color = ui.global_color("GREEN_FONT_COLOR" if result["complete"] else "NORMAL_FONT_COLOR")
    legacy_bar(ui, bar_canvas, 0, 0, hw, result["percent"], color)
    counts = counts_text(ui, result, 14)
    counts_canvas = ui.canvas(max(1, canvas.text_width(counts, line_font)), line_font.height)
    counts_canvas.text(0, 0, counts, line_font, ui.global_color("OBJECTIVE_TRACKER_BLOCK_HEADER_COLOR"))
    tracked_canvas, _ = objective_tracker(ui, [TrackerModule("Legacy", legacy)], container=False)
    # Completion reserves its first line 34 under the header (2, the bar's 26, then 6) and the module counts
    # from headerHeight (25), then the host leaves 10 between sections.
    tracked_top = hy + 25 + line_font.height + 34 + 10
    return scene(
        ui,
        [
            (canvas, 0, 0),
            (bar_canvas, hx, hy + hh + 2),
            (counts_canvas, hx + 20, hy + hh + 34),
            (tracked_canvas, hx, tracked_top),
        ],
    )


# The demo's character explores two more areas east of Astranaar, then collapses the corner and opens the menu.
DEMO_DISCOVERED = ["Mystral Lake", "Raynewood Retreat"]
# (explored beyond EXPLORED, corner collapsed, menu open, seconds held): ten seconds in all.
DEMO_STEPS = [
    (0, False, False, 1.5),
    (1, False, False, 1.5),
    (2, False, False, 2.0),
    (2, True, False, 1.5),
    (2, False, False, 1.0),
    (2, False, True, 2.5),
]
DEMO_FPS = 10
DEMO_FADE = 3  # frames of cross-fade as an area's shading lifts; a click changes the map at once


def render_demo(data):
    """docs/screenshots/demo.gif: Ashenvale's shading lifting and its corner filling as areas are found, the corner
    collapsed with a click, then the Legacy menu. Rendered at 1x, the GIF's final size."""
    ui = make_ui(scale=1)
    steps = []
    for found, collapsed, menu, seconds in DEMO_STEPS:
        live = Live(ui, data, EXPLORED | set(DEMO_DISCOVERED[:found]))
        canvas, button = world_map(ui, data, live, collapsed=collapsed)
        layers = [(canvas, 0, 0)]
        if menu:
            bx, by, bw, bh = button
            layers.append(menu_at(ui, main_menu(ui, live), right=bx + bw, top=by + bh)[:3])
        steps.append((layers, seconds))
    # scene() frames each still to what it draws; the demo frames every step alike, to what any of them draws.
    boxes = [
        (x + left, y + top, x + right, y + bottom)
        for layers, _ in steps
        for canvas, x, y in layers
        for left, top, right, bottom in [canvas.image.getbbox()]
    ]
    left, top = min(b[0] for b in boxes) - 24, min(b[1] for b in boxes) - 24
    width, height = max(b[2] for b in boxes) + 24 - left, max(b[3] for b in boxes) + 24 - top
    stills = []
    for layers, seconds in steps:
        still = backdrop(ui, width, height)
        for canvas, x, y in layers:
            still.paste(canvas, x - left, y - top)
        stills.append((still.image.convert("RGB"), seconds))
    frames = []
    for index, (image, seconds) in enumerate(stills):
        held = round(seconds * DEMO_FPS)
        for step in range(held):
            fade = index > 0 and step < DEMO_FADE and DEMO_STEPS[index][0] != DEMO_STEPS[index - 1][0]
            frames.append(Image.blend(stills[index - 1][0], image, (step + 1) / (DEMO_FADE + 1)) if fade else image)
    # One shared palette from the first and last steps (map and menu) keeps text colours steady and repeated
    # encodes byte-identical.
    palette_source = Image.new("RGB", (width, height * 2))
    palette_source.paste(stills[0][0], (0, 0))
    palette_source.paste(stills[-1][0], (0, height))
    palette = palette_source.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    buffer = io.BytesIO()
    indexed[0].save(
        buffer, format="GIF", save_all=True, append_images=indexed[1:], duration=1000 // DEMO_FPS, loop=0, optimize=True
    )
    assert len(buffer.getvalue()) <= 2_000_000, "demo.gif is over the stores' 2 MB limit"
    return buffer.getvalue(), len(frames)


def main():
    ui = make_ui(scale=2)
    data = load_data()
    live = Live(ui, data)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, render in (
        ("map", render_map),
        ("entrance", render_entrance),
        ("menu", render_menu),
        ("continent", render_continent),
        ("unvisited", render_unvisited),
        ("tracker", render_tracker),
    ):
        render(ui, data, live).save(OUT / f"{name}.png")
        print(f"wrote {OUT / f'{name}.png'}")
    demo, count = render_demo(data)
    (OUT / "demo.gif").write_bytes(demo)
    print(f"wrote {OUT / 'demo.gif'} ({count} frames, {len(demo) // 1024} KB)")


if __name__ == "__main__":
    main()
