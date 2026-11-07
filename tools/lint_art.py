"""Reject art drawn outside the Art helpers, where nothing keeps its shape (forever_tools.art)."""

import argparse
import sys
from pathlib import Path

try:
    from tools.forever_tools import art
    from tools.typecheck_coverage import runtime_files
except ModuleNotFoundError:
    from forever_tools import art
    from typecheck_coverage import runtime_files

# The one file that may set art: every helper in it is under spec (tests/art_spec.lua).
HELPERS = frozenset({"Core/Art.lua"})
# Vendored byte for byte from forever-core (tools/check_core_shared.py), so an art-ok line cannot be added here. Its
# setters draw the client's own row highlight, medals, class icons and the addon's tab icon at native sizes.
VENDORED = frozenset({"UI/Leaderboards.lua"})
check = art.check
__all__ = ["HELPERS", "VENDORED", "check", "main"]


def main() -> int:
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("files", nargs="*", type=Path)
    root = Path(__file__).resolve().parent.parent
    files = args.parse_args().files or [*runtime_files(root), *(root / "UI").rglob("*.xml")]
    # art.run skips every path in `helpers`; the vendored file is skipped for the same reason, not exempted as an
    # art helper, so its existence check still finds every one listed.
    return art.run(root, files, HELPERS | VENDORED)


if __name__ == "__main__":
    sys.exit(main())
