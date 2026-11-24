#!/usr/bin/env python3
"""Run from the repository root: python3 tools/refresh_fdb_test.py"""

import json
import os
import unittest
from unittest import mock

import refresh_fdb

RELEASES = [
    {"tag_name": "data-v2026.11.5", "draft": False, "prerelease": False, "assets": []},
    {
        "tag_name": "data-v2026.11.2",
        "draft": False,
        "prerelease": False,
        "assets": [
            {
                "name": "forever-db-2026.11.2.zip",
                "browser_download_url": "https://example.test/forever-db-2026.11.2.zip",
            },
            {"name": "SHA256SUMS", "browser_download_url": "https://example.test/SHA256SUMS"},
        ],
    },
    {
        "tag_name": "data-v2026.11.3",
        "draft": False,
        "prerelease": True,
        "assets": [
            {
                "name": "forever-db-2026.11.3.zip",
                "browser_download_url": "https://example.test/forever-db-2026.11.3.zip",
            }
        ],
    },
    {
        "tag_name": "addon-v2026.11.9",
        "draft": False,
        "prerelease": False,
        "assets": [
            {
                "name": "forever-db-2026.11.9.zip",
                "browser_download_url": "https://example.test/forever-db-2026.11.9.zip",
            }
        ],
    },
]

SUMS = (
    "0000000000000000000000000000000000000000000000000000000000000000  forever-db-2026.11.1.zip\n"
    "43157067315537a8b95e5c517e30a1b6d55e117022f89094f039e9e6eb6438ad  forever-db-2026.11.2.zip\n"
)


class Response:
    """The part of an `urlopen` response `json.load` reads."""

    def __init__(self, payload):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *exception):
        return False

    def read(self):
        return json.dumps(self.payload).encode()


class TextResponse:
    """The part of an `urlopen` response `fdb_digest` reads: a checksum file's text, not JSON."""

    def __init__(self, text):
        self.text = text

    def __enter__(self):
        return self

    def __exit__(self, *exception):
        return False

    def read(self):
        return self.text.encode()


def sent_requests(call, token):
    """The requests `call` makes, with GITHUB_TOKEN set to `token` (absent when None)."""
    requests = []

    def urlopen(request, timeout=None):
        requests.append(request)
        return Response([])

    with mock.patch.dict(os.environ, {"GITHUB_TOKEN": token} if token is not None else {}, clear=False):
        if token is None:
            os.environ.pop("GITHUB_TOKEN", None)
        with mock.patch.object(refresh_fdb.urllib.request, "urlopen", urlopen):
            call()
    return requests


class RefreshFdb(unittest.TestCase):
    def test_the_release_is_the_newest_data_v_release_with_a_zip(self):
        self.assertEqual(refresh_fdb.newest_fdb_release(RELEASES)["tag_name"], "data-v2026.11.2")
        self.assertEqual(refresh_fdb.newest_fdb_tag("data-v2026.11.2", "data-v2026.11.5"), "data-v2026.11.5")
        self.assertEqual(refresh_fdb.newest_fdb_tag("data-v2026.11.2", "data-v2026.11.1"), "data-v2026.11.2")
        self.assertEqual(refresh_fdb.newest_fdb_tag("data-v2026.11.2", "data-v2026.11.2"), "data-v2026.11.2")
        with self.assertRaises(SystemExit):
            refresh_fdb.newest_fdb_tag("data-v2026.11.2", "2026.11.5")
        with self.assertRaises(SystemExit):
            refresh_fdb.newest_fdb_release([RELEASES[0], RELEASES[2], RELEASES[3]])

    def test_the_asset_is_the_forever_db_zip(self):
        release = {"tag_name": "data-v2026.11.2", "assets": RELEASES[1]["assets"]}
        self.assertEqual(
            refresh_fdb.fdb_zip_asset(release),
            ("forever-db-2026.11.2.zip", "https://example.test/forever-db-2026.11.2.zip"),
        )
        with self.assertRaises(SystemExit):
            refresh_fdb.fdb_zip_asset({"tag_name": "data-v2026.11.2", "assets": [{"name": "SHA256SUMS"}]})

    def test_the_digest_comes_from_the_sums_asset(self):
        release = {"tag_name": "data-v2026.11.2", "assets": RELEASES[1]["assets"]}
        sent = []

        def urlopen(request, timeout=None):
            sent.append(request)
            return TextResponse(SUMS)

        with mock.patch.object(refresh_fdb.urllib.request, "urlopen", urlopen):
            self.assertEqual(
                refresh_fdb.fdb_digest(release, "forever-db-2026.11.2.zip"),
                "43157067315537a8b95e5c517e30a1b6d55e117022f89094f039e9e6eb6438ad",
            )
        self.assertEqual(sent[0].full_url, "https://example.test/SHA256SUMS")
        with mock.patch.object(refresh_fdb.urllib.request, "urlopen", urlopen):
            with self.assertRaises(SystemExit):
                refresh_fdb.fdb_digest(release, "forever-db-2026.11.9.zip")

    def test_pin_rewrites_exactly_one_assignment(self):
        self.assertEqual(refresh_fdb.pin('A = 1\nFDB_TAG = "x"\n', "FDB_TAG", "y"), 'A = 1\nFDB_TAG = "y"\n')
        with self.assertRaises(SystemExit):
            refresh_fdb.pin('FDB_TAG = "x"\nFDB_TAG = "x"\n', "FDB_TAG", "y")


class GitHubToken(unittest.TestCase):
    def test_the_release_list_carries_the_workflow_token(self):
        (request,) = sent_requests(refresh_fdb.fetch_fdb_releases, "s3cret")
        self.assertEqual(request.get_header("Authorization"), "Bearer s3cret")

    def test_the_release_list_without_a_token_carries_none(self):
        (request,) = sent_requests(refresh_fdb.fetch_fdb_releases, None)
        self.assertIsNone(request.get_header("Authorization"))

    def test_the_token_goes_only_to_the_github_api(self):
        with mock.patch.dict(os.environ, {"GITHUB_TOKEN": "s3cret"}):
            request = refresh_fdb.github_request("https://wago.tools/api/builds")
        self.assertIsNone(request.get_header("Authorization"))


if __name__ == "__main__":
    unittest.main()
