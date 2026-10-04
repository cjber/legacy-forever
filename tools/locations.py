"""Validate tools/locations.json, the reviewed facts the client data cannot give, against the pinned DB2 rows
(stdlib only)."""

import json
import re
from pathlib import Path

from db2 import CRITERIA_KINDS, INSTANCE_TYPES, MAP_DUNGEON, MAP_RAID, required

LOCATIONS = Path(__file__).resolve().parent / "locations.json"
KINDS = {"explore", "instance", "kill", "quest", "reputation"}
CURATED_ID = re.compile(r"[1-9][0-9]*")
EVIDENCE = re.compile(r"^Build [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:")
BATTLEGROUNDS = {1459, 1460, 1461}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"locations.json: duplicate key {key}")
        result[key] = value
    return result


def validate_criterion_row(tables, geography, key, row):
    if not CURATED_ID.fullmatch(key):
        raise ValueError(f"locations.json: invalid criteria ID {key}")
    cid = int(key)
    criterion = required(tables["Criteria"], cid, "locations.json criteria")
    fields = {"uiMap", "kind", "achievement", "type", "asset", "evidence"}
    if not isinstance(row, dict) or not fields <= row.keys() or row.keys() - (fields | {"instance", "instanceType"}):
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
    expected = CRITERIA_KINDS.get(criterion["Type"])
    if row["kind"] != expected and not (row["kind"] == "instance" and expected == "kill"):
        raise ValueError(f"locations.json {cid}: kind disagrees with criteria type")
    if not isinstance(row["evidence"], str) or not EVIDENCE.match(row["evidence"]):
        raise ValueError(f"locations.json {cid}: evidence must record its verification build")
    if any((row["kind"] == "instance") != (field in row) for field in ("instance", "instanceType")):
        raise ValueError(f"locations.json {cid}: only instance entries require an instance ID and type")
    if "instance" in row:
        if type(row["instance"]) is not int:
            raise ValueError(f"locations.json {cid}: invalid instance ID")
        instance = required(tables["Map"], row["instance"], "locations.json instance")
        if (
            type(row["instanceType"]) is not int
            or row["instanceType"] not in INSTANCE_TYPES
            or instance["InstanceType"] != row["instanceType"]
        ):
            raise ValueError(f"locations.json {cid}: stale dungeon/raid instance type")
        if instance["InstanceType"] == MAP_RAID and owner["Instance_ID"] != row["instance"]:
            raise ValueError(f"locations.json {cid}: raid instance no longer verified by owning achievement")
    return cid


def validate_completion_row(tables, geography, section, key, row):
    label = f"locations.json {section} {key}"
    if not CURATED_ID.fullmatch(key):
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
    if not EVIDENCE.match(row["evidence"]):
        raise ValueError(f"{label}: evidence must record its verification build")
    if "area" in row:
        if type(row["area"]) is not int or geography.area_zones(row["area"]) != {row["uiMap"]}:
            raise ValueError(f"{label}: area no longer identifies curated zone")
    if "instance" in row:
        if type(row["instance"]) is not int:
            raise ValueError(f"{label}: invalid instance ID")
        instance = required(tables["Map"], row["instance"], label)
        entrances = geography.entrances(row["instance"])
        instance_types = (MAP_DUNGEON,) if section in ("dungeonWings", "compoundInstances") else INSTANCE_TYPES
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
        validate_reputation(tables, key, row, label)


def validate_reputation(tables, key, row, label):
    faction = required(tables["Faction"], int(key), label)
    if faction["Name_lang"] != row["name"] or not faction["Description_lang"].strip() or faction["ReputationIndex"] < 0:
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


def curated_locations(tables, geography):
    data = json.loads(LOCATIONS.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    sections = {"criteria", "taxiNodes", "dungeonWings", "questInstances", "compoundInstances", "reputations"}
    if not isinstance(data, dict) or set(data) != sections or any(not isinstance(data[k], dict) for k in sections):
        raise ValueError(f"locations.json must contain exactly these objects: {', '.join(sorted(sections))}")
    result = {}
    for key, row in data["criteria"].items():
        result[validate_criterion_row(tables, geography, key, row)] = row
    completion = {}
    for section in ("taxiNodes", "dungeonWings", "questInstances", "compoundInstances", "reputations"):
        completion[section] = {}
        for key, row in data[section].items():
            validate_completion_row(tables, geography, section, key, row)
            completion[section][int(key)] = row
    return result, completion


def validate_compound_tree(tables, root, fact):
    label = f"ModifierTree {root} compound instance"
    alternatives = fact["alternatives"]
    if (
        not isinstance(alternatives, dict)
        or len(alternatives) < 2
        or any(
            not CURATED_ID.fullmatch(key) or type(boss) is not int or boss <= 0 for key, boss in alternatives.items()
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
