#!/usr/bin/env python3
"""Move the forever-db pin to the newest release, without regenerating (stdlib only).

    python3 tools/refresh_fdb.py    # the refresh workflow runs it after the build pin moves

FDB_TAG, FDB_ASSET and FDB_SHA256 (fdb_pin.py) follow the newest `data-v*` release of fitzforge/polestar,
whose SHA256SUMS asset states the zip's checksum. A pin never moves backwards. Under GitHub Actions the
step outputs `changed` and `fdb` say what moved.
"""

import json
import os
import re
import urllib.request
from pathlib import Path

import fdb_pin

TOOLS = Path(__file__).resolve().parent
USER_AGENT = "LegacyForever/1.0"


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def github_request(url):
    """A request for `url` that carries the workflow's token on the GitHub API when one is set.

    Without a token the API allows an address 60 requests an hour, shared with every other job on the runner's
    address, so the refresh fails whenever that is spent; the workflow passes its own token.
    """
    headers = {"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"}
    token = os.environ.get("GITHUB_TOKEN")
    if url.startswith("https://api.github.com/") and token:
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.Request(url, headers=headers)


def fetch_fdb_releases():
    request = github_request("https://api.github.com/repos/fitzforge/polestar/releases?per_page=100")
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def _fdb_zip_asset(release):
    """The (name, download URL) of `release`'s forever-db zip asset, or None when it carries none."""
    for asset in release.get("assets", ()):
        name = asset.get("name", "")
        if name.startswith("forever-db-") and name.endswith(".zip"):
            return name, asset.get("browser_download_url", "")
    return None


def newest_fdb_release(releases):
    """The newest non-draft, non-prerelease `data-v*` release that actually carries a forever-db zip."""
    candidates = [
        release
        for release in releases
        if not release.get("draft")
        and not release.get("prerelease")
        and re.fullmatch(r"data-v\d+(?:\.\d+)*", release.get("tag_name", ""))
        and _fdb_zip_asset(release) is not None
    ]
    if not candidates:
        raise SystemExit("no forever-db `data-v*` release on the polestar page carries a forever-db zip")
    return max(candidates, key=lambda release: version_key(release["tag_name"][len("data-v") :]))


def newest_fdb_tag(pinned, tag):
    """The newer of the pinned forever-db `data-vX.Y.Z` tag and `tag`, or `pinned` when `tag` is not newer."""
    if not re.fullmatch(r"data-v\d+(?:\.\d+)*", tag):
        raise SystemExit(f"forever-db release tag {tag!r} is not data-vX.Y.Z")
    return max([pinned, tag], key=lambda value: version_key(value[len("data-v") :]))


def fdb_zip_asset(release):
    """The (name, download URL) of `release`'s forever-db zip asset, matched by its `forever-db-` prefix."""
    found = _fdb_zip_asset(release)
    if found is None:
        raise SystemExit(f"forever-db release {release.get('tag_name', '?')} carries no forever-db zip asset")
    return found


def fdb_digest(release, asset):
    """The sha256 of `asset` as the release's SHA256SUMS asset states it, so the pin never reads a moved file."""
    assets = release.get("assets", ())
    url = next(
        (entry.get("browser_download_url", "") for entry in assets if entry.get("name") == "SHA256SUMS"),
        None,
    )
    if url is None:
        raise SystemExit(f"forever-db release {release.get('tag_name', '?')} carries no SHA256SUMS asset")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        sums = response.read().decode("utf-8")
    for line in sums.splitlines():
        digest, _, stated = line.strip().partition(" ")
        if stated.lstrip() == asset:
            if not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise SystemExit(f"forever-db {asset}: SHA256SUMS states {digest!r}, not a sha256")
            return digest
    raise SystemExit(f"forever-db {asset}: the release's SHA256SUMS names no {asset}")


def pin(text, name, value):
    """`text` with its one `NAME = "..."` assignment set to `value`."""
    replaced, count = re.subn(rf'^{name} = "[^"\n]*"$', f'{name} = "{value}"', text, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"expected one {name} pin, found {count}")
    return replaced


def main():
    release = newest_fdb_release(fetch_fdb_releases())
    tag = newest_fdb_tag(fdb_pin.FDB_TAG, release["tag_name"])
    if tag != fdb_pin.FDB_TAG:
        asset, _ = fdb_zip_asset(release)
        path = TOOLS / "fdb_pin.py"
        text = pin(path.read_text(encoding="utf-8"), "FDB_TAG", tag)
        text = pin(text, "FDB_ASSET", asset)
        path.write_text(pin(text, "FDB_SHA256", fdb_digest(release, asset)), encoding="utf-8")
        summary = f"moved FDB_TAG {fdb_pin.FDB_TAG} -> {tag}"
        if asset != fdb_pin.FDB_ASSET:
            summary += f", FDB_ASSET {fdb_pin.FDB_ASSET} -> {asset}"
    else:
        summary = f"already on {fdb_pin.FDB_TAG}"
    print(summary)
    if "GITHUB_OUTPUT" in os.environ:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"fdb={summary}\n")


if __name__ == "__main__":
    main()
