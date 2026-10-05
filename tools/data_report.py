#!/usr/bin/env python3
"""Report what the generated data adds, removes and changes since a git revision (default HEAD)."""

from check_generated import ROOT
from forever_tools import generated

if __name__ == "__main__":
    generated.data_report(ROOT, ["Data/Legacy.lua"])
