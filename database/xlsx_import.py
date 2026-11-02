"""Bounded, offline OOXML XLSX -> canonical CSV converter.

Import never executes workbook content, opens external relationships or writes to
PostgreSQL.  The HTTP API passes the resulting CSV to the existing _csv_import
validator and calls the transactional store.import_snapshot exactly once.
"""

from __future__ import annotations

import base64
import binascii
import csv
import io
import posixpath
import re
import stat
from xml.etree import ElementTree as ET
from zipfile import BadZipFile, ZipFile, ZIP_DEFLATED, ZIP_STORED

from .xlsx_export import REPORT_COLUMNS, grade_number


MAX_IMPORT_XLSX_BYTES = 8_000_000
MAX_PART_BYTES = 12 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 32 * 1024 * 1024
MAX_MEMBERS = 128
MAX_ROWS = 5000
MAX_CELL_CHARS = 4096
MAX_CSV_BYTES = 1_048_576
CSV_COLUMNS = (
    "student_id", "student_name", "grade_section", "minigame",
    "game_style", "game_mode", "difficulty", "score",
)
LEGACY_COLUMNS = (
    "student_id", "student_name", "grade_section",
    "game_style", "game_mode", "difficulty", "score",
)
MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
PACKAGE_REL = "{http://schemas.openxmlformats.org/package/2006/relationships}"
CELL_ADDRESS = re.compile(r"([A-Z]{1,2})([1-9][0-9]*)\Z")
GRADE_SHEET = re.compile(r"Grade (?:[1-9]|1[0-2])\Z")
DTD = re.compile(rb"<!\s*(?:DOCTYPE|ENTITY)\b", re.IGNORECASE)


class InvalidXlsx(ValueError):
    """Invalid, unsupported or unsafe Excel workbook."""


class XlsxTooLarge(InvalidXlsx):
    """XLSX ZIP, inflated XML, rows or canonical data exceed bounded limits."""


def _xml(raw: bytes) -> ET.Element:
    # Reject DTD/internal entities before xml.etree sees them; disallow UTF-16
    # so the forbidden declaration cannot be hidden between NUL bytes.
    if b"\x00" in raw or DTD.search(raw):
        raise InvalidXlsx("XML document types and entities are not supported")
    try:
        return ET.fromstring(raw)
    except ET.ParseError:
        raise InvalidXlsx("Malformed workbook XML") from None


def _parts(zipped: ZipFile) -> dict[str, bytes]:
    items = zipped.infolist()
    if not items or len(items) > MAX_MEMBERS:
        raise XlsxTooLarge("Workbook has too many ZIP entries")
    contents: dict[str, bytes] = {}
    seen: set[str] = set()
    total = 0
    for info in items:
        name = info.filename
        if (not name or "\\" in name or name.startswith("/") or "//" in name
                or name.split("/")[0] in ("", ".", "..")
                or any(segment in ("", ".", "..") for segment in name.strip("/").split("/"))
                or ":" in name or info.flag_bits & 1
                or stat.S_IFMT(info.external_attr >> 16) == stat.S_IFLNK):
            raise InvalidXlsx("Unsafe or encrypted ZIP entry")
        if info.is_dir():
            continue
        if info.compress_type not in (ZIP_DEFLATED, ZIP_STORED):
            raise InvalidXlsx("Unsupported ZIP compression")
        if name.casefold() in seen:
            raise InvalidXlsx("Duplicate ZIP member")
        seen.add(name.casefold())
        if "/externalLinks/" in name or name.startswith("xl/externalLinks/"):
            raise InvalidXlsx("External workbook links are prohibited")
        if not (name.endswith(".xml") or name.endswith(".rels")):
            raise InvalidXlsx("Unsupported embedded or executable OOXML part")
        if info.file_size > MAX_PART_BYTES or total + info.file_size > MAX_UNCOMPRESSED_BYTES:
            raise XlsxTooLarge("Workbook XML exceeds the bounded size limit")
        if info.file_size > 0 and info.file_size > max(info.compress_size, 1) * 400:
            raise XlsxTooLarge("Suspicious ZIP compression ratio")
        total += info.file_size
        # A crafted ZIP can advertise false sizes; independently enforce an
        # actual per-member output limit before retaining bytes.
        with zipped.open(info) as stream:
            raw = stream.read(MAX_PART_BYTES + 1)
            if len(raw) > MAX_PART_BYTES or len(raw) != info.file_size:
                raise XlsxTooLarge("Workbook contains oversized XML")
        _xml(raw)  # Every XML part is checked, including parts we don't use.
        contents[name] = raw
    for required in ("[Content_Types].xml", "xl/workbook.xml", "xl/_rels/workbook.xml.rels"):
        if required not in contents:
            raise InvalidXlsx("Required Office workbook part is missing")
    # Reject external relationship targets even when they appear in unused
    # worksheet metadata (e.g. malicious external links).
    for name, raw in contents.items():
        if name.endswith(".rels"):
            root = _xml(raw)
            if root.tag != PACKAGE_REL + "Relationships":
                raise InvalidXlsx("Unexpected Office relationship document")
            for relationship in root:
                if relationship.get("TargetMode", "").lower() == "external":
                    raise InvalidXlsx("External workbook relationships are prohibited")
    return contents


def _shared_strings(contents: dict[str, bytes]) -> list[str]:
    raw = contents.get("xl/sharedStrings.xml")
    if raw is None:
        return []
    root = _xml(raw)
    if root.tag != MAIN + "sst":
        raise InvalidXlsx("Invalid shared string table")
    result = []
    for item in root.findall(MAIN + "si"):
        if len(result) > MAX_ROWS * len(REPORT_COLUMNS):
            raise XlsxTooLarge("Shared string table is too large")
        result.append(_rich_text(item))
    return result


def _rich_text(item: ET.Element) -> str:
    # Only regular <t> and rich text <r><t> contribute; do not import
    # pronunciation annotations as ordinary cell content.
    fragments = []
    for child in item:
        if child.tag == MAIN + "t":
            fragments.append(child.text or "")
        elif child.tag == MAIN + "r":
            fragments.extend(t.text or "" for t in child.findall(MAIN + "t"))
    value = "".join(fragments)
    if len(value) > MAX_CELL_CHARS:
        raise XlsxTooLarge("Excel cell exceeds the text limit")
    return value


def _column_index(address: str, row_number: int) -> int:
    match = CELL_ADDRESS.fullmatch(address)
    if not match or int(match.group(2)) != row_number:
        raise InvalidXlsx("Invalid or misplaced Excel cell reference")
    number = 0
    for char in match.group(1):
        number = number * 26 + ord(char) - ord("A") + 1
    if not 1 <= number <= len(REPORT_COLUMNS):
        raise InvalidXlsx("Workbook contains unexpected columns")
    return number - 1


def _cell(cell: ET.Element, strings: list[str], column: int, width: int) -> str:
    if cell.find(MAIN + "f") is not None:
        raise InvalidXlsx("Excel formulas cannot be imported")
    kind = cell.get("t", "n")
    node = cell.find(MAIN + "v")
    raw = node.text or "" if node is not None else ""
    if kind == "inlineStr":
        inline = cell.find(MAIN + "is")
        text = _rich_text(inline) if inline is not None else ""
    elif kind == "s":
        if not re.fullmatch(r"[0-9]{1,7}", raw) or int(raw) >= len(strings):
            raise InvalidXlsx("Invalid shared string index")
        text = strings[int(raw)]
    elif kind == "str":
        text = raw
    elif kind == "n":
        text = raw
        # Only score and ignored metadata/date columns may be represented as
        # numeric cells. Text identifiers converted to numbers lose leading 0s.
        score_column = 7 if width in (8, 10) else 6
        if text and column not in (score_column,) + ((8, 9) if width == 10 else ()):
            raise InvalidXlsx("Identity and grammar fields must be Excel text")
        if text and column == score_column:
            if not re.fullmatch(r"[0-9]+(?:\.0+)?", text):
                raise InvalidXlsx("Score must be a nonnegative integer")
            text = text.split(".", 1)[0]
    else:
        raise InvalidXlsx("Excel error, boolean or unsupported cell type")
    if len(text) > MAX_CELL_CHARS or any(ord(char) == 0 for char in text):
        raise XlsxTooLarge("Excel cell contains excessive or invalid text")
    return text


def _parse_rows(raw: bytes, strings: list[str]) -> tuple[int, list[list[str]]]:
    root = _xml(raw)
    if root.tag != MAIN + "worksheet":
        raise InvalidXlsx("Invalid worksheet XML")
    data = root.find(MAIN + "sheetData")
    if data is None:
        raise InvalidXlsx("Worksheet has no table")
    width = 0
    result: list[list[str]] = []
    seen_rows: set[int] = set()
    for record in data.findall(MAIN + "row"):
        address = record.get("r", "")
        if not address.isdecimal():
            raise InvalidXlsx("Worksheet has invalid row indexes")
        number = int(address)
        if not 1 <= number <= MAX_ROWS + 1 or number in seen_rows:
            raise XlsxTooLarge("Worksheet row limit exceeded or duplicated")
        seen_rows.add(number)
        cells: dict[int, ET.Element] = {}
        for cell in record.findall(MAIN + "c"):
            index = _column_index(cell.get("r", ""), number)
            if index in cells:
                raise InvalidXlsx("Duplicate Excel cell")
            cells[index] = cell
        if number == 1:
            # Header cells must be actual text, not numeric values/formulas.
            header = []
            for index in range(len(REPORT_COLUMNS)):
                if index in cells:
                    if cells[index].get("t", "n") == "n":
                        raise InvalidXlsx("Workbook heading must be text")
                    header.append(_cell(cells[index], strings, index, 10))
            headings = tuple(header)
            if headings == REPORT_COLUMNS:
                width = 10
            elif headings == CSV_COLUMNS:
                width = 8
            elif headings == LEGACY_COLUMNS:
                width = 7
            else:
                raise InvalidXlsx("Workbook headers do not match a supported schema")
            continue
        if not width:
            raise InvalidXlsx("Workbook heading must be on the first row")
        if any(index >= width for index in cells):
            raise InvalidXlsx("Unexpected data outside worksheet columns")
        values = [_cell(cells[index], strings, index, width) if index in cells else ""
                  for index in range(width)]
        if any(values):
            result.append(values)
        if len(result) > MAX_ROWS:
            raise XlsxTooLarge("Workbook row limit exceeded")
    if not width:
        raise InvalidXlsx("Missing workbook column headers")
    return width, result


def workbook_to_csv(source: str) -> str:
    """Convert supported grade-tab XLSX (base64) to the original canonical CSV."""
    if not isinstance(source, str) or not source:
        raise InvalidXlsx("xlsx_base64 must be an encoded workbook")
    if len(source) > 4 * ((MAX_IMPORT_XLSX_BYTES + 2) // 3):
        raise XlsxTooLarge("XLSX request exceeds the encoded size limit")
    try:
        raw = base64.b64decode(source, validate=True)
    except (ValueError, binascii.Error):
        raise InvalidXlsx("Invalid base64 XLSX payload") from None
    if len(raw) > MAX_IMPORT_XLSX_BYTES:
        raise XlsxTooLarge("XLSX exceeds the allowed size")
    try:
        with ZipFile(io.BytesIO(raw)) as zipped:
            contents = _parts(zipped)
    except (BadZipFile, OSError, EOFError, RuntimeError):
        raise InvalidXlsx("Invalid or corrupt XLSX ZIP archive") from None

    workbook = _xml(contents["xl/workbook.xml"])
    if workbook.tag != MAIN + "workbook":
        raise InvalidXlsx("Invalid XLSX workbook")
    links = _xml(contents["xl/_rels/workbook.xml.rels"])
    targets: dict[str, str] = {}
    seen_target_paths: set[str] = set()
    for relationship in links:
        if not relationship.get("Type", "").endswith("/worksheet"):
            continue
        target = relationship.get("Target", "")
        path = (target.lstrip("/") if target.startswith("/")
                else posixpath.normpath(posixpath.join("xl", target)))
        if not path.startswith("xl/worksheets/") or path not in contents:
            raise InvalidXlsx("Worksheet reference leaves the workbook")
        relationship_id = relationship.get("Id", "")
        if not relationship_id or relationship_id in targets or path in seen_target_paths:
            raise InvalidXlsx("Duplicate worksheet relationship")
        seen_target_paths.add(path)
        targets[relationship_id] = path
    sheet_set = workbook.find(MAIN + "sheets")
    if sheet_set is None or not (1 <= len(sheet_set) <= 14):
        raise InvalidXlsx("XLSX must contain grade worksheets")
    strings = _shared_strings(contents)
    names: set[str] = set()
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\r\n")
    writer.writerow(CSV_COLUMNS)
    count = 0
    for sheet in sheet_set:
        name = sheet.get("name", "")
        sheet_id = sheet.get(REL + "id", "")
        if (not (GRADE_SHEET.fullmatch(name) or name in ("Ungraded", "No Students"))
                or name.casefold() in names or sheet_id not in targets
                or sheet.get("state", "visible") != "visible"):
            raise InvalidXlsx("Invalid, hidden or duplicate grade worksheet")
        names.add(name.casefold())
        width, rows = _parse_rows(contents[targets[sheet_id]], strings)
        for row in rows:
            number = grade_number(row[2])
            expected = f"Grade {number}" if number else "Ungraded"
            if name != expected:
                raise InvalidXlsx("Student grade does not match worksheet tab")
            if width == 10:
                canonical = row[:8]
            elif width == 8:
                canonical = row
            else:
                canonical = row[:3] + (["Legacy"] if any(row[3:]) else [""]) + row[3:]
            count += 1
            if count > MAX_ROWS:
                raise XlsxTooLarge("Workbook contains too many student/score records")
            writer.writerow(canonical)
            if output.tell() > MAX_CSV_BYTES:
                raise XlsxTooLarge("Decoded workbook exceeds canonical CSV size")
    if count == 0:
        raise InvalidXlsx("XLSX contains no student records")
    result = output.getvalue()
    if len(result.encode("utf-8")) > MAX_CSV_BYTES:
        raise XlsxTooLarge("Decoded workbook exceeds canonical CSV size")
    return result
