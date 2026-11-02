# About the app

Legacy Forever is a World of Warcraft: Forever addon written in Lua 5.1. It cannot run outside the
game client, and you must never start the game. What runs here is its headless test harness: each
`tests/<name>_spec.lua` stubs the client API, loads the addon files the TOC lists, and checks one
feature. Run a spec with `luajit tests/<name>_spec.lua`; a failing spec exits non-zero and prints
the failed assertion. `luacheck <file>` lints a file.

Two invariants have their own specs and are the first place to look:

- `tests/map_canvas_spec.lua` runs the world-map files against a canvas that fails on any write the
  game's secure code walks. Drawing must go through `UI/MapCanvas.lua` with the addon's own frames.
- The tracker section must be built in `UI/TrackerHost.lua` and rendered only after
  `PLAYER_ENTERING_WORLD` and `VARIABLES_LOADED`, deferred one frame.

Use the specs and `luajit -e` one-liners that load the harness to check what a change claims.
Report a spec that fails, an error that a spec prints, or a behaviour a spec shows that the change
does not intend.

## Sign in

No sign-in.

## Important flows

- The world map: zone shading for unfinished dungeon Legacy challenges, the per-zone badge, and
  the corner percentage that folds away when clicked.
- The map menu with tick boxes per challenge, grouped by type.
- The objective tracker section listing tracked challenges.

## Never do these things

- Never launch the game, Battle.net, Lutris or Wine.
- Never edit, move or delete files.
- Never use the network.
