"""AreaPin's terrain shading, drawn for the screenshots from the same values as the addon.

UI/Map.lua AreaPin:Paint fills each undiscovered area's rings with triangles, a white texture tinted the shading's
own black at AREA_ALPHA and brightened to AREA_HOVER_ALPHA under the mouse (MapContents.Triangles ear-clips each
ring, whose triangles cover exactly the ring). This module fills each ring the same way and finds the pins and
distances UI/MapContents.lua's OutlinePoint computes, so tools/screenshots.py can put them on the world map.
Nothing here reads the client.
"""

import math

from PIL import Image, ImageDraw

# UI/Map.lua: AREA_ALPHA, AREA_HOVER_ALPHA.
AREA_ALPHA, AREA_HOVER_ALPHA = 0.25, 0.40
SHADE_RGB = (0, 0, 0)


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


def outline_shading(canvas, rects, zone, explore_zone, live, hover):
    """UI/Map.lua AreaPin:Paint: every outlined area's rings filled with the shading's black, each ring its own
    fill, the hovered area's brightened as AreaPin:Highlight brightens its triangles. Returns the areas, so
    world_map can pin and name them."""
    mx, my, mw, mh = rects["map"]
    areas = outline_areas(zone, explore_zone, live)
    for area, rings in areas:
        alpha = AREA_HOVER_ALPHA if area["name"] == hover else AREA_ALPHA
        fill = (*SHADE_RGB, round(alpha * 255))
        for ring in rings:
            points = [
                (canvas.px(mx + ring[index] * mw), canvas.px(my + ring[index + 1] * mh))
                for index in range(0, len(ring), 2)
            ]
            if len(points) < 3:
                continue
            layer = Image.new("RGBA", canvas.image.size)
            ImageDraw.Draw(layer).polygon(points, fill=fill)
            canvas.image = Image.alpha_composite(canvas.image, layer)
    return areas
