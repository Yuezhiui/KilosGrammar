"""Offline, dependency-free XLSX reports of the *current saved* student scores.

This is not a game-round audit log: each unique student/minigame/topic/mode/
difficulty has ONE PostgreSQL row, whose completed_at tracks its latest save.
No PostgreSQL writes or external network access occur in this module.
"""

from __future__ import annotations

import base64
from collections import defaultdict
from datetime import date, datetime, timezone
import io
import re
from typing import Any
from xml.sax.saxutils import escape
from zipfile import ZIP_DEFLATED, ZipFile


MIME_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
MAX_XLSX_BYTES = 12 * 1024 * 1024
REPORT_COLUMNS = (
    "Student ID", "Student Name", "Grade & Section", "Minigame", "Grammar Topic",
    "Game Mode", "Difficulty", "Current Score", "Completed At (Last Record)",
    "Student Registered At",
)
XML_INVALID = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\ufffe\uffff]")
SHEET_INVALID = re.compile(r"[\[\]:*?/\\]")
GRADE_RE = re.compile(r"(?i)(?:\bgrade\s*[-:]?\s*|\bg\s*[-:]?\s*)(\d{1,2})\b")
LEADING_GRADE_RE = re.compile(r"^\s*(\d{1,2})(?=\s*(?:[-_/\s]|$))")


def grade_number(value: Any) -> int | None:
    """Map school grade/section labels to a grade without guessing a section."""
    label = str(value or "").strip()
    match = GRADE_RE.search(label) or LEADING_GRADE_RE.match(label)
    if not match:
        return None
    number = int(match.group(1))
    return number if 1 <= number <= 12 else None


def grade_filter_number(value: str) -> int | None:
    """Return a grade number from exactly `1`, `G1`, or `Grade 1`."""
    value = " ".join(value.strip().split())
    if re.fullmatch(r"\d{1,2}", value):
        parsed = int(value)
        return parsed if 1 <= parsed <= 12 else None
    match = re.fullmatch(r"(?i)(?:grade|g)\s*[-:]?\s*(\d{1,2})", value)
    if match:
        parsed = int(match.group(1))
        return parsed if 1 <= parsed <= 12 else None
    return None


def iso_datetime(value: Any) -> str:
    """Normalize database timestamps to ISO 8601 without fabricating dates."""
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return str(value or "").strip()


def _instant(value: Any) -> datetime | None:
    if value is None or value == "":
        return None
    try:
        dt = value if isinstance(value, datetime) else datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if not isinstance(dt, datetime):
            return None
        return (dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt.astimezone(timezone.utc))
    except (TypeError, ValueError, OverflowError):
        return None


def _grade_sort_key(label: str) -> tuple[int, str]:
    number = grade_number(label)
    return (number if number is not None else 99, label.casefold())


def selected_students(
    students: list[dict[str, Any]], scores: list[dict[str, Any]],
    *, grade: str | None = None, grade_section: str | None = None,
    student_id: str | None = None,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Filter complete bounded snapshots; preserve profile-only students."""
    wanted_grade = grade_filter_number(grade) if grade else None
    if grade is not None and wanted_grade is None:
        raise ValueError("Invalid grade filter")
    normalized_section = " ".join(grade_section.split()).casefold() if grade_section else None
    filtered = []
    for student in students:
        if student_id is not None and student["student_id"] != student_id:
            continue
        if normalized_section is not None and " ".join(str(student["grade_section"]).split()).casefold() != normalized_section:
            continue
        if wanted_grade is not None and grade_number(student["grade_section"]) != wanted_grade:
            continue
        filtered.append(dict(student))
    filtered.sort(key=lambda s: (_grade_sort_key(str(s["grade_section"])),
                                  str(s["student_name"]).casefold(), str(s["student_id"])))
    ids = {s["student_id"] for s in filtered}
    filtered_scores = [dict(s) for s in scores if s["student_id"] in ids]
    filtered_scores.sort(key=lambda s: (str(s["student_id"]), str(s.get("minigame", "Legacy")),
                                        str(s["game_style"]), str(s["game_mode"]), str(s["difficulty"])))
    return filtered, filtered_scores


def student_details(students: list[dict[str, Any]], scores: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Serialize a teacher's individual student pull-out without score history claims."""
    by_id: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in scores:
        by_id[row["student_id"]].append({
            "score_id": row.get("score_id"),
            "student_id": row["student_id"],
            "minigame": row.get("minigame", "Legacy"),
            "game_style": row["game_style"], "game_mode": row["game_mode"],
            "difficulty": row["difficulty"], "score": row["score"],
            "completed_at": iso_datetime(row.get("completed_at")) or None,
            "updated_at": iso_datetime(row.get("updated_at")) or None,
        })
    result = []
    for student in students:
        records = by_id.get(student["student_id"], [])
        # Compare instants in UTC, but present the *original* saved timestamp
        # (including its original time-zone offset) rather than inventing a
        # new local clock reading for the teacher.
        played = [(when, s["completed_at"]) for s in records
                  if (when := _instant(s["completed_at"])) is not None]
        last_played = iso_datetime(max(played, key=lambda item: item[0])[1]) if played else None
        result.append({
            "student_id": student["student_id"], "student_name": student["student_name"],
            "grade_section": student["grade_section"],
            "grade": f"Grade {grade_number(student['grade_section'])}" if grade_number(student["grade_section"]) else None,
            "created_at": iso_datetime(student.get("created_at")) or None,
            "updated_at": iso_datetime(student.get("updated_at")) or None,
            "last_played_at": last_played, "scores": records,
        })
    return result


def _safe_xml(value: Any) -> str:
    content = XML_INVALID.sub("\ufffd", str(value))
    return escape(content, {'"': '&quot;', "'": '&apos;'})


def _safe_excel_text(value: Any) -> str:
    """Never let an Excel/Calc cell evaluate untrusted identity text."""
    text = str(value or "")
    if text.lstrip().startswith(("=", "+", "-", "@")):
        return "'" + text
    return text


def _sheet_name(label: str, taken: set[str]) -> str:
    clean = SHEET_INVALID.sub("_", XML_INVALID.sub("", label)).strip("' ")[:31] or "Ungraded"
    base = clean
    suffix = 2
    while clean.casefold() in taken:
        end = f" ({suffix})"
        clean = base[:31 - len(end)] + end
        suffix += 1
    taken.add(clean.casefold())
    return clean


def _column(index: int) -> str:
    output = ""
    while index:
        index, remainder = divmod(index - 1, 26)
        output = chr(ord('A') + remainder) + output
    return output


def _sheet_xml(rows: list[tuple[Any, ...]]) -> bytes:
    out = [
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" '
        'activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>',
        '<cols>',
    ]
    for i, width in enumerate((19, 30, 25, 22, 22, 16, 17, 16, 29, 29), 1):
        out.append(f'<col min="{i}" max="{i}" width="{width}" customWidth="1"/>')
    out.append('</cols><sheetData>')
    for row_index, values in enumerate(rows, 1):
        out.append(f'<row r="{row_index}"' + (' ht="26" customHeight="1"' if row_index == 1 else '') + '>')
        for column_index, value in enumerate(values, 1):
            address = f'{_column(column_index)}{row_index}'
            style = ' s="1"' if row_index == 1 else ''
            if value is None or value == "":
                continue
            # Only trusted score integers are numeric. All user strings use
            # inlineStr (never formula <f> or calculated shared strings).
            if row_index > 1 and column_index == 8 and type(value) is int:
                out.append(f'<c r="{address}"><v>{value}</v></c>')
            else:
                out.append(f'<c r="{address}"{style} t="inlineStr"><is><t xml:space="preserve">'
                           f'{_safe_xml(_safe_excel_text(value))}</t></is></c>')
        out.append('</row>')
    out.append('</sheetData>')
    out.append(f'<autoFilter ref="A1:J{max(len(rows), 1)}"/>')
    out.append('</worksheet>')
    return "".join(out).encode("utf-8")


def build_xlsx(students: list[dict[str, Any]], scores: list[dict[str, Any]]) -> tuple[bytes, list[str]]:
    """Produce a valid Office Open XML workbook using Python's standard library."""
    score_by_id: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for score in scores:
        score_by_id[score["student_id"]].append(score)
    groups: dict[str, list[tuple[Any, ...]]] = defaultdict(list)
    for student in students:
        number = grade_number(student["grade_section"])
        grade_name = f"Grade {number}" if number else "Ungraded"
        student_scores = score_by_id.get(student["student_id"], [])
        for score in student_scores or [None]:
            groups[grade_name].append((
                student["student_id"], student["student_name"], student["grade_section"],
                score.get("minigame", "Legacy") if score else None,
                score["game_style"] if score else None,
                score["game_mode"] if score else None,
                score["difficulty"] if score else None,
                score["score"] if score else None,
                iso_datetime(score.get("completed_at")) if score else None,
                iso_datetime(student.get("created_at")) or None,
            ))
    if not groups:
        groups["No Students"] = []
    names = sorted(groups, key=lambda n: (grade_number(n) or 99, n))
    used: set[str] = set()
    sheets = [(_sheet_name(name, used), [REPORT_COLUMNS, *groups[name]]) for name in names]
    worksheet_defs = []
    relationships = []
    overrides = [
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
    ]
    for i, (name, _rows) in enumerate(sheets, 1):
        worksheet_defs.append(f'<sheet name="{_safe_xml(name)}" sheetId="{i}" r:id="rId{i}"/>')
        relationships.append(f'<Relationship Id="rId{i}" '
                             'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
                             f'Target="worksheets/sheet{i}.xml"/>')
        overrides.append(f'<Override PartName="/xl/worksheets/sheet{i}.xml" '
                         'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>')
    workbook = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                '<sheets>' + ''.join(worksheet_defs) + '</sheets></workbook>')
    workbook_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                     '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                     + ''.join(relationships) +
                     '<Relationship Id="rIdStyles" '
                     'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
                     'Target="styles.xml"/></Relationships>')
    styles = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<fonts count="2"><font><sz val="11"/><name val="Aptos"/></font>'
              '<font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Aptos"/></font></fonts>'
              '<fills count="3"><fill><patternFill patternType="none"/></fill>'
              '<fill><patternFill patternType="gray125"/></fill>'
              '<fill><patternFill patternType="solid"><fgColor rgb="FF245B69"/>'
              '<bgColor indexed="64"/></patternFill></fill></fills>'
              '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
              '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
              '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
              '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" '
              'applyFont="1" applyFill="1"/></cellXfs></styleSheet>')
    base_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                 '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                 '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
                 'Target="xl/workbook.xml"/></Relationships>')
    types = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
             '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
             '<Default Extension="xml" ContentType="application/xml"/>'
             + ''.join(overrides) + '</Types>')
    result = io.BytesIO()
    with ZipFile(result, mode="w", compression=ZIP_DEFLATED, compresslevel=6) as workbook_zip:
        workbook_zip.writestr('[Content_Types].xml', types)
        workbook_zip.writestr('_rels/.rels', base_rels)
        workbook_zip.writestr('xl/workbook.xml', workbook)
        workbook_zip.writestr('xl/_rels/workbook.xml.rels', workbook_rels)
        workbook_zip.writestr('xl/styles.xml', styles)
        for i, (_name, rows) in enumerate(sheets, 1):
            workbook_zip.writestr(f'xl/worksheets/sheet{i}.xml', _sheet_xml(rows))
    workbook_bytes = result.getvalue()
    if len(workbook_bytes) > MAX_XLSX_BYTES:
        raise ValueError('XLSX report is too large')
    return workbook_bytes, [sheet[0] for sheet in sheets]


def encoded_workbook(students: list[dict[str, Any]], scores: list[dict[str, Any]]) -> dict[str, Any]:
    raw, names = build_xlsx(students, scores)
    return {
        "filename": "KilosGrammar_Grades.xlsx", "mime_type": MIME_TYPE,
        "xlsx_base64": base64.b64encode(raw).decode('ascii'),
        "students": len(students), "scores": len(scores), "sheets": names,
        "timestamp_semantics": (
            "completed_at is the latest saved record per student/minigame/topic/mode/difficulty, "
            "not a full play history; a changed CSV import may reset it to import time"
        ),
    }
