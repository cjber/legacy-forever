"""Map previews use the same generated alpha masks as UI/Shading.lua."""

import functools
import math
import subprocess
from pathlib import Path

from PIL import Image

AREA_ALPHA, AREA_HOVER_ALPHA = 0.25, 0.40


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


@functools.cache
def shading_masks(root):
    """Export the actual Lua manifest; formatting cannot change its meaning."""
    text = subprocess.check_output(
        ["luajit", str(Path(root) / "tools/export_shading_masks.lua"), str(Path(root) / "Data/ShadingMasks.lua")],
        text=True,
    )
    maps = {}
    for line in text.splitlines():
        zone, key, left, top, width, height, name = line.split("\t")
        maps.setdefault(int(zone), {})[key] = (int(left), int(top), int(width), int(height), name)
    return maps


def outline_shading(canvas, rects, zone, explore_zone, live, hover, masks_root=None, ui_map_id=None):
    """Composite each runtime mask once, with the same normal and hover opacity."""
    mx, my, mw, mh = rects["map"]
    masks = shading_masks(masks_root or Path(__file__).resolve().parent.parent)
    if ui_map_id is None:
        raise ValueError("outline_shading requires ui_map_id for the zone-qualified mask manifest")
    zone_masks = masks[ui_map_id]
    areas = outline_areas(zone, explore_zone, live)
    for area, _rings in areas:
        alpha = AREA_HOVER_ALPHA if area["name"] == hover else AREA_ALPHA
        descriptor = zone_masks[area["key"]]
        left, top, width, height, basename = descriptor
        mask_root = Path(masks_root or Path(__file__).resolve().parent.parent)
        mask_path = mask_root / "media/legacy-masks" / f"{basename}.tga"
        mask = Image.open(mask_path)
        scale_x = canvas.px(mx + mw) - canvas.px(mx)
        scale_y = canvas.px(my + mh) - canvas.px(my)
        mask = mask.resize((round(width * scale_x / 1002), round(height * scale_y / 668)), Image.Resampling.BILINEAR)
        mask.putalpha(mask.getchannel("A").point(lambda value, scale=alpha: round(value * scale)))
        canvas.image.alpha_composite(mask, (canvas.px(mx + left / 1002 * mw), canvas.px(my + top / 668 * mh)))
    return areas
