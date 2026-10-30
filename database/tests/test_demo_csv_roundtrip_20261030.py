"""Exact DEMO CSV -> import -> export -> mock DELETE -> restore -> leaderboard QA.

All API operations use a disposable IN-MEMORY store and isolated mock teacher
token. This module NEVER connects to PostgreSQL/HTTP or reads local student
records, and NEVER invokes the live DELETE endpoint.
"""

from __future__ import annotations

import csv
import io
import unittest
from pathlib import Path

from database.server import API, CSV_COLUMNS, LEGACY_CSV_COLUMNS, _csv_import
from database.tests.test_csv_admin import BulkMemoryStore


ROOT = Path(__file__).resolve().parents[2]
DEMO_CSV = ROOT / "docs/examples/kilosgrammar_demo_scores_20261030.csv"
LEGACY_CSV = ROOT / "docs/examples/kilosgrammar_demo_legacy_profile_only_20261030.csv"
TOKEN = "in-memory-teacher-only"
GAMES = {"Catch the Word", "Balloon Popping", "Human Plane"}
TOPICS = {"Noun", "Pronoun", "Verb", "Adjective", "Adverb"}
MODES = {"Seconds", "Lives"}
DIFFICULTIES = {"Easy", "Normal", "Hard"}


class RankingBulkStore(BulkMemoryStore):
    """Memory-only score ranking with the real API's get_leaderboard signature."""

    def get_leaderboard(
        self, game_style, game_mode, difficulty, grade_section, limit, minigame=None
    ):
        rows = []
        for score in self.scores.values():
            student = self.students[score["student_id"]]
            if (
                (game_style is not None and score["game_style"] != game_style)
                or (game_mode is not None and score["game_mode"] != game_mode)
                or (difficulty is not None and score["difficulty"] != difficulty)
                or (minigame is not None and score["minigame"] != minigame)
                or (grade_section is not None and student["grade_section"] != grade_section)
            ):
                continue
            rows.append({**score, "student_name": student["student_name"],
                         "grade_section": student["grade_section"]})
        rows.sort(key=lambda row: (-row["score"], row["student_id"], row["minigame"]))
        return [{"rank": i, **row} for i, row in enumerate(rows[:limit], start=1)]


class DemoCsvRoundTrip(unittest.TestCase):
    def setUp(self):
        self.store = RankingBulkStore()
        self.api = API(self.store, admin_token=TOKEN)

    def call(self, method, route, body=None, token=TOKEN):
        status, reply = self.api.dispatch(
            method, route, body, admin_token=token
        )
        self.assertEqual(
            status, 200, f"API {method} {route} unexpectedly rejected: {reply.get('error')}"
        )
        self.assertTrue(reply["ok"])
        return reply["data"]

    def test_demo_rows_match_actual_game_scoring_and_csv_schema(self):
        csv_source = DEMO_CSV.read_text(encoding="utf-8-sig")
        students, scores = _csv_import(csv_source)
        self.assertEqual(len(students), 7)
        self.assertEqual(len(scores), 18)
        self.assertEqual({score["minigame"] for score in scores}, GAMES)
        self.assertEqual({score["game_style"] for score in scores}, TOPICS)
        self.assertEqual({score["game_mode"] for score in scores}, MODES)
        self.assertEqual({score["difficulty"] for score in scores}, DIFFICULTIES)
        self.assertEqual({score["student_id"] for score in scores},
                         {student["student_id"] for student in students
                          if student["student_id"].endswith(tuple("ABCDEF"))})
        self.assertTrue(all(
            score["score"] % 100 == 0 and score["score"] >= 0 for score in scores
        ), "All game scores are achievable increments of +100, including zero")
        for game in GAMES:
            by_game = [score for score in scores if score["minigame"] == game]
            self.assertEqual(len(by_game), 6)
            self.assertEqual({score["game_mode"] for score in by_game}, MODES)
            self.assertEqual({score["difficulty"] for score in by_game}, DIFFICULTIES)
        self.assertTrue(all(
            student["student_id"].startswith("DEMO-KG-20261030-")
            and student["student_name"].startswith("Demo ")
            and student["grade_section"].endswith(" - DEMO")
            for student in students
        ))
        self.assertEqual(
            next(s for s in students if s["student_id"].endswith("-P"))["student_name"],
            "Demo Profile Only"
        )
        header = next(csv.reader(io.StringIO(csv_source)))
        self.assertEqual(tuple(header), CSV_COLUMNS)

        legacy_source = LEGACY_CSV.read_text(encoding="utf-8-sig")
        historical_students, historical_scores = _csv_import(legacy_source)
        self.assertEqual(len(historical_students), 1)
        self.assertEqual(historical_scores, [])
        self.assertEqual(tuple(next(csv.reader(io.StringIO(legacy_source)))),
                         LEGACY_CSV_COLUMNS)

    def test_complete_export_delete_restore_stays_isolated_and_preserves_prior_rows(self):
        # A fake existing record makes it impossible for a partial demo-only
        # backup to pass the test; the full teacher export must be restored.
        existing_csv = (
            "student_id,student_name,grade_section,minigame,game_style,game_mode,difficulty,score\r\n"
            "EXISTING-QA-ONLY,Existing Fake Learner,Grade 4 - DEMO,Human Plane,Verb,Seconds,Easy,700\r\n"
        )
        prior = self.call("POST", "/data/import", {"csv": existing_csv})
        self.assertEqual((prior["students_created"], prior["scores_imported"]), (1, 1))
        initial_export = self.call("GET", "/data/export")
        self.assertEqual((initial_export["students"], initial_export["scores"]), (1, 1))

        inserted = self.call("POST", "/data/import",
                             {"csv": DEMO_CSV.read_text(encoding="utf-8-sig")})
        self.assertEqual((inserted["students_created"], inserted["scores_created"],
                          inserted["scores_imported"]), (7, 18, 18))
        self.assertEqual(len(self.store.students), 8)
        self.assertEqual(len(self.store.scores), 19)
        self.assertEqual(self.store.students["EXISTING-QA-ONLY"]["student_name"],
                         "Existing Fake Learner")
        leaderboard = self.call("GET", "/leaderboard")
        self.assertEqual(leaderboard["count"], 19)
        self.assertEqual(leaderboard["leaderboard"][0]["score"], 700)
        self.assertEqual(leaderboard["leaderboard"][1]["score"], 600)
        demo_ranked = [r for r in leaderboard["leaderboard"]
                       if r["student_id"].startswith("DEMO-")]
        self.assertEqual(len(demo_ranked), 18)
        self.assertEqual([row["score"] for row in demo_ranked],
                         sorted([row["score"] for row in demo_ranked], reverse=True))
        self.assertNotIn("DEMO-KG-20261030-P", [r["student_id"] for r in demo_ranked])
        self.assertEqual(self.call("GET", "/leaderboard?minigame=Catch%20the%20Word")["count"], 6)
        self.assertEqual(self.call("GET", "/leaderboard?minigame=Balloon%20Popping")["count"], 6)
        self.assertEqual(self.call("GET", "/leaderboard?minigame=Human%20Plane")["count"], 7)
        self.assertEqual(self.call("GET", "/leaderboard?difficulty=Hard")["count"], 6)
        self.assertEqual(self.call("GET", "/leaderboard?game_mode=Seconds")["count"], 10)
        self.assertEqual(self.call("GET", "/leaderboard?game_mode=Lives")["count"], 9)

        full_backup = self.call("GET", "/data/export")
        self.assertEqual((full_backup["students"], full_backup["scores"]), (8, 19))
        exported_students, exported_scores = _csv_import(full_backup["csv"])
        self.assertEqual((len(exported_students), len(exported_scores)), (8, 19))
        self.assertEqual(len(list(csv.DictReader(io.StringIO(full_backup["csv"])))), 20)
        self.assertIn("DEMO-KG-20261030-P", full_backup["csv"])
        self.assertIn("EXISTING-QA-ONLY", full_backup["csv"])

        # WARNING: THIS IS A MOCK-ONLY DELETE; live DATABASE IS NOT TOUCHED.
        # Guard with the real API challenge/confirmation contract.
        challenge = self.call("GET", "/data/delete_all/challenge")
        self.assertEqual(challenge["confirmation_phrase"], "DELETE ALL DATA")
        deleted = self.call("POST", "/data/delete_all", {
            "challenge": challenge["challenge"], "confirmation": "DELETE ALL DATA"
        })
        self.assertEqual((deleted["students_deleted"], deleted["scores_deleted"]), (8, 19))
        self.assertEqual(self.call("GET", "/leaderboard")["count"], 0)
        self.assertEqual((len(self.store.students), len(self.store.scores)), (0, 0))

        restored = self.call("POST", "/data/import", {"csv": full_backup["csv"]})
        self.assertEqual((restored["students_created"], restored["scores_created"]), (8, 19))
        self.assertEqual(self.call("GET", "/leaderboard"), leaderboard)
        self.assertEqual(self.call("GET", "/data/export")["csv"], full_backup["csv"])
        self.assertEqual(self.store.students["EXISTING-QA-ONLY"]["student_name"],
                         "Existing Fake Learner")
        self.assertEqual(self.store.delete_calls, 1)

        # Safe repeated import must not duplicate records or overwrite values.
        repeat = self.call("POST", "/data/import", {"csv": full_backup["csv"]})
        self.assertEqual((repeat["students_created"], repeat["scores_created"],
                          repeat["scores_updated"], repeat["scores_unchanged"]),
                         (0, 0, 0, 19))
        self.assertEqual(self.call("GET", "/leaderboard")["count"], 19)
        self.assertEqual(self.store.delete_calls, 1)

    def test_legacy_profile_only_never_fabricates_game_result(self):
        inserted = self.call("POST", "/data/import", {
            "csv": LEGACY_CSV.read_text(encoding="utf-8-sig")
        })
        self.assertEqual((inserted["students_created"], inserted["scores_imported"]), (1, 0))
        self.assertEqual(self.call("GET", "/leaderboard")["count"], 0)
        full = self.call("GET", "/data/export")
        self.assertEqual((full["students"], full["scores"]), (1, 0))
        self.assertEqual(tuple(next(csv.reader(io.StringIO(full["csv"])))), CSV_COLUMNS)
        self.assertEqual(len(list(csv.DictReader(io.StringIO(full["csv"])))), 1)


if __name__ == "__main__":
    unittest.main()
