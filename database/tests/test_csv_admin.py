"""Isolated CSV/admin endpoint contract; never connects to a real database."""

from __future__ import annotations

import csv
import io
import json
import socket
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from database.server import (
    API, CSV_COLUMNS, LEGACY_CSV_COLUMNS, MAX_CSV_BYTES,
    _create_admin_token, _csv_export, _csv_import, make_handler,
)
from database.storage import StudentIdentityConflict


ADMIN_KEY = "mock-only-token-for-unit-tests"


def csv_text(rows):
    sink = io.StringIO(newline="")
    writer = csv.writer(sink, lineterminator="\r\n")
    # Historical seven-column fixtures explicitly exercise legacy imports.
    writer.writerow(LEGACY_CSV_COLUMNS if rows and len(rows[0]) == 7 else CSV_COLUMNS)
    writer.writerows(rows)
    return sink.getvalue()


class BulkMemoryStore:
    """Transaction-like state snapshot for route-level contract tests."""

    def __init__(self):
        self.students = {}
        self.scores = {}
        self.delete_calls = 0

    def export_snapshot(self):
        return list(self.students.values()), list(self.scores.values())

    def import_snapshot(self, students, scores):
        next_students = dict(self.students)
        next_scores = dict(self.scores)
        counters = {
            "students_created": 0, "students_existing": 0, "scores_imported": len(scores),
            "scores_created": 0, "scores_updated": 0, "scores_unchanged": 0,
        }
        for student in students:
            key = student["student_id"]
            if key in next_students:
                if student != next_students[key]:
                    raise StudentIdentityConflict("Existing identity mismatch")
                counters["students_existing"] += 1
            else:
                next_students[key] = student
                counters["students_created"] += 1
        for score in scores:
            key = tuple(score[k] for k in ("student_id", "minigame", "game_style", "game_mode", "difficulty"))
            if key in next_scores:
                counter = "scores_unchanged" if next_scores[key]["score"] == score["score"] else "scores_updated"
            else:
                counter = "scores_created"
            counters[counter] += 1
            next_scores[key] = score
        self.students, self.scores = next_students, next_scores
        return counters

    def delete_all(self):
        result = {"students_deleted": len(self.students), "scores_deleted": len(self.scores)}
        self.delete_calls += 1
        self.students, self.scores = {}, {}
        return result


class AdminCsvContractTests(unittest.TestCase):
    def setUp(self):
        self.store = BulkMemoryStore()
        self.api = API(self.store, admin_token=ADMIN_KEY)

    def dispatch(self, method, route, body=None, token=ADMIN_KEY):
        return self.api.dispatch(method, route, body, admin_token=token)

    def test_csv_export_import_student_with_no_scores_and_lower_score_replacement(self):
        data = csv_text([
            ["KG-1", "Rosa", "4-A", "Noun", "Seconds", "Easy", "99"],
            ["KG-2", "Ben", "4-B", "", "", "", ""],
        ])
        code, result = self.dispatch("POST", "/data/import", {"csv": data})
        self.assertEqual(code, 200)
        self.assertEqual((result["data"]["students_created"], result["data"]["scores_imported"]), (2, 1))
        code, result = self.dispatch("GET", "/data/export")
        self.assertEqual(code, 200)
        self.assertEqual((result["data"]["students"], result["data"]["scores"]), (2, 1))
        rows = list(csv.DictReader(io.StringIO(result["data"]["csv"])))
        self.assertEqual(len(rows), 2)
        self.assertEqual(list(rows[0].keys()), list(CSV_COLUMNS))
        self.assertEqual(rows[0]["minigame"], "Legacy")
        self.assertEqual(next(item for item in rows if item["student_id"] == "KG-2")["score"], "")
        code, result = self.dispatch("POST", "/data/import", {"csv": result["data"]["csv"]})
        self.assertEqual(code, 200)
        self.assertEqual((result["data"]["students_created"], result["data"]["scores_unchanged"]), (0, 1))
        replacement = csv_text([["KG-1", "Rosa", "4-A", "Noun", "Seconds", "Easy", "7"]])
        code, result = self.dispatch("POST", "/data/import", {"csv": replacement})
        self.assertEqual(code, 200)
        self.assertEqual(result["data"]["scores_updated"], 1)
        self.assertEqual(next(iter(self.store.scores.values()))["score"], 7)

    def test_csv_formula_escapes_are_safe_and_roundtrip(self):
        self.store.students = {
            "KG-3": {"student_id": "KG-3", "student_name": "=HYPERLINK(\"bad\")", "grade_section": "'+5"},
            "KG-4": {"student_id": "KG-4", "student_name": "'=AlreadyQuoted", "grade_section": "3-B"},
        }
        text = self.dispatch("GET", "/data/export")[1]["data"]["csv"]
        rows = list(csv.DictReader(io.StringIO(text)))
        self.assertEqual(rows[0]["student_name"][:2], "'=")
        self.assertEqual(rows[0]["grade_section"][:2], "''")
        self.assertEqual(rows[1]["student_name"][:2], "''")
        imported_students, imported_scores = _csv_import(text)
        self.assertEqual(imported_scores, [])
        self.assertEqual(imported_students[0]["student_name"], "=HYPERLINK(\"bad\")")
        self.assertEqual(imported_students[0]["grade_section"], "'+5")
        self.assertEqual(imported_students[1]["student_name"], "'=AlreadyQuoted")

    def test_v2_csv_keeps_catch_human_and_balloon_scores_independent(self):
        imported = csv_text([
            ["KG-1", "Rosa", "4-A", "Catch the Word", "Noun", "Seconds", "Easy", "120"],
            ["KG-1", "Rosa", "4-A", "Human Plane", "Noun", "Seconds", "Easy", "15"],
            ["KG-1", "Rosa", "4-A", "Balloon Popping", "Noun", "Seconds", "Easy", "61"],
        ])
        status, result = self.dispatch("POST", "/data/import", {"csv": imported})
        self.assertEqual(status, 200)
        self.assertEqual(result["data"]["scores_imported"], 3)
        self.assertEqual(len(self.store.scores), 3)
        status, result = self.dispatch("GET", "/data/export")
        self.assertEqual(status, 200)
        rows = list(csv.DictReader(io.StringIO(result["data"]["csv"])))
        self.assertEqual({r["minigame"]: int(r["score"]) for r in rows}, {
            "Catch the Word": 120, "Human Plane": 15, "Balloon Popping": 61,
        })
        self.assertEqual(self.dispatch("POST", "/data/import", {"csv": result["data"]["csv"]})[1]["data"]["scores_unchanged"], 3)
        lower = csv_text([["KG-1", "Rosa", "4-A", "Human Plane", "Noun", "Seconds", "Easy", "1"]])
        self.assertEqual(self.dispatch("POST", "/data/import", {"csv": lower})[0], 200)
        self.assertEqual(self.store.scores[("KG-1", "Human Plane", "Noun", "Seconds", "Easy")]["score"], 1)
        self.assertEqual(self.store.scores[("KG-1", "Catch the Word", "Noun", "Seconds", "Easy")]["score"], 120)

    def test_canonical_csv_rejects_missing_or_empty_minigame_but_accepts_student_only(self):
        canonical_missing = csv_text([["KG-1", "Rosa", "4-A", "", "Noun", "Seconds", "Easy", "5"]])
        self.assertEqual(self.dispatch("POST", "/data/import", {"csv": canonical_missing})[0], 400)
        malformed_student_only = csv_text([["KG-1", "Rosa", "4-A", "Human Plane", "", "", "", ""]])
        self.assertEqual(self.dispatch("POST", "/data/import", {"csv": malformed_student_only})[0], 400)
        student_only = csv_text([["KG-1", "Rosa", "4-A", "", "", "", "", ""]])
        self.assertEqual(self.dispatch("POST", "/data/import", {"csv": student_only})[0], 200)

    def test_reject_corrupt_csv_duplicate_score_and_existing_identity_conflict(self):
        examples = [
            "id,name\n1,Bob\n",
            csv_text([["KG-1", "Rosa", "4-A", "Noun", "", "Easy", "12"]]),
            csv_text([["KG-1", "Rosa", "4-A", "Noun", "Seconds", "Easy", "-1"]]),
            csv_text([["KG-1", "Rosa", "4-A", "Noun", "Seconds", "Easy", "2147483648"]]),
            csv_text([["KG-1", "Rosa", "4-A", "Noun", "Seconds", "Easy", "3", "extra"]]),
        ]
        for text in examples:
            with self.subTest(csv=text):
                code, response = self.dispatch("POST", "/data/import", {"csv": text})
                self.assertEqual(code, 400)
                self.assertFalse(response["ok"])
        bad_identity = csv_text([
            ["KG-1", "Rosa", "4-A", "", "", "", ""],
            ["KG-1", "Maria", "4-A", "", "", "", ""],
        ])
        self.assertEqual(self.dispatch("POST", "/data/import", {"csv": bad_identity})[0], 409)
        bad_score = csv_text([
            ["KG-1", "Rosa", "4-A", "Noun", "Lives", "Easy", "20"],
            ["KG-1", "Rosa", "4-A", "Noun", "Lives", "Easy", "10"],
        ])
        self.assertEqual(self.dispatch("POST", "/data/import", {"csv": bad_score})[0], 409)
        self.assertEqual(self.store.students, {})
        self.store.students["KG-1"] = {"student_id": "KG-1", "student_name": "Rosa", "grade_section": "4-A"}
        conflicting = csv_text([["KG-1", "Different", "4-A", "", "", "", ""]])
        self.assertEqual(self.dispatch("POST", "/data/import", {"csv": conflicting})[0], 409)
        self.assertEqual(self.store.students["KG-1"]["student_name"], "Rosa")

    def test_csv_size_and_no_silent_export_truncation(self):
        huge = csv_text([["KG-1", "Rosa", "A" * (MAX_CSV_BYTES + 1), "", "", "", ""]])
        self.assertEqual(self.dispatch("POST", "/data/import", {"csv": huge})[0], 413)
        rows = csv_text([[f"KG-{i}", "Rosa", "4-A", "", "", "", ""] for i in range(5001)])
        self.assertEqual(self.dispatch("POST", "/data/import", {"csv": rows})[0], 413)
        self.store.students = {
            "KG-1": {"student_id": "KG-1", "student_name": "A" * MAX_CSV_BYTES, "grade_section": "4-A"}
        }
        self.assertEqual(self.dispatch("GET", "/data/export")[0], 413)

    def test_admin_token_and_delete_challenge_are_both_mandatory_one_use(self):
        self.store.students = {"KG-1": {"student_id": "KG-1", "student_name": "Rosa", "grade_section": "4-A"}}
        for method, path, body in (
            ("GET", "/data/export", None),
            ("POST", "/data/import", {"csv": csv_text([["KG-2", "Ben", "4-B", "", "", "", ""]])}),
            ("GET", "/data/delete_all/challenge", None),
            ("POST", "/data/delete_all", {"confirmation": "DELETE ALL DATA", "challenge": "guess"}),
        ):
            with self.subTest(path=path):
                self.assertEqual(self.dispatch(method, path, body, token="incorrect")[0], 403)
        self.assertEqual(self.dispatch("POST", "/data/delete_all", {
            "confirmation": "DELETE ALL DATA", "challenge": "guess"
        })[0], 403)
        code, response = self.dispatch("GET", "/data/delete_all/challenge")
        self.assertEqual(code, 200)
        token = response["data"]["challenge"]
        self.assertEqual(self.dispatch("POST", "/data/delete_all", {
            "challenge": token, "confirmation": "DELETE ALL"
        })[0], 400)
        self.assertEqual(self.store.delete_calls, 0)
        code, result = self.dispatch("POST", "/data/delete_all", {
            "challenge": token, "confirmation": "DELETE ALL DATA"
        })
        self.assertEqual(code, 200)
        self.assertEqual(result["data"]["students_deleted"], 1)
        self.assertEqual(self.store.delete_calls, 1)
        self.assertEqual(self.dispatch("POST", "/data/delete_all", {
            "challenge": token, "confirmation": "DELETE ALL DATA"
        })[0], 403)
        self.assertEqual(self.store.delete_calls, 1)

    def test_expired_delete_challenge_is_rejected(self):
        with patch("database.server.time.monotonic", return_value=100.0):
            token = self.dispatch("GET", "/data/delete_all/challenge")[1]["data"]["challenge"]
        with patch("database.server.time.monotonic", return_value=161.0):
            self.assertEqual(self.dispatch("POST", "/data/delete_all", {
                "challenge": token, "confirmation": "DELETE ALL DATA"
            })[0], 403)
        self.assertEqual(self.store.delete_calls, 0)


class AdminHttpTests(unittest.TestCase):
    def test_http_requires_token_and_validates_large_csv_body(self):
        store = BulkMemoryStore()
        httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(API(store, admin_token=ADMIN_KEY)))
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{httpd.server_port}"
        try:
            for token, expected in ((None, 403), ("invalid", 403), (ADMIN_KEY, 200)):
                headers = {"X-Kilos-Admin-Token": token} if token else {}
                request = Request(base + "/data/export", headers=headers)
                try:
                    with urlopen(request, timeout=3) as response:
                        actual = response.status
                except HTTPError as error:
                    actual = error.code
                self.assertEqual(actual, expected)
            csv_body = csv_text([["KG-1", "Rosa", "4-A", "Noun", "Lives", "Easy", "3"]])
            request = Request(
                base + "/data/import", method="POST",
                data=json.dumps({"csv": csv_body}).encode(),
                headers={"X-Kilos-Admin-Token": ADMIN_KEY, "Content-Type": "application/json"},
            )
            with urlopen(request, timeout=3) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(json.load(response)["data"]["scores_imported"], 1)
        finally:
            httpd.shutdown()
            httpd.server_close()
            thread.join(timeout=3)

    def test_admin_token_file_created_outside_repository(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict("os.environ", {"LOCALAPPDATA": directory}):
            token = _create_admin_token()
            file = Path(directory) / "KilosGrammar" / "admin_api_token.txt"
            self.assertTrue(file.is_file())
            self.assertEqual(file.read_text(encoding="ascii"), token)
            self.assertNotEqual(token, _create_admin_token())

    def test_colliding_service_start_cannot_replace_running_api_token(self):
        from database.server import main

        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            occupied = listener.getsockname()[1]
            with patch.dict("os.environ", {"KILOS_HTTP_PORT": str(occupied)}), patch(
                "database.server._create_admin_token"
            ) as rotate:
                with self.assertRaises(OSError):
                    main()
                rotate.assert_not_called()


if __name__ == "__main__":
    unittest.main()
