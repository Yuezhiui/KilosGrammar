"""Offline/restart/replay/HTTP fault injection: never uses a real database."""

from __future__ import annotations

import json
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path

from database.recovery_store import RecoveryStore, normalized_full_name
from database.server import API
from database.storage import StudentIdentityConflict


class FakePostgres:
    def __init__(self) -> None:
        self.available = True
        self.students = {}
        self.scores = {}
        self.score_writes = 0
        self.register_writes = 0
        self.fail_score_after_commit_once = False
        self.fail_student_after_commit_once = False

    def _online(self):
        if not self.available:
            raise OSError("postgres unavailable")

    def health(self):
        self._online()
        return {"status": "ok", "database": "connected"}

    def find_student(self, student_id):
        self._online()
        return self.students.get(student_id)

    def find_score(self, student_id, game_style, game_mode, difficulty, minigame="Legacy"):
        self._online()
        return self.scores.get((student_id, minigame, game_style, game_mode, difficulty))

    def find_students_by_name(self, name):
        self._online()
        return [row for row in self.students.values()
                if normalized_full_name(row["student_name"]) == normalized_full_name(name)]

    def register_student(self, student_id, student_name, grade_section):
        self._online()
        existing = self.students.get(student_id)
        if existing:
            if (existing["student_name"], existing["grade_section"]) != (student_name, grade_section):
                raise StudentIdentityConflict("same ID registered to different person")
            return existing, False
        record = {"student_id": student_id, "student_name": student_name,
                  "grade_section": grade_section}
        self.students[student_id] = record
        self.register_writes += 1
        if self.fail_student_after_commit_once:
            self.fail_student_after_commit_once = False
            raise OSError("network lost after primary COMMIT")
        return record, True

    def complete_round_and_replace_score(
        self, student_id, game_style, game_mode, difficulty, score, minigame="Legacy",
    ):
        self._online()
        if student_id not in self.students:
            error = Exception("foreign key: student does not exist")
            error.sqlstate = "23503"
            raise error
        key = (student_id, minigame, game_style, game_mode, difficulty)
        old = self.scores.get(key)
        record = {
            "student_id": student_id, "minigame": minigame,
            "game_style": game_style, "game_mode": game_mode,
            "difficulty": difficulty, "score": score,
            "score_id": old["score_id"] if old is not None else len(self.scores) + 1,
        }
        self.scores[key] = record
        self.score_writes += 1
        if self.fail_score_after_commit_once:
            self.fail_score_after_commit_once = False
            raise OSError("network lost after primary COMMIT")
        return record

    def update_student(self, student_id, changes):
        self._online()
        student = self.students.get(student_id)
        if student:
            student.update(changes)
        return student

    def get_leaderboard(self, *_args, **_kwargs):
        self._online()
        return []

    def export_snapshot(self):
        self._online()
        return list(self.students.values()), list(self.scores.values())

    def import_snapshot(self, students, scores):
        self._online()
        return {"students_created": len(students), "scores_imported": len(scores)}

    def delete_all(self):
        self._online()
        result = {"students_deleted": len(self.students), "scores_deleted": len(self.scores)}
        self.students.clear()
        self.scores.clear()
        return result


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="kilos_recovery_test_")
        self.path = Path(self.temp.name) / "recovery.sqlite3"
        self.pg = FakePostgres()
        self.store = RecoveryStore(self.pg, self.path)
        self.api = API(self.store)

    def tearDown(self):
        self.temp.cleanup()

    def call(self, method, path, body=None):
        status, result = self.api.dispatch(method, path, body)
        return status, result["data"], result["error"]

    def student(self, student_id="ST-001", student_name="Alex Santos"):
        return {"student_id": student_id, "student_name": student_name,
                "grade_section": "Grade 4 - Blue"}

    def score(self, score=450, student_id="ST-001", minigame="Catch the Word", request_id=None):
        payload = {"student_id": student_id, "minigame": minigame,
                   "game_style": "Noun", "game_mode": "Seconds",
                   "difficulty": "Easy", "score": score}
        if request_id is not None:
            payload["request_id"] = request_id
        return payload

    def assert_pending(self, total):
        status, payload, _error = self.call("GET", "/health")
        self.assertEqual(status, 200)
        self.assertEqual(payload["recovery_pending"], total)

    def test_offline_registration_and_score_survive_new_process_then_sync(self):
        self.pg.available = False
        status, body, _ = self.call("POST", "/students", self.student())
        self.assertEqual(status, 201)
        self.assertTrue(body["student"]["recovery_pending"])
        status, body, _ = self.call("POST", "/rounds/complete", self.score(request_id="round-001"))
        self.assertEqual(status, 200)
        self.assertTrue(body["score"]["recovery_pending"])
        self.assert_pending(2)
        self.assertTrue(self.path.exists())
        # No Postgres writes while disconnected; discard server/store objects
        # and use a different object on the original disk file.
        self.api = API(RecoveryStore(self.pg, self.path))
        self.assert_pending(2)
        self.pg.available = True
        status, ready, _ = self.call("GET", "/health")
        self.assertEqual((status, ready["database"], ready["recovery_pending"]), (200, "connected", 0))
        self.assertEqual(self.pg.students["ST-001"]["student_name"], "Alex Santos")
        self.assertEqual(len(self.pg.scores), 1)
        self.assertEqual(next(iter(self.pg.scores.values()))["score"], 450)
        self.assertEqual((self.pg.register_writes, self.pg.score_writes), (1, 1))

    def test_postgres_only_student_can_save_offline_and_sync(self):
        self.pg.register_student("OLD-001", "Previously Registered", "5-A")
        self.pg.available = False
        status, body, _ = self.call("POST", "/rounds/complete", self.score(100, "OLD-001"))
        self.assertEqual(status, 200)
        self.assertTrue(body["score"]["recovery_pending"])
        self.pg.available = True
        self.assert_pending(0)
        self.assertEqual(len(self.pg.scores), 1)
        self.assertEqual(next(iter(self.pg.scores.values()))["student_id"], "OLD-001")

    def test_existing_primary_identity_is_idempotent_and_unknown_score_rejected(self):
        self.pg.register_student("OLD-002", "Existing Student", "Grade 4 - Blue")
        existing = self.student("OLD-002", "Existing Student")
        self.assertEqual(self.call("POST", "/students", existing)[0], 200)
        self.assertEqual(self.pg.register_writes, 1)
        status, _, error = self.call("POST", "/rounds/complete", self.score(30, "NOT-REGISTERED"))
        self.assertEqual((status, error["code"]), (404, "student_not_found"))
        self.assert_pending(0)

    def test_recovery_disk_write_error_cannot_report_success_or_touch_postgres(self):
        def fail_local(*_args):
            raise sqlite3.OperationalError("disk full")
        self.store._enqueue = fail_local
        status, _, error = self.call("POST", "/students", self.student())
        self.assertEqual((status, error["code"]), (503, "database_unavailable"))
        self.assertFalse(self.pg.students)
        self.assertEqual(self.pg.register_writes, 0)

    def test_idempotency_request_id_and_crash_after_commit(self):
        self.pg.fail_student_after_commit_once = True
        status, body, _ = self.call("POST", "/students", self.student())
        self.assertEqual(status, 201)
        self.assertTrue(body["student"]["recovery_pending"])
        self.pg.fail_score_after_commit_once = True
        status, body, _ = self.call("POST", "/rounds/complete", self.score(request_id="round-one"))
        self.assertEqual(status, 200)
        self.assertTrue(body["score"]["recovery_pending"])
        self.assertEqual(len(self.pg.scores), 1)
        self.api = API(RecoveryStore(self.pg, self.path))
        self.assert_pending(0)
        self.assertEqual((len(self.pg.students), len(self.pg.scores)), (1, 1))
        self.assertEqual(self.call("POST", "/rounds/complete", self.score(request_id="round-one"))[0], 200)
        self.assertEqual(len(self.pg.scores), 1)
        self.assertEqual(self.call("POST", "/rounds/complete", self.score(150, request_id="round-one"))[0], 409)
        self.assertEqual(next(iter(self.pg.scores.values()))["score"], 450)

    def test_offline_multiple_scores_order_and_different_minigames(self):
        self.pg.available = False
        self.call("POST", "/students", self.student())
        self.call("POST", "/rounds/complete", self.score(150, request_id="r-1"))
        self.call("POST", "/rounds/complete", self.score(50, request_id="r-2"))
        self.call("POST", "/rounds/complete", self.score(75, minigame="Human Plane", request_id="r-3"))
        self.assert_pending(4)
        self.pg.available = True
        self.assert_pending(0)
        self.assertEqual(len(self.pg.scores), 2)
        self.assertEqual(self.pg.scores["ST-001", "Catch the Word", "Noun", "Seconds", "Easy"]["score"], 50)
        self.assertEqual(self.pg.scores["ST-001", "Human Plane", "Noun", "Seconds", "Easy"]["score"], 75)

    def test_no_wrong_student_fallback_when_id_conflicts(self):
        self.pg.available = False
        self.call("POST", "/students", self.student())
        self.call("POST", "/rounds/complete", self.score(request_id="same-id-score"))
        self.pg.available = True
        self.pg.register_student("ST-001", "A Different Person", "5-Z")
        status, body, error = self.call("GET", "/health")
        self.assertEqual((body["recovery_conflicts"], body["recovery_pending"]), (1, 1))
        self.assertEqual(len(self.pg.scores), 0)
        self.assertEqual(self.call("POST", "/students", self.student())[0], 409)
        with self.store._connection() as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM recovery_events").fetchone()[0], 2)

    def test_one_identity_conflict_does_not_starve_other_students(self):
        self.pg.available = False
        self.call("POST", "/students", self.student("CONFLICT-1", "Offline Student"))
        self.call("POST", "/rounds/complete", self.score(80, "CONFLICT-1", request_id="c-1"))
        self.call("POST", "/students", self.student("SAFE-2", "Unrelated Student"))
        self.call("POST", "/rounds/complete", self.score(55, "SAFE-2", request_id="s-2"))
        self.pg.available = True
        self.pg.register_student("CONFLICT-1", "Different Student", "5-Z")
        status, state, _ = self.call("GET", "/health")
        self.assertEqual(status, 200)
        self.assertEqual(state["recovery_conflicts"], 1)
        self.assertEqual(self.pg.students["SAFE-2"]["student_name"], "Unrelated Student")
        self.assertEqual(self.pg.scores["SAFE-2", "Catch the Word", "Noun", "Seconds", "Easy"]["score"], 55)
        self.assertNotIn(("CONFLICT-1", "Catch the Word", "Noun", "Seconds", "Easy"), self.pg.scores)

    def test_failed_orphan_score_does_not_starve_valid_student(self):
        self.pg.available = False
        self.call("POST", "/rounds/complete", self.score(10, "NOT-REGISTERED", request_id="orphan"))
        self.call("POST", "/students", self.student("SAFE-3", "Valid Student"))
        self.call("POST", "/rounds/complete", self.score(95, "SAFE-3", request_id="safe"))
        self.pg.available = True
        self.call("GET", "/health")
        self.assertEqual(self.pg.students["SAFE-3"]["student_name"], "Valid Student")
        self.assertEqual(self.pg.scores["SAFE-3", "Catch the Word", "Noun", "Seconds", "Easy"]["score"], 95)
        self.assert_pending(1)

    def test_orphan_score_can_replay_after_later_registration_without_order_loss(self):
        self.pg.available = False
        self.call("POST", "/rounds/complete", self.score(41, "LATE-1", request_id="late-1"))
        self.call("POST", "/students", self.student("LATE-1", "Later Registered"))
        self.call("POST", "/rounds/complete", self.score(84, "LATE-1", request_id="late-2"))
        self.pg.available = True
        # First pass sees missing FK for score 41, then applies registration;
        # must not skip ahead and write score 84 ahead of the older 41.
        self.store.sync()
        self.assertEqual(self.pg.score_writes, 0)
        self.store.sync()
        self.assertEqual(self.pg.scores["LATE-1", "Catch the Word", "Noun", "Seconds", "Easy"]["score"], 84)
        self.assert_pending(0)

    def test_repeated_upserts_and_stale_ack_never_rollback_newer_score(self):
        self.call("POST", "/students", self.student())
        for score in range(120):
            code, data, _ = self.call("POST", "/rounds/complete", self.score(score, request_id="round-%03d" % score))
            self.assertEqual(code, 200)
            self.assertFalse(data["recovery_pending"])
        self.assertEqual(len(self.pg.scores), 1)
        self.assertEqual(next(iter(self.pg.scores.values()))["score"], 119)
        previous_writes = self.pg.score_writes
        response_code, replay, _ = self.call("POST", "/rounds/complete", self.score(2, request_id="round-002"))
        self.assertEqual(response_code, 200)
        self.assertEqual(replay["score"]["score"], 119)
        self.assertTrue(replay["score"]["idempotent_replay"])
        self.assertTrue(replay["score"]["score_superseded"])
        self.assertEqual(self.pg.score_writes, previous_writes)
        self.assertEqual(next(iter(self.pg.scores.values()))["score"], 119)

    def test_applied_score_tombstone_after_delete_cannot_claim_phantom_success(self):
        self.call("POST", "/students", self.student())
        status, original, error = self.call(
            "POST", "/rounds/complete", self.score(123, request_id="lost-after-delete")
        )
        self.assertEqual((status, error), (200, None))
        self.assertFalse(original["recovery_pending"])
        self.assertEqual(len(self.pg.scores), 1)
        self.assert_pending(0)
        with self.store._connection() as db:
            state = db.execute(
                "SELECT state FROM recovery_events WHERE event_key=?",
                ("score:request:lost-after-delete",),
            ).fetchone()["state"]
        self.assertEqual(state, "applied")
        # Primary transaction committed before a simulated crash and before
        # delete_all() could clear SQLite's already-applied tombstones.
        self.pg.delete_all()
        self.api = API(RecoveryStore(self.pg, self.path))  # simulated API restart
        self.assertFalse(self.pg.students)
        writes = self.pg.score_writes
        status, body, error = self.call(
            "POST", "/rounds/complete", self.score(123, request_id="lost-after-delete")
        )
        self.assertNotEqual(status, 200)
        self.assertIsNone(body)
        self.assertIsNotNone(error)
        self.assertEqual(self.pg.score_writes, writes)
        self.assertEqual(len(self.pg.scores), 0)
        self.assert_pending(0)
        # Even after teacher explicitly re-registers that ID, the old round
        # may NOT resurrect a deleted score. New rounds use new request_ids.
        self.assertEqual(self.call("POST", "/students", self.student())[0], 201)
        status, _, _ = self.call(
            "POST", "/rounds/complete", self.score(123, request_id="lost-after-delete")
        )
        self.assertNotEqual(status, 200)
        self.assertFalse(self.pg.scores)
        self.assertEqual(
            self.call("POST", "/rounds/complete", self.score(345, request_id="new-round"))[0], 200
        )
        self.assertEqual(next(iter(self.pg.scores.values()))["score"], 345)
        # Replaying the deleted old round after a new legitimate completed
        # round must acknowledge the verified latest row, not roll it back.
        score_writes = self.pg.score_writes
        status, result, error = self.call(
            "POST", "/rounds/complete", self.score(123, request_id="lost-after-delete")
        )
        self.assertEqual((status, error), (200, None))
        self.assertEqual(result["score"]["score"], 345)
        self.assertTrue(result["score"]["score_superseded"])
        self.assertEqual(self.pg.score_writes, score_writes)

    def test_applied_score_tombstone_while_postgres_offline_is_not_verified_success(self):
        self.call("POST", "/students", self.student())
        self.assertEqual(
            self.call("POST", "/rounds/complete", self.score(77, request_id="offline-applied"))[0], 200
        )
        writes = self.pg.score_writes
        self.pg.available = False
        status, body, error = self.call(
            "POST", "/rounds/complete", self.score(77, request_id="offline-applied")
        )
        self.assertEqual(status, 503)
        self.assertIsNone(body)
        self.assertEqual(error["code"], "database_unavailable")
        self.assertEqual(self.pg.score_writes, writes)
        # A genuine new offline completed round must still enqueue normally.
        status, body, error = self.call(
            "POST", "/rounds/complete", self.score(88, request_id="offline-new-round")
        )
        self.assertEqual((status, error), (200, None))
        self.assertTrue(body["recovery_pending"])
        self.assert_pending(1)
        self.pg.available = True
        self.assert_pending(0)
        self.assertEqual(next(iter(self.pg.scores.values()))["score"], 88)

    def test_explicit_registration_recovers_after_pg_admin_delete_before_local_ack(self):
        # Simulate power loss between PostgreSQL DELETE COMMIT and the SQLite
        # cleanup in RecoveryStore.delete_all(): applied journal entry remains.
        self.call("POST", "/students", self.student())
        self.assert_pending(0)
        self.pg.delete_all()
        self.assertNotIn("ST-001", self.pg.students)
        status, body, _ = self.call("POST", "/students", self.student())
        self.assertEqual(status, 201)
        self.assertIn("ST-001", self.pg.students)
        self.assertFalse(body["student"]["recovery_pending"])

    def test_exact_name_ambiguity_and_offline_safety(self):
        self.call("POST", "/students", self.student("A-1", "  María   Dela   Cruz  "))
        status, result, _ = self.call("GET", "/students/by-name?name=mAR%C3%ADa%20dela%20cruz")
        self.assertEqual((status, result["student"]["student_id"]), (200, "A-1"))
        self.assertEqual(self.call("GET", "/students/by-name?name=Mar%C3%ADa")[0], 404)
        self.call("POST", "/students", self.student("A-2", "María Dela Cruz"))
        status, _, error = self.call("GET", "/students/by-name?name=Mar%C3%ADa%20Dela%20Cruz")
        self.assertEqual((status, error["code"]), (409, "student_ambiguous"))
        self.assertEqual(self.call("GET", "/students/A-2")[1]["student"]["student_id"], "A-2")
        self.pg.available = False
        status, _, error = self.call("GET", "/students/by-name?name=Mar%C3%ADa%20Dela%20Cruz")
        self.assertEqual((status, error["code"]), (503, "lookup_unavailable"))
        for query in ["", "  ", "Marie%00Dela", "A%26B&name=C"]:
            self.assertEqual(self.call("GET", "/students/by-name?name=" + query)[0], 400)

    def test_applied_cached_profile_never_overrides_explicit_update_during_pg_outage(self):
        self.call("POST", "/students", self.student())
        self.assert_pending(0)
        self.assertEqual(self.call("PATCH", "/students/ST-001", {"student_name": "Updated By Teacher"})[0], 200)
        self.pg.available = False
        # SQLite's old *applied* registration is not a safe offline profile:
        # Postgres may have later authorized edits. Refuse stale autofill.
        status, _body, error = self.call("GET", "/students/ST-001")
        self.assertEqual((status, error["code"]), (503, "database_unavailable"))
        self.pg.available = True
        self.assertEqual(self.call("GET", "/students/ST-001")[1]["student"]["student_name"], "Updated By Teacher")

    def test_admin_delete_refuses_pending_and_preserves_rows(self):
        self.pg.available = False
        self.call("POST", "/students", self.student())
        with self.assertRaises(Exception):
            self.store.delete_all()
        self.assert_pending(1)
        self.pg.available = True
        self.assert_pending(0)
        self.assertEqual(self.store.delete_all()["students_deleted"], 1)
        self.assertEqual(len(self.pg.students), 0)
        self.assertEqual(self.call("POST", "/students", self.student())[0], 201)

    def test_multi_thread_offline_repeat(self):
        self.pg.available = False
        results = []
        def register():
            results.append(self.call("POST", "/students", self.student())[0])
        threads = [threading.Thread(target=register) for _ in range(12)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(results.count(201), 1)
        self.assertEqual(results.count(200), 11)
        self.assert_pending(1)


if __name__ == "__main__":
    unittest.main()
