from __future__ import annotations

import unittest

from database.config import Config
from database.storage import BulkLimitExceeded, PostgreSQLStore, StudentIdentityConflict


class Cursor:
    def __init__(self, one=None, many=None, rowcount=0):
        self.one = one
        self.many = many or []
        self.rowcount = rowcount

    def fetchone(self):
        return self.one

    def fetchall(self):
        return self.many


class Connection:
    def __init__(self, results=None, should_fail=False):
        self.results = list(results or [])
        self.queries = []
        self.should_fail = should_fail
        self.committed = False
        self.rolled_back = False

    def __enter__(self):
        return self

    def __exit__(self, kind, value, traceback):
        if kind is not None:
            self.rolled_back = True
        else:
            self.committed = True

    def execute(self, statement, params=()):
        self.queries.append((statement, params))
        if self.should_fail:
            raise RuntimeError("write aborted")
        return Cursor(one=self.results.pop(0) if self.results else None)


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.store = PostgreSQLStore(Config())

    def test_completed_score_upsert_is_one_transaction_with_bound_values(self):
        fake = Connection(results=[{"score_id": 11, "student_id": "KG-1", "score": 4}])
        self.store._connect = lambda: fake
        result = self.store.complete_round_and_replace_score("KG-1", "Noun", "Seconds", "Easy", 4)
        self.assertEqual(result["score"], 4)
        query, params = fake.queries[0]
        self.assertIn("ON CONFLICT (student_id, minigame, game_style, game_mode, difficulty) DO UPDATE", query)
        self.assertIn("SET score = EXCLUDED.score", query)
        self.assertNotIn("GREATEST", query)
        self.assertEqual(params, ("KG-1", "Legacy", "Noun", "Seconds", "Easy", 4))
        self.assertTrue(fake.committed)

    def test_failed_completion_rolls_back(self):
        fake = Connection(should_fail=True)
        self.store._connect = lambda: fake
        with self.assertRaisesRegex(RuntimeError, "write aborted"):
            self.store.complete_round_and_replace_score("KG-1", "Noun", "Seconds", "Easy", 12)
        self.assertTrue(fake.rolled_back)
        self.assertFalse(fake.committed)

    def test_idempotent_insert_checks_existing_profile_with_lock(self):
        same = {"student_id": "KG-1", "student_name": "Rosa", "grade_section": "4-A"}
        fake = Connection(results=[None, same])
        self.store._connect = lambda: fake
        student, created = self.store.register_student("KG-1", "Rosa", "4-A")
        self.assertFalse(created)
        self.assertEqual(student, same)
        self.assertIn("ON CONFLICT (student_id) DO NOTHING", fake.queries[0][0])
        self.assertIn("FOR UPDATE", fake.queries[1][0])
        mismatch = Connection(results=[None, same])
        self.store._connect = lambda: mismatch
        with self.assertRaises(StudentIdentityConflict):
            self.store.register_student("KG-1", "Another Name", "4-A")
        self.assertTrue(mismatch.rolled_back)

    def test_optional_filtered_leaderboard_uses_bound_values(self):
        fake = Connection()
        self.store._connect = lambda: fake
        self.store.get_leaderboard(None, None, None, None, 500)
        query, params = fake.queries[-1]
        self.assertNotIn("WHERE", query)
        self.assertIn("sc.minigame, sc.game_style, sc.game_mode, sc.difficulty", query)
        self.assertEqual(params, (500,))
        self.store.get_leaderboard("Noun", "Lives", "Hard", "5-B", 20)
        query, params = fake.queries[-1]
        self.assertIn("sc.game_style = %s", query)
        self.assertIn("st.grade_section = %s", query)
        self.assertEqual(params, ("Noun", "Lives", "Hard", "5-B", 20))
        self.store.get_leaderboard("Noun", "Seconds", "Easy", None, 12, "Human Plane")
        query, params = fake.queries[-1]
        self.assertIn("sc.minigame = %s", query)
        self.assertEqual(params, ("Human Plane", "Noun", "Seconds", "Easy", 12))

    def test_config_rejects_nonlocal_database_host(self):
        from unittest.mock import patch
        with patch.dict("os.environ", {"KILOS_DB_HOST": "remote.example.com"}):
            with self.assertRaises(ValueError):
                Config.from_env()

    def test_default_http_port_is_free_local_service_port(self):
        from unittest.mock import patch
        with patch.dict("os.environ", {}, clear=True):
            self.assertEqual(Config.from_env().http_port, 18765)
        with patch.dict("os.environ", {"KILOS_HTTP_PORT": "19080"}):
            self.assertEqual(Config.from_env().http_port, 19080)

    def test_snapshot_export_reads_all_rows_in_consistent_read_only_transaction(self):
        class ExportConnection(Connection):
            def execute(self, statement, params=()):
                self.queries.append((statement, params))
                if "FROM students" in statement:
                    return Cursor(many=[{"student_id": "KG-2", "student_name": "Ben", "grade_section": "5-A"}])
                if "FROM student_scores" in statement:
                    return Cursor(many=[])
                return Cursor()

        connection = ExportConnection()
        self.store._connect = lambda: connection
        students, scores = self.store.export_snapshot()
        self.assertEqual((len(students), len(scores)), (1, 0))
        self.assertIn("REPEATABLE READ READ ONLY", connection.queries[0][0])
        self.assertNotIn("LIMIT 500 ", connection.queries[1][0])
        self.assertEqual(connection.queries[1][1], (5001,))
        self.assertTrue(connection.committed)

    def test_snapshot_export_refuses_more_than_5000_students_or_scores(self):
        class TooMany(Connection):
            def execute(self, query, params=()):
                self.queries.append((query, params))
                if "FROM students" in query:
                    return Cursor(many=[{"student_id": f"KG-{n}"} for n in range(5001)])
                return Cursor()

        fake = TooMany()
        self.store._connect = lambda: fake
        with self.assertRaises(BulkLimitExceeded):
            self.store.export_snapshot()
        self.assertTrue(fake.rolled_back)

    def test_bulk_import_is_one_transaction_creates_then_noops_on_reimport(self):
        student = {"student_id": "KG-1", "student_name": "Rose", "grade_section": "5-A"}
        score = {"student_id": "KG-1", "game_style": "Noun", "game_mode": "Lives", "difficulty": "Hard", "score": 8}
        created = Connection(results=[{"student_id": "KG-1"}, None, None])
        self.store._connect = lambda: created
        response = self.store.import_snapshot([student], [score])
        self.assertEqual(response["students_created"], 1)
        self.assertEqual(response["scores_created"], 1)
        self.assertEqual(response["scores_imported"], 1)
        self.assertIn("ON CONFLICT (student_id) DO NOTHING", created.queries[0][0])
        self.assertIn("student_scores.score IS DISTINCT FROM EXCLUDED.score", created.queries[2][0])
        self.assertEqual(created.queries[2][1], ("KG-1", "Legacy", "Noun", "Lives", "Hard", 8))

        self.assertTrue(created.committed)

        unchanged = Connection(results=[None, {"student_name": "Rose", "grade_section": "5-A"}, {"score": 8}])
        self.store._connect = lambda: unchanged
        response = self.store.import_snapshot([student], [score])
        self.assertEqual(response["students_existing"], 1)
        self.assertEqual(response["scores_unchanged"], 1)
        self.assertEqual(len(unchanged.queries), 3)  # no score rewrite / timestamp change

    def test_distinct_minigame_score_identity_in_parameterized_queries(self):
        fake = Connection(results=[{"score_id": 12, "score": 10, "minigame": "Catch the Word"}])
        self.store._connect = lambda: fake
        result = self.store.complete_round_and_replace_score("KG-1", "Noun", "Seconds", "Easy", 10, "Catch the Word")
        self.assertEqual(result["minigame"], "Catch the Word")
        self.assertEqual(fake.queries[0][1], ("KG-1", "Catch the Word", "Noun", "Seconds", "Easy", 10))
        assert "minigame" in fake.queries[0][0]
        lookup = Connection(results=[{"score": 7, "minigame": "Human Plane"}])
        self.store._connect = lambda: lookup
        found = self.store.find_score("KG-1", "Noun", "Seconds", "Easy", "Human Plane")
        self.assertEqual(found["minigame"], "Human Plane")
        self.assertEqual(lookup.queries[0][1], ("KG-1", "Human Plane", "Noun", "Seconds", "Easy"))

    def test_bulk_import_lower_score_replaces_and_rollbacks_on_identity_conflict(self):
        student = {"student_id": "KG-1", "student_name": "Rose", "grade_section": "5-A"}
        lower_score = {"student_id": "KG-1", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 2}
        updated = Connection(results=[None, {"student_name": "Rose", "grade_section": "5-A"}, {"score": 18}, None])
        self.store._connect = lambda: updated
        response = self.store.import_snapshot([student], [lower_score])
        self.assertEqual(response["scores_updated"], 1)
        self.assertIn("SET score = EXCLUDED.score", updated.queries[-1][0])
        self.assertEqual(updated.queries[-1][1][-1], 2)

        conflict = Connection(results=[None, {"student_name": "Different", "grade_section": "5-A"}])
        self.store._connect = lambda: conflict
        with self.assertRaises(StudentIdentityConflict):
            self.store.import_snapshot([student], [lower_score])
        self.assertTrue(conflict.rolled_back)
        self.assertEqual(len(conflict.queries), 2)  # must not try score upsert

    def test_bulk_import_write_failure_rolls_back_entire_transaction(self):
        class FailAfterFirst(Connection):
            def execute(self, statement, params=()):
                if len(self.queries) > 0:
                    raise RuntimeError("bulk write failed")
                return super().execute(statement, params)

        student = {"student_id": "KG-1", "student_name": "Rose", "grade_section": "5-A"}
        fake = FailAfterFirst(results=[{"student_id": "KG-1"}])
        self.store._connect = lambda: fake
        with self.assertRaisesRegex(RuntimeError, "bulk write failed"):
            self.store.import_snapshot([student], [{"student_id": "KG-1", "game_style": "Verb", "game_mode": "Lives", "difficulty": "Hard", "score": 1}])
        self.assertTrue(fake.rolled_back)
        self.assertFalse(fake.committed)

    def test_delete_all_is_atomic_and_orders_score_rows_before_student_rows(self):
        class DeletionConnection(Connection):
            def execute(self, statement, params=()):
                self.queries.append((statement, params))
                return Cursor(rowcount=7 if "student_scores" in statement else 4)

        fake = DeletionConnection()
        self.store._connect = lambda: fake
        result = self.store.delete_all()
        self.assertEqual(result, {"scores_deleted": 7, "students_deleted": 4})
        self.assertEqual([entry[0] for entry in fake.queries], [
            "DELETE FROM student_scores", "DELETE FROM students",
        ])
        self.assertTrue(fake.committed)

        class FailDelete(DeletionConnection):
            def execute(self, statement, params=()):
                if "DELETE FROM students" in statement:
                    raise RuntimeError("delete failed")
                return super().execute(statement, params)

        failed = FailDelete()
        self.store._connect = lambda: failed
        with self.assertRaisesRegex(RuntimeError, "delete failed"):
            self.store.delete_all()
        self.assertTrue(failed.rolled_back)


if __name__ == "__main__":
    unittest.main()
