#!/usr/bin/env python3
"""Print the newest WoW: Forever client build listed on wago.tools (stdlib only)."""

import json
import urllib.request

# wow_classic_beta carries other Classic betas too; Forever builds are 1.6x.
request = urllib.request.Request("https://wago.tools/api/builds", headers={"User-Agent": "LegacyForever/1.0"})
with urllib.request.urlopen(request, timeout=60) as response:
    builds = json.load(response)["wow_classic_beta"]
forever = [b["version"] for b in builds if b["version"].startswith("1.6")]
if not forever:
    raise SystemExit("no Forever build listed on wago.tools")
print(max(forever, key=lambda v: tuple(int(p) for p in v.split("."))))
