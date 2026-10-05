#!/usr/bin/env python3
"""Reject implicit select() expansion in Lua 5.1 calls, tables and returns."""

import argparse
import sys
from pathlib import Path

try:
    from tools.forever_tools import multivalue
    from tools.forever_tools.lua import LuaSyntaxError
    from tools.forever_tools.multivalue import Parser, lua_files
except ModuleNotFoundError:
    from forever_tools import multivalue
    from forever_tools.lua import LuaSyntaxError
    from forever_tools.multivalue import Parser, lua_files

__all__ = ["LuaSyntaxError", "Parser", "lua_files", "main"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, default=[Path(".")])
    # Unlike the TOC-driven lints, this one also covers tests and local declarations.
    return multivalue.run(lua_files(parser.parse_args().paths))


if __name__ == "__main__":
    sys.exit(main())
