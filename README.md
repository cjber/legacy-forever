<p align="center"><img src="https://raw.githubusercontent.com/cjber/legacy-here/main/media/icon-400.png" width="96" alt=""></p>

<h1 align="center">Legacy Here</h1>

<p align="center">
Your unfinished WoW: Forever Legacy challenges, on the world map, for the zone you're looking at.<br>
<a href="https://github.com/cjber/legacy-here/actions/workflows/ci.yml"><img src="https://github.com/cjber/legacy-here/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/cjber/legacy-here/releases/latest"><img src="https://img.shields.io/github/v/release/cjber/legacy-here" alt="Latest release"></a>
</p>

Legacy points are account-wide and come from challenges spread over the whole world: areas to discover, dungeons to clear, bosses, quests and reputations. The Legacy panel lists them, but it doesn't tell you which ones you can work on where you are. This addon adds that to the world map, and keeps a small tracker of the challenges you pick.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/legacy-here/main/docs/screenshots/map.png" width="640" alt="Ashenvale on the world map with undiscovered areas shaded, the zone completion corner and the Legacy menu open"></p>

## Features

- **Map button** in the world map's top-right button column, with a count of the unfinished objectives on the map you're viewing. Its menu lists them by challenge, with a tick box to track each one. Challenges with no fixed place are grouped the way the Legacy panel groups them. Undiscovered areas are shaded on the zone map; the same menu turns the shading off.
- **Tracker**: a Legacy section at the top of the objective tracker lists the challenges you track, each unfinished step with its live progress (12/20, or areas done in an exploration step). Click a challenge to open it in the Legacy panel; right-click for a menu that can stop tracking it. Forever doesn't allow Blizzard's own tracking of these, so this replaces it.
- **Map pins** on dungeon entrances, with the challenge each counts toward and its Legacy points.
- **Undiscovered areas** are shaded darker in their real shape on the zone map, so you can see where to go at a glance. Hovering one names it and, when a Legacy challenge counts it, shows the challenge, its points and how many of the zone's areas are left.
- **Zone completion**: how much of a zone you've done, Guild Wars 2 style. Areas explored, flight paths learned and local reputations at Friendly count for the character; dungeons, raids and the zone's other Legacy objectives count your Legacy progress on the account. A zone reaching 100% gets a toast and a sound, and continent maps show how many of the continent's zones are complete. It shows in the world map's corner, for the zone you're viewing, and in each zone badge's tooltip on continent maps. It can also show in the objective tracker, for the zone you're in (the zone name, a percentage and one row of counts), once you tick that in the map menu. Each can be collapsed, and hovering lists what's left. "What counts" in the same menu leaves out any category you don't care about, and the percentage follows.
- **No fixed location** lists challenges whose remaining work isn't tied to a place, such as levels, skills and ranks.
- Progress comes from the game each time, so it matches the Legacy panel and follows whichever challenge set your character sees.

## Install

Install it from [CurseForge](https://www.curseforge.com/wow/addons/legacy-here) or [Wago Addons](https://addons.wago.io/addons/legacy-here), or download the zip from [Releases](https://github.com/cjber/legacy-here/releases). To install the zip by hand, extract it into `_classic_beta_/Interface/AddOns/` so you end up with `AddOns/LegacyHere/LegacyHere.toc`.

## Usage

Open the world map. The Legacy button sits below the map's own tracking buttons. Tick a challenge in its menu to add it to the tracker.

| Command | What it does |
|---|---|
| `/lh` | Short help |
| `/lh audit` | Compare the bundled data with what the game reports, and list any objective the game doesn't know |
| `/lh criteria 684` | List every criterion the game reports for one achievement (useful alongside an audit's unknown IDs) |

## Where the locations come from

Everything is generated from the Forever client's own data (via [wago.tools](https://wago.tools)) by `tools/gen_legacy.py`. Nothing is matched by name or scraped from a database site.

- **Areas:** each exploration criterion names a world map overlay. The zone map shades that overlay on the zone's current map art; exploration is never pinned.
- **Dungeons and raids:** placed at the client's entrance marker, only where the zone is certain.
- **Zone completion:** areas are the zone's map overlays, the same ones the game reveals as you explore. Flight paths are the client's flight nodes for your faction, placed by the zone in each node's name. The game only says which ones a character knows at a flight master, so flight paths count once you've opened one on that continent, and show as "?" until then. Special services with nothing to learn, such as the Nighthaven druid flights, are left out. Dungeons are the single-boss clears in the Legacy Spelunker challenges, by the zone of the instance entrance. Raids are the Conqueror challenges' bosses, by the zone of the raid entrance, and count once every boss is down; only Onyxia's Lair has an entrance in the client data so far. Legacy objectives are the zone's other placed Legacy steps, with a step's variants counted once. Reputations are a short curated list of factions tied to a single zone, such as Booty Bay for Stranglethorn. Quests and rares are left out: the client doesn't say which belong to a zone, and no openly licensed list covers Forever.
- **Kills, quests and reputations:** the client ships no spawn or encounter data for these (none of the 53 Legacy kill targets has a Creature row), so they stay unpinned. Track the challenge to follow their progress instead.

**Found a wrong or missing objective?** Run `/lh audit` and [open an issue](https://github.com/cjber/legacy-here/issues/new) with the output.

## Development

```sh
# link the checkout into the game
ln -s "$PWD" ".../World of Warcraft/_classic_beta_/Interface/AddOns/LegacyHere"

luacheck .                     # lint
stylua --check .               # format
luajit tests/data_spec.lua     # generated data
luajit tests/model_spec.lua    # zone / challenge logic
python3 tools/gen_legacy.py    # regenerate Data/Legacy.lua (see tools/README.md)
```

CI runs these checks on every push. Each day a scheduled job checks wago.tools for a newer Forever build and, if the Legacy data differs, opens a pull request with the regenerated `Data/Legacy.lua`.

**Releasing:** move the `[Unreleased]` notes in `CHANGELOG.md` under `## [X.Y.Z] - YYYY-MM-DD`, then `git tag -s vX.Y.Z && git push --tags`. The [BigWigs packager](https://github.com/BigWigsMods/packager) builds the zip and uploads it to GitHub Releases, CurseForge and Wago, with that version's entry (`tools/changelog.py`) as the release notes.

## Licence

GPL-3.0-or-later. Game data comes from the client via [wago.tools](https://wago.tools).

Made by Cillian Berragan · [cillian.dev](https://cillian.dev) · [GitHub](https://github.com/cjber) · [Twitter](https://twitter.com/cjberragan)
