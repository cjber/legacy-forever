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
`WorldMapOverlay`, `AreaTable`, `UiMap`, `UiMapAssignment`, `UiMapXMapArt`,
`UiMapArt`, `UiMapArtStyleLayer`, `Map`, `DungeonEncounter`, and `TaxiNodes`. Currency 4225
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

Instances use the owning Achievement.Instance_ID or a type-165
DungeonEncounter.MapID. Map.CorpseMapID selects the world map; Corpse_0/1 supply
world X/Y. For a matching UiMapAssignment, UI X reverses world Y over
Region_1..Region_4, and UI Y reverses world X over Region_0..Region_3; each is
scaled into UiMin..UiMax. WMO-local assignments are excluded. Overlapping zone
rectangles require a verified zone selection, not a nearest-centre guess.
Onyxia's Map 249 projects through assignment 46755 into Dustwallow (1445) at
0.529, 0.777. These are client corpse entrance markers, not boss-room positions.

## Verified locations and current coverage

Add an entry under `locations.json` → `criteria`, keyed by decimal Criteria.ID,
with `uiMap`, `kind`, and an `evidence` string naming verified row IDs or an
unambiguous geography fact. `kind = "instance"` also requires `instance = Map.ID`;
other kinds omit it. For these Legacy objectives, never add coordinates, name-based
joins, or Wowhead data.
The generator validates IDs, reachability, types, and conflicts with client data,
and derives any instance pin itself. The two current facts select Dustwallow for
Onyxia's two criteria variants; new Forever bosses/quests remain unresolved.

Build **1.60.1.69913**, snapshot **2026-09-21**: 130 rewards, 46 supporting
achievements (43 exploration achievements plus three metas), 47 populated zones.
There are **549 exploration entries: 493 pinned, 56 unpinned**. Of 497 old-art
criteria overlays, 449 have a unique current-art match, 48 have none, and zero
have multiple matches. One unique match disagrees with the area-derived zone;
448 remaps are accepted, yielding 447 additional pins and one empty rectangle.
The 56 unpinned entries comprise 48 unmatched overlays, one zone mismatch, and
seven empty rectangles. There are **two pinned instance entries** for one entrance
and **two curated criteria**. No exploration objective is unresolved.

Unresolved direct reward `(achievement, criteria)` pairs across both variants:
kill **106**, instance/encounter **2**, quest **8**, reputation **16**, level **54**,
skill **36**, rank **10**; **232** total. The two Explorer meta criteria are expanded,
not counted as unresolved. Global progress and unplaced objectives stay absent
from `zones` for the addon's “No fixed location” view.
## Zone completion

`completion[uiMapID]` is independent of Legacy objectives. Each populated zone
always has `areas`, `taxis`, and `dungeons` arrays, including empty arrays for
categories with no items. Names come from the pinned English client export;
no progress, coordinates, faction eligibility rules, or runtime state is emitted.

- **Areas:** enumerate WorldMapOverlay on the zone's current phase-0 UiMap art,
  reusing Geography's art join. The key is exactly
  `OffsetX:OffsetY:TextureWidth:TextureHeight`, formatted as four decimal integers;
  the name is AreaTable.AreaName_lang for AreaID_0. Empty hit rectangles still
  count; zero-size textures do not, since they never draw on the map. Exclude Zephras Isle (2521, colliding zero keys) and battleground maps
  1459–1461. Duplicate keys within a zone or duplicate phase-0 art fail generation.
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
  These completion facts do not add Legacy objective pins.

Completion curation must cite the pinned build and client row facts. Unknown,
unreachable, renamed, or redundant taxi overrides and stale wing curation fail
before output is replaced. Unassigned taxis, duplicate wing names/references,
and unexpected Spelunker step types also fail. A wing without verified entrance
geography is omitted and printed by name and boss ID; it is not assigned by
nearest map rectangle. Instance entrances can overlap multiple zone rectangles,
so curation selects the documented exterior approach (Blackrock Depths uses
Searing Gorge; both Spire wings use Burning Steppes).

Build **1.60.1.69913**: **43 completion zones, 555 areas, 71 taxis** (32 Alliance,
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
`luajit tests/model_spec.lua`, `luacheck Data tests`, and `stylua --check Data tests`.
The generator renders Lua in the repository's StyLua style without depending on
a formatter or excluding the generated file from CI.
