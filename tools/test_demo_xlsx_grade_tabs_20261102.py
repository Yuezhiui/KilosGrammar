"""Generate and validate eight fictional demo students; never touch live DB.

Run from repo root: python tools/test_demo_xlsx_grade_tabs_20261102.py
Output is isolated under docs/examples; no network, PostgreSQL or app mutations.
"""
from __future__ import annotations

import csv
import io
import base64
from pathlib import Path
from zipfile import ZipFile
import xml.etree.ElementTree as ET

from database.xlsx_export import REPORT_COLUMNS, build_xlsx
from database.server import CSV_COLUMNS, _csv_import
from database.xlsx_import import workbook_to_csv

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "examples"
XLSX = OUTPUT / "KilosGrammar_DEMO_8_Students_Grades_1_to_4_20261102.xlsx"

NAMES = (
    ("G1-A", "Demo Alice Maple", "Grade 1 - Sunflower", "Catch the Word", "Noun", "Seconds", "Easy", 12),
    ("G1-B", "Demo Ben Cedar", "Grade 1 - Sunflower", "Balloon Popping", "Verb", "Lives", "Normal", 17),
    ("G2-A", "Demo Cara Birch", "Grade 2 - Orchid", "Human Plane", "Adjective", "Seconds", "Easy", 22),
    ("G2-B", "Demo Dino Aspen", "Grade 2 - Orchid", "Catch the Word", "Pronoun", "Lives", "Hard", 27),
    ("G3-A", "Demo Ella Willow", "Grade 3 - Jasmine", "Balloon Popping", "Adverb", "Seconds", "Normal", 31),
    ("G3-B", "Demo Finn Elm", "Grade 3 - Jasmine", "Human Plane", "Verb", "Lives", "Easy", 36),
    ("G4-A", "Demo Gia Olive", "Grade 4 - Sampaguita", "Catch the Word", "Noun", "Seconds", "Hard", 43),
    ("G4-B", "Demo Hugo Pine", "Grade 4 - Sampaguita", "Balloon Popping", "Pronoun", "Lives", "Normal", 48),
)


def dataset():
    students, scores = [], []
    for suffix, name, grade, minigame, topic, mode, difficulty, score in NAMES:
        grade, letter = suffix.split("-")
        student_id = f"DEMO-{grade}-{'01' if letter == 'A' else '02'}"
        students.append({"student_id": student_id, "student_name": name,
                         "grade_section": grade, "created_at": None})
        scores.append({"student_id": student_id, "minigame": minigame,
                       "game_style": topic, "game_mode": mode,
                       "difficulty": difficulty, "score": score, "completed_at": None})
    return students, scores


def validate_xlsx(raw: bytes, sheets: list[str]):
    namespace = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    assert sheets == ["Grade 1", "Grade 2", "Grade 3", "Grade 4"], sheets
    with ZipFile(io.BytesIO(raw)) as archive:
        assert archive.testzip() is None
        for grade in range(1, 5):
            xml = ET.fromstring(archive.read(f"xl/worksheets/sheet{grade}.xml"))
            rows = xml.findall("s:sheetData/s:row", namespace)
            assert len(rows) == 3, (grade, len(rows))  # header + exactly two students
            assert len(rows[0].findall("s:c", namespace)) == len(REPORT_COLUMNS)


def main() -> None:
    students, scores = dataset()
    assert len(students) == len({s["student_id"] for s in students}) == 8
    workbook, sheet_names = build_xlsx(students, scores)
    validate_xlsx(workbook, sheet_names)
    text_file = io.StringIO(newline="")
    writer = csv.writer(text_file, lineterminator="\r\n")
    writer.writerow(CSV_COLUMNS)
    for student, score in zip(students, scores):
        writer.writerow([student["student_id"], student["student_name"],
                         student["grade_section"], score["minigame"],
                         score["game_style"], score["game_mode"],
                         score["difficulty"], score["score"]])
    csv_text = text_file.getvalue()
    imported_students, imported_scores = _csv_import(csv_text)
    assert len(imported_students) == len(imported_scores) == 8
    roundtrip_csv = workbook_to_csv(base64.b64encode(workbook).decode("ascii"))
    xlsx_students, xlsx_scores = _csv_import(roundtrip_csv)
    assert {s["student_id"] for s in xlsx_students} == {s["student_id"] for s in students}
    assert len(xlsx_scores) == 8
    assert sorted(s["score"] for s in xlsx_scores) == sorted(s["score"] for s in scores)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    if XLSX.exists():
        existing = XLSX.read_bytes()
        validate_xlsx(existing, sheet_names)
        with ZipFile(io.BytesIO(existing)) as prior, ZipFile(io.BytesIO(workbook)) as generated:
            assert set(prior.namelist()) == set(generated.namelist())
            assert all(prior.read(name) == generated.read(name) for name in prior.namelist()), \
                "Existing XLSX contents differ from canonical fixture"
    else:
        XLSX.write_bytes(workbook)
    print(f"PASS: {len(students)} fictional student profiles, {len(scores)} score rows; tabs {sheet_names}")
    print(f"Verified {XLSX} ({len(workbook)} bytes)")



if __name__ == "__main__":
    main()
