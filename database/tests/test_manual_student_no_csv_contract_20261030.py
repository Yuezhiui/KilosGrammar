"""Student create/read/patch contract without CSV or live PostgreSQL.

All writes below target a disposable in-memory store or temporary SQLite
recovery journal backed by FakePostgres. No installed database is contacted.
This regression captures current behavior and documents client/API mismatches.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from database.recovery_store import RecoveryStore
from database.server import API
from database.config import Config
from database.storage import PostgreSQLStore
from database.tests.test_recovery_store import FakePostgres
from database.tests.test_server import MemoryStore
from database.tests.test_storage import Connection


class NameLookupMemoryStore(MemoryStore):
    """MemoryStore's ordinary fixture deliberately omits by-name lookup."""

    def find_students_by_name(self, name):
        from database.storage import normalized_full_name
        return [profile for profile in self.students.values()
                if normalized_full_name(profile["student_name"]) == normalized_full_name(name)]


class ManualStudentNoCsvContract(unittest.TestCase):
    def setUp(self) -> None:
        self.store = MemoryStore()
        self.api = API(self.store)
        self.student = {
            "student_id": "MANUAL-TEST-001",
            "student_name": "Ada Rivera",
            "grade_section": "Grade 4 - Testing",
        }

    def call(self, method: str, route: str, payload=None):
        return self.api.dispatch(method, route, payload)

    def test_empty_database_missing_then_manual_create_without_csv_or_score(self):
        status, result = self.call("GET", "/students/MANUAL-TEST-001")
        self.assertEqual((status, result["error"]["code"]), (404, "student_not_found"))
        self.assertEqual((self.store.students, self.store.scores), ({}, {}))

        status, result = self.call("POST", "/students", self.student)
        self.assertEqual(status, 201)
        self.assertTrue(result["ok"])
        self.assertEqual(result["data"]["student"]["student_id"], self.student["student_id"])
        self.assertFalse(result["data"]["recovery_pending"])
        self.assertEqual(self.store.actions, ["register"])
        self.assertEqual(self.store.scores, {})

        # Simulate a new UI session against the same persistent storage object.
        self.api = API(self.store)
        status, result = self.call("GET", "/students/MANUAL-TEST-001")
        self.assertEqual((status, result["data"]["student"]["student_name"]), (200, "Ada Rivera"))
        status, result = self.call("GET", "/leaderboard")
        self.assertEqual((status, result["data"]["count"], result["data"]["leaderboard"]), (200, 0, []))
        self.assertEqual(self.store.scores, {})

    def test_idempotent_registration_identity_conflict_explicit_patch_and_not_found(self):
        self.assertEqual(self.call("POST", "/students", self.student)[0], 201)
        self.assertEqual(self.call("POST", "/students", self.student)[0], 200)
        self.assertEqual(self.store.actions, ["register"])
        changed = {**self.student, "student_name": "Someone Else"}
        status, result = self.call("POST", "/students", changed)
        self.assertEqual((status, result["error"]["code"]), (409, "student_exists"))
        self.assertEqual(self.store.students[self.student["student_id"]]["student_name"], "Ada Rivera")

        status, result = self.call("PATCH", "/students/MANUAL-TEST-001", {
            "student_name": "Ada Rivera Updated", "grade_section": "Grade 5 - Testing",
        })
        self.assertEqual((status, result["data"]["student"]["grade_section"]), (200, "Grade 5 - Testing"))
        self.assertEqual(self.store.actions, ["register", "update"])
        status, result = self.call("GET", "/students/MANUAL-TEST-001")
        self.assertEqual(result["data"]["student"]["student_name"], "Ada Rivera Updated")
        self.assertEqual(status, 200)
        status, result = self.call("PATCH", "/students/ABSENT", {"student_name": "Nobody"})
        self.assertEqual((status, result["error"]["code"]), (404, "student_not_found"))
        self.assertEqual(len(self.store.students), 1)

    def test_invalid_manual_id_is_400_not_404_and_is_not_a_new_student(self):
        # Compatibility discrepancy: Godot currently accepts these printable
        # values client-side, but the Python server rejects them with 400.
        invalid_ids = ["A&B/2", "manual id", "Student@Home", "X" * 65, "A\\B"]
        for invalid_id in invalid_ids:
            with self.subTest(invalid_id=invalid_id):
                status, result = self.call("POST", "/students", {**self.student, "student_id": invalid_id})
                self.assertEqual((status, result["error"]["code"]), (400, "invalid_input"))
        for invalid_id in ["A&B/2", "manual id", "Student@Home", "X" * 65]:
            with self.subTest(lookup=invalid_id):
                from urllib.parse import quote
                status, result = self.call("GET", "/students/" + quote(invalid_id, safe=""))
                self.assertEqual((status, result["error"]["code"]), (400, "invalid_input"))
        self.assertEqual(self.store.students, {})
        self.assertEqual(self.call("POST", "/students", {**self.student, "student_id": "Y" * 64})[0], 201)

    def test_backend_accepts_one_word_manual_name_that_client_name_lookup_rejects(self):
        self.store = NameLookupMemoryStore()
        self.api = API(self.store)
        one_word = {**self.student, "student_name": "Ada"}
        status, _result = self.call("POST", "/students", one_word)
        self.assertEqual(status, 201)
        status, result = self.call("GET", "/students/by-name?name=Ada")
        self.assertEqual((status, result["data"]["student"]["student_id"]), (200, "MANUAL-TEST-001"))
        # ui/database/postgres_client.gd:301 rejects names with <2 components.

    def test_long_manual_name_server_limit_150_differs_from_client_limit_200(self):
        allowed_name = "A" * 150
        rejected_name = "B" * 151
        self.assertEqual(self.call("POST", "/students", {**self.student, "student_name": allowed_name})[0], 201)
        status, result = self.call("POST", "/students", {**self.student,
            "student_id": "MANUAL-TEST-002", "student_name": rejected_name})
        self.assertEqual((status, result["error"]["code"]), (400, "invalid_input"))

    def test_offline_queue_persists_new_profile_across_restart_without_csv(self):
        with tempfile.TemporaryDirectory(prefix="kg_manual_no_csv_") as folder:
            journal = Path(folder) / "recovery.sqlite3"
            fake_pg = FakePostgres()
            fake_pg.available = False
            api = API(RecoveryStore(fake_pg, journal))
            status, result = api.dispatch("POST", "/students", self.student)
            self.assertEqual(status, 201)
            self.assertTrue(result["data"]["recovery_pending"])
            self.assertTrue(journal.is_file())
            self.assertEqual((fake_pg.students, fake_pg.scores), ({}, {}))

            api = API(RecoveryStore(fake_pg, journal))
            status, result = api.dispatch("GET", "/students/MANUAL-TEST-001")
            self.assertEqual(status, 200)
            self.assertTrue(result["data"]["student"]["recovery_pending"])
            self.assertEqual(api.dispatch("POST", "/students", self.student)[0], 200)
            fake_pg.available = True
            status, result = api.dispatch("GET", "/health")
            self.assertEqual((status, result["data"]["recovery_pending"]), (200, 0))
            self.assertEqual(fake_pg.students[self.student["student_id"]]["student_name"], "Ada Rivera")
            self.assertEqual(fake_pg.scores, {})
            self.assertEqual(fake_pg.register_writes, 1)

    def test_offline_update_of_registered_student_does_not_claim_success(self):
        with tempfile.TemporaryDirectory(prefix="kg_manual_patch_") as folder:
            fake_pg = FakePostgres()
            journal = Path(folder) / "journal.sqlite3"
            api = API(RecoveryStore(fake_pg, journal))
            self.assertEqual(api.dispatch("POST", "/students", self.student)[0], 201)
            fake_pg.available = False
            status, result = api.dispatch("PATCH", "/students/MANUAL-TEST-001", {
                "grade_section": "Grade 6",
            })
            # An edit requires live authoritative identity; do not promise
            # offline PATCH persistence or silently overwrite the profile.
            self.assertFalse(result["ok"])
            self.assertIn(result["error"]["code"], ("database_unavailable", "recovery_pending"))
            self.assertIn(status, (409, 503))
            self.assertEqual(fake_pg.students[self.student["student_id"]]["grade_section"],
                             self.student["grade_section"])

    def test_postgresql_queries_use_bound_params_and_separate_create_get_patch(self):
        # Exercise real PostgreSQLStore methods using injected cursor results.
        # PostgreSQLStore._connect is stubbed: no actual socket or SQL execution.
        sql_store = PostgreSQLStore(Config())
        created_row = {**self.student, "created_at": "t0", "updated_at": "t0"}
        insertion = Connection(results=[created_row])
        sql_store._connect = lambda: insertion
        profile, created = sql_store.register_student(**self.student)
        self.assertTrue(created)
        self.assertEqual(profile, created_row)
        self.assertEqual(insertion.queries[0][1], tuple(self.student.values()))
        self.assertIn("INSERT INTO students", insertion.queries[0][0])
        self.assertIn("ON CONFLICT (student_id) DO NOTHING", insertion.queries[0][0])
        self.assertTrue(insertion.committed)

        reading = Connection(results=[created_row])
        sql_store._connect = lambda: reading
        self.assertEqual(sql_store.find_student(self.student["student_id"]), created_row)
        self.assertIn("FROM students WHERE student_id = %s", reading.queries[0][0])
        self.assertEqual(reading.queries[0][1], (self.student["student_id"],))

        changed = {**created_row, "grade_section": "Grade 5 - Testing"}
        updating = Connection(results=[changed])
        sql_store._connect = lambda: updating
        self.assertEqual(sql_store.update_student(self.student["student_id"],
                             {"grade_section": "Grade 5 - Testing"}), changed)
        sql, params = updating.queries[0]
        self.assertIn("UPDATE students SET grade_section = %s, updated_at = now()", sql)
        self.assertIn("WHERE student_id = %s", sql)
        self.assertEqual(params, ("Grade 5 - Testing", self.student["student_id"]))
        self.assertTrue(updating.committed)
        for connection in (insertion, reading, updating):
            self.assertFalse(any("student_scores" in statement for statement, _ in connection.queries))

    def test_api_health_recovery_is_not_the_same_as_postgresql_identity_lookup(self):
        with tempfile.TemporaryDirectory(prefix="kg_lookup_offline_") as folder:
            fake_pg = FakePostgres()
            fake_pg.available = False
            api = API(RecoveryStore(fake_pg, Path(folder) / "journal.sqlite3"))
            status, result = api.dispatch("GET", "/health")
            self.assertEqual((status, result["data"]["database"]), (200, "recovery"))
            status, result = api.dispatch("GET", "/students/NOT-KNOWN")
            self.assertEqual((status, result["error"]["code"]), (503, "database_unavailable"))
            status, result = api.dispatch("GET", "/students/by-name?name=Ada%20Rivera")
            self.assertEqual((status, result["error"]["code"]), (503, "lookup_unavailable"))
            self.assertEqual((fake_pg.students, fake_pg.scores), ({}, {}))


if __name__ == "__main__":
    unittest.main()
