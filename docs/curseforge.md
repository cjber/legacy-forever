Legacy Here puts your unfinished WoW: Forever Legacy challenges on the world map, for the zone you're looking at. The Legacy panel lists every challenge, but not which ones you can work on where you are; this adds that to the map, and keeps a small tracker of the challenges you pick.

![Ashenvale on the world map with undiscovered areas shaded, the zone completion corner and the Legacy menu open](https://raw.githubusercontent.com/cjber/legacy-here/main/docs/screenshots/map.png)

![The Legacy map menu with tick boxes to track challenges, grouped by type](https://raw.githubusercontent.com/cjber/legacy-here/main/docs/screenshots/menu.png)

![Kalimdor on the world map with a Legacy badge on each zone that still has dungeon objectives](https://raw.githubusercontent.com/cjber/legacy-here/main/docs/screenshots/continent.png)

![The objective tracker with Ashenvale's completion and the tracked Legacy challenges](https://raw.githubusercontent.com/cjber/legacy-here/main/docs/screenshots/tracker.png)

## Features

- **Map button** in the world map's button column, with a count of the unfinished objectives on the map you're viewing. Its menu lists them by challenge, with a tick box to track each one.
- **Tracker**: a Legacy section at the top of the objective tracker shows what you track with live progress. A zone ticked in the map menu tracks just that zone, such as "0/12 Explore Felwood" under Explorer. Click one to open it in the Legacy panel.
- **Map pins** on dungeon entrances, with the challenge each counts toward and its Legacy points.
- **Undiscovered areas** are shaded in their real shape on the zone map. Hover one to see which challenge counts it and how many of the zone's areas are left.
- **Zone completion**, Guild Wars 2 style: areas explored, dungeons, raids and the zone's other Legacy objectives, as a percentage in the map's corner and, if you choose, in the tracker. Flight paths and local reputations can be added under "What counts". A zone reaching 100% gets a toast and a sound.
- **No fixed location** lists challenges whose remaining work isn't tied to a place, such as levels, skills and ranks.

Progress comes from the game each time, so it always matches the Legacy panel.

## Usage

Open the world map: the Legacy button sits below the map's own tracking buttons. Tick a challenge in its menu to track it.

- `/lh` shows short help.
- `/lh audit` compares the bundled data with what the game reports. Found a wrong or missing objective? Include its output in an issue on [GitHub](https://github.com/cjber/legacy-here/issues).

Locations are generated from the Forever client's own data; nothing is matched by name or scraped from a database site.

Source code: [github.com/cjber/legacy-here](https://github.com/cjber/legacy-here). Licence: GPL-3.0-or-later.
