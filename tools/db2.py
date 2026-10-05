"""Pinned wago.tools DB2 exports: download, cache and parse them; the enum codes the generator reads (stdlib only)."""

from forever_tools import wago
from forever_tools.fsio import atomic_write

__all__ = ["atomic_write", "db2", "required"]

USER_AGENT = "LegacyForever/1.0"

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


def db2(name, columns, build, cache, **options):
    """One table's rows by ID, parsed and checked; `columns` are the fields kept besides ID."""
    kept = ("ID", *columns)
    # Only these projection fields are floating point; IDs stay exact integers.
    floats = [key for key in kept if key.startswith(("Region_", "UiMin_", "UiMax_", "Corpse_"))]
    ints = [key for key in kept if key not in floats and not key.endswith("_lang")]
    rows = {}
    for row in wago.db2_rows(
        name, build, cache, user_agent=USER_AGENT, ints=ints, floats=floats, required=kept, **options
    ):
        key = row["ID"]
        if key < 0 or key in rows:
            raise ValueError(f"{name}: negative/duplicate ID {key}")
        rows[key] = {column: row[column] for column in kept}
    return rows


def required(rows, key, label):
    if key not in rows:
        raise ValueError(f"{label}: missing referenced ID {key}")
    return rows[key]
