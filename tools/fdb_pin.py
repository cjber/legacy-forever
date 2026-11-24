#!/usr/bin/env python3
"""The forever-db pin: the Polestar project's published quest database, the build's second source.

`FDB_TAG` follows the newest `data-v*` release of https://github.com/fitzforge/polestar (tools/refresh_fdb.py
moves it). `FDB_ASSET` is the zip asset of that release and `FDB_SHA256` its checksum, as the release's own
SHA256SUMS states it. The database is GPL-3.0 (their own layer CC BY 4.0) and carries every source's credit in
its NOTICE.md; see THIRD_PARTY.md for what Legacy Forever reads from it.
"""

FDB_TAG = "data-v2026.11.2"
FDB_ASSET = "forever-db-2026.11.2.zip"
FDB_SHA256 = "43157067315537a8b95e5c517e30a1b6d55e117022f89094f039e9e6eb6438ad"
FDB_URL = f"https://github.com/fitzforge/polestar/releases/download/{FDB_TAG}/{FDB_ASSET}"
