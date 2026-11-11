"""AreaPin's terrain glow, drawn for the screenshots from the same values as the addon.

UI/Map.lua AreaPin:Paint shows each undiscovered area's rings as a wide soft stroke under a brighter core,
tinted gold and feathered by media/Glow.tga (Core/Art.lua Art.GlowLine). This module draws those lines and
finds the pins and distances UI/MapContents.lua's OutlinePoint computes, so tools/screenshots.py can put them
on the world map. Nothing here reads the client.
"""

import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent

# UI/Map.lua: GOLD_R, GOLD_G, GOLD_B, GLOW_WIDE, GLOW_WIDE_ALPHA, GLOW_CORE, GLOW_CORE_ALPHA, GLOW_HOVER.
GLOW_RGB = (255, 204, 89)  # 1, 0.8, 0.35
GLOW_WIDE, GLOW_WIDE_ALPHA = 11, 0.20
GLOW_CORE, GLOW_CORE_ALPHA = 2.5, 0.75
GLOW_HOVER = 1.7
FEATHER = Image.open(ROOT / "media" / "Glow.tga").convert("RGBA")


def outline_player(zone, name, art):
    """A character standing at the centre of an explored area's map overlay: the same 0..1 map space
    C_Map.GetPlayerMapPosition answers in, and the overlay key is in the map art's own pixels."""
    area = next(area for area in zone["areas"] if area["name"] == name)
    x, y, width, height = (int(value) for value in area["key"].split(":"))
    return (x + width / 2) / art.width, (y + height / 2) / art.height


def outline_areas(zone, explore_zone, live):
    """UI/MapContents.lua's Outline: the zone's undiscovered areas that have terrain rings, in data order."""
    found = []
    for area in zone["areas"]:
        key = area.get("key")
        rings = explore_zone["areas"].get(key) if key else None
        if rings and key not in live.explored:
            found.append((area, rings))
    return found


def outline_point(explore_zone, rings, player):
    """UI/MapContents.lua's OutlinePoint: the ring vertex nearest the player, and the yards to it from the
    zone rectangle's width and height. The player is always on the map for these scenes."""
    u, v = player
    best = None
    for ring in rings:
        for index in range(0, len(ring), 2):
            dx = (ring[index] - u) * explore_zone["width"]
            dy = (ring[index + 1] - v) * explore_zone["height"]
            distance = dx * dx + dy * dy
            if best is None or distance < best[0]:
                best = (distance, ring[index], ring[index + 1])
    return best[1], best[2], math.sqrt(best[0])


def glow_edge(canvas, x1, y1, x2, y2, thickness, alpha):
    """One Line region as UI/Map.lua's AreaPin:DrawEdge and Core/Art.lua's Art.GlowLine draw it: media/Glow.tga
    on a line `thickness` UI units across, tinted gold at SetVertexColor's alpha. Each edge reaches half a
    thickness past its ends so neighbouring edges meet the way the client's line rasterizer joins them."""
    length = math.hypot(x2 - x1, y2 - y1)
    if length == 0:
        return
    ux, uy = (x2 - x1) / length, (y2 - y1) / length
    half = thickness / 2
    ax, ay = x1 - ux * half, y1 - uy * half
    bx, by = x2 + ux * half, y2 + uy * half
    scale = canvas.ui.scale
    width = max(1, round(math.hypot(bx - ax, by - ay) * scale))
    height = max(1, round(thickness * scale))
    strip = FEATHER.resize((width, height), Image.LANCZOS)
    band = strip.getchannel("A").point(lambda value: min(255, round(value * alpha)))
    tinted = Image.new("RGBA", strip.size, (*GLOW_RGB, 255))
    tinted.putalpha(band)
    tinted = tinted.rotate(-math.degrees(math.atan2(by - ay, bx - ax)), expand=True, resample=Image.BICUBIC)
    canvas.image.alpha_composite(
        tinted,
        (
            round((ax + bx) / 2 * scale - tinted.width / 2),
            round((ay + by) / 2 * scale - tinted.height / 2),
        ),
    )


def outline_glow(canvas, rects, zone, explore_zone, live, hover):
    """UI/Map.lua AreaPin:Paint: every outlined area's rings as a wide soft stroke under a brighter core, the
    hovered area's brightened by GLOW_HOVER. Returns the areas, so world_map can pin and name them."""
    mx, my, mw, mh = rects["map"]
    areas = outline_areas(zone, explore_zone, live)
    for area, rings in areas:
        factor = GLOW_HOVER if area["name"] == hover else 1
        for ring in rings:
            for index in range(0, len(ring), 2):
                following = (index + 2) % len(ring)
                x1, y1 = mx + ring[index] * mw, my + ring[index + 1] * mh
                x2, y2 = mx + ring[following] * mw, my + ring[following + 1] * mh
                glow_edge(canvas, x1, y1, x2, y2, GLOW_WIDE, GLOW_WIDE_ALPHA * factor)
                glow_edge(canvas, x1, y1, x2, y2, GLOW_CORE, GLOW_CORE_ALPHA * factor)
    return areas
