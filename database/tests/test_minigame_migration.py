"""Read-only migration contract tests; NEVER touch the user's PostgreSQL."""

from __future__ import annotations

import io
import sys
import types
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

from database import migrate
from database.config import Config
from database.storage import PostgreSQLStore, SchemaNotReady


SQL_FILE = Path(migrate.MINIGAME_MIGRATION)


class MigrationSafetyTests(unittest.TestCase):
    def test_new_migration_is_explicit_additive_and_preserves_legacy(self):
        sql = SQL_FILE.read_text(encoding="utf-8")
        self.assertIn("ADD COLUMN IF NOT EXISTS minigame TEXT NOT NULL DEFAULT 'Legacy'", sql)
        self.assertIn("UNIQUE (student_id, minigame, game_style, game_mode, difficulty)", sql)
        self.assertIn("uq_student_scores_minigame_identity", sql)
        self.assertIn("DROP CONSTRAINT student_scores_student_id_game_style_game_mode_difficulty_key", sql)
        self.assertIn("CREATE INDEX IF NOT EXISTS idx_student_scores_minigame_leaderboard", sql)
        for destructive in ("DROP TABLE", "TRUNCATE", "DELETE FROM", "UPDATE student_scores SET score"):
            self.assertNotIn(destructive, sql.upper())
        self.assertLessEqual(len("uq_student_scores_minigame_identity"), 63)

    def test_doing_nothing_does_not_connect_or_apply_sql(self):
        output = io.StringIO()
        with patch.object(sys, "argv", ["migrate"]), patch("database.config.Config.from_env") as configuration:
            with redirect_stdout(output):
                migrate.main()
            configuration.assert_not_called()
        self.assertIn("--apply-minigame", output.getvalue())

    def test_explicit_minigame_flag_selects_only_forward_migration_with_mock_connection(self):
        connection_calls: list[str] = []

        class FakeConnection:
            def __enter__(self):
                return self

            def __exit__(self, kind, error, traceback):
                self.committed = kind is None

            def execute(self, query):
                connection_calls.append(query)

        connection = FakeConnection()
        fake_psycopg = types.SimpleNamespace(connect=lambda **_kwargs: connection)
        with patch.dict(sys.modules, {"psycopg": fake_psycopg}), patch.object(
            sys, "argv", ["migrate", "--apply-minigame"]
        ), patch("database.migrate.Config.from_env", return_value=Config()):
            with redirect_stdout(io.StringIO()):
                migrate.main()
        self.assertEqual(connection_calls, [SQL_FILE.read_text(encoding="utf-8")])
        self.assertTrue(connection.committed)

    def test_backend_health_refuses_old_schema_before_any_mutating_work(self):
        class FakeConnection:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                pass

            def execute(self, query):
                self.query = query
                return self

            def fetchone(self):
                return {
                    "has_students": True, "has_scores": True,
                    "has_minigame": False, "has_minigame_identity": False,
                }

        store = PostgreSQLStore(Config())
        fake = FakeConnection()
        store._connect = lambda: fake
        with self.assertRaises(SchemaNotReady):
            store.health()
        self.assertIn("information_schema.columns", fake.query)
        self.assertIn("uq_student_scores_minigame_identity", fake.query)

    def test_backend_health_refuses_incomplete_migration_missing_new_unique(self):
        class ProbeConnection:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def execute(self, _query):
                return self

            def fetchone(self):
                return {
                    "has_students": True, "has_scores": True,
                    "has_minigame": True, "has_minigame_identity": False,
                }

        store = PostgreSQLStore(Config())
        store._connect = ProbeConnection
        with self.assertRaises(SchemaNotReady):
            store.health()


if __name__ == "__main__":
    unittest.main()
