"""The world map's terrain shading, drawn for the screenshots from the same values as the addon.

UI/Shading.lua's Shading.Area, called by UI/Map.lua's AreaPin:Paint, fills each undiscovered area's rings with
triangles, a white texture tinted the shading's own black at AREA_ALPHA and brightened to AREA_HOVER_ALPHA under the
mouse (MapContents.Triangles ear-clips each ring, whose triangles cover exactly the ring), then feathers each ring
edge outward over FEATHER of the map's width, fading from that alpha at the edge to nothing. This module fills and
feathers each ring the same way and finds the pins and distances UI/MapContents.lua's OutlinePoint computes, so
tools/screenshots.py can put them on the world map. Nothing here reads the client.
"""

import math

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# UI/Map.lua: AREA_ALPHA, AREA_HOVER_ALPHA, FEATHER.
AREA_ALPHA, AREA_HOVER_ALPHA = 0.25, 0.40
SHADE_RGB = (0, 0, 0)
# UI/Shading.lua's FEATHER: the share of the map's width the exploration overlay alpha takes to fall to nothing.
FEATHER = 40 / 1002


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


def outward_ramp(mask, band):
    """Just outside a filled mask, full at its edge and 0 `band` pixels out, as UI/Shading.lua's DrawFeather fades
    a ring edge. Dilating one pixel at a time gives that distance band."""
    ramp = Image.new("L", mask.size, 0)
    grown = mask
    for step in range(band):
        outer = grown.filter(ImageFilter.MaxFilter(3))
        ramp.paste(round(255 * (1 - (step + 1) / band)), ImageChops.subtract(outer, grown))
        grown = outer
    return ramp


def outline_shading(canvas, rects, zone, explore_zone, live, hover):
    """UI/Shading.lua's Shading.Area, called by UI/Map.lua's AreaPin:Paint: every outlined area's rings filled with the
    shading's black and feathered outward from each edge, the hovered area's brightened as AreaPin:Highlight
    brightens its fill and feathers. Returns the
    areas, so world_map can pin and name them."""
    mx, my, mw, mh = rects["map"]
    band = round(FEATHER * (canvas.px(mx + mw) - canvas.px(mx)))
    areas = outline_areas(zone, explore_zone, live)
    for area, rings in areas:
        alpha = AREA_HOVER_ALPHA if area["name"] == hover else AREA_ALPHA
        for ring in rings:
            points = [
                (canvas.px(mx + ring[index] * mw), canvas.px(my + ring[index + 1] * mh))
                for index in range(0, len(ring), 2)
            ]
            if len(points) < 3:
                continue
            left = max(0, min(x for x, _ in points) - band)
            top = max(0, min(y for _, y in points) - band)
            right = min(canvas.image.width, max(x for x, _ in points) + band + 1)
            bottom = min(canvas.image.height, max(y for _, y in points) + band + 1)
            mask = Image.new("L", (right - left, bottom - top), 0)
            ImageDraw.Draw(mask).polygon([(x - left, y - top) for x, y in points], fill=255)
            cover = ImageChops.lighter(mask, outward_ramp(mask, band))
            layer = Image.new("RGBA", mask.size, (*SHADE_RGB, 0))
            layer.putalpha(cover.point(lambda value, scale=alpha: round(value * scale)))
            canvas.image.alpha_composite(layer, (left, top))
    return areas
