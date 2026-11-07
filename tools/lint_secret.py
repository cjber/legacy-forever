#!/usr/bin/env python3
"""Reject unguarded reads of values the client may keep secret, and tooltip hooks that touch a forbidden tooltip
(forever_tools.readable). Read them through `ns.Readable`; start a tooltip hook with `if not ns.Usable(tooltip)`.
"""

import sys
from pathlib import Path

try:
    from tools.forever_tools import readable as secret
    from tools.typecheck_coverage import runtime_files
except ModuleNotFoundError:
    from forever_tools import readable as secret
    from typecheck_coverage import runtime_files

POLICY = secret.DEFAULT_POLICY
# Vendored byte for byte from forever-core (tools/check_core_shared.py), so a secret-ok line cannot be added here. The
# shared leaderboards data reads UnitName, then clears the name and realm through canaccessvalue before using either;
# this policy only follows the `ns.Readable(...)` form, so the check would keep flagging the shared copy.
VENDORED = frozenset({"Core/LeaderboardsData.lua"})
check = secret.check


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    files = [Path(arg) for arg in sys.argv[1:]] or runtime_files(root)
    files = [path for path in files if path.resolve().relative_to(root).as_posix() not in VENDORED]
    return secret.run(files, POLICY)


if __name__ == "__main__":
    sys.exit(main())
