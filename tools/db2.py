"""Pinned wago.tools DB2 exports: download, cache and parse them; the enum codes the generator reads (stdlib only)."""

import csv
import io
import math
import tempfile
import urllib.request
from pathlib import Path

# Criteria.Type codes and the objective kind each one is. Two codes are kills: one names the creature
# (Asset), the other leaves Asset 0 and lets a ModifierTree say which creatures count.
CRITERIA_KILL_CREATURE = 0
CRITERIA_KILL_ANY_CREATURE = 78
CRITERIA_KINDS = {
    CRITERIA_KILL_CREATURE: "kill",
    5: "level",
    7: "skill",
    8: "meta",
    27: "quest",
    43: "explore",
    CRITERIA_KILL_ANY_CREATURE: "kill",
    165: "instance",
    243: "reputation",
    261: "rank",
}
# Map.InstanceType codes for the instances with an entrance on a zone map.
MAP_DUNGEON = 1
MAP_RAID = 2
INSTANCE_TYPES = (MAP_DUNGEON, MAP_RAID)


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


def download(url, path, refresh=False, offline=False):
    fetch = refresh or not path.exists()
    if not fetch:
        data = path.read_bytes()
    elif offline:
        raise ValueError(f"Missing cached source: {path}")
    else:
        request = urllib.request.Request(url, headers={"User-Agent": "LegacyForever/1.0"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
    content = data.decode("utf-8-sig")
    if not content.strip() or content.lstrip().startswith("<"):
        raise ValueError(f"Expected CSV, received empty data or HTML {f'from {url}' if fetch else f'in {path}'}")
    if fetch:
        atomic_write(path, data)
    return content


def db2(name, columns, build, cache, **options):
    """One table's rows by ID, parsed and checked; `columns` are the fields kept besides ID."""
    content = download(
        f"https://wago.tools/db2/{name}/csv?build={build}",
        cache / f"{name}-{build}.csv",
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
        raise ValueError(f"{name}: empty DB2 export for {build}")
    return rows


def required(rows, key, label):
    if key not in rows:
        raise ValueError(f"{label}: missing referenced ID {key}")
    return rows[key]
