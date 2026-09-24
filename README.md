<p align="center"><img src="https://raw.githubusercontent.com/cjber/legacy-forever/main/media/icon-400.png" width="96" alt=""></p>

<h1 align="center">Legacy Forever</h1>

<p align="center">
Your unfinished WoW: Forever Legacy challenges, on the world map, for the zone you're looking at.<br>
<a href="https://github.com/cjber/legacy-forever/actions/workflows/ci.yml"><img src="https://github.com/cjber/legacy-forever/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/cjber/legacy-forever/releases/latest"><img src="https://img.shields.io/github/v/release/cjber/legacy-forever" alt="Latest release"></a>
</p>

Legacy points are account-wide and come from challenges spread over the whole world: areas to discover, dungeons to clear, bosses, quests and reputations. The Legacy panel lists them, but it doesn't tell you which ones you can work on where you are. This addon adds that to the world map, and keeps a small tracker of the challenges you pick. It uses the map's own buttons, menus and pins, and the objective tracker, so it looks like it came with the game.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/legacy-forever/main/docs/screenshots/map.png" width="640" alt="Ashenvale on the world map with undiscovered areas shaded, the zone completion corner and the Legacy menu open"></p>

## Features

- **Map button** in the world map's top-right button column: a Legacy shield with a number inside, the unfinished objectives on the map you're viewing. Its menu lists them by challenge, with a tick box to track each one. Challenges with no fixed place are grouped the way the Legacy panel groups them. Undiscovered areas are shaded on the zone map; the same menu turns the shading off.
- **Tracker**: a Legacy section at the top of the objective tracker lists what you track, with live progress. Tick a zone's objective in the map menu and it tracks just that zone: the challenge as a header with a line under it, such as "0/12 Explore Felwood", one line for each zone you tick. Challenges ticked under "No fixed location" list every unfinished step (12/20, or areas done in an exploration step). Click a challenge to open it in the Legacy panel; right-click for a menu that can stop tracking it. Forever doesn't allow Blizzard's own tracking of these, so this replaces it.
- **Map pins** on dungeon entrances, with the challenge each counts toward and its Legacy points. Left-click a pin to travel there: with [Shortest Path Forever](https://github.com/cjber/shortest-path-forever) it plans the whole journey, otherwise it sets the game's own waypoint.
- **Undiscovered areas** are shaded darker in their real shape on the zone map, so you can see where to go at a glance. Hovering one names it and, when a Legacy challenge counts it, shows the challenge, its points and how many of the zone's areas are left.
- **Zone completion**: how much of a zone's Legacy objectives you've done, Guild Wars 2 style. Out of the box it counts areas explored (each is a step of the zone's Explore achievement, toward Explorer) for the character, and dungeons, raids and the zone's other Legacy objectives for your Legacy progress on the account. Flight paths learned and local reputations at Friendly aren't Legacy objectives; tick them under "What counts" to count them too. A zone reaching 100% of what you count gets a toast and a sound, and continent maps show how many of the continent's zones are complete. It shows in the world map's corner, for the zone you're viewing, and in each zone badge's tooltip on continent maps; unticking "On the world map" in the map menu hides both the corner and the continent badges. It can also show in the objective tracker, for the zone you're in (the zone name, a percentage and one row of counts), once you tick that in the map menu. Each can be collapsed, and hovering lists what's left. "What counts" in the same menu adds or leaves out any category, and the percentage and the toast follow.
- **No fixed location** lists challenges whose remaining work isn't tied to a place, such as levels, skills and ranks.
- Progress comes from the game each time, so it matches the Legacy panel and follows whichever challenge set your character sees.

## Install

Install it from [CurseForge](https://www.curseforge.com/wow/addons/legacy-forever) or [Wago Addons](https://addons.wago.io/addons/legacy-forever), or download the zip from [Releases](https://github.com/cjber/legacy-forever/releases). To install the zip by hand, extract it into `_classic_beta_/Interface/AddOns/` so you end up with `AddOns/LegacyForever/LegacyForever.toc`.

## Usage

Open the world map. The Legacy button sits below the map's own tracking buttons. Tick a challenge in its menu to add it to the tracker.

| Command | What it does |
|---|---|
| `/lf` | Short help |
| `/lf audit` | Compare the bundled data with what the game reports, and list any objective the game doesn't know |
| `/lf criteria 684` | List every criterion the game reports for one achievement (useful alongside an audit's unknown IDs) |

## Where the locations come from

Everything is generated from the Forever client's own data (via [wago.tools](https://wago.tools)) by `tools/gen_legacy.py`. Objectives are joined by ID, not by name, and nothing is scraped from a database site; flight paths are the one exception, placed by the zone named in each node's name.

- **Areas:** each exploration criterion names a world map overlay. The zone map shades that overlay on the zone's current map art; exploration is never pinned.
- **Dungeons and raids:** placed at the client's entrance marker, only where the zone is certain.
- **Zone completion:** what each category counts, and why quests and rares are left out, is in [docs/zone-completion.md](docs/zone-completion.md).
- **Kills, quests and reputations:** the client ships no spawn or encounter data for these (none of the 53 Legacy kill targets has a Creature row), so they stay unpinned. The exception is Valthalak, a quest whose Blackrock Spire entrance was reviewed by hand. Track the challenge to follow their progress instead.

**Found a wrong or missing objective?** Run `/lf audit` and [open an issue](https://github.com/cjber/legacy-forever/issues/new) with the output.

## Development

```sh
# link the checkout into the game
ln -s "$PWD" ".../World of Warcraft/_classic_beta_/Interface/AddOns/LegacyForever"

luacheck .                     # lint
stylua --check .               # format
ruff format --check . && ruff check .
tools/typecheck.sh             # LuaLS 3.19.1 + multi-value lint and Python self-tests
for s in tests/*_spec.lua; do luajit "$s" || exit 1; done   # generated data, zone and challenge logic
python3 tools/gen_legacy.py    # regenerate Data/Legacy.lua (see tools/README.md)
```

Install LuaLS **3.19.1**, Python 3.12+ and Git before running `tools/typecheck.sh`. The first run
fetches the pinned WoW API annotations and their pinned FrameXML submodule into ignored `.types/`;
later runs verify and reuse that checkout. It checks every runtime Lua file, including generated
data, and fails on every diagnostic. `types/` supplies the addon and missing Forever API contracts.
See [the tooling notes](tools/README.md#type-checking) for the multi-value rule.

CI runs these checks on main pushes and pull requests. Each day a scheduled job checks wago.tools for a newer Forever build and, if the Legacy data differs, opens a pull request with the regenerated `Data/Legacy.lua`.

**Releasing:** move the `[Unreleased]` notes in `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD`, then `git tag -s vX.Y.Z && git push --tags`. The [BigWigs packager](https://github.com/BigWigsMods/packager) builds the zip and uploads it to GitHub Releases, CurseForge and Wago, with that version's entry (`tools/changelog.py`) as the release notes.

**Contributing:** read [CONTRIBUTING.md](https://github.com/cjber/.github/blob/main/CONTRIBUTING.md) and this repository's [AGENTS.md](AGENTS.md). Report security problems privately, as [SECURITY.md](https://github.com/cjber/.github/blob/main/SECURITY.md) describes.

## Licence

GPL-3.0-or-later. Game data comes from the client via [wago.tools](https://wago.tools).

Made by Cillian Berragan · [cillian.dev](https://cillian.dev) · [GitHub](https://github.com/cjber) · [Twitter](https://twitter.com/cjberragan)
