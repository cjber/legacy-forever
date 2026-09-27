# Data audit: build 1.60.1.69913 (2026-09-21)

What `tools/gen_legacy.py` found for Forever build **1.60.1.69913** (source snapshot 2026-09-21), and why each
objective it could not place stays unplaced. The counts belong to that build: a later build's run prints its own
(`python3 tools/gen_legacy.py`), and [tools/README.md](../tools/README.md) describes how each join works.

## Legacy objectives

Build **1.60.1.69913**, snapshot **2026-09-21**: 130 rewards, 46 supporting
achievements (43 exploration achievements plus three metas), 47 populated zones.
There are **549 exploration entries: 524 pinned, 25 unpinned**. Of 497 old-art
criteria overlays, 449 have a current-art overlay with the same subzones and 35
more have exactly one current-art overlay on the zone whose subzones the old one
covered (old art sometimes drew several subzones as one overlay, as in Silithus);
13 have neither, and none have several. One match disagrees with the area-derived
zone; 483 remaps are accepted. The 25 unpinned entries comprise 13 unmatched
overlays, one zone mismatch, ten empty rectangles and one inverted rectangle
(Kharanos, WorldMapOverlay 5136, a client data defect that keeps its key). There are **60 instance entries: 54 pinned, six zone-only**,
using **two curated criteria**, 27 wing facts with Map IDs, one curated quest,
and one compound fact with two variant references.
No exploration objective is unresolved.

Unresolved direct reward `(achievement, criteria)` pairs across both variants:
kill **50**, instance/encounter **2**, quest **6**, reputation **16**, level **54**,
skill **36**, rank **10**; **174** total. The two Explorer meta criteria are expanded,
not counted as unresolved. Global progress and unplaced objectives stay absent
from `zones` for the addon's "No fixed location" view.

Unlocated objectives by challenge category, counting both variants:

| Challenge category | Remaining unlocated and reason |
| --- | --- |
| Dungeons (Spelunker) | 10: Drowned City (2) has no verified entrance/Map; Blackmaw Hold, Alcaz Prison, Krol'dok Stronghold, Shaper's Terrace (8) have reviewed exterior zones but no instance Map IDs. |
| Raids | 42: Wilds (26) and Deeps (16) lack encounter/instance evidence even for reviewed curation; see the audit below. Onyxia's two entries are located. |
| Adventure | None; both Valthalak variants use the reviewed Spire entrance. |
| Field of Honor | 6: quests 96915/96918/96921 have outdoor Map 1 POIs, not dungeon/raid bindings. |
| Level / skill / rank / reputation | 116: global progress, not instance objectives. |

Raid audit: None of the 20 Type-0 Raid boss descriptions
has an encounter row in this build; Type-165 Time-Lost Battalion references
missing encounter 3339. The owning achievements have Instance_ID -1, and no
other instance-bound achievement supplies these boss assets. There is no Map
row for Hyjal Summit or Barrow Deeps. Map 2995 (Hyjal Crater) is InstanceType 4,
not a dungeon/raid; the four Nightmare Grove encounters on Map 2832 do not
identify these objectives. Descriptive similarities are insufficient to curate
an instance or invent a corpse entrance.
Hyjal Summit and Barrow Deeps therefore remain outside `completion.raids`:
neither has a verified Map/encounter/entrance link in this build.
**WMOAreaTable 143937** associates "The Barrow Deeps" with Winterspring Area
**618**, but establishes neither an instance nor an entrance; related Area
**17180** is absent. This is an **unverified lead**, not placement evidence.

## Zone completion

All 43 completion zones use **256 × 256** tiles, and all 1,739 source tile rows use layer 0. One area has no
tile rows: **WorldMapOverlay 5252, Zul'Gurub** in Stranglethorn (1434), key **`483:8:256:256`**; its Legacy
criterion 1222 keeps its key and pin. 536 of the 555 areas carry a hit rectangle. Of the exploration entries,
**535 match** a completion area's key and **14 do not**. The only raid is Onyxia's Lair (Map 249, Dustwallow
1445): one boss, Onyxia, refs `{684, 3271}` and `{64030, 117792}`.

Build **1.60.1.69913**: **43 completion zones, 555 areas, 937 tiles** (one area
without tiles), **65 taxis** (31 Alliance,
30 Horde, 4 Neutral; 35 Alliance-usable and 34 Horde-usable), and **31 of 32 wings**
with **62 references**. Twelve taxi exceptions and 31 wing locations are curated.
There is **one raid entry / one boss / two refs**, Onyxia's Lair in Dustwallow
(1445), Type 0 / Asset 10184 / Amount 1; those refs no longer count as Legacy.
The **two** remaining non-exploration references on completion maps collapse
into **one Legacy entry** (one duplicate removed): Valthalak in Burning Steppes
(1428), Type 27 / Asset 84195 / Amount 1. Valthalak retains
`{62054, 111555}` and `{64014, 117727}` in one entry and uses the achievement's
questline description because both leaf descriptions are empty. Legacy entry
counts for **1428 / 1434 / 1439 are 1 / 0 / 0**. Exploration and located dungeon
wing and raid references account for everything else on completion maps. The
two compound refs live only in `zones[1454]`; no completion map is added.

**Seven reputations** are curated: six neutral and one Alliance-only. All facts
below were reviewed against build **1.60.1.69913**; full evidence is in
`locations.json.reputations`.

| Faction ID / name | Zone | Client geography and normal Friendly route |
| --- | --- | --- |
| 21 Booty Bay | 1434 Stranglethorn Vale | Faction describes the coastal city; Area 35 → 33. Local quests and pirate kills; both sides. |
| 270 Zandalar Tribe | 1434 Stranglethorn Vale | Faction names Yojamba Isle and Zul'Gurub; Area 3357 → 33. Local raid kills and island turn-ins; both sides. |
| 369 Gadgetzan | 1446 Tanaris | Faction describes the cartel capital; Area 976 → 440. Local quests and pirate kills; both sides. |
| 470 Ratchet | 1413 The Barrens | Faction explicitly names the Barrens; Area 392 → 17. Local quests and Southsea pirate kills; both sides. |
| 577 Everlook | 1452 Winterspring | Faction explicitly names Winterspring; Area 2255 → 618. Local quests; both sides. |
| 59 Thorium Brotherhood | 1427 Searing Gorge | Blackrock craftsmen based at Thorium Point, Area 1446 → 51. Local quests and material turn-ins reach Friendly before later instance turn-ins; both sides. |
| 589 Wintersaber Trainers | 1452 Winterspring | Faction names Winterspring; Frostsaber Rock, Area 2241 → 618. Local repeatable provisions quest; Alliance only, with Horde capped at -42000. |

Rejected candidates: **Timbermaw Hold (576)** has Area 1769 in Felwood and
Timbermaw Post (2243) in Winterspring; **Cenarion Circle (609)** explicitly calls
Moonglade home while Cenarion Hold (3425) is in Silithus; **Argent Dawn (529)**
explicitly describes strongholds in both Plaguelands. None has one clear zone.
**Ravenholdt (349)** has a verified manor (Area 3486 → 36, Alterac Mountains), but
the client rows do not establish normal Friendly access for every class: the
classic emblem route requires rogue pickpocketing, and an unrestricted Syndicate
kill route is not verified for this build. Keep it out rather than assuming
retail behavior. **Bloodsail Buccaneers (87)** oppose included Booty Bay and the
cartel; **Syndicate (70)** cannot reach Friendly (client maximum 0). Battleground
factions and broader faction umbrellas are outside this curation.

**The Drowned City** (boss 260274) remains unplaced: WMOAreaTable 144590 names it
but points to AreaTable 17037, which is absent from this build; Map and AreaTable
supply no verified entrance zone. The separate compound step is excluded, not
counted among these 32 wings.

For reference, Gnomeregan uses `{62032, 18529}` and `{64017, 117738}`;
The Deadmines uses `{62031, 3262}` and `{64016, 117731}`.
