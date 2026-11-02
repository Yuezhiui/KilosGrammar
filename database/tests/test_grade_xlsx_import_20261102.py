"""Isolated XLSX grade-tab import/export, safety and atomic admin-contract QA.

Uses a fake transaction store and in-memory OOXML. No live PostgreSQL or data
reset, no modified classroom database and no external services.
"""

from __future__ import annotations

import base64
import io
import json
import os
import unittest
import warnings
from http.server import ThreadingHTTPServer
from threading import Thread
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile

from database.server import API, CSV_COLUMNS, MAX_XLSX_JSON_BODY_BYTES, make_handler
from database.tests.test_csv_admin import BulkMemoryStore
from database.xlsx_export import MAX_XLSX_BYTES, REPORT_COLUMNS, build_xlsx
from database.xlsx_import import MAX_IMPORT_XLSX_BYTES, workbook_to_csv

TOKEN = "xlsx-unit-admin-token"
STUDENTS = [
    {"student_id": "G1-A", "student_name": "First", "grade_section": "Grade 1 - Ruby"},
    {"student_id": "G1-B", "student_name": "Second", "grade_section": "Grade 1 - Jade"},
    {"student_id": "G2-A", "student_name": "Third", "grade_section": "Grade 2 - Jade"},
    {"student_id": "G3-A", "student_name": "=Literal text", "grade_section": "Grade 3 - Blue"},
    {"student_id": "G4-A", "student_name": "Profile Only", "grade_section": "Grade 4 - Yellow"},
]
SCORES = [
    {"student_id": "G1-A", "minigame": "Catch the Word",
     "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 21},
    {"student_id": "G1-A", "minigame": "Human Plane",
     "game_style": "Verb", "game_mode": "Lives", "difficulty": "Normal", "score": 3},
    {"student_id": "G2-A", "minigame": "Balloon Popping",
     "game_style": "Adverb", "game_mode": "Seconds", "difficulty": "Hard", "score": 77},
]


def encode(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def rewrite(raw: bytes, changes: dict[str, bytes] | None = None,
            extra: dict[str, bytes] | None = None) -> bytes:
    """Repackage test ZIP without invoking Excel/openpyxl or writing to disk."""
    changes = changes or {}
    output = io.BytesIO()
    with ZipFile(io.BytesIO(raw)) as original, ZipFile(output, "w", ZIP_DEFLATED) as dest:
        for filename in original.namelist():
            dest.writestr(filename, changes.get(filename, original.read(filename)))
        for filename, data in (extra or {}).items():
            dest.writestr(filename, data)
    return output.getvalue()


class CountingStore(BulkMemoryStore):
    def __init__(self):
        super().__init__()
        self.import_calls = 0

    def import_snapshot(self, students, scores):
        self.import_calls += 1
        return super().import_snapshot(students, scores)


class XlsxImportContractTests(unittest.TestCase):
    def setUp(self):
        self.store = CountingStore()
        self.api = API(self.store, admin_token=TOKEN)
        self.raw, self.sheets = build_xlsx(STUDENTS, SCORES)
        self.body = {"xlsx_base64": encode(self.raw)}

    def request(self, body=None, token=TOKEN, target="/data/import_xlsx"):
        return self.api.dispatch("POST", target, self.body if body is None else body,
                                 admin_token=token)

    def test_all_grade_sheets_import_with_profile_only_and_latest_score_semantics(self):
        self.assertEqual(self.sheets, ["Grade 1", "Grade 2", "Grade 3", "Grade 4"])
        self.assertLessEqual(len(self.raw), MAX_XLSX_BYTES)
        self.assertEqual(MAX_IMPORT_XLSX_BYTES, MAX_XLSX_BYTES)
        status, reply = self.request()
        self.assertEqual(status, 200, reply)
        self.assertEqual((len(self.store.students), len(self.store.scores)), (5, 3))
        self.assertEqual(reply["data"]["students_created"], 5)
        self.assertEqual(reply["data"]["scores_imported"], 3)
        self.assertEqual(self.store.import_calls, 1)
        self.assertEqual(self.store.students["G3-A"]["student_name"], "=Literal text")
        self.assertEqual(self.store.students["G4-A"]["student_name"], "Profile Only")
        self.assertEqual(self.store.scores[("G1-A", "Human Plane", "Verb", "Lives", "Normal")]["score"], 3)
        status, repeat = self.request(target="/data/import/xlsx")
        self.assertEqual(status, 200, repeat)
        self.assertEqual((repeat["data"]["students_existing"], repeat["data"]["scores_unchanged"]), (5, 3))
        self.assertEqual(self.store.import_calls, 2)

    def test_csv_roundtrip_keeps_canonical_schema_and_score_dimensions(self):
        status, exported = self.api.dispatch("GET", "/data/export_xlsx", admin_token=TOKEN)
        self.assertEqual(status, 200)
        self.assertEqual(exported["data"]["sheets"], ["No Students"])
        # Fill via the same transactional XLSX route, then export a new
        # full grade workbook and import into another test-only memory store.
        self.assertEqual(self.request()[0], 200)
        status, exported = self.api.dispatch("GET", "/data/export_xlsx", admin_token=TOKEN)
        self.assertEqual(status, 200)
        self.assertEqual(exported["data"]["sheets"], self.sheets)
        canonical = workbook_to_csv(exported["data"]["xlsx_base64"])
        self.assertEqual(canonical.splitlines()[0], ",".join(CSV_COLUMNS))
        second_store = CountingStore()
        second = API(second_store, admin_token=TOKEN)
        status, reply = second.dispatch("POST", "/data/import_xlsx",
                                        {"xlsx_base64": exported["data"]["xlsx_base64"]}, admin_token=TOKEN)
        self.assertEqual(status, 200, reply)
        self.assertEqual((len(second_store.students), len(second_store.scores)), (5, 3))

    def test_authentication_and_payload_keys_required_before_any_db_call(self):
        for token in (None, "wrong", ""):
            with self.subTest(token=token):
                code, reply = self.request(token=token)
                self.assertEqual((code, reply["error"]["code"]), (403, "admin_authorization_required"))
        for target in ("/data/import_xlsx?unused=1", "/data/import/xlsx?unused=1"):
            self.assertEqual(self.request(target=target)[0], 400)
        for body in ({}, {"csv": "id"}, {"xlsx_base64": encode(self.raw), "unexpected": True}):
            self.assertEqual(self.request(body=body)[0], 400)
        self.assertEqual(self.store.import_calls, 0)

    def test_corrupted_base64_zip_and_encoded_size_are_rejected(self):
        inputs = [
            {"xlsx_base64": "not%base64"},
            {"xlsx_base64": encode(b"not-a-zip")},
            {"xlsx_base64": 123},
            {"xlsx_base64": ""},
        ]
        for body in inputs:
            with self.subTest(body=str(body)[:60]):
                code, reply = self.request(body=body)
                self.assertEqual((code, reply["error"]["code"]), (400, "invalid_xlsx"))
        huge = "A" * (4 * ((MAX_IMPORT_XLSX_BYTES + 2) // 3) + 16)
        self.assertEqual(self.request(body={"xlsx_base64": huge})[0], 413)
        self.assertEqual(self.store.import_calls, 0)

    def test_xml_entities_formula_and_external_relationships_never_import(self):
        with ZipFile(io.BytesIO(self.raw)) as parts:
            sheet = parts.read("xl/worksheets/sheet1.xml")
            rels = parts.read("xl/_rels/workbook.xml.rels")
            workbook = parts.read("xl/workbook.xml")
        preamble, worksheet = sheet.split(b"?>", 1)
        valid_doctype = (preamble + b'?>' +
                         b'<!DOCTYPE worksheet [<!ENTITY test "not permitted">]>' + worksheet)
        attacks = [
            rewrite(self.raw, {"xl/worksheets/sheet1.xml": valid_doctype}),
            rewrite(self.raw, {"xl/worksheets/sheet1.xml":
                              sheet.replace(b"</sheetData>", b'<row r="5"><c r="A5"><f>1+1</f><v>2</v></c></row></sheetData>')}),
            rewrite(self.raw, {"xl/_rels/workbook.xml.rels":
                              rels.replace(b'Target="styles.xml"', b'Target="https://invalid.test/bad" TargetMode="External"')}),
            rewrite(self.raw, {"xl/workbook.xml":
                              workbook.replace(b'<sheets>', b'<!DOCTYPE x [<!ENTITY xxe SYSTEM "file:///secrets">]><sheets>')}),
        ]
        for malicious in attacks:
            with self.subTest(archive=len(malicious)):
                code, reply = self.request(body={"xlsx_base64": encode(malicious)})
                self.assertEqual((code, reply["error"]["code"]), (400, "invalid_xlsx"))
        self.assertEqual(self.store.import_calls, 0)

    def test_zip_bomb_duplicate_paths_and_embedded_payloads_are_rejected(self):
        # Fully valid spreadsheet plus a highly compressible oversized part:
        # metadata preflight rejects without inflating a 13 MiB XML tree.
        bomb = rewrite(self.raw, extra={"xl/bomb.xml": b"X" * (13 * 1024 * 1024)})
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            dup = rewrite(self.raw, extra={"xl/workbook.xml": b"<malicious/>"})
        embedded = rewrite(self.raw, extra={"xl/vbaProject.bin": b"macro"})
        traversal = rewrite(self.raw, extra={"../outside.xml": b"<x/>"})
        for raw in (bomb, dup, embedded, traversal):
            status, reply = self.request(body={"xlsx_base64": encode(raw)})
            self.assertIn(status, (400, 413))
            self.assertIn(reply["error"]["code"], ("invalid_xlsx", "xlsx_too_large"))
        self.assertEqual(self.store.import_calls, 0)

    def test_grade_tab_mismatch_and_conflicting_students_are_atomic(self):
        with ZipFile(io.BytesIO(self.raw)) as zipped:
            sheet = zipped.read("xl/worksheets/sheet1.xml")
        bad_grade = rewrite(self.raw, {"xl/worksheets/sheet1.xml": sheet.replace(
            b"Grade 1 - Ruby", b"Grade 2 - Ruby")})
        code, reply = self.request(body={"xlsx_base64": encode(bad_grade)})
        self.assertEqual((code, reply["error"]["code"]), (400, "invalid_xlsx"))
        self.assertEqual(self.store.import_calls, 0)
        self.store.students = {"G1-A": {"student_id": "G1-A", "student_name": "Other",
                                        "grade_section": "Grade 1 - Ruby"}}
        before = dict(self.store.students)
        code, reply = self.request()
        # Store-level existing identity conflicts keep the established API
        # student_exists error rather than being converted into a silent reset.
        self.assertEqual((code, reply["error"]["code"]), (409, "student_exists"))
        self.assertEqual(self.store.students, before)
        self.assertEqual(self.store.scores, {})

    def test_legacy_seven_column_workbook_preserves_legacy_minigame(self):
        # Construct legitimate alternate heading/columns by replacing the
        # normal report's first worksheet using the existing OOXML writer.
        from database.xlsx_export import _sheet_xml
        row = ("LEG-1", "Legacy Learner", "Grade 1 - Rose", "Noun", "Seconds", "Easy", 7)
        xml = _sheet_xml([("student_id", "student_name", "grade_section",
                           "game_style", "game_mode", "difficulty", "score"), row])
        raw = rewrite(self.raw, {"xl/worksheets/sheet1.xml": xml})
        # Also remove the other sheets' rows; duplicate exported records would
        # otherwise be imported and mask this alternate contract.
        with ZipFile(io.BytesIO(raw)) as zipped:
            replacements = {}
            for i in (2, 3, 4):
                replacement = _sheet_xml([REPORT_COLUMNS])
                replacements[f"xl/worksheets/sheet{i}.xml"] = replacement
        raw = rewrite(raw, replacements)
        code, reply = self.request(body={"xlsx_base64": encode(raw)})
        self.assertEqual(code, 200, reply)
        self.assertEqual(len(self.store.students), 1)
        self.assertEqual(self.store.scores[("LEG-1", "Legacy", "Noun", "Seconds", "Easy")]["score"], 7)

    def test_shared_strings_are_supported_and_formula_text_is_not_executed(self):
        with ZipFile(io.BytesIO(self.raw)) as zipped:
            sheet = zipped.read("xl/worksheets/sheet1.xml")
        # Replace one inline text item with shared-string reference. Real Excel
        # produces this encoding; a missing string table must be rejected.
        inline = b'<c r="A2" t="inlineStr"><is><t xml:space="preserve">G1-A</t></is></c>'
        self.assertIn(inline, sheet)
        changed = sheet.replace(inline, b'<c r="A2" t="s"><v>0</v></c>')
        shared = (b'<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/'
                  b'spreadsheetml/2006/main"><si><t>G1-A</t></si></sst>')
        raw = rewrite(self.raw, {"xl/worksheets/sheet1.xml": changed},
                      extra={"xl/sharedStrings.xml": shared})
        self.assertEqual(self.request(body={"xlsx_base64": encode(raw)})[0], 200)
        self.assertEqual(self.store.students["G1-A"]["student_id"], "G1-A")

    def test_one_score_change_updates_only_that_record_without_reset(self):
        self.assertEqual(self.request()[0], 200)
        self.store.students["OTHER"] = {"student_id": "OTHER", "student_name": "Still Here",
                                         "grade_section": "Grade 4 - Blue"}
        with ZipFile(io.BytesIO(self.raw)) as zipped:
            sheet = zipped.read("xl/worksheets/sheet1.xml")
        changed = sheet.replace(b'<c r="H3"><v>21</v></c>', b'<c r="H3"><v>19</v></c>')
        # Score column order is deterministic only within a sheet; find and
        # replace the unique matching original numeric value instead.
        if changed == sheet:
            changed = sheet.replace(b'<v>21</v>', b'<v>19</v>', 1)
        self.assertNotEqual(changed, sheet)
        modified = rewrite(self.raw, {"xl/worksheets/sheet1.xml": changed})
        status, reply = self.request(body={"xlsx_base64": encode(modified)})
        self.assertEqual(status, 200, reply)
        self.assertEqual(reply["data"]["scores_updated"], 1)
        self.assertIn("OTHER", self.store.students)
        self.assertEqual(len(self.store.scores), 3)


class XlsxHttpBoundaryTests(unittest.TestCase):
    def test_http_accepts_over_one_megabyte_json_only_for_admin_xlsx_route(self):
        store = CountingStore()
        api = API(store, admin_token=TOKEN)
        http = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(api))
        thread = Thread(target=http.serve_forever, daemon=True)
        thread.start()
        try:
            # Invalid >1 MiB payload is intentional: 400 invalid_xlsx proves
            # the large JSON reached the parser instead of the old HTTP cap.
            raw = os.urandom(900_000)
            payload = json.dumps({"xlsx_base64": encode(raw)}).encode()
            self.assertGreater(len(payload), 1_000_000)
            self.assertGreater(MAX_XLSX_JSON_BODY_BYTES, len(payload))
            request = Request(
                f"http://127.0.0.1:{http.server_port}/data/import_xlsx",
                data=payload, method="POST",
                headers={"Content-Type": "application/json", "X-Kilos-Admin-Token": TOKEN},
            )
            with self.assertRaises(HTTPError) as response:
                urlopen(request, timeout=6)
            self.assertEqual(response.exception.code, 400)
            decoded = json.loads(response.exception.read())
            self.assertEqual(decoded["error"]["code"], "invalid_xlsx")
            self.assertEqual(store.import_calls, 0)
        finally:
            http.shutdown()
            http.server_close()
            thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
