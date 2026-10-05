#!/usr/bin/env python3
"""Print the newest WoW: Forever client build listed on wago.tools (stdlib only)."""

try:
    from tools.forever_tools.latest_build import latest
except ModuleNotFoundError:
    from forever_tools.latest_build import latest

if __name__ == "__main__":
    print(latest("LegacyForever/1.0"))
