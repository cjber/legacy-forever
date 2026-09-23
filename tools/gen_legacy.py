#!/usr/bin/env python3
"""Generate Legacy objectives and zone completion for a pinned Forever build (stdlib only)."""

import argparse
import csv
import io
import json
import math
import re
import sys
import tempfile
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path

BUILD = "1.60.1.69913"
SOURCE_DATE = "2026-09-21"
ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache"
OUTPUT = ROOT / "Data" / "Legacy.lua"
LOCATIONS = ROOT / "tools" / "locations.json"
KINDS = {"explore", "instance", "kill", "quest", "reputation"}
BATTLEGROUNDS = {1459, 1460, 1461}
SPELUNKER = (62031, 62032, 62033, 64016, 64017, 64018)
COMPLETION_CATEGORIES = ("areas", "taxis", "dungeons", "raids", "legacy", "reputations")
CRITERIA_KINDS = {
    0: "kill",
    5: "level",
    7: "skill",
    8: "meta",
    27: "quest",
    43: "explore",
    78: "kill",
    165: "instance",
    243: "reputation",
    261: "rank",
}
SCHEMAS = {
    "TraitCurrencySource": ("TraitCurrencyID", "AchievementID"),
    "Achievement": ("Criteria_tree", "Shares_criteria", "Instance_ID", "Title_lang", "Description_lang"),
    "Criteria": ("Type", "Asset", "Modifier_tree_ID"),
    "ModifierTree": ("Parent", "Operator", "Amount", "Type", "Asset", "SecondaryAsset", "TertiaryAsset"),
    "CriteriaTree": ("Parent", "CriteriaID", "Description_lang", "Amount"),
    "WorldMapOverlay": (
        "UiMapArtID",
        "HitRectTop",
        "HitRectBottom",
        "HitRectLeft",
        "HitRectRight",
        "AreaID_0",
        "AreaID_1",
        "AreaID_2",
        "AreaID_3",
        "OffsetX",
        "OffsetY",
        "TextureWidth",
        "TextureHeight",
    ),
    "WorldMapOverlayTile": ("RowIndex", "ColIndex", "LayerIndex", "FileDataID", "WorldMapOverlayID"),
    "AreaTable": ("ParentAreaID", "AreaName_lang"),
    "UiMap": ("Type", "System", "Name_lang"),
    "TaxiNodes": ("Name_lang", "Flags", "CharacterBitNumber"),
    "Faction": ("Name_lang", "Description_lang", "ReputationIndex")
    + tuple(f"{field}_{index}" for index in range(4) for field in ("ReputationMax", "ReputationClassMask"))
    + tuple(f"ReputationRaceMasks{index}_0" for index in range(4)),
    "UiMapAssignment": (
        "UiMapID",
        "MapID",
        "AreaID",
        "WMODoodadPlacementID",
        "WMOGroupID",
        "UiMin_0",
        "UiMin_1",
        "UiMax_0",
        "UiMax_1",
        "Region_0",
        "Region_1",
        "Region_3",
        "Region_4",
    ),
    "UiMapXMapArt": ("UiMapID", "UiMapArtID", "PhaseID"),
    "UiMapArt": ("UiMapArtStyleID",),
    "UiMapArtStyleLayer": ("UiMapArtStyleID", "LayerIndex", "LayerWidth", "LayerHeight", "TileWidth", "TileHeight"),
    "Map": ("MapName_lang", "InstanceType", "CorpseMapID", "Corpse_0", "Corpse_1"),
    "DungeonEncounter": ("MapID", "Name_lang"),
    "QuestV2": (),
}


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + ".", delete=False) as f:
            temporary = Path(f.name)
            f.write(data)
        temporary.chmod(0o644)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def download(url, filename, refresh=False, offline=False):
    path = CACHE / filename
    if path.exists() and not refresh:
        data = path.read_bytes()
    else:
        if offline:
            raise ValueError(f"Missing cached source: {path}")
        request = urllib.request.Request(url, headers={"User-Agent": "LegacyHere/1.0"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
        content = data.decode("utf-8-sig")
        if not content.strip() or content.lstrip().startswith("<"):
            raise ValueError(f"Expected CSV, received empty data or HTML from {url}")
        atomic_write(path, data)
    content = data.decode("utf-8-sig")
    if not content.strip() or content.lstrip().startswith("<"):
        raise ValueError(f"Expected CSV, received empty data or HTML in {path}")
    return content


def db2(name, columns, **options):
    content = download(
        f"https://wago.tools/db2/{name}/csv?build={BUILD}",
        f"{name}-{BUILD}.csv",
        **options,
    )
    reader = csv.DictReader(io.StringIO(content), strict=True)
    fields = reader.fieldnames or []
    missing = {"ID", *columns} - set(fields)
    if missing or len(fields) != len(set(fields)):
        raise ValueError(f"{name}: missing/duplicate columns (missing: {sorted(missing)})")
    rows = {}
    for number, row in enumerate(reader, 2):
        if None in row or None in row.values():
            raise ValueError(f"{name}:{number}: malformed CSV row")
        # Only these projection fields are floating point; IDs stay exact integers.
        parsed = {}
        for key in ("ID", *columns):
            if key.endswith("_lang"):
                parsed[key] = row[key]
                continue
            try:
                value = float(row[key]) if key.startswith(("Region_", "UiMin_", "UiMax_", "Corpse_")) else int(row[key])
                if not math.isfinite(value):
                    raise ValueError
                parsed[key] = value
            except ValueError as error:
                raise ValueError(f"{name}:{number}: invalid {key}={row[key]!r}") from error
        key = parsed["ID"]
        if key < 0 or key in rows:
            raise ValueError(f"{name}:{number}: negative/duplicate ID {key}")
        rows[key] = parsed
    if not rows:
        raise ValueError(f"{name}: empty DB2 export for {BUILD}")
    return rows


def required(rows, key, label):
    if key not in rows:
        raise ValueError(f"{label}: missing referenced ID {key}")
    return rows[key]


class Achievements:
    def __init__(self, tables):
        self.achievements = tables["Achievement"]
        self.criteria = tables["Criteria"]
        self.trees = tables["CriteriaTree"]
        self.children = defaultdict(list)
        self.memo = {}
        for key, row in self.trees.items():
            self.children[row["Parent"]].append(key)

    def walk(self, key, active):
        if key in active:
            raise ValueError(f"CriteriaTree cycle at {key}")
        row = required(self.trees, key, "CriteriaTree")
        yield row
        for child in sorted(self.children[key]):
            yield from self.walk(child, active | {key})

    def tree(self, key):
        leaves = set()
        for row in self.walk(key, set()):
            if row["CriteriaID"]:
                required(self.criteria, row["CriteriaID"], f"CriteriaTree {row['ID']}")
                leaves.add(row["CriteriaID"])
        return leaves

    def leaves(self, achievement):
        if achievement not in self.memo:
            row = required(self.achievements, achievement, "Achievement")
            # Sharing semantics need a deliberate review if they enter this graph.
            if row["Shares_criteria"]:
                raise ValueError(f"Achievement {achievement}: unsupported Shares_criteria")
            leaves = self.tree(row["Criteria_tree"])
            if not leaves:
                raise ValueError(f"Achievement {achievement}: empty criteria tree")
            self.memo[achievement] = leaves
        return self.memo[achievement]

    def expand(self, achievement, reward, feeds, active):
        if achievement in active:
            raise ValueError(f"Achievement meta cycle at {achievement}")
        if achievement != reward:
            feeds[achievement].add(reward)
        for cid in sorted(self.leaves(achievement)):
            row = self.criteria[cid]
            if row["Type"] not in CRITERIA_KINDS:
                raise ValueError(f"Criteria {cid}: unsupported type {row['Type']}")
            if row["Type"] == 8:
                self.expand(row["Asset"], reward, feeds, active | {achievement})

    def objective_details(self, achievement, cid):
        owner = self.achievements[achievement]
        steps = {
            (row["Description_lang"], row["Amount"])
            for row in self.walk(owner["Criteria_tree"], set())
            if row["CriteriaID"] == cid
        }
        if len(steps) != 1:
            raise ValueError(
                f"Achievement {achievement}, criteria {cid}: missing/conflicting objective descriptions or amounts"
            )
        name, amount = next(iter(steps))
        # Live.WholeAchievement uses the description, then title, for single steps.
        if not name.strip() and len(self.leaves(achievement)) == 1:
            name = owner["Description_lang"] or owner["Title_lang"]
        if not name.strip() or amount <= 0:
            raise ValueError(f"Achievement {achievement}, criteria {cid}: empty objective name or invalid amount")
        return name, amount


def overlay_areas(overlay):
    return frozenset(overlay[f"AreaID_{index}"] for index in range(4) if overlay[f"AreaID_{index}"])


def overlay_key(overlay):
    return ":".join(str(overlay[k]) for k in ("OffsetX", "OffsetY", "TextureWidth", "TextureHeight"))


class Geography:
    def __init__(self, tables):
        self.tables = tables
        self.by_area = defaultdict(set)
        self.by_art = defaultdict(set)
        self.by_map = defaultdict(list)
        self.layers = {}
        self.tiles = defaultdict(list)
        self.current_overlays = defaultdict(list)
        self.zone_art = {}
        for row in tables["UiMapAssignment"].values():
            if not self.is_zone(row["UiMapID"]):
                continue
            # WMO-local coordinates cannot be treated as continent coordinates.
            if row["WMODoodadPlacementID"] or row["WMOGroupID"]:
                continue
            self.by_map[row["UiMapID"]].append(row)
            if row["AreaID"]:
                self.by_area[row["AreaID"]].add(row["UiMapID"])
        for row in tables["UiMapXMapArt"].values():
            if row["PhaseID"] == 0 and self.is_zone(row["UiMapID"]):
                if row["UiMapID"] in self.zone_art:
                    raise ValueError(f"UiMap {row['UiMapID']}: duplicate phase-0 art")
                self.zone_art[row["UiMapID"]] = row["UiMapArtID"]
                self.by_art[row["UiMapArtID"]].add(row["UiMapID"])
        for row in tables["WorldMapOverlay"].values():
            area_ids = overlay_areas(row)
            if area_ids and row["UiMapArtID"] in self.by_art:
                self.current_overlays[area_ids].append(row)
        for row in tables["UiMapArtStyleLayer"].values():
            if row["LayerIndex"] == 0:
                style = row["UiMapArtStyleID"]
                if style in self.layers:
                    raise ValueError(f"UiMapArtStyle {style}: duplicate base layer")
                self.layers[style] = row
        for row in tables["WorldMapOverlayTile"].values():
            self.tiles[row["WorldMapOverlayID"]].append(row)

    def base_layer(self, art_id):
        art = required(self.tables["UiMapArt"], art_id, "UiMapArt")
        layer = required(self.layers, art["UiMapArtStyleID"], f"UiMapArt {art_id} base layer")
        if any(layer[k] <= 0 for k in ("LayerWidth", "LayerHeight", "TileWidth", "TileHeight")):
            raise ValueError(f"UiMapArt {art_id}: invalid layer/tile size")
        return layer

    def overlay_tiles(self, overlay):
        layer = self.base_layer(overlay["UiMapArtID"])
        width, height = overlay["TextureWidth"], overlay["TextureHeight"]
        if width <= 0 or height <= 0:
            raise ValueError(f"WorldMapOverlay {overlay['ID']}: invalid texture size")
        wide = (width + layer["TileWidth"] - 1) // layer["TileWidth"]
        tall = (height + layer["TileHeight"] - 1) // layer["TileHeight"]
        source_tiles = self.tiles[overlay["ID"]]
        if not source_tiles:
            return None
        tiles = [tile for tile in source_tiles if tile["LayerIndex"] == 0]
        if len(tiles) != wide * tall:
            raise ValueError(
                f"WorldMapOverlay {overlay['ID']}: expected {wide * tall} layer-0 tiles "
                f"({wide} x {tall}), got {len(tiles)}"
            )
        cells = {}
        files = set()
        for tile in tiles:
            cell = tile["RowIndex"], tile["ColIndex"]
            file_id = tile["FileDataID"]
            if cell in cells or not (0 <= cell[0] < tall and 0 <= cell[1] < wide):
                raise ValueError(f"WorldMapOverlay {overlay['ID']}: duplicate/out-of-grid tile {cell}")
            if file_id <= 0 or file_id in files:
                raise ValueError(f"WorldMapOverlay {overlay['ID']}: missing/duplicate tile FileDataID {file_id}")
            cells[cell] = file_id
            files.add(file_id)
        # DB2 indices are zero-based; Lua's dense array is one-based.
        return [cells[row, col] for row in range(tall) for col in range(wide)]

    def is_zone(self, key):
        row = required(self.tables["UiMap"], key, "UiMap")
        return row["Type"] == 3 and row["System"] == 0

    def area_zones(self, key):
        seen = set()
        while key:
            if key in seen:
                raise ValueError(f"AreaTable parent cycle at {key}")
            seen.add(key)
            row = required(self.tables["AreaTable"], key, "AreaTable")
            if self.by_area[key]:
                return self.by_area[key]
            key = row["ParentAreaID"]
        return set()

    def explore(self, cid, counts):
        criterion = self.tables["Criteria"][cid]
        overlay = self.tables["WorldMapOverlay"].get(criterion["Asset"])
        if overlay is None:
            counts["missing overlay"] += 1
            return None
        areas = set()
        for index in range(4):
            areas.update(self.area_zones(overlay[f"AreaID_{index}"]))
        art_zones = self.by_art[overlay["UiMapArtID"]]
        # Art is authoritative for its coordinate space (e.g. Thunder Bluff's
        # reveal region on Mulgore). Never put those pixels on the city's map.
        candidates = art_zones or areas
        if len(candidates) != 1:
            counts["ambiguous/missing explore zone"] += 1
            return None
        zone = next(iter(candidates))
        entry = {"kind": "explore"}
        if not art_zones:
            counts["overlay art not on current zone"] += 1
            old_areas = overlay_areas(overlay)
            matches = self.current_overlays[old_areas]
            if not matches:
                # Old art sometimes drew several subzones as one overlay where current art
                # draws one each (Silithus): take the single current overlay on this zone
                # whose subzones the old one covered.
                matches = [
                    row
                    for area_ids, rows in self.current_overlays.items()
                    if area_ids and area_ids <= old_areas
                    for row in rows
                    if self.by_art[row["UiMapArtID"]] == {zone}
                ]
                if len(matches) == 1:
                    counts["current-art remap by contained subzone"] += 1
            if len(matches) != 1:
                counts["current-art remap missing" if not matches else "current-art remap ambiguous"] += 1
                return zone, entry
            replacement = matches[0]
            replacement_zones = self.by_art[replacement["UiMapArtID"]]
            if replacement_zones != areas or replacement_zones != {zone}:
                counts["current-art remap zone mismatch"] += 1
                return zone, entry
            # Keep the criterion's identity; only the pin's pixel source changes.
            overlay = replacement
            art_zones = replacement_zones
            counts["current-art overlay remaps"] += 1
        if art_zones:
            if areas and areas != art_zones:
                counts["art overrides area zone"] += 1
            layer = self.base_layer(overlay["UiMapArtID"])
            width, height = layer["LayerWidth"], layer["LayerHeight"]
            entry["key"] = overlay_key(overlay)
            top, bottom, left, right = (overlay[f"HitRect{k}"] for k in ("Top", "Bottom", "Left", "Right"))
            if top == bottom == left == right == 0:
                counts["empty hit rectangle"] += 1
            elif top > bottom or left > right:
                # Client data defect (Kharanos 5136 has top and bottom swapped): no pin
                # position, but the overlay's key and tiles still stand.
                counts["inverted hit rectangle"] += 1
                print(f"  Inverted hit rectangle: WorldMapOverlay {overlay['ID']}", file=sys.stderr)
            elif not (0 <= left < right <= width and 0 <= top < bottom <= height):
                raise ValueError(f"WorldMapOverlay {overlay['ID']}: invalid hit rectangle")
            else:
                entry.update(x=(left + right) / (2 * width), y=(top + bottom) / (2 * height))
        return zone, entry

    def entrances(self, instance):
        row = self.tables["Map"].get(instance)
        if row is None or row["InstanceType"] not in (1, 2) or row["CorpseMapID"] < 0:
            return {}
        px, py = row["Corpse_0"], row["Corpse_1"]
        if px == py == 0:
            return {}
        results = defaultdict(set)
        for zone, assignments in self.by_map.items():
            for assignment in assignments:
                if assignment["MapID"] != row["CorpseMapID"]:
                    continue
                r = assignment
                if not (r["Region_0"] <= px <= r["Region_3"] and r["Region_1"] <= py <= r["Region_4"]):
                    continue
                if r["Region_0"] == r["Region_3"] or r["Region_1"] == r["Region_4"]:
                    raise ValueError(f"UiMapAssignment {r['ID']}: zero-size world rectangle")
                # World +Y is left and +X is up; UI axes run right and down.
                x = r["UiMin_0"] + (r["Region_4"] - py) / (r["Region_4"] - r["Region_1"]) * (
                    r["UiMax_0"] - r["UiMin_0"]
                )
                y = r["UiMin_1"] + (r["Region_3"] - px) / (r["Region_3"] - r["Region_0"]) * (
                    r["UiMax_1"] - r["UiMin_1"]
                )
                if 0 <= x <= 1 and 0 <= y <= 1:
                    results[zone].add((x, y))
        return {zone: next(iter(points)) for zone, points in results.items() if len(points) == 1}

    def instance_location(self, instance, zone=None):
        entrances = self.entrances(instance)
        if zone is None:
            if len(entrances) != 1:
                return None
            zone = next(iter(entrances))
        elif entrances and zone not in entrances:
            raise ValueError(f"Map {instance}: curated zone {zone} excludes the client entrance")
        entry = {"kind": "instance", "instance": instance}
        if zone in entrances:
            entry["x"], entry["y"] = entrances[zone]
        return zone, entry


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"locations.json: duplicate key {key}")
        result[key] = value
    return result


def curated_locations(tables, geography):
    data = json.loads(LOCATIONS.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    sections = {"criteria", "taxiNodes", "dungeonWings", "questInstances", "compoundInstances", "reputations"}
    if not isinstance(data, dict) or set(data) != sections or any(not isinstance(data[k], dict) for k in sections):
        raise ValueError(f"locations.json must contain exactly these objects: {', '.join(sorted(sections))}")
    result = {}
    for key, row in data["criteria"].items():
        if not re.fullmatch(r"[1-9][0-9]*", key):
            raise ValueError(f"locations.json: invalid criteria ID {key}")
        cid = int(key)
        criterion = required(tables["Criteria"], cid, "locations.json criteria")
        fields = {"uiMap", "kind", "achievement", "type", "asset", "evidence"}
        if (
            not isinstance(row, dict)
            or not fields <= row.keys()
            or row.keys() - (fields | {"instance", "instanceType"})
        ):
            raise ValueError(f"locations.json {cid}: unexpected/missing fields")
        if any(type(row[k]) is not int for k in ("achievement", "type", "asset")) or (row["type"], row["asset"]) != (
            criterion["Type"],
            criterion["Asset"],
        ):
            raise ValueError(f"locations.json {cid}: stale criterion type/asset")
        owner = required(tables["Achievement"], row["achievement"], f"locations.json {cid} achievement")
        if type(row["uiMap"]) is not int or not geography.is_zone(row["uiMap"]):
            raise ValueError(f"locations.json {cid}: invalid zone uiMap")
        if not isinstance(row["kind"], str) or row["kind"] not in KINDS:
            raise ValueError(f"locations.json {cid}: invalid kind")
        expected = CRITERIA_KINDS.get(tables["Criteria"][cid]["Type"])
        if row["kind"] != expected and not (row["kind"] == "instance" and expected == "kill"):
            raise ValueError(f"locations.json {cid}: kind disagrees with criteria type")
        if not isinstance(row["evidence"], str) or not re.match(
            r"^Build [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:", row["evidence"]
        ):
            raise ValueError(f"locations.json {cid}: evidence must record its verification build")
        if any((row["kind"] == "instance") != (field in row) for field in ("instance", "instanceType")):
            raise ValueError(f"locations.json {cid}: only instance entries require an instance ID and type")
        if "instance" in row:
            if type(row["instance"]) is not int:
                raise ValueError(f"locations.json {cid}: invalid instance ID")
            instance = required(tables["Map"], row["instance"], "locations.json instance")
            if (
                type(row["instanceType"]) is not int
                or row["instanceType"] not in (1, 2)
                or instance["InstanceType"] != row["instanceType"]
            ):
                raise ValueError(f"locations.json {cid}: stale dungeon/raid instance type")
            if instance["InstanceType"] == 2 and owner["Instance_ID"] != row["instance"]:
                raise ValueError(f"locations.json {cid}: raid instance no longer verified by owning achievement")
        result[cid] = row
    completion = {}
    for section in ("taxiNodes", "dungeonWings", "questInstances", "compoundInstances", "reputations"):
        completion[section] = {}
        for key, row in data[section].items():
            label = f"locations.json {section} {key}"
            if not re.fullmatch(r"[1-9][0-9]*", key):
                raise ValueError(f"{label}: invalid ID")
            fields = {"uiMap", "name", "evidence"}
            optional = {"area", "instance"} if section in ("dungeonWings", "questInstances") else set()
            if section == "questInstances":
                fields |= {"instance", "encounter"}
            elif section == "compoundInstances":
                fields |= {"instance", "instanceName", "area", "boss", "alternatives", "refs"}
            elif section == "reputations":
                fields.add("area")
                optional.add("side")
            if not isinstance(row, dict) or not fields <= row.keys() or row.keys() - (fields | optional):
                raise ValueError(f"{label}: unexpected/missing fields")
            if type(row["uiMap"]) is not int or not geography.is_zone(row["uiMap"]) or row["uiMap"] in BATTLEGROUNDS:
                raise ValueError(f"{label}: invalid completion zone")
            if any(not isinstance(row[k], str) or not row[k].strip() for k in ("name", "evidence")):
                raise ValueError(f"{label}: name and evidence required")
            # Evidence records its review build; current rows below decide validity.
            if not re.match(r"^Build [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:", row["evidence"]):
                raise ValueError(f"{label}: evidence must record its verification build")
            if "area" in row:
                if type(row["area"]) is not int or geography.area_zones(row["area"]) != {row["uiMap"]}:
                    raise ValueError(f"{label}: area no longer identifies curated zone")
            if "instance" in row:
                if type(row["instance"]) is not int:
                    raise ValueError(f"{label}: invalid instance ID")
                instance = required(tables["Map"], row["instance"], label)
                entrances = geography.entrances(row["instance"])
                instance_types = (1,) if section in ("dungeonWings", "compoundInstances") else (1, 2)
                if instance["InstanceType"] not in instance_types or (entrances and row["uiMap"] not in entrances):
                    raise ValueError(f"{label}: invalid instance or conflicting client entrance")
            if section == "compoundInstances":
                if instance["MapName_lang"] != row["instanceName"] or not instance["MapName_lang"].strip():
                    raise ValueError(f"{label}: stale/empty instance name")
                if row["uiMap"] not in entrances:
                    raise ValueError(f"{label}: missing verified alternative entrance")
                validate_compound_tree(tables, int(key), row)
            elif section == "questInstances":
                required(tables["QuestV2"], int(key), label)
                if type(row["encounter"]) is not int:
                    raise ValueError(f"{label}: invalid encounter ID")
                encounter = required(tables["DungeonEncounter"], row["encounter"], label)
                if encounter["MapID"] != row["instance"] or encounter["Name_lang"] != row["name"]:
                    raise ValueError(f"{label}: stale encounter name/instance")
            elif section == "reputations":
                faction = required(tables["Faction"], int(key), label)
                if (
                    faction["Name_lang"] != row["name"]
                    or not faction["Description_lang"].strip()
                    or faction["ReputationIndex"] < 0
                ):
                    raise ValueError(f"{label}: stale faction name/description or non-reputation faction")
                if "side" in row and row["side"] not in ("Alliance", "Horde"):
                    raise ValueError(f"{label}: invalid faction side")
                # Check the original playable race bits against the client caps.
                # Curation separately reviews the normal zone-play route to Friendly.
                eligible = 0
                for index in range(4):
                    if faction[f"ReputationClassMask_{index}"] == 0 and faction[f"ReputationMax_{index}"] >= 3000:
                        eligible |= faction[f"ReputationRaceMasks{index}_0"] & 0xFFFFFFFF
                sides = {side for side, mask in (("Alliance", 0x4D), ("Horde", 0xB2)) if eligible & mask == mask}
                expected = {row["side"]} if "side" in row else {"Alliance", "Horde"}
                if sides != expected:
                    raise ValueError(f"{label}: Friendly eligibility disagrees with curated side")
            completion[section][int(key)] = row
    return result, completion


def validate_compound_tree(tables, root, fact):
    label = f"ModifierTree {root} compound instance"
    alternatives = fact["alternatives"]
    if (
        not isinstance(alternatives, dict)
        or len(alternatives) < 2
        or any(
            not re.fullmatch(r"[1-9][0-9]*", key) or type(boss) is not int or boss <= 0
            for key, boss in alternatives.items()
        )
        or len(set(alternatives.values())) != len(alternatives)
        or type(fact["boss"]) is not int
        or fact["boss"] not in alternatives.values()
    ):
        raise ValueError(f"{label}: invalid alternative creature leaves")
    expected = {
        root: dict(ID=root, Parent=0, Operator=8, Amount=1, Type=0, Asset=0, SecondaryAsset=0, TertiaryAsset=0),
        **{
            int(key): dict(
                ID=int(key), Parent=root, Operator=2, Amount=1, Type=4, Asset=boss, SecondaryAsset=0, TertiaryAsset=0
            )
            for key, boss in alternatives.items()
        },
    }
    if root in {int(key) for key in alternatives}:
        raise ValueError(f"{label}: root cannot be an alternative")
    for key, row in expected.items():
        if required(tables["ModifierTree"], key, label) != row:
            raise ValueError(f"{label}: changed OR root or creature leaf {key}")
    children = {key for key, row in tables["ModifierTree"].items() if row["Parent"] in expected}
    if children != set(expected) - {root}:
        raise ValueError(f"{label}: changed alternative children")


def compound_objectives(tables, graph, curated):
    objectives = {}
    for root, fact in curated.items():
        if not isinstance(fact["refs"], list) or not fact["refs"]:
            raise ValueError(f"ModifierTree {root}: compound references required")
        for ref in fact["refs"]:
            if not isinstance(ref, list) or len(ref) != 2 or any(type(value) is not int or value <= 0 for value in ref):
                raise ValueError(f"ModifierTree {root}: invalid compound reference")
            achievement, cid = ref
            criterion = required(tables["Criteria"], cid, "Compound criteria")
            if (
                achievement not in SPELUNKER
                or cid not in graph.leaves(achievement)
                or (criterion["Type"], criterion["Asset"], criterion["Modifier_tree_ID"]) != (78, 0, root)
                or graph.objective_details(achievement, cid) != (fact["name"], 1)
            ):
                raise ValueError(f"ModifierTree {root}: stale compound reference {ref}")
            if tuple(ref) in objectives:
                raise ValueError(f"ModifierTree {root}: duplicate compound reference {ref}")
            objectives[tuple(ref)] = fact
    return objectives


def group_objectives(tables, graph, refs, label):
    groups = {}
    seen = set()
    for ref in sorted(refs):
        if ref in seen:
            raise ValueError(f"{label}: duplicate reference {ref}")
        seen.add(ref)
        criterion = tables["Criteria"][ref[1]]
        name, amount = graph.objective_details(*ref)
        # Client objective identity and quantity, never display-name matching.
        key = criterion["Type"], criterion["Asset"], amount
        entry = groups.setdefault(key, {"name": name, "refs": []})
        if entry["name"] != name:
            raise ValueError(f"{label}, objective {key}: conflicting variant names")
        entry["refs"].append(ref)
    return sorted(groups.values(), key=lambda entry: (entry["name"], entry["refs"]))


def generate_completion(tables, geography, graph, curated, compounds, zones, counts):
    completion = defaultdict(lambda: {category: [] for category in COMPLETION_CATEGORIES})
    keys = defaultdict(set)
    for overlay in sorted(tables["WorldMapOverlay"].values(), key=lambda r: r["ID"]):
        for zone in sorted(geography.by_art[overlay["UiMapArtID"]] - BATTLEGROUNDS - {2521}):
            # A zero-size overlay never draws, so there is nothing on the map to reveal.
            if not (overlay["TextureWidth"] and overlay["TextureHeight"]):
                continue
            key = overlay_key(overlay)
            if key in keys[zone]:
                raise ValueError(f"WorldMapOverlay {overlay['ID']}: duplicate completion key {key} in UiMap {zone}")
            keys[zone].add(key)
            name = required(tables["AreaTable"], overlay["AreaID_0"], f"WorldMapOverlay {overlay['ID']}")[
                "AreaName_lang"
            ]
            if not name.strip():
                raise ValueError(f"WorldMapOverlay {overlay['ID']}: empty area name")
            tiles = geography.overlay_tiles(overlay)
            area = {"key": key, "name": name}
            # Blizzard's own hover target for the area (MapExplorationPinMixin's hitRect); absent when zero.
            hit = tuple(overlay[f"HitRect{side}"] for side in ("Left", "Top", "Right", "Bottom"))
            if hit[2] > hit[0] and hit[3] > hit[1]:
                area["hit"] = hit
            if tiles is None:
                counts["completion areas without tiles"] += 1
                print(
                    f"  Tile-less area: WorldMapOverlay {overlay['ID']}, UiMap {zone}, key {key} "
                    f"({name}; zero tile rows)",
                    file=sys.stderr,
                )
            else:
                area["tiles"] = tiles
                counts["completion tiles"] += len(tiles)
            completion[zone]["areas"].append(area)
            counts["completion areas"] += 1

    zone_names = defaultdict(set)
    for zone, row in tables["UiMap"].items():
        if geography.is_zone(zone):
            zone_names[row["Name_lang"]].add(zone)
    used_taxis = set()
    for node, row in sorted(tables["TaxiNodes"].items()):
        mask = row["Flags"] & 3
        name = row["Name_lang"]
        # CharacterBitNumber 0 = a special service (Nighthaven druid flights, the Eastern
        # Plaguelands tower hops) with no discovery bit, so no character ever learns it.
        if not mask or row["CharacterBitNumber"] == 0 or name.lower().startswith("zz"):
            continue
        suffix = name.rpartition(", ")[2] if ", " in name else ""
        candidates = zone_names.get(suffix, set())
        fact = curated["taxiNodes"].get(node)
        if fact:
            if fact["name"] != name or candidates == {fact["uiMap"]}:
                raise ValueError(f"TaxiNodes {node}: stale/redundant curated location")
            used_taxis.add(node)
            zone = fact["uiMap"]
        elif len(candidates) == 1:
            zone = next(iter(candidates))
        else:
            raise ValueError(f"TaxiNodes {node} ({name}): unassigned/ambiguous zone; add verified curation")
        if zone in BATTLEGROUNDS:
            continue
        faction = {1: "Alliance", 2: "Horde", 3: "Neutral"}[mask]
        # Listed under its zone, so the ", Zone" suffix would only repeat it.
        place = name.rpartition(", ")[0] or name
        completion[zone]["taxis"].append({"node": node, "faction": faction, "name": place})
        counts["completion taxis " + faction] += 1
    stale = curated["taxiNodes"].keys() - used_taxis
    if stale:
        raise ValueError(f"Curated taxi nodes no longer used: {sorted(stale)}")

    wings = {}
    seen_refs = set()
    used_compounds = set()
    for achievement in SPELUNKER:
        root = required(tables["Achievement"], achievement, "Spelunker")["Criteria_tree"]
        for step in graph.walk(root, set()):
            cid = step["CriteriaID"]
            if not cid:
                continue
            criterion = required(tables["Criteria"], cid, "Spelunker criteria")
            ref = achievement, cid
            if ref in seen_refs:
                raise ValueError(f"Spelunker: duplicate reference {ref}")
            seen_refs.add(ref)
            if ref in compounds:
                # Validated OR objectives get Legacy pins, never single-boss wings.
                used_compounds.add(ref)
                continue
            if criterion["Type"] != 0 or criterion["Asset"] <= 0 or step["Amount"] != 1:
                raise ValueError(f"Spelunker {cid}: expected a single-boss kill step")
            boss = criterion["Asset"]
            name = step["Description_lang"]
            wing = wings.setdefault(boss, {"name": name, "refs": []})
            if not name.strip() or wing["name"] != name:
                raise ValueError(f"Spelunker boss {boss}: empty/conflicting wing names")
            wing["refs"].append(ref)
    if used_compounds != compounds.keys():
        raise ValueError("Spelunker: stale compound-step references")
    stale = curated["dungeonWings"].keys() - wings.keys()
    if stale:
        raise ValueError(f"Curated dungeon bosses no longer in Spelunker: {sorted(stale)}")
    unplaced = []
    wing_names = set()
    for boss, wing in sorted(wings.items()):
        if wing["name"] in wing_names:
            raise ValueError(f"Spelunker: duplicate wing name {wing['name']}")
        wing_names.add(wing["name"])
        wing["refs"].sort()
        fact = curated["dungeonWings"].get(boss)
        if fact:
            if fact["name"] != wing["name"]:
                raise ValueError(f"Spelunker boss {boss}: stale curated wing name")
            completion[fact["uiMap"]]["dungeons"].append(wing)
            counts["completion wings placed"] += 1
        else:
            unplaced.append((boss, wing["name"]))
    counts["completion wings unplaced"] = len(unplaced)
    for zone, objectives in sorted(zones.items()):
        # Located Legacy objectives do not create completion maps by themselves.
        # In particular the compound RFC pin must not add Orgrimmar completion.
        if zone not in completion:
            continue
        dungeon_refs = {ref for wing in completion[zone]["dungeons"] for ref in wing["refs"]}
        raids = defaultdict(list)
        for objective in objectives:
            if objective["kind"] != "instance":
                continue
            instance = objective["instance"]
            if tables["Map"][instance]["InstanceType"] == 2:
                if zone not in geography.entrances(instance):
                    raise ValueError(f"Raid Map {instance}: missing verified entrance in UiMap {zone}")
                raids[instance].append((objective["achievement"], objective["criteria"]))
        raid_refs = set()
        raid_names = set()
        for instance, refs in sorted(raids.items()):
            name = tables["Map"][instance]["MapName_lang"]
            if not name.strip() or name in raid_names:
                raise ValueError(f"Raid Map {instance}: empty/duplicate raid name")
            raid_names.add(name)
            bosses = group_objectives(tables, graph, refs, f"Raid Map {instance}")
            completion[zone]["raids"].append({"name": name, "bosses": bosses})
            raid_refs.update(refs)
            counts["completion raids"] += 1
            counts["completion raid bosses"] += len(bosses)
            counts["completion raid refs"] += len(refs)
        if raid_refs & dungeon_refs:
            raise ValueError(f"UiMap {zone}: raid references also occur in dungeon wings")
        refs = [
            (objective["achievement"], objective["criteria"])
            for objective in objectives
            if objective["kind"] != "explore"
            and (objective["achievement"], objective["criteria"]) not in dungeon_refs | raid_refs
        ]
        for entry in group_objectives(tables, graph, refs, f"UiMap {zone} Legacy"):
            completion[zone]["legacy"].append(entry)
            counts["completion legacy entries"] += 1
            counts["completion legacy refs"] += len(entry["refs"])
            counts["completion legacy groups collapsed"] += len(entry["refs"]) > 1
            counts["completion legacy refs collapsed"] += len(entry["refs"]) - 1
    for faction, fact in sorted(curated["reputations"].items()):
        entry = {"faction": faction, "name": tables["Faction"][faction]["Name_lang"]}
        if "side" in fact:
            entry["side"] = fact["side"]
        completion[fact["uiMap"]]["reputations"].append(entry)
        counts["completion reputations"] += 1
        counts["completion reputations " + fact.get("side", "Neutral")] += 1
    for zone, entry in completion.items():
        art = required(geography.zone_art, zone, "Completion zone art")
        layer = geography.base_layer(art)
        entry.update(tileWidth=layer["TileWidth"], tileHeight=layer["TileHeight"])
    counts["completion zones"] = len(completion)
    return completion, unplaced


def generate(tables):
    graph = Achievements(tables)
    geography = Geography(tables)
    curated, completion_curated = curated_locations(tables, geography)
    compounds = compound_objectives(tables, graph, completion_curated["compoundInstances"])
    instance_zones = {}
    for fact in [
        *completion_curated["dungeonWings"].values(),
        *completion_curated["questInstances"].values(),
        *completion_curated["compoundInstances"].values(),
    ]:
        if "instance" in fact:
            instance, zone = fact["instance"], fact["uiMap"]
            if instance in instance_zones and instance_zones[instance] != zone:
                raise ValueError(f"Map {instance}: conflicting curated entrance zones")
            instance_zones[instance] = zone
    rewards = {r["AchievementID"] for r in tables["TraitCurrencySource"].values() if r["TraitCurrencyID"] == 4225}
    if not rewards or 0 in rewards:
        raise ValueError("TraitCurrencySource 4225: missing reward achievements")
    feeds = defaultdict(set)
    for reward in sorted(rewards):
        graph.expand(reward, reward, feeds, set())
    zones = defaultdict(list)
    counts = Counter(
        {
            "current-art overlay remaps": 0,
            "current-art remap missing": 0,
            "current-art remap ambiguous": 0,
            "current-art remap zone mismatch": 0,
        }
    )
    unresolved = Counter()
    used_curated = set()
    used_quests = set()
    used_compounds = set()
    explore_achievements = set()
    for achievement in sorted(rewards | feeds.keys()):
        for cid in sorted(graph.leaves(achievement)):
            criterion = tables["Criteria"][cid]
            kind = CRITERIA_KINDS[criterion["Type"]]
            if kind == "meta":
                if achievement in rewards:
                    counts["expanded reward meta"] += 1
                continue
            location = None
            instance_ids = set()
            compound = compounds.get((achievement, cid))
            if compound:
                used_compounds.add((achievement, cid))
                instance_ids.add(compound["instance"])
            if kind in ("kill", "instance"):
                instance = tables["Achievement"][achievement]["Instance_ID"]
                if instance > 0:
                    instance_ids.add(instance)
                if criterion["Type"] == 165:
                    encounter = tables["DungeonEncounter"].get(criterion["Asset"])
                    if encounter:
                        instance_ids.add(encounter["MapID"])
                if criterion["Type"] == 0:
                    # Reuse reviewed boss-ID facts, never match encounter names.
                    wing = completion_curated["dungeonWings"].get(criterion["Asset"])
                    if wing and "instance" in wing:
                        instance_ids.add(wing["instance"])
            if criterion["Type"] == 27:
                quest = completion_curated["questInstances"].get(criterion["Asset"])
                if quest:
                    used_quests.add(criterion["Asset"])
                    instance_ids.add(quest["instance"])
                    owner_instance = tables["Achievement"][achievement]["Instance_ID"]
                    if owner_instance > 0:
                        instance_ids.add(owner_instance)
            if len(instance_ids) > 1:
                raise ValueError(f"Achievement {achievement}, criteria {cid}: conflicting instance IDs")
            if kind == "explore":
                explore_achievements.add(achievement)
                location = geography.explore(cid, counts)
            elif instance_ids:
                instance = next(iter(instance_ids))
                location = geography.instance_location(instance, instance_zones.get(instance))
            if cid in curated:
                used_curated.add(cid)
                fact = curated[cid]
                if achievement != fact["achievement"]:
                    raise ValueError(f"Criteria {cid}: stale curated owning achievement")
                if location and (location[0] != fact["uiMap"] or location[1]["kind"] != fact["kind"]):
                    raise ValueError(f"Criteria {cid}: curated location conflicts with client data")
                if fact["kind"] == "explore":
                    # Curation may add a zone but can never supply pixel positions.
                    location = location or (fact["uiMap"], {"kind": "explore"})
                else:
                    entry = {"kind": fact["kind"]}
                    if "instance" in fact:
                        instance = fact["instance"]
                        if instance_ids and instance_ids != {instance}:
                            raise ValueError(f"Criteria {cid}: curated instance conflicts with client data")
                        _, entry = geography.instance_location(instance, fact["uiMap"])
                    location = fact["uiMap"], entry
            if location:
                zone, entry = location
                entry.update(achievement=achievement, criteria=cid)
                zones[zone].append(entry)
                counts[entry["kind"] + (" pinned" if "x" in entry else " unpinned")] += 1
            elif achievement in rewards:
                unresolved[kind] += 1
            else:
                counts["unresolved supporting " + kind] += 1
    if curated.keys() - used_curated:
        raise ValueError(f"Curated criteria no longer reachable from rewards: {sorted(curated.keys() - used_curated)}")
    stale_quests = completion_curated["questInstances"].keys() - used_quests
    if stale_quests:
        raise ValueError(f"Curated quests no longer reachable from rewards: {sorted(stale_quests)}")
    if compounds.keys() - used_compounds:
        raise ValueError(
            f"Curated compound references no longer reachable from rewards: {sorted(compounds.keys() - used_compounds)}"
        )
    if counts["explore pinned"] + counts["explore unpinned"] < 500:
        raise ValueError("Fewer than 500 exploration entries; refusing a likely broken join")
    counts["exploration achievements"] = len(explore_achievements)
    counts["curated criteria"] = len(used_curated)
    counts["curated instance quests"] = len(used_quests)
    counts["curated compound refs"] = len(used_compounds)
    completion, unplaced = generate_completion(tables, geography, graph, completion_curated, compounds, zones, counts)
    for zone, entries in sorted(zones.items()):
        keys = {area["key"] for area in completion.get(zone, {}).get("areas", [])}
        for entry in entries:
            if entry["kind"] != "explore":
                continue
            if entry.get("key") in keys:
                counts["explore area matched"] += 1
            else:
                entry.pop("key", None)
                counts["explore area unmatched"] += 1
                print(
                    f"  Unmatched explore area: UiMap {zone}, achievement {entry['achievement']}, "
                    f"criteria {entry['criteria']}",
                    file=sys.stderr,
                )
    return rewards, feeds, zones, completion, counts, unresolved, unplaced


def lua_string(value):
    return (
        '"'
        + "".join(
            "\\" + char if char in ('"', "\\") else f"\\{ord(char):03d}" if ord(char) < 32 else char for char in value
        )
        + '"'
    )


def render_entry(fields, depth, refs=()):
    indent = "\t" * depth
    compact = "{ " + ", ".join(fields) + " },"
    if len(compact) + depth * 4 <= 120:
        return [indent + compact]
    lines = [indent + "{"]
    for field in fields:
        if field.startswith("refs =") and len(field) + (depth + 1) * 4 + 1 > 120:
            lines.append(indent + "\trefs = {")
            lines.extend(indent + f"\t\t{{ {a}, {c} }}," for a, c in refs)
            lines.append(indent + "\t},")
        else:
            lines.append(indent + "\t" + field + ",")
    lines.append(indent + "},")
    return lines


def render(rewards, feeds, zones, completion):
    lines = [
        f"-- Generated by tools/gen_legacy.py from WoW: Forever build {BUILD}. Do not edit by hand.",
        f"-- Source snapshot: {SOURCE_DATE}; https://wago.tools/db2/ (pinned CSV exports).",
        "local _, ns = ...",
        "",
        "ns.Data = {",
        f'\tbuild = "{BUILD}",',
        "\t-- Reward-bearing Legacy challenges (both variant sets).",
        "\trewards = {",
    ]
    lines.extend(f"\t\t[{key}] = true," for key in sorted(rewards))
    lines.extend(["\t},", "\t-- Supporting achievement -> reward-bearing challenges it counts toward.", "\tfeeds = {"])
    for key, targets in sorted(feeds.items()):
        lines.append(f"\t\t[{key}] = {{ {', '.join(map(str, sorted(targets)))} }},")
    lines.extend(["\t},", "\t-- Location-bound objectives by zone uiMapID.", "\tzones = {"])
    for zone, entries in sorted(zones.items()):
        lines.append(f"\t\t[{zone}] = {{")
        for entry in sorted(entries, key=lambda e: (e["kind"], e["achievement"], e["criteria"])):
            fields = [
                f"achievement = {entry['achievement']}",
                f"criteria = {entry['criteria']}",
                f'kind = "{entry["kind"]}"',
            ]
            if "instance" in entry:
                fields.append(f"instance = {entry['instance']}")
            if "key" in entry:
                fields.append(f"key = {lua_string(entry['key'])}")
            if "x" in entry:
                fields.extend((f"x = {entry['x']:.3f}", f"y = {entry['y']:.3f}"))
            compact = "{ " + ", ".join(fields) + " },"
            if len(compact) + 3 * 4 <= 120:
                lines.append("\t\t\t" + compact)
            else:
                lines.append("\t\t\t{")
                lines.extend("\t\t\t\t" + field + "," for field in fields)
                lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines.extend(
        [
            "\t},",
            "\t-- Zone completion: areas, taxis, dungeon wings, raids, Legacy objectives, and reputations.",
            "\tcompletion = {",
        ]
    )
    for zone, categories in sorted(completion.items()):
        lines.append(f"\t\t[{zone}] = {{")
        lines.extend(f"\t\t\t{key} = {categories[key]}," for key in ("tileWidth", "tileHeight"))
        for category in COMPLETION_CATEGORIES:
            entries = categories[category]
            if not entries:
                lines.append(f"\t\t\t{category} = {{}},")
                continue
            lines.append(f"\t\t\t{category} = {{")
            order = {"areas": "key", "taxis": "node"}.get(category, "name")
            for entry in sorted(entries, key=lambda e: (e[order], e.get("refs", []), e.get("faction", 0))):
                if category == "raids":
                    lines.extend(
                        ["\t\t\t\t{", f"\t\t\t\t\tname = {lua_string(entry['name'])},", "\t\t\t\t\tbosses = {"]
                    )
                    for boss in entry["bosses"]:
                        refs = ", ".join(f"{{ {a}, {c} }}" for a, c in boss["refs"])
                        fields = [f"name = {lua_string(boss['name'])}", f"refs = {{ {refs} }}"]
                        lines.extend(render_entry(fields, 6, boss["refs"]))
                    lines.extend(["\t\t\t\t\t},", "\t\t\t\t},"])
                    continue
                elif category == "areas":
                    fields = [f"key = {lua_string(entry['key'])}", f"name = {lua_string(entry['name'])}"]
                    if "hit" in entry:
                        fields.append("hit = { " + ", ".join(map(str, entry["hit"])) + " }")
                    if "tiles" in entry:
                        tiles = ", ".join(map(str, entry["tiles"]))
                        fields.append(f"tiles = {{ {tiles} }}")
                elif category == "taxis":
                    fields = [
                        f"node = {entry['node']}",
                        f"faction = {lua_string(entry['faction'])}",
                        f"name = {lua_string(entry['name'])}",
                    ]
                elif category == "reputations":
                    fields = [f"faction = {entry['faction']}", f"name = {lua_string(entry['name'])}"]
                    if "side" in entry:
                        fields.append(f"side = {lua_string(entry['side'])}")
                else:
                    refs = ", ".join(f"{{ {a}, {c} }}" for a, c in entry["refs"])
                    fields = [f"name = {lua_string(entry['name'])}", f"refs = {{ {refs} }}"]
                # Match the repository's StyLua width without a formatter dependency.
                lines.extend(render_entry(fields, 4, entry.get("refs", ())))
            lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines.extend(["\t},", "}"])
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="redownload the pinned sources")
    mode.add_argument("--offline", action="store_true", help="use cached sources only")
    args = parser.parse_args()
    tables = {name: db2(name, columns, refresh=args.refresh, offline=args.offline) for name, columns in SCHEMAS.items()}
    rewards, feeds, zones, completion, counts, unresolved, unplaced = generate(tables)
    output = render(rewards, feeds, zones, completion)
    atomic_write(OUTPUT, output.encode("utf-8"))
    print(
        f"Build {BUILD} ({SOURCE_DATE}): {len(rewards)} rewards; {len(feeds)} supporting achievements; "
        f"{len(zones)} zones",
        file=sys.stderr,
    )
    for key, count in sorted(counts.items()):
        print(f"  {key}: {count}", file=sys.stderr)
    print(
        "  Unresolved direct reward criteria (achievement, criteria pairs; both variants; metas expanded):",
        file=sys.stderr,
    )
    for key in sorted(set(CRITERIA_KINDS.values()) - {"meta"}):
        print(f"    {key}: {unresolved[key]}", file=sys.stderr)
    for boss, name in unplaced:
        print(f"  Unplaced Spelunker wing: {name} (boss {boss}; no verified zone)", file=sys.stderr)
    print(f"Wrote {OUTPUT.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, csv.Error) as error:
        sys.exit(f"error: {error}")
