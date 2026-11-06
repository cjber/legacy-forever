# About the code

Legacy Forever is a World of Warcraft: Forever addon in Lua 5.1. The files `LegacyForever.toc` lists are
what the game loads; `tests/*_spec.lua` load them in that order inside a stubbed client.

- Keep every saved variable name and every global the TOC exposes unchanged.
- Generated data, `Libs/` and `tools/forever_tools/` are never edited by hand.
- Taint: never replace a Blizzard global or hook a secure function a spec does not already hook.
- Never launch the game, Battle.net, Lutris or Wine, and never use the network.

`python3 tools/repo_rules.py` holds the rules no linter covers; run it with the other checks.

## Live roots

Things reached indirectly: none of them is dead code, even when no file calls it by name.

- `LegacyForever.toc` file list: load order `Locales/enUS.lua` (then any `Locales/<locale>.lua`), `Data/Legacy.lua, Core, Saved, ForeverFamily, WhatsNew, Model, Live, Quests, Navigate,
  ZoneCompletion, TrackerHost, Tracker, UI/Completion.xml, Completion, Settings, MapContents, UI/Map.xml, Map, API`; never reorder as formatting.
- `## SavedVariables: LegacyForeverDB`: persisted keys `tracked`, `zoneCompletion`,
  `flightPaths`, `trackerHost`, `showAreas`, `showEntrances`, `whatsNew`, `lastVersion`, named only in `Core/Saved.lua`, and `suggestFamily` (default
  in `Core/Saved.lua`) and `familyDismissed`, which the shared `UI/ForeverFamily.lua` (byte-identical in all five addons; never edit it
  here) also reads and writes through `ns.FamilyDB()`; old keys in players' saved data are compatibility obligations (`companions`, pre-0.8, is
  migrated to `suggestFamily` once and dropped).
- `## AddonCompartmentFunc: LegacyForever_OnAddonCompartmentClick`: global called by the client.
- `SLASH_LEGACYFOREVER1/2` + `SlashCmdList.LEGACYFOREVER` (Core/Core.lua): `/lf`, `/lf audit`, `/lf criteria`.
- XML `mixin=` names (`LegacyForeverMapButtonMixin`, `LegacyForeverZoneOverlayMixin`) and `<Scripts>` `method=` handlers (`OnLoad`, `OnShow`, `OnHide`, `OnClick`,
  `OnEnter`, `OnLeave`).
- Pin methods `UI/MapCanvas.lua` calls by name (`OnLoad`, `OnAcquired`, `OnReleased`, `OnMouseEnter`,
  `OnMouseLeave`, `OnMouseClickAction`), `ForeverMapMarkers.LegacyForever` (read by Tweaks Forever), tracker-module
  methods (`LayoutContents`, `OnBlockHeaderClick/Enter/Leave`), and
  addon-owned callback targets (tracker `SetCollapsed`); native manager hooks are forbidden.
- Event names registered in `Core/Live.lua` and callbacks via `EventRegistry`/`EventUtil`.
- `ns.*` fields: each file receives the shared addon table `ns`; a field set in one file is read
  in another with no import. Search all `.lua` files, including `tests/`.
- `tools/gen_legacy.py` output format: `Data/Legacy.lua` keys are the contract read through `ns.Data` by
  every TOC Lua file after it (`rg -n 'ns\.Data' .`) and by `tests/data_spec.lua`.
- `tools/legacy_render.py`: imported by `gen_legacy.py` and `screenshots.py`; `tools/db2.py` and
  `tools/locations.py`: imported by `gen_legacy.py`;
  `tools/screenshots.py`: run by hand after UI changes (needs Pillow and `wowmock`), and runs
  `tools/screenshots_model.lua` under LuaJIT so the scenes come from the real `Core/Model.lua`;
  `tools/check_diagnostics.py`, `tools/lint_multivalue.py`: run by `tools/typecheck.sh`.
- `tools/latest_build.py`: run by `.github/workflows/refresh-data.yml`; `tools/changelog.py`:
  run by `release.yml` and (`--check`) `ci.yml`; `tools/repo_rules.py`: run by `ci.yml`; `refresh-data.yml` also rewrites the `BUILD = "..."` and
  `SOURCE_DATE = "..."` lines of `gen_legacy.py` with `sed`, so keep them single-line.

## Settled

Shapes that look like defects here but are not. Add an entry when the same shape keeps being raised and
dismissed for the same reason.

- nil guard after a `number?` return (defensive-noise): a nil guard right after `ParseKey` or
  another `number?` return narrows the type for LuaLS; removing it trades the branch for a
  `---@cast`, e.g. `Core/Model.lua`
- Tracker `uiOrder` `0` (defensive-noise): Legacy Forever's registered slot in WFA-5, not a missing
  negative, e.g. `UI/Tracker.lua`
- sibling names in the shared tracker host (comment-narration, dead-code): `UI/TrackerHost.lua`,
  `tests/tracker_host_spec.lua` and `tests/tracker_geometry_spec.lua` are kept byte-identical with the copies
  in the sibling addon repositories, so `/agf tracker`, `AGF_TRACKER_HOSTS` and `lint_copy` refer to those
  copies; an edit to any of the three is the owner's decision across all copies, e.g. `UI/TrackerHost.lua`

## Open questions for reviewers

- SavedVariables timing: `LegacyForever.toc` sets `LoadSavedVariablesFirst: 1` and Core/Saved.lua relies
  on it, but UI/Completion.lua still defers for a client that might ignore the directive. Until that
  is confirmed in game, the `LegacyForeverDB or {}` guard in `Core/Saved.lua` is not defensive noise.
- FrameXML helpers (`tContains`, `tIndexOf`, `CountTable`, `Mixin`) are the platform for reinvented
  helpers, but only `tContains` and `Mixin` are confirmed on this client.
