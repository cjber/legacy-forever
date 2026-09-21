# Legacy data generator

Run from the repository root:

```sh
python3 tools/gen_legacy.py --refresh
python3 tools/gen_legacy.py --offline
luajit tests/data_spec.lua
```

Python's standard library is sufficient. The generator pins `BUILD` and
`SOURCE_DATE`, downloads CSVs from
`https://wago.tools/db2/<Table>/csv?build=<BUILD>` into ignored `tools/.cache/`,
and atomically writes `Data/Legacy.lua`. The default reuses cached downloads;
`--refresh` replaces them and `--offline` requires them. Coverage goes to stderr;
malformed schemas, unknown relevant criteria types, graph cycles, and stale
curated IDs fail without replacing the generated output. `latest_build.py` is
copied unchanged from SkillUp Forever and only reports the newest Forever build.

Sources: `TraitCurrencySource`, `Achievement`, `Criteria`, `CriteriaTree`,
`WorldMapOverlay`, `WorldMapOverlayTile`, `AreaTable`, `UiMap`, `UiMapAssignment`, `UiMapXMapArt`,
`UiMapArt`, `UiMapArtStyleLayer`, `Map`, `DungeonEncounter`, `QuestV2`, and `TaxiNodes`. Currency 4225
selects both reward variants. Type-8 criteria recursively populate `feeds`;
objectives retain the owning achievement and actual Criteria.ID, never a tree
node ID or a copied parent achievement ID.

## Coordinates and verification

Exploration uses Criteria.Asset → WorldMapOverlay.ID. All nonzero overlay AreaIDs
are followed through AreaTable.ParentAreaID to UiMapAssignment.AreaID. Multiple
candidate zones remain unresolved. An exact, unphased UiMapXMapArt match takes
precedence: its map owns the overlay's coordinate space. In particular, overlay
202 / Criteria 911 outlines Thunder Bluff **on Mulgore**, not on the city map.

If the criterion's overlay has no UiMapXMapArt row, an exact match of its nonzero
AreaID set must identify exactly one overlay on current art. The replacement's
art/UiMap must agree with the area-derived zone. Its hit rectangle supplies the
pin; achievement and Criteria.ID remain unchanged. Missing, ambiguous, or
zone-conflicting matches stay unpinned and are counted.

UiMapArt.UiMapArtStyleID joins the base (`LayerIndex = 0`) UiMapArtStyleLayer.
Hit rectangles already use full-layer pixels; texture offsets are not added:

```text
x = (HitRectLeft + HitRectRight) / (2 * LayerWidth)
y = (HitRectTop + HitRectBottom) / (2 * LayerHeight)
```

Two sanity checks, also asserted by the Lua spec, use the 1002 × 668 layer:

| Area / ID-backed chain | Rectangle (left, right, top, bottom) | Pin |
| --- | --- | --- |
| Bloodhoof Village: Criteria 914 → overlay 186 → Area 222 → parent 215 → UiMap 1412; art 1200 | 434, 507, 388, 445 | 0.470, 0.624 |
| Lakeshire: Criteria 1185 → overlay 364 → Area 69 → parent 44 → UiMap 1433; art 2121 | 94, 334, 263, 342 | 0.214, 0.453 |

Both lie within their independently joined zone bounds, in southern Mulgore and
western Redridge respectively. A remap assertion covers Dun Morogh Criteria 502:
old overlay 117 and current overlay 5129 share AreaID 800; current art 2151 gives
0.349, 0.681 on UiMap 1426. Only the current overlay supplies pixel coordinates.
Empty hit rectangles receive no pin. Output coordinates have three decimals.

Instances use the owning Achievement.Instance_ID, a type-165
Criteria.Asset → DungeonEncounter.ID → MapID, or a type-0 Criteria.Asset →
the exact boss ID in `locations.json.dungeonWings` → its verified `instance`
(Map.ID). Wing facts with only exterior geography cannot establish an instance
ID and do not create Legacy entries. Reviewed quest associations use Type-27
Criteria.Asset → `locations.json.questInstances` (keyed by QuestV2.ID) →
DungeonEncounter.ID → MapID. No other instance-completion criterion
types occur in the reachable Legacy graph in this build.

Reuse the curated entrance zone for the same Map.ID, rejecting conflicts
between facts. Otherwise require exactly one entrance projection, or existing
criterion curation. Map.CorpseMapID selects the world map; Corpse_0/1 supply
world X/Y. For a matching UiMapAssignment, UI X reverses world Y over
Region_1..Region_4, and UI Y reverses world X over Region_0..Region_3; each is
scaled into UiMin..UiMax. WMO-local assignments are excluded. Overlapping zone
rectangles require a verified zone selection, not a nearest-centre guess.
Onyxia's Map 249 projects through assignment 46755 into Dustwallow (1445) at
0.529, 0.777. These are client corpse entrance markers, not boss-room positions.
The entry remains `{achievement, criteria, kind = "instance", instance, x, y}`;
omit both coordinates when a reviewed zone is known but Map has no corpse
marker (City of Dalaran, Ruins of Lordaeron, Excavation Site: Wetlands).

The journal route cannot be used here: `JournalEncounterCreature`,
`JournalEncounter`, and `JournalInstance` return HTTP 404 for this build.
`Creature`/`CreatureDifficulty` expose no creature-to-map link, and every
`LFGDungeons` row has MapID and FinalEncounterID zero. These tables were inspected
via the same cached helper; they are not generator dependencies.

**Valthalak uses reviewed quest curation.** Achievement 62054 → CriteriaTree
221563/221564 → Criteria 111555 (Type 27) → quest 84195; variant 64014 → trees
234126/234127 → Criteria 117727 has the same asset. `questInstances[84195]`
associates that quest with DungeonEncounter 3070 → Map 229 (Blackrock Spire).
This association is explicitly reviewed curation, not a quest-table foreign key
or a generated name match. QuestV2 confirms the quest exists; the generator
validates the encounter's exact name and MapID, the Map's instance type, exterior
area ancestry, entrance projection, and reachability from a Legacy criterion.
Both variants use Burning Steppes (1428), **0.330, 0.252**, reusing the Spire wing
entrance facts. Their original quest criteria remain the progress identifiers.

## Verified locations and current coverage

Add an entry under `locations.json` → `criteria`, keyed by decimal Criteria.ID,
with `uiMap`, `kind`, and an `evidence` string naming verified row IDs or an
unambiguous geography fact. `kind = "instance"` also requires `instance = Map.ID`;
other kinds omit it. Quest curation has `uiMap`, `name` (the expected encounter
name), `instance`, `encounter`, `evidence`, and optional exterior `area`.
Evidence must cite the criterion/tree, encounter and Map rows, and the entrance
corpse point or reviewed exterior zone. Never add coordinates, generated name
joins, or Wowhead data.
The generator validates IDs, reachability, types, and conflicts with client data,
and derives any instance pin itself. The two criterion facts select Dustwallow for
Onyxia's two variants; the existing wing facts also locate matching boss criteria.
Evidence records the build on which a fact was reviewed; it need not equal the
current `BUILD`. The refresh workflow changes BUILD/SOURCE_DATE without rewriting
curation. Names, referenced IDs, instance types, ancestry, conflicts, and
reachability are still checked against the newly fetched tables. A simulated
build bump to 1.60.1.69914 with identical rows passes; changed referenced facts
still fail. No workflow change is necessary.

Build **1.60.1.69913**, snapshot **2026-09-21**: 130 rewards, 46 supporting
achievements (43 exploration achievements plus three metas), 47 populated zones.
There are **549 exploration entries: 493 pinned, 56 unpinned**. Of 497 old-art
criteria overlays, 449 have a unique current-art match, 48 have none, and zero
have multiple matches. One unique match disagrees with the area-derived zone;
448 remaps are accepted, yielding 447 additional pins and one empty rectangle.
The 56 unpinned entries comprise 48 unmatched overlays, one zone mismatch, and
seven empty rectangles. There are **58 instance entries: 52 pinned, six zone-only**,
using **two curated criteria**, 27 wing facts with Map IDs, and one curated quest.
No exploration objective is unresolved.

Unresolved direct reward `(achievement, criteria)` pairs across both variants:
kill **52**, instance/encounter **2**, quest **6**, reputation **16**, level **54**,
skill **36**, rank **10**; **176** total. The two Explorer meta criteria are expanded,
not counted as unresolved. Global progress and unplaced objectives stay absent
from `zones` for the addon's “No fixed location” view.

Changes from the previous slice, counting both variants:

| Challenge category | Newly located | Remaining unlocated and reason |
| --- | ---: | --- |
| Dungeons (Spelunker) | 54 | 12: compound Ragefire/Hall of Thanes (2) is not one instance; Drowned City (2) has no verified entrance/Map; Blackmaw Hold, Alcaz Prison, Krol'dok Stronghold, Shaper's Terrace (8) have reviewed exterior zones but no instance Map IDs. |
| Raids | 0 | 42: Wilds (26) and Deeps (16) lack encounter/instance evidence even for reviewed curation; see the audit below. Onyxia's two entries were already located. |
| Adventure | 2 | None; both Valthalak variants use the reviewed Spire entrance. |
| Field of Honor | 0 | 6: quests 96915/96918/96921 have outdoor Map 1 POIs, not dungeon/raid bindings. |
| Level / skill / rank / reputation | 0 | 116: global progress, not instance objectives. |

Raid audit: refreshed DungeonEncounter (341 rows) and Map (73 rows) exports are
identical to the cached sources. None of the 20 Type-0 Raid boss descriptions
has an encounter row in this build; Type-165 Time-Lost Battalion references
missing encounter 3339. The owning achievements have Instance_ID -1, and no
other instance-bound achievement supplies these boss assets. There is no Map
row for Hyjal Summit or Barrow Deeps. Map 2995 (Hyjal Crater) is InstanceType 4,
not a dungeon/raid; the four Nightmare Grove encounters on Map 2832 do not
identify these objectives. Descriptive similarities are insufficient to curate
an instance or invent a corpse entrance.

## Zone completion

`completion[uiMapID]` is independent of Legacy objectives. Each populated zone
always has `areas`, `taxis`, and `dungeons` arrays, including empty arrays for
categories with no items, and `tileWidth`/`tileHeight` from
UiMapXMapArt (PhaseID 0) → UiMapArt.UiMapArtStyleID → UiMapArtStyleLayer (LayerIndex 0).
All 43 completion zones use **256 × 256** tiles. Names come from the pinned
English client export; no progress, faction eligibility rules, or runtime state
is emitted.

- **Areas:** enumerate WorldMapOverlay on the zone's current phase-0 UiMap art,
  reusing Geography's art join. The key is exactly
  `OffsetX:OffsetY:TextureWidth:TextureHeight`, formatted as four decimal integers;
  the name is AreaTable.AreaName_lang for AreaID_0. Empty hit rectangles still
  count; zero-size textures do not, since they never draw on the map. Exclude Zephras Isle (2521, colliding zero keys) and battleground maps
  1459–1461. Duplicate keys within a zone or duplicate phase-0 art fail generation.
  Areas with tile rows have `tiles = {FileDataID, ...}` from WorldMapOverlayTile, layer 0;
  all 1,739 source tile rows in this build use layer 0. Require exactly
  `ceil(TextureWidth / TileWidth) * ceil(TextureHeight / TileHeight)` cells.
  An overlay with **zero source tile rows** stays countable and omits `tiles`;
  print its ID, zone and key. This build has exactly one: **5252, Zul'Gurub** in
  Stranglethorn (1434), key **`483:8:256:256`**. Its Legacy criterion 1222 keeps
  its key and pin; runtime skips shading when `tiles` is absent.
  Reject partial, duplicate, out-of-grid, nonpositive, or mis-sized layer-0 grids
  before replacing output, including overlays with only nonzero-layer rows.
  DB2 RowIndex/ColIndex start at zero; the emitted dense Lua array is
  row-major, indexed `(row - 1) * numWide + col` with one-based runtime indices.
  Runtime must apply Blizzard's edge-tile power-of-two padding/texture cropping;
  the key's offsets and dimensions remain full-layer pixels.
  Legacy `kind = "explore"` entries carry the same `key` when their current-art
  overlay occurs in their zone's completion areas: **500 matched, 49 unmatched**.
  Unmatched entries remain in `zones` without a key and are printed individually.
- **Taxis:** take TaxiNodes with `Flags & 3`, excluding names beginning `zz`
  (case insensitive) and battleground destinations. Bits 1/2/3 become
  `Alliance`/`Horde`/`Neutral`. Match the exact suffix after the last `", "` to
  UiMap.Name_lang. `locations.json.taxiNodes`, keyed by TaxiNodes.ID, supplies
  only missing, abbreviated, or incorrect suffixes. Each fact has `uiMap`, the
  exact node `name`, and `evidence`. Crossroads and Kargath already have correct
  suffixes; no overrides are needed. City-named nodes retain the suffix's zone
  (for example Ironforge belongs to Dun Morogh). The emitted name drops the
  `", Zone"` suffix, since it is always listed under a zone. Runtime filters own faction
  plus Neutral; these strings are not the differently numbered live taxi enum.
- **Dungeons:** walk all six Spelunker achievements (62031–62033, 64016–64018),
  retaining single-boss Type-0 kill steps. Group by Criteria.Asset (boss ID),
  keep the wing's CriteriaTree description, and collect every sorted
  `{achievement, criteria}` reference across variants and tiers. Separate wings
  remain separate even when they share an instance. Exclude only the verified
  Type-78 compound step 19213/117733, “Ragefire Chasm or Hall of Thanes”; raids
  never enter this graph. `locations.json.dungeonWings`, keyed by boss ID,
  supplies `uiMap`, the exact wing `name`, and `evidence`. Optional `area` and
  `instance` IDs validate the exterior AreaTable ancestry and Map entrance.
  Facts with a verified `instance` also locate Legacy objectives for the exact
  boss ID, using the instance entrance rules above; names are validation only.

Completion curation must cite its verification build and client row facts. Unknown,
unreachable, renamed, or redundant taxi overrides and stale wing curation fail
before output is replaced. Unassigned taxis, duplicate wing names/references,
and unexpected Spelunker step types also fail. A wing without verified entrance
geography is omitted and printed by name and boss ID; it is not assigned by
nearest map rectangle. Instance entrances can overlap multiple zone rectangles,
so curation selects the documented exterior approach (Blackrock Depths uses
Searing Gorge; both Spire wings use Burning Steppes).

Build **1.60.1.69913**: **43 completion zones, 555 areas, 937 tiles** (one area
without tiles), **71 taxis** (32 Alliance,
31 Horde, 8 Neutral; 40 Alliance-usable and 39 Horde-usable), and **31 of 32 wings**
with **62 references**. Twelve taxi exceptions and 31 wing locations are curated.
**The Drowned City** (boss 260274) remains unplaced: WMOAreaTable 144590 names it
but points to AreaTable 17037, which is absent from this build; Map and AreaTable
supply no verified entrance zone. The separate compound step is excluded, not
counted among these 32 wings.

For reference, Gnomeregan uses `{62032, 18529}` and `{64017, 117738}`;
The Deadmines uses `{62031, 3262}` and `{64016, 117731}`.

Verify with two consecutive `python3 tools/gen_legacy.py --offline` runs and
compare `Data/Legacy.lua` byte-for-byte, then run `luajit tests/data_spec.lua`,
`luajit tests/model_spec.lua`, `luacheck .`, and `stylua --check .`.
The generator renders Lua in the repository's StyLua style without depending on
a formatter or excluding the generated file from CI.
