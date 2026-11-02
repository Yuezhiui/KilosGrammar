"""Offline grade workbook and read-only roster endpoint tests.

No real PostgreSQL, filesystem export, tokens, destructive calls or internet.
"""

from __future__ import annotations

import base64
from datetime import datetime, timezone, timedelta
import io
import unittest
from xml.etree import ElementTree as ET
from zipfile import ZipFile

from database.server import API, CSV_COLUMNS, LEGACY_CSV_COLUMNS
from database.xlsx_export import build_xlsx, grade_number, selected_students

ADMIN_KEY = "isolated-teacher-capability"
X = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


class ReportingFakeStore:
    def __init__(self):
        self.calls = []
        self.students = [
            {"student_id": "G1-A", "student_name": "Alice", "grade_section": "Grade 1 - Rose",
             "created_at": datetime(2026, 10, 10, 7, 0, tzinfo=timezone.utc)},
            {"student_id": "G1-B", "student_name": "Bob", "grade_section": "Grade 1 - Blue",
             "created_at": datetime(2026, 10, 11, 8, 0, tzinfo=timezone.utc)},
            {"student_id": "G2-A", "student_name": "Chris", "grade_section": "2-Green"},
            {"student_id": "G3-A", "student_name": "=HYPERLINK(\"danger\")", "grade_section": "G3 - Sun"},
            {"student_id": "G4-A", "student_name": "Dana", "grade_section": "Unknown"},
            {"student_id": "G2-B", "student_name": "Elliot", "grade_section": "Grade 2"},
        ]
        self.scores = [
            {"score_id": 1, "student_id": "G1-A", "minigame": "Catch the Word",
             "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 120,
             "completed_at": datetime(2026, 10, 30, 13, 44, tzinfo=timezone(timedelta(hours=8)))},
            {"score_id": 2, "student_id": "G1-A", "minigame": "Human Plane",
             "game_style": "Noun", "game_mode": "Lives", "difficulty": "Hard", "score": 75,
             "completed_at": datetime(2026, 11, 1, 14, 1, tzinfo=timezone(timedelta(hours=8)))},
            {"score_id": 3, "student_id": "G2-A", "minigame": "Balloon Popping",
             "game_style": "Verb", "game_mode": "Seconds", "difficulty": "Normal", "score": 90,
             "completed_at": "2026-11-02T09:21:00+08:00"},
            {"score_id": 4, "student_id": "G3-A", "minigame": "=1+2",
             "game_style": "@cmd", "game_mode": "+start", "difficulty": "-bad", "score": 1,
             "completed_at": "2026-11-02T09:22:00+08:00"},
        ]

    def export_snapshot(self):
        self.calls.append("export_snapshot")
        return self.students, self.scores

    def import_snapshot(self, *_args):
        raise AssertionError("Unexpected import request")

    def delete_all(self):
        raise AssertionError("Unexpected delete request")


def read_workbook(data: str) -> tuple[ZipFile, list[str]]:
    raw = base64.b64decode(data, validate=True)
    f = ZipFile(io.BytesIO(raw))
    entries = f.namelist()
    for path in entries:
        if path.endswith(".xml") or path.endswith(".rels"):
            ET.fromstring(f.read(path))
    book = ET.fromstring(f.read("xl/workbook.xml"))
    names = [s.attrib["name"] for s in book.findall("m:sheets/m:sheet", X)]
    return f, names


def worksheet_values(raw: bytes):
    root = ET.fromstring(raw)
    table = []
    for row in root.findall("m:sheetData/m:row", X):
        cells = {}
        for cell in row.findall("m:c", X):
            address = cell.attrib["r"]
            value = cell.find("m:is/m:t", X)
            if value is None:
                value = cell.find("m:v", X)
            cells[address.rstrip("0123456789")] = value.text if value is not None else None
        table.append(cells)
    return table


class GradeXlsxTests(unittest.TestCase):
    def setUp(self):
        self.store = ReportingFakeStore()
        self.api = API(self.store, admin_token=ADMIN_KEY)

    def call(self, path, token=ADMIN_KEY, method="GET"):
        return self.api.dispatch(method, path, admin_token=token)

    def test_grade_sheet_grouping_all_offline_and_unscored_students_preserved(self):
        status, reply = self.call("/data/export_xlsx")
        self.assertEqual(status, 200)
        data = reply["data"]
        self.assertEqual((data["students"], data["scores"]), (6, 4))
        self.assertEqual(data["filename"], "KilosGrammar_Grades.xlsx")
        self.assertEqual(data["mime_type"], "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        zipped, names = read_workbook(data["xlsx_base64"])
        self.assertEqual(names, ["Grade 1", "Grade 2", "Grade 3", "Ungraded"])
        self.assertEqual(names, data["sheets"])
        grade_1 = worksheet_values(zipped.read("xl/worksheets/sheet1.xml"))
        self.assertEqual(len(grade_1), 4)  # heading + two scores for Alice + unscored Bob
        self.assertEqual(grade_1[1]["A"], "G1-B")  # Blue sorts before Rose
        self.assertNotIn("H", grade_1[1])  # student without scores retained
        self.assertNotIn("I", grade_1[1])  # do not invent a play date
        self.assertEqual(grade_1[2]["A"], "G1-A")
        self.assertEqual(grade_1[2]["H"], "120")
        self.assertEqual(grade_1[2]["I"], "2026-10-30T13:44:00+08:00")
        self.assertEqual(len(worksheet_values(zipped.read("xl/worksheets/sheet2.xml"))), 3)
        self.assertEqual(self.store.calls, ["export_snapshot"])

    def test_individual_student_and_grade_filters_are_exact(self):
        status, reply = self.call("/data/students?student_id=G1-A")
        self.assertEqual(status, 200)
        body = reply["data"]
        self.assertEqual((body["count"], body["score_count"]), (1, 2))
        student = body["students"][0]
        self.assertEqual(student["grade"], "Grade 1")
        self.assertEqual(student["last_played_at"], "2026-11-01T14:01:00+08:00")
        self.assertEqual(student["scores"][0]["completed_at"], "2026-10-30T13:44:00+08:00")

        status, reply = self.call("/data/students?grade=Grade%202&grade_section=2-Green")
        self.assertEqual(status, 200)
        self.assertEqual([s["student_id"] for s in reply["data"]["students"]], ["G2-A"])
        status, reply = self.call("/data/export/xlsx?student_id=G2-B")
        self.assertEqual(status, 200)
        self.assertEqual((reply["data"]["students"], reply["data"]["scores"]), (1, 0))
        self.assertEqual(read_workbook(reply["data"]["xlsx_base64"])[1], ["Grade 2"])

    def test_invalid_filters_do_not_trigger_snapshot_and_are_readonly(self):
        for path in (
            "/data/students?grade=Grade%2013", "/data/export_xlsx?grade=12;DROP",
            "/data/students?student_id=../../etc", "/data/students?grade=1&grade=2",
            "/data/export_xlsx?unexpected=1", "/data/export_xlsx?grade_section=",
        ):
            with self.subTest(path=path):
                status, reply = self.call(path)
                self.assertEqual((status, reply["error"]["code"]), (400, "invalid_input"))
        self.assertEqual(self.store.calls, [])

    def test_xlsx_and_student_roster_require_teacher_token_while_scoreboard_remains_readable(self):
        for path in ("/data/export_xlsx", "/data/export/xlsx", "/data/students", "/data/export"):
            with self.subTest(path=path):
                for token in (None, "wrong"):
                    status, reply = self.call(path, token=token)
                    self.assertEqual((status, reply["error"]["code"]), (403, "admin_authorization_required"))
        self.assertEqual(self.store.calls, [])

    def test_injection_values_stay_text_without_excel_formulas(self):
        status, reply = self.call("/data/export_xlsx")
        self.assertEqual(status, 200)
        zipped, names = read_workbook(reply["data"]["xlsx_base64"])
        self.assertEqual(names[2], "Grade 3")
        xml = zipped.read("xl/worksheets/sheet3.xml")
        root = ET.fromstring(xml)
        self.assertEqual(root.findall(".//m:f", X), [])
        for cell in root.findall(".//m:c", X):
            self.assertNotEqual(cell.attrib.get("t"), "f")
        values = worksheet_values(xml)
        self.assertEqual(values[1]["B"], "'=HYPERLINK(\"danger\")")
        self.assertEqual(values[1]["D"], "'=1+2")
        self.assertEqual(values[1]["E"], "'@cmd")
        self.assertEqual(values[1]["F"], "'+start")
        self.assertEqual(values[1]["G"], "'-bad")
        self.assertEqual(values[1]["H"], "1")

    def test_no_csv_columns_changed_and_legacy_csv_contract_preserved(self):
        self.assertEqual(tuple(LEGACY_CSV_COLUMNS),
                         ("student_id", "student_name", "grade_section", "game_style", "game_mode", "difficulty", "score"))
        self.assertEqual(len(CSV_COLUMNS), 8)
        self.assertEqual(self.call("/data/export")[0], 200)
        self.assertTrue(self.call("/data/export")[1]["data"]["csv"].startswith(",".join(CSV_COLUMNS)))

    def test_grade_detection_is_conservative_and_sheetnames_sanitized(self):
        for section, expected in (("Grade 1 - Rose", 1), ("G3 - Sun", 3), ("2-Green", 2),
                                  ("10-A", 10), ("Kindergarten", None), ("Grade 13", None),
                                  ("Section 3 - Blue", None), ("=cmd", None)):
            with self.subTest(section=section):
                self.assertEqual(grade_number(section), expected)
        students = [{"student_id": "=1+2", "student_name": "-Trick", "grade_section": "[bad]/Name*"}]
        raw, names = build_xlsx(students, [])
        self.assertEqual(names, ["Ungraded"])
        zipped = ZipFile(io.BytesIO(raw))
        values = worksheet_values(zipped.read("xl/worksheets/sheet1.xml"))
        self.assertEqual(values[1]["A"], "'=1+2")
        self.assertEqual(values[1]["B"], "'-Trick")


if __name__ == "__main__":
    unittest.main()
