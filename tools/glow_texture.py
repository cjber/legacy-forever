#!/usr/bin/env python3
"""Draw media/Glow.tga, the feathered strip every world-map glow line is drawn with (stdlib only).

The alpha falls from 1 at the middle row to 0 at the top and bottom, so a line thick enough to show the
strip keeps a bright centre and soft edges. RGB is white: a line's vertex colour is the Legacy gold.
"""

import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "media" / "Glow.tga"
SIZE = 32
# TGA header: no colour map, uncompressed true colour, 32 bits with eight alpha bits, top-left origin.
HEADER = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)


def pixels():
    for y in range(SIZE):
        alpha = round(255 * math.sin(math.pi * (y + 0.5) / SIZE) ** 1.5)
        for _ in range(SIZE):
            yield bytes((255, 255, 255, alpha))


def main():
    data = HEADER + b"".join(pixels())
    OUTPUT.write_bytes(data)
    print(f"Wrote {OUTPUT.relative_to(ROOT)} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
