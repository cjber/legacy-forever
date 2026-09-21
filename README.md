<p align="center"><img src="https://raw.githubusercontent.com/cjber/legacy-here/main/media/icon-400.png" width="96" alt=""></p>

<h1 align="center">Legacy Here</h1>

<p align="center">
Your unfinished WoW: Forever Legacy challenges, on the world map, for the zone you're looking at.<br>
<a href="https://github.com/cjber/legacy-here/actions/workflows/ci.yml"><img src="https://github.com/cjber/legacy-here/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/cjber/legacy-here/releases/latest"><img src="https://img.shields.io/github/v/release/cjber/legacy-here" alt="Latest release"></a>
</p>

Legacy points are account-wide and come from challenges spread over the whole world: areas to discover, dungeons to clear, bosses, quests and reputations. The Legacy panel lists them, but it doesn't tell you which ones you can work on where you are. This addon adds that to the world map. It does not open a separate frame.

## Features

- **Map button** in the world map's top-right button column, with a count of the unfinished objectives on the map you're viewing. Its menu groups them by challenge; click one to open it in the Legacy panel. It can also hide the area pins.
- **Map pins** on areas you haven't discovered yet (small and quiet, with how many of the zone's areas are left) and on dungeon entrances, with the challenge each counts toward and its Legacy points.
- **No fixed location** lists challenges whose remaining work isn't tied to a place, such as levels, skills and ranks.
- Progress comes from the game each time, so it matches the Legacy panel and follows whichever challenge set your character sees.

## Install

Download the zip from [Releases](https://github.com/cjber/legacy-here/releases) and extract it into `_classic_beta_/Interface/AddOns/`, so you end up with `AddOns/LegacyHere/LegacyHere.toc`.

## Usage

Open the world map. The Legacy button sits below the map's own tracking buttons.

| Command | What it does |
|---|---|
| `/lh` | Short help |
| `/lh audit` | Compare the bundled data with what the game reports, and list any objective the game doesn't know |

## Where the locations come from

Everything is generated from the Forever client's own data (via [wago.tools](https://wago.tools)) by `tools/gen_legacy.py`. Nothing is matched by name or scraped from a database site.

- **Areas:** each exploration criterion names a world map overlay. Its pin is the centre of that overlay on the zone's current map art.
- **Dungeons and raids:** placed at the client's entrance marker, only where the zone is certain.
- **Kills, quests and reputations:** the client data has no reliable location for most of these, so they stay in the list without a pin until a location is verified from game data.

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

**Releasing:** add the notes to `CHANGELOG.md`, then `git tag -s vX.Y.Z && git push --tags`. The [BigWigs packager](https://github.com/BigWigsMods/packager) builds the zip and uploads it to GitHub Releases, CurseForge and Wago.

## Licence

GPL-3.0-or-later. Game data comes from the client via [wago.tools](https://wago.tools).
