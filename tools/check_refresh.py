#!/usr/bin/env python3
"""Diff the regenerated data against the committed one for lost data, with forever-db's evidence (stdlib only).

    python3 tools/check_refresh.py --old <data-file> --new <data-file> [--fdb <forever-db.zip>]

Dumps both generated files through tools/legacy_dump.lua (LuaJIT) and fails on a regression: an objective that
lost every zone it had while its achievement is still a reward or feed, an objective that lost its pin or its
drawn explore key, a feed link, a drawn completion area that lost its tiles, or a wing, raid boss or Legacy
entry that lost a reference. A refresh's other effects are only reported: gained pins, keys, tiles and
references, moved zones and pins, changed counts, and rewards, objectives and entries added or dropped. Every
regression prints what forever-db -- the zip at --fdb, or the release pinned in tools/fdb_pin.py fetched into
tools/.cache when --fdb is omitted -- says about the ids the entry carries (its zone's ui_map record and its
instance's spawn coverage), so the reader can tell whether the second source has facts for it at all; the
guard reads only its ui_map and spawn tables, whose spawn points stop at the Classic continents' maps, so an
instance pin normally has none. The zip is checked against the pin's FDB_SHA256 before it is read, whatever fetched it.
"""

import argparse
import hashlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

import fdb_pin

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
CACHE = TOOLS / ".cache"
USER_AGENT = "LegacyForever/1.0"


def group(records):
    """The guarded rows grouped by what identifies one, as dump's lines arrive."""
    data = {
        "rewards": {},
        "feeds": {},
        "objectives": {},
        "areas": {},
        "taxis": {},
        "wings": {},
        "bosses": {},
        "legacy": {},
        "reputations": {},
    }
    for record in records:
        kind = record["kind"]
        if kind == "reward":
            data["rewards"][record["id"]] = True
        elif kind == "feed":
            data["feeds"][record["id"]] = set(record["targets"])
        elif kind == "objective":
            pair = record["achievement"], record["criteria"]
            data["objectives"].setdefault(pair, {})[record["zone"]] = record
        elif kind == "area":
            data["areas"][record["zone"], record["name"]] = record
        elif kind == "taxi":
            data["taxis"][record["node"]] = record
        elif kind == "wing":
            data["wings"][record["name"]] = record
        elif kind == "boss":
            data["bosses"][record["raid"], record["name"]] = record
        elif kind == "legacy":
            data["legacy"][record["zone"], record["name"]] = record
        elif kind == "reputation":
            data["reputations"][record["faction"]] = record
        else:
            raise ValueError(f"legacy_dump wrote an unknown kind: {kind}")
    return data


def dump(data_file):
    """The generated file's guarded rows as tools/legacy_dump.lua's JSON lines, grouped by what identifies one."""
    if shutil.which("luajit") is None:
        raise SystemExit("check_refresh: luajit is not on PATH")
    with tempfile.TemporaryDirectory(prefix="legacy-refresh-") as scratch:
        lines = Path(scratch) / "rows.jsonl"
        subprocess.run(
            ["luajit", str(TOOLS / "legacy_dump.lua"), str(data_file), str(lines)],
            cwd=ROOT,
            check=True,
        )
        return group(json.loads(line) for line in lines.read_text(encoding="utf-8").splitlines())


def download(url, name):
    """`url`'s bytes into tools/.cache under `name`, streamed, and the file's bytes back."""
    CACHE.mkdir(parents=True, exist_ok=True)
    target = CACHE / name
    partial = target.with_name(f"{name}.part")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response, partial.open("wb") as out:
        while chunk := response.read(1 << 20):
            out.write(chunk)
    partial.replace(target)
    return target.read_bytes()


def fetch_fdb(path):
    """The pinned forever-db zip's bytes: `path`'s when it exists, otherwise fetched into tools/.cache under
    the sha256 name the pin's hash is. Checked against the pin's FDB_SHA256 before anything reads it."""
    # Resolved, so a relative --fdb (the workflow passes tools/.cache/fdb-<sha>.zip) still counts as the cache
    # path and is fetched when absent, instead of failing as a missing file.
    path = path.resolve()
    name = f"fdb-{fdb_pin.FDB_SHA256}.zip"
    if path.is_file():
        content = path.read_bytes()
        if path.parent == CACHE and path.name == name:
            try:
                verify_fdb(content, path)
            except ValueError:
                # A changed or corrupted cached zip: redownload once, then hold the pin.
                content = download(fdb_pin.FDB_URL, name)
    elif path.parent == CACHE and path.name == name:
        content = download(fdb_pin.FDB_URL, name)
        try:
            verify_fdb(content, path)
        except ValueError:
            # A changed or corrupted cached zip: redownload once, then hold the pin.
            (CACHE / name).unlink()
            content = download(fdb_pin.FDB_URL, name)
    else:
        raise SystemExit(f"check_refresh: {path} does not exist")
    verify_fdb(content, path)
    return content


def verify_fdb(content, path):
    """`content`'s sha256, raised against the pin's FDB_SHA256 so the guard never reads another zip."""
    digest = hashlib.sha256(content).hexdigest()
    if digest != fdb_pin.FDB_SHA256:
        raise ValueError(f"check_refresh: {path}: sha256 {digest} does not match the pin's {fdb_pin.FDB_SHA256}")


def member(archive, stem):
    """The archive member holding `stem` under its data/ folder, whatever folder prefix the release packs."""
    found = [name for name in archive.namelist() if name == f"data/{stem}" or name.endswith(f"/data/{stem}")]
    if len(found) != 1:
        raise ValueError(f"check_refresh: expected one data/{stem} member in the release, found {len(found)}")
    return found[0]


def read_fdb(content, zones, instances):
    """The forever-db rows the guard reads, from the zip's bytes after fetch_fdb checked them against the pin:
    every ui_map row, and the spawn points on the instance maps the two dumps name (the spawn table holds
    world maps and a few battlegrounds, so most instance maps have none)."""
    fdb = {"ui_maps": {}, "spawn_maps": {}}
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        with archive.open(member(archive, "ui_map.jsonl")) as rows:
            for row in rows:
                entry = json.loads(row)
                fdb["ui_maps"][entry["ui_map"]] = entry
        with archive.open(member(archive, "spawn.jsonl")) as rows:
            for row in rows:
                entry = json.loads(row)
                if entry["map"] in instances:
                    fdb["spawn_maps"][entry["map"]] = fdb["spawn_maps"].get(entry["map"], 0) + 1
    return fdb


def evidence(fdb, context):
    """What forever-db says about a regression's ids: its zone's ui_map record and each instance map's spawn
    coverage, so the reader can tell whether the second source has facts for it at all."""
    zone, instances = context
    parts = []
    row = fdb["ui_maps"].get(zone)
    if row:
        parts.append(
            f"zone {zone}: map {row['map']} bounds ({row['left']}, {row['top']})..({row['right']}, {row['bottom']})"
        )
    else:
        parts.append(f"zone {zone}: no forever-db record")
    for instance in instances:
        count = fdb["spawn_maps"].get(instance)
        parts.append(
            f"map {instance}: {count} spawn points in forever-db"
            if count
            else f"map {instance}: no spawn points in forever-db"
        )
    return "; ".join(parts) or "no forever-db record"


def coverage(fdb, new):
    """How much of the new data's id space forever-db could speak to at all, printed on every run."""
    zones = {record["zone"] for zones in new["objectives"].values() for record in zones.values()}
    zones.update(zone for zone, _ in new["areas"])
    zones.update(record["zone"] for record in new["taxis"].values())
    named = sum(1 for zone in zones if zone in fdb["ui_maps"])
    instances = {
        record["instance"]
        for zones in new["objectives"].values()
        for record in zones.values()
        if record.get("instance")
    }
    spawned = sum(1 for instance in instances if fdb["spawn_maps"].get(instance))
    return (
        f"forever-db names {named} of the {len(zones)} zones the data uses and carries spawn points on "
        f"{spawned} of its {len(instances)} instance maps"
    )


def summary(data):
    """The data's shape, as the no-changes line and the end of every report state it."""
    return (
        f"{len(data['rewards'])} rewards, {len(data['feeds'])} feeds, "
        f"{sum(len(zones) for zones in data['objectives'].values())} objectives, {len(data['areas'])} areas, "
        f"{len(data['taxis'])} taxis, {len(data['wings'])} wings, {len(data['bosses'])} raid bosses, "
        f"{len(data['legacy'])} Legacy entries, {len(data['reputations'])} reputations"
    )


def context_for_achievement(book, achievement):
    """Where an achievement's objectives last stood in `book`, for a dropped link's or ref's forever-db
    lookups; None when the old data never placed it."""
    zones = [
        (zone, record)
        for (ach, _criteria), placed in book["objectives"].items()
        if ach == achievement
        for zone, record in placed.items()
    ]
    if not zones:
        return None
    zone, record = zones[-1]
    return zone, (record["instance"],) if record.get("instance") else ()


def context_of(record):
    """A regression's forever-db lookups: the entry's zone and its instance map."""
    return record["zone"], (record["instance"],) if record.get("instance") else ()


def compare(old, new):
    """The refresh's regressions, which fail it, and its other changes, which are only reported. A regression
    carries the context its forever-db evidence reads; None means forever-db has no ids to look up."""
    regressions, reports = [], []
    dropped_feed_links, dropped_refs = [], []

    def regression(context, text):
        regressions.append((context, text))

    def report(text):
        reports.append(text)

    for reward_id in sorted(set(old["rewards"]) - set(new["rewards"])):
        report(f"reward {reward_id} is gone")
    for reward_id in sorted(set(new["rewards"]) - set(old["rewards"])):
        report(f"reward {reward_id} is new")

    for feed_id in sorted(set(old["feeds"]) & set(new["feeds"])):
        had, has = old["feeds"][feed_id], new["feeds"][feed_id]
        for target in sorted(had - has):
            dropped_feed_links.append((feed_id, target))
        for target in sorted(has - had):
            report(f"feed {feed_id}: gained its link to reward {target}")
    for feed_id in sorted(set(new["feeds"]) - set(old["feeds"])):
        report(f"feed {feed_id} is new")
    for feed_id in sorted(set(old["feeds"]) - set(new["feeds"])):
        report(f"feed {feed_id} is gone")

    for pair in sorted(set(old["objectives"]) & set(new["objectives"])):
        achievement, criteria = pair
        label = f"objective {achievement}/{criteria}"
        had_zones, has_zones = old["objectives"][pair], new["objectives"][pair]
        for zone in sorted(set(had_zones) - set(has_zones)):
            report(f"{label}: no longer in zone {zone}")
        for zone in sorted(set(has_zones) - set(had_zones)):
            report(f"{label}: now also in zone {zone}")
        for zone in sorted(set(had_zones) & set(has_zones)):
            was, now = had_zones[zone], has_zones[zone]
            context = context_of(now)
            if "key" in was and "key" not in now:
                regression(context, f"{label} in zone {zone}: lost its drawn key ({was['key']})")
            elif "key" in now and "key" not in was:
                report(f"{label} in zone {zone}: gained a drawn key ({now['key']})")
            elif was.get("key") != now.get("key"):
                report(f"{label} in zone {zone}: changed its drawn key from {was['key']} to {now['key']}")
            if "x" in was and "x" not in now:
                regression(context, f"{label} in zone {zone}: lost its pin")
            elif "x" in now and "x" not in was:
                report(f"{label} in zone {zone}: gained a pin at {now['x']}, {now['y']}")
            elif ("x" in was and "y" in was) and (was["x"] != now["x"] or was["y"] != now["y"]):
                report(f"{label} in zone {zone}: moved its pin from {was['x']}, {was['y']} to {now['x']}, {now['y']}")
            if was.get("obj") != now.get("obj"):
                report(f"{label} in zone {zone}: is now a {now.get('obj')} objective (was a {was.get('obj')} one)")
            if was.get("instance") != now.get("instance"):
                report(
                    f"{label} in zone {zone}: changed its instance from {was.get('instance')} to {now.get('instance')}"
                )
            if bool(was.get("raid")) != bool(now.get("raid")):
                report(f"{label} in zone {zone}: {'gained' if now.get('raid') else 'lost'} its raid flag")
    for pair in sorted(set(new["objectives"]) - set(old["objectives"])):
        achievement, criteria = pair
        report(f"objective {achievement}/{criteria} is new")
    for pair in sorted(set(old["objectives"]) - set(new["objectives"])):
        achievement, criteria = pair
        label = f"objective {achievement}/{criteria}"
        if achievement in new["rewards"] or achievement in new["feeds"]:
            # The client still names the challenge, so its objectives' every place going missing is a broken
            # join, not content the build dropped.
            regression(
                context_for_achievement(old, achievement),
                f"{label}: lost every zone it had (the achievement is still a reward or feed)",
            )
        else:
            report(f"{label} is gone")

    for key in sorted(set(old["areas"]) & set(new["areas"])):
        was, now = old["areas"][key], new["areas"][key]
        label = f"area {key[1]} (zone {key[0]})"
        context = (key[0], ())
        if "key" in was and "key" not in now:
            regression(context, f"{label}: lost its drawn key ({was['key']})")
        elif "key" in now and "key" not in was:
            report(f"{label}: gained a drawn key ({now['key']})")
        elif was.get("key") != now.get("key"):
            report(f"{label}: changed its drawn key from {was['key']} to {now['key']}")
        had_tiles, has_tiles = was.get("tiles") or 0, now.get("tiles") or 0
        if had_tiles > 0 and has_tiles == 0:
            regression(context, f"{label}: lost its tiles ({had_tiles} -> none)")
        elif had_tiles != has_tiles:
            report(f"{label}: now has {has_tiles} tiles (was {had_tiles})")
        if was.get("criteria") != now.get("criteria"):
            report(f"{label}: changed its criteria from {was.get('criteria')} to {now.get('criteria')}")
    for key in sorted(set(new["areas"]) - set(old["areas"])):
        report(f"area {key[1]} (zone {key[0]}) is new")
    for key in sorted(set(old["areas"]) - set(new["areas"])):
        report(f"area {key[1]} (zone {key[0]}) is gone")

    for node in sorted(set(old["taxis"]) & set(new["taxis"])):
        was, now = old["taxis"][node], new["taxis"][node]
        label = f"taxi node {node}"
        if was["zone"] != now["zone"]:
            report(f"{label}: moved from zone {was['zone']} to zone {now['zone']}")
        if was["faction"] != now["faction"]:
            report(f"{label}: changed its faction from {was['faction']} to {now['faction']}")
        if was["name"] != now["name"]:
            report(f"{label}: was renamed from {was['name']} to {now['name']}")
    for node in sorted(set(new["taxis"]) - set(old["taxis"])):
        record = new["taxis"][node]
        report(f"taxi node {node} ({record['name']}, zone {record['zone']}) is new")
    for node in sorted(set(old["taxis"]) - set(new["taxis"])):
        record = old["taxis"][node]
        report(f"taxi node {node} ({record['name']}, zone {record['zone']}) is gone")

    for name in sorted(set(old["wings"]) & set(new["wings"])):
        was, now = old["wings"][name], new["wings"][name]
        label = f"wing {name}"
        if was["zone"] != now["zone"]:
            report(f"{label}: moved from zone {was['zone']} to zone {now['zone']}")
        had_refs, has_refs = (
            {(ref[0], ref[1]) for ref in was.get("refs") or ()},
            {(ref[0], ref[1]) for ref in now.get("refs") or ()},
        )
        for ref in sorted(had_refs - has_refs):
            dropped_refs.append((label, now["zone"], ref))
        for ref in sorted(has_refs - had_refs):
            report(f"{label}: gained ref {ref[0]}/{ref[1]}")
    for name in sorted(set(new["wings"]) - set(old["wings"])):
        record = new["wings"][name]
        report(f"wing {name} (zone {record['zone']}) is new")
    for name in sorted(set(old["wings"]) - set(new["wings"])):
        record = old["wings"][name]
        report(f"wing {name} (zone {record['zone']}) is gone")

    for key in sorted(set(old["bosses"]) & set(new["bosses"])):
        was, now = old["bosses"][key], new["bosses"][key]
        label = f"raid boss {key[1]} ({key[0]})"
        if was["zone"] != now["zone"]:
            report(f"{label}: moved from zone {was['zone']} to zone {now['zone']}")
        had_refs, has_refs = (
            {(ref[0], ref[1]) for ref in was.get("refs") or ()},
            {(ref[0], ref[1]) for ref in now.get("refs") or ()},
        )
        for ref in sorted(had_refs - has_refs):
            dropped_refs.append((label, now["zone"], ref))
        for ref in sorted(has_refs - had_refs):
            report(f"{label}: gained ref {ref[0]}/{ref[1]}")
    for key in sorted(set(new["bosses"]) - set(old["bosses"])):
        report(f"raid boss {key[1]} ({key[0]}) is new")
    for key in sorted(set(old["bosses"]) - set(new["bosses"])):
        report(f"raid boss {key[1]} ({key[0]}) is gone")

    for key in sorted(set(old["legacy"]) & set(new["legacy"])):
        was, now = old["legacy"][key], new["legacy"][key]
        label = f"Legacy entry {key[1]} (zone {key[0]})"
        had_refs, has_refs = (
            {(ref[0], ref[1]) for ref in was.get("refs") or ()},
            {(ref[0], ref[1]) for ref in now.get("refs") or ()},
        )
        for ref in sorted(had_refs - has_refs):
            dropped_refs.append((label, key[0], ref))
        for ref in sorted(has_refs - had_refs):
            report(f"{label}: gained ref {ref[0]}/{ref[1]}")
    for key in sorted(set(new["legacy"]) - set(old["legacy"])):
        report(f"Legacy entry {key[1]} (zone {key[0]}) is new")
    for key in sorted(set(old["legacy"]) - set(new["legacy"])):
        report(f"Legacy entry {key[1]} (zone {key[0]}) is gone")

    for feed_id, target in dropped_feed_links:
        if target in new["rewards"]:
            regression(context_for_achievement(old, target), f"feed {feed_id}: dropped its link to reward {target}")
        else:
            report(f"feed {feed_id}: dropped its link to reward {target} (the reward is gone from the new data)")
    for label, _zone, ref in dropped_refs:
        if ref in new["objectives"]:
            regression(context_for_achievement(old, ref[0]), f"{label}: dropped ref {ref[0]}/{ref[1]}")
        else:
            report(f"{label}: dropped ref {ref[0]}/{ref[1]} (the objective is gone from the new data)")

    for faction in sorted(set(old["reputations"]) & set(new["reputations"])):
        was, now = old["reputations"][faction], new["reputations"][faction]
        label = f"reputation {faction}"
        if was["zone"] != now["zone"]:
            report(f"{label}: moved from zone {was['zone']} to zone {now['zone']}")
        if was.get("side") != now.get("side"):
            report(f"{label}: changed its side from {was.get('side')} to {now.get('side')}")
        if was["name"] != now["name"]:
            report(f"{label}: was renamed from {was['name']} to {now['name']}")
    for faction in sorted(set(new["reputations"]) - set(old["reputations"])):
        record = new["reputations"][faction]
        report(f"reputation {faction} ({record['name']}, zone {record['zone']}) is new")
    for faction in sorted(set(old["reputations"]) - set(new["reputations"])):
        record = old["reputations"][faction]
        report(f"reputation {faction} ({record['name']}, zone {record['zone']}) is gone")

    return regressions, reports


def wanted_ids(data):
    """The zone and instance map ids the two dumps carry, for read_fdb's filtered scan."""
    zones = {record["zone"] for zones in data["objectives"].values() for record in zones.values()}
    zones.update(zone for zone, _ in data["areas"])
    zones.update(zone for zone, _ in data["legacy"])
    zones.update(record["zone"] for record in data["taxis"].values())
    zones.update(record["zone"] for record in data["wings"].values())
    zones.update(record["zone"] for record in data["bosses"].values())
    zones.update(record["zone"] for record in data["reputations"].values())
    instances = {
        record["instance"]
        for zones in data["objectives"].values()
        for record in zones.values()
        if record.get("instance")
    }
    return zones, instances


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--old", type=Path, required=True, help="the committed data the previous pins built")
    parser.add_argument("--new", type=Path, required=True, help="the data the refreshed pins built")
    parser.add_argument(
        "--fdb",
        type=Path,
        default=CACHE / f"fdb-{fdb_pin.FDB_SHA256}.zip",
        help="the forever-db release zip, fetched into tools/.cache here when it is absent",
    )
    options = parser.parse_args()
    content = fetch_fdb(options.fdb)
    old = dump(options.old.resolve())
    new = dump(options.new.resolve())
    zones, instances = wanted_ids(old)
    new_zones, new_instances = wanted_ids(new)
    zones |= new_zones
    instances |= new_instances
    fdb = read_fdb(content, zones, instances)
    regressions, reports = compare(old, new)
    fills = coverage(fdb, new)
    if not regressions and not reports:
        print(f"no data changes ({summary(new)})")
        print(fills)
        return 0
    if regressions:
        print(f"REGRESSIONS ({len(regressions)}):")
        for context, line in regressions:
            print(f"  {line}")
            if context is not None:
                print(f"    forever-db: {evidence(fdb, context)}")
    if reports:
        print(f"REPORTED ({len(reports)}):")
        for line in reports:
            print(f"  {line}")
    print(fills)
    return 1 if regressions else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        sys.exit(f"check_refresh: {error}")
