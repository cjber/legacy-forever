# LegacyForever.API

Other addons can read Legacy Forever's zone completion and a zone's unfinished Legacy objectives, send the player
to one, and track one in the objective tracker, through the global `LegacyForever.API`. It is version 1, minor 3;
check `version == 1` and that each function exists before calling it. The full types are in
[`types/API.lua`](../types/API.lua). On ForeverCore 1.3.2 or later the same table is listed by
`ForeverCore.APIKit.Addons()`, so an addon that does not know this one's global can still find it.

Every call returns fresh tables that you may keep or change. `map` is a UiMapID, or nil for the zone the player is
in, and coordinates run from 0 to 1.

## Published functions

`ZoneSummary(map)`, `Targets(map, limit)`, `IsTracked(key)`, `SetTracked(key, tracked)`, `Navigate(map, key)`,
`Subscribe(callback)`, `Stats()` and `Leaderboard(limit?)`, each described below.

## Minor history

- `minor` 0: version 1's first members, `ZoneSummary(map)`, `Targets(map, limit)`, `Navigate(map, key)`,
  `Subscribe(callback)` and `Stats()`, which shipped before minors were counted.
- `minor` 1: `Leaderboard(limit)`.
- `minor` 2: `Subscribe`'s `changes` table, delivered on the frame after a change, and `Targets`' not-ready answer
  before the game has reported the player.
- `minor` 3: IsTracked, SetTracked, tracked change, nil map means the current zone, achievementName and points on
  targets.

## Not ready

A read that has nothing to answer returns `nil, reason`, as `ForeverCore.APIKit.NotReady` builds it. The reason says
whether to ask again.

| reason | meaning |
|---|---|
| `"loading"` | Legacy Forever is still reading the game, so ask again later |
| `"disabled"` | the player turned the feature off |
| `"none"` | there is nothing to answer: no map was given and the player is not in a zone Legacy Forever has data for |

`ZoneSummary` and `Targets` answer `nil, "loading"` until the game has reported the player, which is when this
character's progress exists. Neither answers `"disabled"`: a category the player turned off is left out of
`categories`, and a zone with nothing counted still answers with zeroes. Called with no map they answer for the
zone the player is in, and `nil, "none"` when there is none: on a continent, or in a zone without data.

`IsTracked` and `SetTracked` answer `nil, "loading"` the same way. `Navigate` and `Stats` have no not-ready answer,
and `Leaderboard`'s only nil is `nil, "invalid"` for a bad limit.

## `ZoneSummary(map) -> LFZoneSummary?, LFReadError?`

The zone's completion, as the tracker and the continent badges show it: `done`, `total`, `pending` and `complete`, with
one entry in `categories` per category the player counts ("What counts" in the Legacy map menu). A category that is
switched off, or that the zone has none of, is left out. Pending items, whose state the game hasn't reported yet,
stay outside `total`. A zone with nothing counted is never `complete`.

Each category has a `scope`: areas, flight paths, reputations and quests are this character's; dungeons, raids and
Legacy objectives are account-wide.

`questsStatus` is `"ready"` when quests are counted and indexed, `"disabled"` when quests aren't counted,
`"missing"` without QuestieDB, `"unsupported"` for a QuestieDB this version can't read, and `"loading"` while
Questie starts or before its quests have been indexed. The index is never built during a call: a read that finds
it cold schedules the build, which runs a slice a frame, and subscribers hear when it is done.

`map` may be left out, which reads the zone the player is in, the same one Legacy Forever's map corner and tracker
show.

Errors: `"invalid"` for a map that isn't an integer, `"unsupported"` for a map Legacy Forever has no completion
data for, and `"none"` for a call with no map and no current zone. Before the game has reported the player it
answers `nil, "loading"` (see Not ready).

## `Targets(map, limit) -> LFTarget[]?, LFReadError?`

Up to `limit` (clamped to 1..5, and 5 when left out) unfinished objectives in the zone from Legacy challenges the
game lists for this character, in a stable order. An objective whose progress the game doesn't report is left out,
so `{}` means nothing unfinished is known there. `key` is opaque and stays the same for the same objective.
`achievementName` is the achievement's name and `points` the Legacy points it awards, left out when the game
reports none. `place` is set only when the bundled data has the objective's coordinates; `quantity` and `required`
only for counted criteria such as "3/10".

`map` may be left out, which reads the zone the player is in.

Errors: `"invalid"` for a non-integer map or non-number limit, `"unsupported"` for a map with no Legacy data, and
`"none"` for a call with no map and no current zone. Before the game has reported the player, whose challenge list
is empty until it does, it answers `nil, "loading"` (see Not ready).

## `IsTracked(key) -> boolean?, LFReadError?`

Whether the tracker shows the challenge the target `key` belongs to. `key` is the `key` of a `Targets` row: the
tracker holds a challenge's share of one zone, or a feeding achievement whole, so every objective of the same group
answers alike, and the API converts its own key to the tracker's at the edge.

Answers `nil, "invalid"` for a key that names no objective Legacy Forever knows, or whose challenge the game no
longer lists, and `nil, "loading"` before the game has reported the player (see Not ready).

## `SetTracked(key, tracked) -> boolean?, LFReadError?`

Tracks (`true`) or stops tracking (`false`) the challenge the target `key` belongs to, with the same `key` as
`IsTracked`. Returns `true` when the tracker's list changed, and `false` when it did not: `tracked` isn't a
boolean, `key` names no known challenge, or the list already held that state. The player's own ticks in the map
menu are the same list, so both see each other. Answers `nil, "loading"` before the game has reported the player.

## `Navigate(map, key) -> boolean, LFNavError?`

Reads the zone's objectives again and sends the player to the one `key` names: a Shortest Path Forever journey when
it takes one, else the game's own waypoint. Printing the place in chat never counts as success.

Reasons: `"invalid"` (bad map or key), `"stale"` (the objective is finished or no longer listed), `"unlocated"` (no
coordinates), `"combat"` (Shortest Path declined in combat and the map takes no waypoint) and `"unavailable"`.

## `Subscribe(callback) -> unsubscribe`

Calls `callback(changes)` on the frame after what the API answers for the zone the player is in changes. `changes` is
a fresh table naming only what changed. Calls come at most once per burst of game events, however many changes the
burst held, and never in the same call as the change. Only the subscribers there when the burst is dispatched are
called; one added by a callback waits for the next burst. An error in a callback goes to Legacy Forever's error
handler without stopping the others. The returned function unsubscribes and is safe to call twice.

`changes` has only the names that changed, each set to `true`:

| name | what changed |
|---|---|
| `progress` | any progress, quest source or "What counts" change, in any zone: what every earlier `Subscribe` call heard |
| `zone` | the zone the player is in |
| `summary` | what `ZoneSummary(zone)` answers: progress, a quest source or "What counts" |
| `targets` | what `Targets(zone, limit)` answers: the first five objectives' identities, text, achievement name, points and progress |
| `tracked` | the tracker's list: a challenge tracked or untracked, by the player's map menu or `SetTracked` |

`zone`, `summary` and `targets` read the zone the player is in; a caller showing another map reads it again when
`progress` is set. `tracked` reads this character's tracker list, the same wherever the player is. The first
subscriber starts from what the channels answer then, so it hears only later changes. Legacy Forever's own map and
tracker display switches change nothing the API answers and are not named. Read the API again rather than replaying
the change.

Earlier minors called `callback()` synchronously, within the event that changed something, and called a callback
added by another callback in the same burst. Code that relied on either now needs the next frame and the `changes`
table; `changes` is there on every minor 2 call.

## `Stats() -> LFActivityRecord[]`

Returns one row per flight path currently known in this character's most recently opened flight-master maps. A node that becomes unreachable leaves this current-known view. These rows use the latest map observation timestamp; the cumulative leaderboard retains distinct nodes and their discovery timestamps. Each row has
`addon`, `metric`, `subject`, `value`, and `eventUnix` when the client provided a timestamp. Forever's zone
exploration data marks every taxi node as discovered, so Legacy only records this metric from the flight master's
own node states. These per-node rows remain local. The leaderboard shares only a cumulative distinct-path snapshot with guild and group channels, classified by the client mode and Hardcore flag; no realm-wide record is claimed.


## `Leaderboard(limit?) -> LFFlightLeaderboard?, LFReadError?`

Available from minor 1. Returns fresh ranked rows for cumulative observed flight paths: `rank`, `name`, `value`, optional `eventUnix`, and `self` for the personal row. `metric` is `flight_path_known`, `scope` is `guild_group`, `ruleset` contains the client mode ID and Hardcore flag, `sharing` reports active participation, and `total` counts all eligible rows. Peer values are player-reported. Only the current client ruleset is compared; an unknown ruleset has no peer comparison. Self-declared challenges such as Ironman are not automatically classified.

The default top list is 10, capped at 25, with the personal row retained even below the limit. A non-integer or negative limit returns `nil, "invalid"`; zero requests only the personal row. Opt-out hides peer rows and cancels pending sends without deleting personal history or the classified peer cache. Legacy never migrates the old unclassified peer cache into a ruleset board.

Opting out cannot retract totals already received by other players. Their cached copies can remain visible.
