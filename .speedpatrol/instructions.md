# About the app

Legacy Forever is a World of Warcraft: Forever addon in Lua 5.1. The game cannot run here. The
benchmarks run the headless harness the specs use, which stubs the client API and loads the files
`LegacyForever.toc` lists in order.

- CI runs `harness.perf` on every pull request (`.github/workflows/speedpatrol.yml`, 3 rounds) and fails on a
  regression. `gate.specs` runs only in local patrols.
- Keep a change only when it speeds up a file the TOC loads or the spec suite itself. A change to a
  bench script or other measuring code is not a speed-up.
- Every change must pass the full gate in `AGENTS.md` under "Commands".
- Generated data and vendored code are never edited by hand.
- Commit only the files the change needs: no profiler output or scratch files.
- Never use the network, and never start the game, Battle.net, Lutris or Wine. The headless client (forever-core's `wow-forever-addon/in-game.md`) tests the build linked into the game, not this checkout, so in-game checks belong to the agent that ships a change.
