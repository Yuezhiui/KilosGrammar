"""Release evidence: API registration does not imply a completed score.

Pure in-memory API/store contract, no PostgreSQL, credentials, outbound calls,
Windows recovery outbox, or school student records.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from database.recovery_store import RecoveryStore
from database.server import API
from database.tests.test_recovery_store import FakePostgres
from database.tests.test_server import MemoryStore


class ProfileScoreSeparationReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.store = MemoryStore()
        self.api = API(self.store)

    def call(self, verb: str, route: str, body: dict | None = None):
        status, response = self.api.dispatch(verb, route, body)
        return status, response["data"], response["error"]

    def test_api_registration_and_lookup_persist_without_score(self) -> None:
        student = {
            "student_id": "QA-API-UNFINISHED-1",
            "student_name": "QA Incomplete Student",
            "grade_section": "Grade 4 - Test",
        }
        status, data, error = self.call("POST", "/students", student)
        self.assertEqual((status, error), (201, None))
        self.assertEqual(data["student"]["student_id"], student["student_id"])
        self.assertEqual(len(self.store.students), 1)
        self.assertEqual(self.store.scores, {})

        # A newly instantiated API, simulating a subsequent UI query/session,
        # sees the same student profile, but no imaginary completed score.
        self.api = API(self.store)
        status, data, error = self.call("GET", "/students/QA-API-UNFINISHED-1")
        self.assertEqual((status, error), (200, None))
        self.assertEqual(data["student"]["student_name"], student["student_name"])

        status, data, error = self.call("GET", "/leaderboard")
        self.assertEqual((status, error), (200, None))
        self.assertEqual((data["count"], data["leaderboard"]), (0, []))

        status, data, error = self.call(
            "GET",
            "/scores?student_id=QA-API-UNFINISHED-1"
            "&game_style=Noun&game_mode=Seconds&difficulty=Easy"
            "&minigame=Catch%20the%20Word",
        )
        self.assertEqual((status, error), (200, None))
        self.assertIsNone(data["score"])
        self.assertEqual(self.store.actions, ["register"])

    def test_identity_reuse_without_score_cannot_register_another_student(self) -> None:
        student = {
            "student_id": "QA-API-RETURN-2",
            "student_name": "QA Returning Student",
            "grade_section": "Grade 4 - Test",
        }
        self.assertEqual(self.call("POST", "/students", student)[0], 201)
        self.assertEqual(self.call("POST", "/students", student)[0], 200)
        self.assertEqual(self.store.actions.count("register"), 1)
        self.assertEqual(self.store.scores, {})

        different_name = {**student, "student_name": "QA Different Student"}
        status, data, error = self.call("POST", "/students", different_name)
        self.assertEqual(status, 409)
        self.assertIsNone(data)
        self.assertEqual(error["code"], "student_exists")
        self.assertEqual(self.store.students[student["student_id"]]["student_name"], student["student_name"])
        self.assertEqual(self.call("GET", "/leaderboard")[1]["count"], 0)

    def test_completed_score_appears_only_after_separate_completion_request(self) -> None:
        unfinished = {
            "student_id": "QA-API-PROFILE-ONLY",
            "student_name": "QA Profile Only",
            "grade_section": "Grade 6",
        }
        finished = {
            "student_id": "QA-API-FINISHED",
            "student_name": "QA Completed Game",
            "grade_section": "Grade 5",
        }
        for item in (unfinished, finished):
            self.assertEqual(self.call("POST", "/students", item)[0], 201)
        self.assertEqual(len(self.store.students), 2)
        self.assertEqual(self.call("GET", "/leaderboard")[1]["count"], 0)

        score = {
            "student_id": finished["student_id"], "game_style": "Noun",
            "game_mode": "Seconds", "difficulty": "Easy",
            "minigame": "Catch the Word", "score": 431,
        }
        status, data, error = self.call("POST", "/rounds/complete", score)
        self.assertEqual((status, error), (200, None))
        self.assertEqual(data["score"]["score"], 431)

        self.api = API(self.store)
        status, data, error = self.call("GET", "/leaderboard")
        self.assertEqual((status, error), (200, None))
        self.assertEqual(data["count"], 1)
        self.assertEqual(data["leaderboard"][0]["student_id"], finished["student_id"])
        self.assertEqual(data["leaderboard"][0]["score"], 431)
        self.assertNotIn(unfinished["student_id"], [row["student_id"] for row in data["leaderboard"]])
        status, filtered, error = self.call(
            "GET", "/leaderboard?minigame=Human%20Plane&game_mode=Seconds"
        )
        self.assertEqual((status, error), (200, None))
        self.assertEqual((filtered["count"], filtered["leaderboard"]), (0, []))
        status, filtered, error = self.call(
            "GET", "/leaderboard?minigame=Catch%20the%20Word&game_mode=Seconds"
        )
        self.assertEqual((status, error), (200, None))
        self.assertEqual(filtered["count"], 1)

    def test_independent_api_profile_survives_offline_restart_without_any_score(self) -> None:
        # This exercises the actual recovery SQLite journal with a disposable
        # temporary path and FakePostgres; there is NO real PostgreSQL socket.
        with tempfile.TemporaryDirectory(prefix="kilos_api_profile_only_") as folder:
            path = Path(folder) / "release_only.sqlite3"
            fake_pg = FakePostgres()
            fake_pg.available = False
            api = API(RecoveryStore(fake_pg, path))
            student = {
                "student_id": "QA-API-OFFLINE-4",
                "student_name": "QA Durable Profile",
                "grade_section": "Grade 2 - Test",
            }
            status, payload = api.dispatch("POST", "/students", student)
            self.assertEqual(status, 201)
            self.assertTrue(payload["data"]["student"]["recovery_pending"])
            self.assertTrue(path.is_file())
            self.assertEqual((fake_pg.students, fake_pg.scores), ({}, {}))

            # New service instance, same disposable disk journal, still offline.
            api = API(RecoveryStore(fake_pg, path))
            status, payload = api.dispatch("GET", "/students/QA-API-OFFLINE-4")
            self.assertEqual(status, 200)
            self.assertEqual(payload["data"]["student"]["student_name"], student["student_name"])
            self.assertTrue(payload["data"]["student"]["recovery_pending"])
            self.assertEqual((fake_pg.register_writes, fake_pg.score_writes), (0, 0))

            fake_pg.available = True
            status, payload = api.dispatch("GET", "/health")
            self.assertEqual(status, 200)
            self.assertEqual(payload["data"]["recovery_pending"], 0)
            self.assertEqual(fake_pg.students[student["student_id"]]["student_name"], student["student_name"])
            self.assertEqual(fake_pg.scores, {})
            self.assertEqual((fake_pg.register_writes, fake_pg.score_writes), (1, 0))
            status, payload = api.dispatch("GET", "/leaderboard")
            self.assertEqual((status, payload["data"]["count"]), (200, 0))


if __name__ == "__main__":
    unittest.main()
