#!/usr/bin/env python3
"""Generate location-bound Legacy objectives for a pinned Forever build (stdlib only)."""

import argparse
from collections import Counter, defaultdict
import csv
import io
import json
import math
from pathlib import Path
import re
import sys
import tempfile
import urllib.error
import urllib.request


BUILD = "1.60.1.69913"
SOURCE_DATE = "2026-09-21"
ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache"
OUTPUT = ROOT / "Data" / "Legacy.lua"
LOCATIONS = ROOT / "tools" / "locations.json"
KINDS = {"explore", "instance", "kill", "quest", "reputation"}
CRITERIA_KINDS = {
    0: "kill", 5: "level", 7: "skill", 8: "meta", 27: "quest",
    43: "explore", 78: "kill", 165: "instance", 243: "reputation", 261: "rank",
}
SCHEMAS = {
    "TraitCurrencySource": ("TraitCurrencyID", "AchievementID"),
    "Achievement": ("Criteria_tree", "Shares_criteria", "Instance_ID"),
    "Criteria": ("Type", "Asset"),
    "CriteriaTree": ("Parent", "CriteriaID"),
    "WorldMapOverlay": (
        "UiMapArtID", "HitRectTop", "HitRectBottom", "HitRectLeft", "HitRectRight",
        "AreaID_0", "AreaID_1", "AreaID_2", "AreaID_3",
    ),
    "AreaTable": ("ParentAreaID",),
    "UiMap": ("Type", "System"),
    "UiMapAssignment": (
        "UiMapID", "MapID", "AreaID", "WMODoodadPlacementID", "WMOGroupID",
        "UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1",
        "Region_0", "Region_1", "Region_3", "Region_4",
    ),
    "UiMapXMapArt": ("UiMapID", "UiMapArtID", "PhaseID"),
    "UiMapArt": ("UiMapArtStyleID",),
    "UiMapArtStyleLayer": ("UiMapArtStyleID", "LayerIndex", "LayerWidth", "LayerHeight"),
    "Map": ("InstanceType", "CorpseMapID", "Corpse_0", "Corpse_1"),
    "DungeonEncounter": ("MapID",),
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
        f"{name}-{BUILD}.csv", **options,
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

    def tree(self, key, active):
        if key in active:
            raise ValueError(f"CriteriaTree cycle at {key}")
        row = required(self.trees, key, "CriteriaTree")
        leaves = set()
        if row["CriteriaID"]:
            required(self.criteria, row["CriteriaID"], f"CriteriaTree {key}")
            leaves.add(row["CriteriaID"])
        for child in self.children[key]:
            leaves.update(self.tree(child, active | {key}))
        return leaves

    def leaves(self, achievement):
        if achievement not in self.memo:
            row = required(self.achievements, achievement, "Achievement")
            # Sharing semantics need a deliberate review if they enter this graph.
            if row["Shares_criteria"]:
                raise ValueError(f"Achievement {achievement}: unsupported Shares_criteria")
            leaves = self.tree(row["Criteria_tree"], set())
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


def overlay_areas(overlay):
    return frozenset(overlay[f"AreaID_{index}"] for index in range(4) if overlay[f"AreaID_{index}"])


class Geography:
    def __init__(self, tables):
        self.tables = tables
        self.by_area = defaultdict(set)
        self.by_art = defaultdict(set)
        self.by_map = defaultdict(list)
        self.layers = defaultdict(set)
        self.current_art = {row["UiMapArtID"] for row in tables["UiMapXMapArt"].values()}
        self.current_overlays = defaultdict(list)
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
                self.by_art[row["UiMapArtID"]].add(row["UiMapID"])
        for row in tables["WorldMapOverlay"].values():
            area_ids = overlay_areas(row)
            if area_ids and row["UiMapArtID"] in self.current_art:
                self.current_overlays[area_ids].append(row)
        for row in tables["UiMapArtStyleLayer"].values():
            if row["LayerIndex"] == 0:
                self.layers[row["UiMapArtStyleID"]].add((row["LayerWidth"], row["LayerHeight"]))

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
            if overlay["UiMapArtID"] in self.current_art:
                return zone, entry
            matches = self.current_overlays[overlay_areas(overlay)]
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
            art = required(self.tables["UiMapArt"], overlay["UiMapArtID"], "UiMapArt")
            sizes = self.layers[art["UiMapArtStyleID"]]
            if len(sizes) != 1:
                raise ValueError(f"UiMapArt {art['ID']}: ambiguous/missing base layer size")
            width, height = next(iter(sizes))
            if width <= 0 or height <= 0:
                raise ValueError(f"UiMapArt {art['ID']}: invalid layer size")
            top, bottom, left, right = (overlay[f"HitRect{k}"] for k in ("Top", "Bottom", "Left", "Right"))
            if top == bottom == left == right == 0:
                counts["empty hit rectangle"] += 1
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
                x = r["UiMin_0"] + (r["Region_4"] - py) / (r["Region_4"] - r["Region_1"]) * (r["UiMax_0"] - r["UiMin_0"])
                y = r["UiMin_1"] + (r["Region_3"] - px) / (r["Region_3"] - r["Region_0"]) * (r["UiMax_1"] - r["UiMin_1"])
                if 0 <= x <= 1 and 0 <= y <= 1:
                    results[zone].add((x, y))
        return {zone: next(iter(points)) for zone, points in results.items() if len(points) == 1}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"locations.json: duplicate key {key}")
        result[key] = value
    return result


def curated_locations(tables, geography):
    data = json.loads(LOCATIONS.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    if not isinstance(data, dict) or set(data) != {"criteria"} or not isinstance(data["criteria"], dict):
        raise ValueError('locations.json must contain only a "criteria" object')
    result = {}
    for key, row in data["criteria"].items():
        if not re.fullmatch(r"[1-9][0-9]*", key):
            raise ValueError(f"locations.json: invalid criteria ID {key}")
        cid = int(key)
        required(tables["Criteria"], cid, "locations.json criteria")
        if not isinstance(row, dict) or not {"uiMap", "kind", "evidence"} <= row.keys() or row.keys() - {"uiMap", "kind", "instance", "evidence"}:
            raise ValueError(f"locations.json {cid}: unexpected/missing fields")
        if type(row["uiMap"]) is not int or not geography.is_zone(row["uiMap"]):
            raise ValueError(f"locations.json {cid}: invalid zone uiMap")
        if not isinstance(row["kind"], str) or row["kind"] not in KINDS:
            raise ValueError(f"locations.json {cid}: invalid kind")
        expected = CRITERIA_KINDS.get(tables["Criteria"][cid]["Type"])
        if row["kind"] != expected and not (row["kind"] == "instance" and expected == "kill"):
            raise ValueError(f"locations.json {cid}: kind disagrees with criteria type")
        if not isinstance(row["evidence"], str) or not row["evidence"].strip():
            raise ValueError(f"locations.json {cid}: evidence required")
        if (row["kind"] == "instance") != ("instance" in row):
            raise ValueError(f"locations.json {cid}: only instance entries require an instance ID")
        if "instance" in row:
            if type(row["instance"]) is not int:
                raise ValueError(f"locations.json {cid}: invalid instance ID")
            instance = required(tables["Map"], row["instance"], "locations.json instance")
            if instance["InstanceType"] not in (1, 2):
                raise ValueError(f"locations.json {cid}: Map is not a dungeon/raid")
        result[cid] = row
    return result


def generate(tables):
    graph = Achievements(tables)
    geography = Geography(tables)
    curated = curated_locations(tables, geography)
    rewards = {r["AchievementID"] for r in tables["TraitCurrencySource"].values() if r["TraitCurrencyID"] == 4225}
    if not rewards or 0 in rewards:
        raise ValueError("TraitCurrencySource 4225: missing reward achievements")
    feeds = defaultdict(set)
    for reward in sorted(rewards):
        graph.expand(reward, reward, feeds, set())
    zones = defaultdict(list)
    counts = Counter({
        "current-art overlay remaps": 0, "current-art remap missing": 0,
        "current-art remap ambiguous": 0, "current-art remap zone mismatch": 0,
    })
    unresolved = Counter()
    used_curated = set()
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
            if kind in ("kill", "instance"):
                instance = tables["Achievement"][achievement]["Instance_ID"]
                if instance > 0:
                    instance_ids.add(instance)
                if criterion["Type"] == 165:
                    encounter = tables["DungeonEncounter"].get(criterion["Asset"])
                    if encounter:
                        instance_ids.add(encounter["MapID"])
            if len(instance_ids) > 1:
                raise ValueError(f"Achievement {achievement}, criteria {cid}: conflicting instance IDs")
            if kind == "explore":
                explore_achievements.add(achievement)
                location = geography.explore(cid, counts)
            elif instance_ids:
                instance = next(iter(instance_ids))
                entrances = geography.entrances(instance)
                if len(entrances) == 1:
                    zone, (x, y) = next(iter(entrances.items()))
                    location = zone, {"kind": "instance", "instance": instance, "x": x, "y": y}
            if cid in curated:
                used_curated.add(cid)
                fact = curated[cid]
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
                        entry["instance"] = instance
                        entrances = geography.entrances(instance)
                        if entrances and fact["uiMap"] not in entrances:
                            raise ValueError(f"Criteria {cid}: curated zone excludes the client entrance")
                        if fact["uiMap"] in entrances:
                            entry["x"], entry["y"] = entrances[fact["uiMap"]]
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
    if counts["explore pinned"] + counts["explore unpinned"] < 500:
        raise ValueError("Fewer than 500 exploration entries; refusing a likely broken join")
    counts["exploration achievements"] = len(explore_achievements)
    counts["curated criteria"] = len(used_curated)
    return rewards, feeds, zones, counts, unresolved


def render(rewards, feeds, zones):
    lines = [
        f"-- Generated by tools/gen_legacy.py from WoW: Forever build {BUILD}. Do not edit by hand.",
        f"-- Source snapshot: {SOURCE_DATE}; https://wago.tools/db2/ (pinned CSV exports).",
        "local _, ns = ...", "", "ns.Data = {", f'\tbuild = "{BUILD}",',
        "\t-- Reward-bearing Legacy challenges (both variant sets).", "\trewards = {",
    ]
    lines.extend(f"\t\t[{key}] = true," for key in sorted(rewards))
    lines.extend(["\t},", "\t-- Supporting achievement -> reward-bearing challenges it counts toward.", "\tfeeds = {"])
    for key, targets in sorted(feeds.items()):
        lines.append(f"\t\t[{key}] = {{ {', '.join(map(str, sorted(targets)))} }},")
    lines.extend(["\t},", "\t-- Location-bound objectives by zone uiMapID.", "\tzones = {"])
    for zone, entries in sorted(zones.items()):
        lines.append(f"\t\t[{zone}] = {{")
        for entry in sorted(entries, key=lambda e: (e["kind"], e["achievement"], e["criteria"])):
            fields = [f"achievement = {entry['achievement']}", f"criteria = {entry['criteria']}", f'kind = "{entry["kind"]}"']
            if "instance" in entry:
                fields.append(f"instance = {entry['instance']}")
            if "x" in entry:
                fields.extend((f"x = {entry['x']:.3f}", f"y = {entry['y']:.3f}"))
            lines.append("\t\t\t{ " + ", ".join(fields) + " },")
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
    rewards, feeds, zones, counts, unresolved = generate(tables)
    output = render(rewards, feeds, zones)
    atomic_write(OUTPUT, output.encode("utf-8"))
    print(f"Build {BUILD} ({SOURCE_DATE}): {len(rewards)} rewards; {len(feeds)} supporting achievements; {len(zones)} zones", file=sys.stderr)
    for key, count in sorted(counts.items()):
        print(f"  {key}: {count}", file=sys.stderr)
    print("  Unresolved direct reward criteria (achievement, criteria pairs; both variants; metas expanded):", file=sys.stderr)
    for key in sorted(set(CRITERIA_KINDS.values()) - {"meta"}):
        print(f"    {key}: {unresolved[key]}", file=sys.stderr)
    print(f"Wrote {OUTPUT.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, csv.Error, urllib.error.URLError) as error:
        sys.exit(f"error: {error}")
