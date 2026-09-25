# LegacyForever.API

Other addons can read Legacy Forever's zone completion and a zone's unfinished Legacy objectives, and send the
player to one, through the global `LegacyForever.API`. It is version 1; check `version == 1` and that each function
exists before calling it. The full types are in [`types/API.lua`](../types/API.lua).

Every call returns fresh tables that you may keep or change. `map` is always a UiMapID and coordinates run from 0
to 1.

## `ZoneSummary(map) -> LFZoneSummary?, LFReadError?`

The zone's completion, as the map corner and tracker show it: `done`, `total`, `pending` and `complete`, with one
entry in `categories` per category the player counts ("What counts" in the Legacy map menu). A category that is
switched off, or that the zone has none of, is left out. Pending items, whose state the game hasn't reported yet,
stay outside `total`. A zone with nothing counted is never `complete`.

Each category has a `scope`: areas, flight paths, reputations and quests are this character's; dungeons, raids and
Legacy objectives are account-wide.

`questsStatus` is `"disabled"` when quests aren't counted, `"missing"` without QuestieDB, `"unsupported"` for a
QuestieDB this version can't read, and `"loading"` while Questie starts or before its quests have been indexed. The
index is never built during a call: a read that finds it cold schedules the build for the next frame, and
subscribers hear when it is done.

Errors: `"invalid"` for a map that isn't an integer, `"unsupported"` for a map Legacy Forever has no completion
data for, `"loading"` before the game has reported the player's faction.

## `Targets(map, limit) -> LFTarget[]?, LFReadError?`

Up to `limit` (clamped to 1..5) unfinished objectives in the zone from Legacy challenges the game lists for this
character, in a stable order. An objective whose progress the game doesn't report is left out, so `{}` means
nothing unfinished is known there. `key` is opaque and stays the same for the same objective. `place` is set only
when the bundled data has the objective's coordinates; `quantity` and `required` only for counted criteria such as
"3/10".

Errors: `"invalid"` for a non-integer map or non-number limit, `"unsupported"` for a map with no Legacy data.

## `Navigate(map, key) -> boolean, LFNavError?`

Reads the zone's objectives again and sends the player to the one `key` names: a Shortest Path Forever journey when
it takes one, else the game's own waypoint. Printing the place in chat never counts as success.

Reasons: `"invalid"` (bad map or key), `"stale"` (the objective is finished or no longer listed), `"unlocated"` (no
coordinates), `"combat"` (Shortest Path declined in combat and the map takes no waypoint) and `"unavailable"`.

## `Subscribe(callback) -> unsubscribe`

Calls `callback` with no arguments after progress, a quest source or "What counts" changes; reread what you show.
Calls come at most once per burst of game events. The returned function unsubscribes and is safe to call twice. An
error in a callback goes to the game's error handler without stopping the others.
