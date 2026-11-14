# Third-party inputs

Everything Legacy Forever is built from that it did not write itself: where each comes from, where its pin lives, its
licence, and whether any of it reaches the zip players install. A pin is named by the constant that holds it, so a data
refresh that moves the pin never leaves this file behind. The addon itself is GPL-3.0-or-later ([LICENSE](LICENSE)).

## Ships in the zip

| Input | Used for | Pin | Licence |
|---|---|---|---|
| WoW: Forever client tables, via [wago.tools](https://wago.tools) | Achievements, criteria, zones and instances in `Data/Legacy.lua` | `BUILD` in `tools/gen_legacy.py` | Blizzard Entertainment's game data |
| WoW: Forever client terrain files (root ADT files), via [wago.tools](https://wago.tools) | Exploration area outlines in `Data/Explore.lua` | `BUILD` in `tools/gen_explore.py` | Blizzard Entertainment's game data |
| `tools/locations.json` | Reviewed facts the client data cannot give (where a criterion happens), each with its evidence | Committed; `tools/locations.py` checks it against the pinned rows | This addon's own |

No embedded libraries ship. `media/` is this addon's own: the icon is drawn in `media/icon.svg`. `Locales/frFR.lua`
is the French translation Brainc3ll wrote (#99), since extended with machine-translated lines (marked `-- mt`) for new
strings, under this addon's licence.

## Read in game, never bundled

| Input | Used for | Licence |
|---|---|---|
| Questie and QuestieDB, if installed | A zone's quests for the Quests category | QuestieDB carries no licence; nothing is copied |
| AtlasLoot Classic, if installed | Recommended dungeon levels, through its public ItemDB and Loader APIs | GPL-2.0; nothing is copied |
| Shortest Path Forever, if installed | Routes to a zone or objective, through its public API | GPL-3.0-or-later |

## Build and test only

| Input | Used for | Pin | Licence |
|---|---|---|---|
| [Blizzard UI source](https://github.com/Gethe/wow-ui-source) | The native tracker integration spec, fetched into `tools/.cache/` | `REVISION` in `tools/fetch_tracker_ui.py` | Blizzard Entertainment's; fetched, never committed |
| [Ketho's WoW API annotations](https://github.com/Ketho/vscode-wow-api) | lua-language-server types in `tools/typecheck.sh` | `revision` in `tools/typecheck.sh` | MIT |
| [FrameXML annotations](https://github.com/NumyAddon/FramexmlAnnotations) | FrameXML types, the Ketho checkout's `Annotations/FrameXML` submodule | The gitlink in that Ketho revision | MIT |
| [forever_tools](https://github.com/cjber/forever-core/tree/main/.agents/skills/wow-forever-addon/tooling/forever_tools) | Shared lints, release checks and the generated-data gate, vendored in `tools/forever_tools/` | `revision` in `tools/forever_tools/MANIFEST.json` | MIT |
| [forever-core/tools/wowmock](https://github.com/cjber/forever-core/tree/main/tools/wowmock) and the client art it fetches | `tools/screenshots.py` | `FOREVER_CORE` (a local forever-core checkout); chrome art at `UI_ART_BUILD` in `tools/screenshots.py`, map content at the build recorded in `Data/Legacy.lua` | MIT; the art is Blizzard Entertainment's, fetched at build time and committed only as it appears in `docs/screenshots/` |
| [forever_sim](https://github.com/cjber/forever-core/tree/main/.agents/skills/wow-forever-addon/tooling/forever_sim) | Real Blizzard UI scenario tests, vendored in `tools/forever_sim/` | `revision` in `tools/forever_sim/MANIFEST.json` | MIT; Blizzard UI is fetched, never bundled |
| Ko-fi's Support me on Ko-fi button | The support button in the README (`ko-fi.com/img/githubbutton_sm.svg`) and its PNG render, `docs/kofi-button.png`, in the store description | None: the README links Ko-fi's live file; the PNG is rendered from it | Ko-fi's brand asset, used as Ko-fi provides it for linking to a Ko-fi page |
| `docs/github-sponsors-button.png` | The GitHub Sponsors button in the README and store description; drawn here to match the Ko-fi button, with the heart from GitHub's [Octicons](https://github.com/primer/octicons) and the Adwaita Sans font | None | Octicons: MIT; Adwaita Sans: SIL OFL 1.1 |
| `docs/discord-button.png` | The Discord button on the store page; drawn in forever-core with Discord's logo from [Simple Icons](https://simpleicons.org) and the Adwaita Sans font | None | Simple Icons: CC0; Adwaita Sans: SIL OFL 1.1; the logo is Discord's, used to link to a Discord server |

CI tools (StyLua, ruff, luacheck, lua-language-server, actionlint, zizmor, gitleaks, the BigWigs packager) are pinned in `.github/workflows/` and `tools/typecheck.sh`, except luajit and luacheck, which come from the runner's apt; they build and check the addon and are never part of it.

## Players

Credit for the reports, translations and requests behind the addon.

| Who | What | Notes |
|---|---|---|
| [kowakowa93](https://github.com/kowakowa93) | Hide the region progress bar when its tracker section is collapsed | GitHub; #516, [report and fix](https://github.com/cjber/forever-core/issues/602#issuecomment-6882241203) |
| cotijelucie | Count quests finished by other characters | Discord #help, #513 |
| Brainc3ll | French translation | GitHub; #99, #203, #353 |
| Bigabyte | Tracker no longer shifts in Edit Mode | GitHub; #103 |
| overspark | Dungeon entrance pins can be hidden | CurseForge; #139 |
| overspark | Level ranges on entrance tooltips | CurseForge; #222 |
| overspark | Cleared entrances drawn faded | CurseForge |
| [Mouchoir](https://github.com/Mouchoir) | Fixed the map button errors (code) | GitHub; #147, #148, PR #149 |
| [DanielVafidis](https://github.com/DanielVafidis) | Fixed the addon breaking Questie | GitHub; #150 |
| TheCheat54 | Tirisfal Glades counts 18 exploration areas | GitHub; #332 |
| KeijinDE | Fixed the ForeverCore link | CurseForge; #441 |
| Lûca | Zone completion corner back on the world map | Discord |
| cotijelucie | Show where to discover areas | Discord; #459 |
| cotijelucie | Map markers drawn above the area shading | Discord; #464 |
| Lûca | Undiscovered areas shaded above Leatrix Maps' unexplored tint | Discord; #470 |

## Inspired by

Credit for the addons and projects an idea came from.

| Who | What | Notes |
|---|---|---|
| [Polestar](https://github.com/fitzforge/polestar) by Fitz | Drawing the world map on frames of its own; the shared report window and tooling | GPL-3.0. Inspired only; no code was copied. Fitz is welcome to use our code. |

Thanks also to everyone else who reported a bug, here or on CurseForge.
