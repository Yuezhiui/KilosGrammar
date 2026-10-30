"""Regression for the user's Windows beta.5 leaderboard 403 mismatch.

Only temporary LOCALAPPDATA and an in-memory API store are touched. No live
PostgreSQL, student records, credentials, ports, or installed token are used.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from database.server import API, _admin_token_path, _create_admin_token
from database.tests.test_server import MemoryStore


class AdminTokenSessionRegression(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, {"LOCALAPPDATA": self.temp.name})
        env.start()
        self.addCleanup(env.stop)

    def test_second_server_does_not_rotate_active_admin_token(self) -> None:
        first = _create_admin_token()
        self.assertGreaterEqual(len(first), 32)
        self.assertEqual(_create_admin_token(), first)
        self.assertEqual(_admin_token_path().read_text(encoding="ascii"), first)

    def test_invalid_existing_capability_is_preserved_and_never_replaced(self) -> None:
        path = _admin_token_path()
        path.write_text("broken", encoding="ascii")
        with self.assertRaisesRegex(RuntimeError, "unreadable"):
            _create_admin_token()
        self.assertEqual(path.read_text(encoding="ascii"), "broken")

    def test_read_only_export_still_enforces_capability_after_legacy_rotation(self) -> None:
        old_token = _create_admin_token()
        store = MemoryStore()
        store.export_snapshot = lambda: ([], [])
        api = API(store, admin_token=old_token)
        api._admin_token_file = _admin_token_path()
        fresh_token = "test-" + "u" * 42
        api._admin_token_file.write_text(fresh_token, encoding="ascii")

        rejected, bad = api.dispatch("GET", "/data/export", admin_token=old_token)
        self.assertEqual((rejected, bad["error"]["code"]), (403, "admin_authorization_required"))
        authorized, result = api.dispatch("GET", "/data/export", admin_token=fresh_token)
        self.assertEqual(authorized, 200)
        self.assertTrue(result["ok"])
        # The export is read-only. The in-memory store remains empty.
        self.assertEqual((store.students, store.scores), ({}, {}))


if __name__ == "__main__":
    unittest.main()
