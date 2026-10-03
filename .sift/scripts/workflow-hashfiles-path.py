#!/usr/bin/env python3
# sift-scope: all
# sift-fix: delete the argument or name the replacement file: hashFiles ignores a path that matches nothing
"""Report a literal hashFiles() path in a workflow that names no file.

Seen in .github/workflows/ci.yml: a cache key hashed 'tools/diff_forever.py', a file
the repository never had. One hit over the whole tree, a true positive, no backlog.
Arguments with glob characters are skipped: an empty glob can be intentional.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

CALL = re.compile(r"hashFiles\(([^)]*)\)")
ARG = re.compile(r"'([^']*)'")
GLOB = set("*?[!")


def main() -> int:
    rule = os.environ["SIFT_RULE"]
    hits = []
    for path in Path(os.environ["SIFT_FILES"]).read_text().splitlines():
        if not path.startswith(".github/workflows/") or not path.endswith((".yml", ".yaml")):
            continue
        for number, line in enumerate(Path(path).read_text().splitlines(), 1):
            for call in CALL.finditer(line):
                for arg in ARG.findall(call.group(1)):
                    if not GLOB & set(arg) and not Path(arg).exists():
                        hits.append(f"{path}:{number}: {rule} hashFiles names '{arg}', which does not exist")
    for hit in hits:
        print(hit)
    return int(bool(hits))


if __name__ == "__main__":
    sys.exit(main())
