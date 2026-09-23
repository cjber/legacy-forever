# Changelog

What changed in each release, in the terms someone chasing Legacy points would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists: what matters about a release is why the map or tracker now shows something different.

Each version's entry is also its release notes on GitHub, CurseForge and Wago. Older entries are kept
verbatim rather than rewritten as the addon moves.

## [Unreleased]

- **Ticking a zone's objective in the map menu tracks just that zone**, not the whole challenge. Ticking "Explore Felwood" adds Explorer to the tracker with one line under it, "0/12 Explore Felwood", counting up as you discover its areas; tick more zones and each gets its own line under the same challenge. A dungeon ticked from its zone's map shows that dungeon under its Spelunker challenge in the same way. Unticking a zone removes its line, and the challenge goes once nothing under it is tracked. Challenges ticked under "No fixed location", and anything you tracked before this version, still show every unfinished step.
- **Zone badges on continent maps carry their count on the icon's corner**, like a stack count on a bag slot, in the game's small number font, instead of floating beside the icon.

## [0.3.0] - 2026-09-23

A menu on the zone completion tracker, a new icon that matches the other WoW: Forever addons, and two fixes.

- **Right-click a zone in the completion tracker for a menu**: open the map or hide the section, as on the Legacy section. A left click still opens the map.
- **Fixed** the collapsed zone box on the world map keeping the width of the counts it hides.
- **Fixed** a "couldn't add a section to the objective tracker" warning after a slow login, when the section attached a moment later.
- **A new icon in the addon list**, drawn to match the other WoW: Forever addons, so it is easy to spot beside them.

## [0.2.0] - 2026-09-21

Zone completion, Guild Wars 2 style, with a reward when a zone reaches 100%.

- **Zone completion**: each zone shows how much of it you've done, as areas explored, flight paths learned, dungeons cleared for Legacy, the zone's other Legacy objectives and its local reputations at Friendly, with the rest listed on hover. It sits in the world map's corner for the zone you're viewing, and on continent maps it is in each zone badge's tooltip. Tick it in the map menu to also add the zone you're in to the objective tracker. Each collapses to just the zone and its percentage, and the map menu turns either off. "What counts" in the map menu drops any category from the count and the percentage. Flight paths count once you've opened a flight master on that continent, since that is the only place the game says which ones you know; until then they show as "?" with a note to visit one.
- **Raids count toward zone completion**, once every boss is down, on any character. Onyxia's Lair counts in Dustwallow Marsh.
- **A zone reaching 100% gets a toast and a sound**, in the game's own achievement style, with your continent's progress in chat. Click the toast to open that zone's map. Zones already complete when you log in stay quiet, and every category counts toward the toast whatever "What counts" shows.
- **Continent progress** sits under each zone badge's summary on continent maps, as in "Kalimdor: 3 of 20 zones complete (15%)".
- **The map menu shows each challenge with its map icon**: the Legacy icon for objectives pinned on the map, the compass for exploration, which the map shades rather than pins.
- **Undiscovered areas are shaded instead of pinned.** Each area you haven't found is now shaded darker, in the area's own shape, the way unseen ground reads on a map, rather than having a Legacy icon dropped in its middle. Areas are big, and the shading shows where they start and end. It's on by default; "Show undiscovered areas" in the map menu turns it off. Exploration is never pinned now, and continent badges count only objectives with a place, such as bosses and dungeons. Map pin icons are a little larger.
- **More dungeon objectives have a place.** 56 objectives that sat under "No fixed location" are now pinned at their dungeon's entrance, including Lord Valthalak Laid to Rest at Upper Blackrock Spire. The Novice Spelunker step "Ragefire Chasm or Hall of Thanes" is now pinned at Ragefire Chasm in Orgrimmar. Hall of Thanes, the Hyjal Summit and Barrow Deeps raid bosses, and Forever's other new dungeons stay under "No fixed location": the client data doesn't give their entrances yet, and no addon or database has them either.
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
