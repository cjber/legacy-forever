# Changelog

What changed in each release, in the terms someone chasing Legacy points would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists: what matters about a release is why the map or tracker now shows something different.

Each version's entry is also its release notes on GitHub, CurseForge and Wago. Older entries are kept
verbatim rather than rewritten as the addon moves.

## [Unreleased]

- **Zone completion**: each zone shows how much of it you've done, as areas explored, flight paths learned, dungeons cleared for Legacy, the zone's other Legacy objectives and its local reputations at Friendly, with the rest listed on hover. It sits in the world map's corner for the zone you're viewing, and continent maps show every zone's percentage. Tick it in the map menu to also add the zone you're in to the objective tracker. Each collapses to just the zone and its percentage, and the map menu turns either off. "What counts" in the map menu drops any category from the count and the percentage. Flight paths count once you've opened a flight master on that continent, since that is the only place the game says which ones you know; until then they show as "?" with a note to visit one.
- **Undiscovered areas are shaded instead of pinned.** Each area you haven't found is now shaded darker, in the area's own shape, the way unseen ground reads on a map, rather than having a Legacy icon dropped in its middle. Areas are big, and the shading shows where they start and end. It's on by default; "Show undiscovered areas" in the map menu turns it off.
- **More dungeon objectives have a place.** 56 objectives that sat under "No fixed location" are now pinned at their dungeon's entrance, including Lord Valthalak Laid to Rest at Upper Blackrock Spire. Raid bosses stay unpinned for now: the client data doesn't yet tie them to their raid.
- **Counts on the map read more cleanly**, in the game's regular small font with a soft shadow instead of the heavy outlined numbers.
- **`/lh audit`** now also checks the zone you're in against what the game reports for areas and flight paths, and runs even when no Legacy challenges are listed yet.

## [0.1.0] - 2026-09-21

First release.

- A Legacy button on the world map counts the unfinished Legacy objectives on the map you're viewing.
- Pins mark 493 undiscovered areas and dungeon entrances; area pins show how much of the zone is left and are off until turned on in the map menu.
- Challenges with no fixed location are listed separately.
- Tick a challenge in the map menu to track it in a Legacy section of the objective tracker, with each unfinished step and its live progress.
- `/lh audit` checks the bundled data against the game.
- Data from Forever build 1.60.1.69913.
