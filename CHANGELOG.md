# Changelog

What changed in each release, in the terms someone chasing Legacy points would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists: what matters about a release is why the map or tracker now shows something different.

Each version's entry is also its release notes on GitHub, CurseForge and Wago. Older entries are kept
verbatim rather than rewritten as the addon moves.

## [Unreleased]

- **Zone completion**, an optional extension turned on from the map menu: each zone shows how much of it you've done, as areas explored, flight paths learned and dungeons cleared for Legacy, with the rest listed on hover. It can sit in the objective tracker for the zone you're in, in the world map's corner for the zone you're viewing, or both, and each collapses to just the zone and its percentage. Continent maps show every zone's percentage.
- **`/lh audit`** now also checks the zone you're in against what the game reports for areas and flight paths, and runs even when no Legacy challenges are listed yet.

## [0.1.0] - 2026-09-21

First release.

- A Legacy button on the world map counts the unfinished Legacy objectives on the map you're viewing.
- Pins mark 493 undiscovered areas and dungeon entrances; area pins show how much of the zone is left and are off until turned on in the map menu.
- Challenges with no fixed location are listed separately.
- Tick a challenge in the map menu to track it in a Legacy section of the objective tracker, with each unfinished step and its live progress.
- `/lh audit` checks the bundled data against the game.
- Data from Forever build 1.60.1.69913.
