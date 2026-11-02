"""Typed, localhost-only JSON HTTP boundary for the Godot application.

Run from the project root with: python -m database.server
"""

from __future__ import annotations

import csv
import hmac
import io
import json
import os
import re
import secrets
import socket
import stat
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import parse_qs, unquote, urlsplit

from .config import Config
from .recovery_store import (
    LookupUnavailable, RecoveryPendingError, RecoveryRequestConflict,
    RecoveryStore, UnknownStudentForScore,
)
from .storage import MAX_BULK_ROWS, BulkLimitExceeded, PostgreSQLStore, SchemaNotReady, StudentIdentityConflict
from .xlsx_export import encoded_workbook, grade_filter_number, selected_students, student_details

LEGACY_MINIGAME = "Legacy"
LEGACY_CSV_COLUMNS = ("student_id", "student_name", "grade_section", "game_style", "game_mode", "difficulty", "score")
CSV_COLUMNS = ("student_id", "student_name", "grade_section", "minigame", "game_style", "game_mode", "difficulty", "score")
MAX_CSV_BYTES = 1_048_576
MAX_JSON_BODY_BYTES = MAX_CSV_BYTES + 64_000
CONFIRM_DELETE = "DELETE ALL DATA"
CHALLENGE_LIFETIME_SECONDS = 60


def _export_cell(value: Any) -> str:
    """Escape Excel/Calc formula injection without corrupting normal CSV data."""
    cell = str(value)
    if cell.lstrip().startswith(("=", "+", "-", "@", "'")):
        return "'" + cell
    return cell


def _import_cell(value: str) -> str:
    if value.startswith("'") and value[1:].lstrip().startswith(("=", "+", "-", "@", "'")):
        return value[1:]
    return value


def _csv_export(students: list[dict[str, Any]], scores: list[dict[str, Any]]) -> str:
    student_by_id = {student["student_id"]: student for student in students}
    scored = set()
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\r\n")
    writer.writerow(CSV_COLUMNS)
    for score in scores:
        identity = student_by_id[score["student_id"]]
        scored.add(score["student_id"])
        writer.writerow([
            _export_cell(identity["student_id"]), _export_cell(identity["student_name"]),
            _export_cell(identity["grade_section"]), _export_cell(score.get("minigame", LEGACY_MINIGAME)),
            _export_cell(score["game_style"]),
            _export_cell(score["game_mode"]), _export_cell(score["difficulty"]), str(score["score"]),
        ])
    for student in students:
        if student["student_id"] not in scored:
            writer.writerow([
                _export_cell(student["student_id"]), _export_cell(student["student_name"]),
                _export_cell(student["grade_section"]), "", "", "", "", "",
            ])
    result = output.getvalue()
    if len(result.encode("utf-8")) > MAX_CSV_BYTES:
        raise ApiError(413, "csv_too_large", "Complete CSV export exceeds the supported size")
    return result


def _csv_import(source: Any) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    if not isinstance(source, str):
        raise ApiError(400, "invalid_csv", "csv must be UTF-8 CSV text")
    if len(source.encode("utf-8")) > MAX_CSV_BYTES or "\x00" in source:
        raise ApiError(413, "csv_too_large", "CSV exceeds the supported size")
    try:
        reader = csv.reader(io.StringIO(source.lstrip("\ufeff"), newline=""), strict=True)
        header = next(reader, None)
        is_legacy_csv = header == list(LEGACY_CSV_COLUMNS)
        if header != list(CSV_COLUMNS) and not is_legacy_csv:
            raise ApiError(400, "invalid_csv", "CSV must have the eight-column schema or the original seven-column legacy schema")
        students: dict[str, dict[str, str]] = {}
        scores: dict[tuple[str, str, str, str, str], dict[str, Any]] = {}
        row_count = 0
        for row in reader:
            row_count += 1
            if row_count > MAX_BULK_ROWS:
                raise ApiError(413, "csv_too_large", "CSV contains too many rows")
            columns = LEGACY_CSV_COLUMNS if is_legacy_csv else CSV_COLUMNS
            if len(row) != len(columns):
                raise ApiError(400, "invalid_csv", f"CSV row {row_count + 1} has the wrong number of columns")
            fields = dict(zip(columns, [_import_cell(item) for item in row]))
            student_id = student_id_field(fields["student_id"])
            name = text_field(fields["student_name"], "student_name")
            grade = text_field(fields["grade_section"], "grade_section")
            profile = {"student_id": student_id, "student_name": name, "grade_section": grade}
            if student_id in students and students[student_id] != profile:
                raise ApiError(409, "student_conflict", "CSV has incompatible student names or grades for the same ID")
            students[student_id] = profile
            parts = (fields["game_style"], fields["game_mode"], fields["difficulty"], fields["score"])
            if not any(parts):
                if not is_legacy_csv and fields["minigame"]:
                    raise ApiError(400, "invalid_csv", "A student-only CSV row must have all game columns blank")
                continue
            if not all(parts):
                raise ApiError(400, "invalid_csv", "Score columns must all be present or all be blank")
            minigame = LEGACY_MINIGAME if is_legacy_csv else text_field(fields["minigame"], "minigame")
            selection = [text_field(parts[i], LEGACY_CSV_COLUMNS[i + 3]) for i in range(3)]
            if not re.fullmatch(r"[0-9]{1,10}", parts[3]):
                raise ApiError(400, "invalid_csv", "score must be a nonnegative integer")
            score = score_field(int(parts[3]))
            key = (student_id, minigame, *selection)
            new_score = {
                "student_id": student_id, "minigame": minigame, "game_style": selection[0],
                "game_mode": selection[1], "difficulty": selection[2], "score": score,
            }
            if key in scores and scores[key] != new_score:
                raise ApiError(409, "score_conflict", "CSV contains conflicting current scores for one game selection")
            scores[key] = new_score
        return list(students.values()), list(scores.values())
    except (csv.Error, UnicodeError, ValueError) as exc:
        raise ApiError(400, "invalid_csv", "CSV is malformed") from None


def _admin_token_path() -> Path:
    """Keep the local teacher capability scoped to the signed-in OS user."""
    appdata = os.getenv("LOCALAPPDATA") or os.getenv("XDG_DATA_HOME")
    if not appdata:
        raise RuntimeError("User-local profile path is required for administrative operations")
    folder = Path(appdata) / "KilosGrammar"
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    return folder / "admin_api_token.txt"


def _read_admin_token_file(path: Path) -> str | None:
    """Read only a regular, valid local capability; never accept a symlink."""
    try:
        if path.is_symlink() or not path.is_file():
            return None
        token = path.read_text(encoding="ascii").strip()
        if not 32 <= len(token) <= 256 or any(ord(char) <= 32 or ord(char) >= 127 or char == ":" for char in token):
            return None
        return token
    except (OSError, UnicodeError):
        return None


def _create_admin_token() -> str:
    """Reuse the signed-in user's capability instead of rotating it per API.

    The value is not a database credential. The OS user's profile directory
    provides the access boundary. Never expose this token through HTTP, logs,
    argv, or a repository file. An independent test/server on a DIFFERENT HTTP
    port must not invalidate the teacher's existing live leaderboard controls.
    """
    path = _admin_token_path()
    existing = _read_admin_token_file(path)
    if existing is not None:
        return existing
    if path.exists() or path.is_symlink():
        raise RuntimeError("Existing local admin capability is unreadable; preserve it for owner review")
    proposed = secrets.token_urlsafe(32)
    try:
        # O_EXCL prevents simultaneous API startups from racing to replace the
        # same user capability. Permissions are owner-only where supported.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        concurrent = _read_admin_token_file(path)
        if concurrent is None:
            raise RuntimeError("Local capability initialization is incomplete") from None
        return concurrent
    try:
        with os.fdopen(fd, "w", encoding="ascii") as file:
            file.write(proposed)
            file.flush()
            os.fsync(file.fileno())
        os.chmod(path, stat.S_IREAD | stat.S_IWRITE)
    except Exception:
        path.unlink(missing_ok=True)
        raise
    return proposed


class Store(Protocol):
    def health(self) -> dict[str, Any]: ...
    def find_student(self, student_id: str) -> dict[str, Any] | None: ...
    def find_students_by_name(self, student_name: str) -> list[dict[str, Any]]: ...
    def register_student(self, student_id: str, student_name: str, grade_section: str) -> tuple[dict[str, Any], bool]: ...
    def update_student(self, student_id: str, changes: dict[str, str]) -> dict[str, Any] | None: ...
    def find_score(
        self, student_id: str, game_style: str, game_mode: str, difficulty: str, minigame: str = LEGACY_MINIGAME
    ) -> dict[str, Any] | None: ...
    def complete_round_and_replace_score(
        self, student_id: str, game_style: str, game_mode: str, difficulty: str, score: int,
        minigame: str = LEGACY_MINIGAME
    ) -> dict[str, Any]: ...
    def get_leaderboard(
        self, game_style: str | None, game_mode: str | None, difficulty: str | None,
        grade_section: str | None, limit: int, minigame: str | None = None
    ) -> list[dict[str, Any]]: ...
    def export_snapshot(self) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]: ...
    def import_snapshot(self, students: list[dict[str, Any]], scores: list[dict[str, Any]]) -> dict[str, Any]: ...
    def delete_all(self) -> dict[str, int]: ...


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str) -> None:
        self.status = status
        self.code = code
        self.message = message
        super().__init__(message)


def text_field(value: Any, field: str, max_length: int = 150) -> str:
    if not isinstance(value, str):
        raise ApiError(400, "invalid_input", f"{field} must be a string")
    value = value.strip()
    if not value or len(value) > max_length or any(ord(char) < 32 or ord(char) == 127 for char in value):
        raise ApiError(400, "invalid_input", f"{field} must contain 1-{max_length} printable characters")
    return value


def student_id_field(value: Any) -> str:
    value = text_field(value, "student_id", 64)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value):
        raise ApiError(400, "invalid_input", "student_id must use letters, numbers, dot, underscore or hyphen")
    return value


def score_field(value: Any) -> int:
    if type(value) is not int or not 0 <= value <= 2_147_483_647:
        raise ApiError(400, "invalid_input", "score must be a nonnegative 32-bit integer")
    return value


def object_body(body: Any, required: set[str], allowed: set[str] | None = None) -> dict[str, Any]:
    if not isinstance(body, dict):
        raise ApiError(400, "invalid_input", "Expected a JSON object")
    allowed = required if allowed is None else allowed
    if not required.issubset(body) or (body.keys() - allowed):
        raise ApiError(400, "invalid_input", "Missing required fields or unexpected fields")
    return body


def query_params(query: str, required: set[str], optional: set[str] = frozenset()) -> dict[str, str]:
    try:
        raw = parse_qs(query, keep_blank_values=True, max_num_fields=12)
    except ValueError:
        raise ApiError(400, "invalid_input", "Invalid query parameters") from None
    if not required.issubset(raw) or (raw.keys() - required - optional):
        raise ApiError(400, "invalid_input", "Missing required query parameters or unexpected parameters")
    if any(len(values) != 1 for values in raw.values()):
        raise ApiError(400, "invalid_input", "Query parameters must occur once")
    return {key: values[0] for key, values in raw.items()}


def _translate_database_error(error: Exception) -> ApiError:
    # Never send underlying DB exception strings: they may include connection details.
    if isinstance(error, SchemaNotReady) or getattr(error, "sqlstate", None) in {"42P01", "42703"}:
        return ApiError(503, "schema_not_ready", "Run the reviewed database migration")
    if getattr(error, "sqlstate", None) == "23505":
        return ApiError(409, "student_exists", "This student ID is already registered")
    if isinstance(error, StudentIdentityConflict):
        return ApiError(409, "student_exists", "This student ID has different registered details; use explicit update")
    if isinstance(error, RecoveryRequestConflict):
        return ApiError(409, "request_id_conflict", "This request ID was already used with different score details")
    if isinstance(error, RecoveryPendingError):
        return ApiError(409, "recovery_pending", "Finish recovering pending student scores before data administration")
    if isinstance(error, LookupUnavailable):
        return ApiError(503, "lookup_unavailable", "Full-name uniqueness cannot be verified until PostgreSQL reconnects")
    if isinstance(error, UnknownStudentForScore):
        return ApiError(404, "student_not_found", "Register the student before recording scores")
    if isinstance(error, BulkLimitExceeded):
        return ApiError(413, "csv_too_large", "Complete CSV export exceeds the supported row limit")
    if getattr(error, "sqlstate", None) == "23503":
        return ApiError(404, "student_not_found", "Register the student before recording scores")
    return ApiError(503, "database_unavailable", "Local database service is unavailable")


class API:
    def __init__(self, store: Store, admin_token: str | None = None) -> None:
        self.store = store
        self._admin_token = admin_token
        # Enabled only by the real localhost server. MemoryStore unit tests
        # using an explicit injected capability retain isolated semantics.
        self._admin_token_file: Path | None = None
        self._challenge_lock = threading.Lock()
        self._delete_challenge: tuple[str, float] | None = None

    def dispatch(
        self, method: str, target: str, body: Any = None, admin_token: str | None = None
    ) -> tuple[int, dict[str, Any]]:
        try:
            parsed = urlsplit(target)
            if parsed.path.startswith("/data/"):
                if self._admin_token_file is not None:
                    # Legacy API processes may predate a second API startup
                    # that rotated the shared file. Synchronize only with a
                    # valid OS-user-scoped token; never weaken the 403 guard.
                    self._admin_token = _read_admin_token_file(self._admin_token_file)
                if not self._admin_token or not isinstance(admin_token, str) or not hmac.compare_digest(
                    self._admin_token, admin_token
                ):
                    raise ApiError(403, "admin_authorization_required", "Local administrator authorization required")
            status, data = self._handle(method, target, body)
            return status, {"ok": True, "data": data, "error": None}
        except ApiError as error:
            return error.status, {
                "ok": False, "data": None, "error": {"code": error.code, "message": error.message},
            }
        except Exception as error:
            safe = _translate_database_error(error)
            return safe.status, {
                "ok": False, "data": None, "error": {"code": safe.code, "message": safe.message},
            }

    def _handle(self, method: str, target: str, body: Any) -> tuple[int, dict[str, Any]]:
        parsed = urlsplit(target)
        path = parsed.path.rstrip("/") or "/"
        reporting_routes = {"/data/export_xlsx", "/data/export/xlsx", "/data/students"}
        if path.startswith("/data/") and parsed.query and path not in reporting_routes:
            raise ApiError(400, "invalid_input", "Unexpected query parameters")
        if method == "GET" and path == "/data/export":
            students, scores = self.store.export_snapshot()
            return 200, {"csv": _csv_export(students, scores), "students": len(students), "scores": len(scores)}
        if method == "GET" and path in reporting_routes:
            # Only teacher-authorized /data/ routes expose the full student
            # roster, including profiles with no scores. Never use the 500-row
            # public leaderboard as a source for an XLSX/data backup.
            filters = query_params(parsed.query, set(), {"grade", "grade_section", "student_id"})
            grade = filters.get("grade")
            if grade is not None and grade_filter_number(grade) is None:
                raise ApiError(400, "invalid_input", "grade must be Grade 1 through Grade 12")
            section = filters.get("grade_section")
            if section is not None:
                section = text_field(section, "grade_section")
            identifier = filters.get("student_id")
            if identifier is not None:
                identifier = student_id_field(identifier)
            students, scores = self.store.export_snapshot()
            students, scores = selected_students(
                students, scores, grade=grade, grade_section=section, student_id=identifier,
            )
            if path == "/data/students":
                return 200, {"students": student_details(students, scores),
                             "count": len(students), "score_count": len(scores),
                             "timestamp_semantics": (
                                 "completed_at is the latest saved record per game selection, "
                                 "not every round; a changed CSV import may reset this timestamp"
                             )}
            try:
                return 200, encoded_workbook(students, scores)
            except ValueError:
                raise ApiError(413, "xlsx_too_large", "Complete XLSX report exceeds the supported size") from None
        if method == "POST" and path == "/data/import":
            request = object_body(body, {"csv"})
            students, scores = _csv_import(request["csv"])
            if not students:
                raise ApiError(400, "invalid_csv", "CSV must contain at least one student row")
            return 200, self.store.import_snapshot(students, scores)
        if method == "GET" and path == "/data/delete_all/challenge":
            challenge = secrets.token_urlsafe(24)
            with self._challenge_lock:
                self._delete_challenge = (challenge, time.monotonic() + CHALLENGE_LIFETIME_SECONDS)
            return 200, {
                "challenge": challenge, "confirmation_phrase": CONFIRM_DELETE,
                "expires_in_seconds": CHALLENGE_LIFETIME_SECONDS,
            }
        if method == "POST" and path == "/data/delete_all":
            request = object_body(body, {"challenge", "confirmation"})
            if request["confirmation"] != CONFIRM_DELETE:
                raise ApiError(400, "confirmation_required", "Exact DELETE ALL DATA confirmation is required")
            challenge = request["challenge"]
            if not isinstance(challenge, str) or len(challenge) > 128:
                raise ApiError(400, "invalid_input", "Invalid delete confirmation challenge")
            with self._challenge_lock:
                saved = self._delete_challenge
                if not saved or time.monotonic() > saved[1] or not hmac.compare_digest(saved[0], challenge):
                    raise ApiError(403, "confirmation_expired", "Delete confirmation expired or was already used")
                self._delete_challenge = None
            return 200, self.store.delete_all()
        if method == "GET" and path == "/health":
            if parsed.query:
                raise ApiError(400, "invalid_input", "Unexpected query parameters")
            return 200, self.store.health()

        if method == "GET" and path == "/students/by-name":
            params = query_params(parsed.query, {"name"})
            name = text_field(params["name"], "name")
            if not hasattr(self.store, "find_students_by_name"):
                raise ApiError(503, "lookup_unavailable", "Full-name lookup is unavailable")
            matches = self.store.find_students_by_name(name)
            if len(matches) > 1:
                raise ApiError(409, "student_ambiguous", "Multiple student IDs share this full name; enter student ID instead")
            if not matches:
                raise ApiError(404, "student_not_found", "No student registered with this full name")
            return 200, {"student": matches[0], "match": "full_name"}

        if path.startswith("/students/"):
            student_id = student_id_field(unquote(path[len("/students/"):]))
            if parsed.query:
                raise ApiError(400, "invalid_input", "Unexpected query parameters")
            if method == "GET":
                found = self.store.find_student(student_id)
                if found is None:
                    raise ApiError(404, "student_not_found", "No student registered with this ID")
                return 200, {"student": found}
            if method == "PATCH":
                request = object_body(body, set(), {"student_name", "grade_section"})
                if not request:
                    raise ApiError(400, "invalid_input", "Provide a field to update explicitly")
                changes = {
                    field: text_field(value, field)
                    for field, value in request.items()
                }
                updated = self.store.update_student(student_id, changes)
                if updated is None:
                    raise ApiError(404, "student_not_found", "No student registered with this ID")
                return 200, {"student": updated}

        if method == "POST" and path == "/students":
            request = object_body(body, {"student_id", "student_name", "grade_section"})
            student, created = self.store.register_student(
                student_id_field(request["student_id"]),
                text_field(request["student_name"], "student_name"),
                text_field(request["grade_section"], "grade_section"),
            )
            return (201 if created else 200), {
                "student": student, "recovery_pending": bool(student.get("recovery_pending", False)),
            }

        if method == "GET" and path == "/scores":
            params = query_params(parsed.query, {"student_id", "game_style", "game_mode", "difficulty"}, {"minigame"})
            score = self.store.find_score(
                student_id_field(params["student_id"]),
                text_field(params["game_style"], "game_style"),
                text_field(params["game_mode"], "game_mode"),
                text_field(params["difficulty"], "difficulty"),
                text_field(params["minigame"], "minigame") if "minigame" in params else LEGACY_MINIGAME,
            )
            return 200, {"score": score}

        if method == "POST" and path in {"/rounds/complete", "/scores/completed"}:
            request = object_body(
                body, {"student_id", "game_style", "game_mode", "difficulty", "score"},
                {"student_id", "minigame", "game_style", "game_mode", "difficulty", "score", "request_id"},
            )
            args = (
                student_id_field(request["student_id"]),
                text_field(request["game_style"], "game_style"),
                text_field(request["game_mode"], "game_mode"),
                text_field(request["difficulty"], "difficulty"),
                score_field(request["score"]),
                text_field(request["minigame"], "minigame") if "minigame" in request else LEGACY_MINIGAME,
            )
            if "request_id" in request:
                request_id = request["request_id"]
                if not isinstance(request_id, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", request_id):
                    raise ApiError(400, "invalid_input", "request_id must be a stable 1-128 character identifier")
                if not isinstance(self.store, RecoveryStore):
                    result = self.store.complete_round_and_replace_score(*args)
                else:
                    result = self.store.complete_round_and_replace_score(*args, request_id=request_id)
            else:
                result = self.store.complete_round_and_replace_score(*args)
            return 200, {
                "score": result, "recovery_pending": bool(result.get("recovery_pending", False)),
            }

        if method == "GET" and path == "/leaderboard":
            params = query_params(
                parsed.query,
                set(),
                {"minigame", "game_style", "game_mode", "difficulty", "grade_section", "limit"},
            )
            # Empty filters mean 'All'. The leaderboard screen can filter the
            # returned style/mode/difficulty dimensions locally if desired.
            filters = {
                field: text_field(params[field], field) if params.get(field) else None
                for field in ("minigame", "game_style", "game_mode", "difficulty", "grade_section")
            }
            limit = 500
            if "limit" in params:
                if not re.fullmatch(r"[0-9]{1,3}", params["limit"]):
                    raise ApiError(400, "invalid_input", "limit must be an integer from 1 to 500")
                limit = int(params["limit"])
                if not 1 <= limit <= 500:
                    raise ApiError(400, "invalid_input", "limit must be an integer from 1 to 500")
            entries = self.store.get_leaderboard(
                filters["game_style"], filters["game_mode"], filters["difficulty"], filters["grade_section"], limit,
                filters["minigame"],
            )
            return 200, {"leaderboard": entries, "count": len(entries)}

        raise ApiError(404, "not_found", "Unknown API endpoint")


def make_handler(api: API) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "KilosLocalDB/1"
        sys_version = ""
        protocol_version = "HTTP/1.1"

        def setup(self) -> None:
            super().setup()
            self.connection.settimeout(5)

        def _json_response(self, status: int, result: dict[str, Any]) -> None:
            # Every reply has an exact byte length. Close the connection rather
            # than trying to reuse a socket with untrusted/unread request data.
            data = json.dumps(result, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            self.close_connection = True
            try:
                self.send_response(status)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Connection", "close")
                self.send_header("Cache-Control", "no-store")
                self.send_header("X-Content-Type-Options", "nosniff")
                self.end_headers()
                self.wfile.write(data)
                self.wfile.flush()
            except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
                # The peer (or a local security product) already severed this
                # connection. It cannot receive our response; never retry or
                # reinterpret the rejected request as authorized.
                return

        def _drain_rejected_body(self) -> None:
            """Best effort: avoid Windows TCP RST when refusing a short POST.

            On Windows, closing a socket with unread bytes from a POST often
            discards the 403 response by resetting the connection (10053).
            Read ONLY a bounded, explicitly framed body under a short deadline
            before sending denial. Refuse unframed/oversized bodies without
            blocking or trusting their content. This is not authentication.
            """
            if self.headers.get_all("Transfer-Encoding", []):
                return
            lengths = self.headers.get_all("Content-Length", [])
            if len(lengths) != 1 or not re.fullmatch(r"[0-9]{1,6}", lengths[0]):
                return
            length = int(lengths[0])
            if not (0 < length <= 16_384):
                return
            try:
                self.connection.settimeout(0.2)
                self.rfile.read(length)
            except (OSError, TimeoutError, ValueError):
                # Denial still proceeds even when the client withholds bytes.
                pass
            finally:
                self.connection.settimeout(5)

        def _valid_local_request(self) -> bool:
            """Block DNS-rebinding hosts and cross-origin browser requests.

            Native Godot clients usually send no Origin header. If one is
            provided, its origin must match the HTTP Host exactly. Both Host
            and listener remain local even when another machine's DNS maps
            a public hostname to 127.0.0.1.
            """
            hosts = self.headers.get_all("Host", [])
            port = self.server.server_address[1]
            allowed_hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
            if len(hosts) != 1 or hosts[0].lower() not in allowed_hosts:
                self._drain_rejected_body()
                self._error(403, "forbidden_host", "Use the local service address")
                return False

            origins = self.headers.get_all("Origin", [])
            if len(origins) > 1 or (origins and origins[0].lower() != f"http://{hosts[0].lower()}"):
                self._drain_rejected_body()
                self._error(403, "forbidden_origin", "Cross-origin access is not allowed")
                return False

            # A local app must send an origin-form path, not a proxy-style
            # absolute URL (which can disguise an unrelated destination).
            if not self.path.startswith("/") or self.path.startswith("//"):
                self._drain_rejected_body()
                self._error(400, "invalid_target", "Use a local relative API path")
                return False
            return True

        def handle_expect_100(self) -> bool:
            # Never send a provisional "100 Continue" to a disallowed
            # Host/Origin. For an allowed request, normal 100 handling applies
            # before the full body and a second validation in _request.
            if not self._valid_local_request():
                return False
            return super().handle_expect_100()

        def _request(self) -> None:
            if not self._valid_local_request():
                return
            admin_token = None
            if urlsplit(self.path).path.startswith("/data/"):
                tokens = self.headers.get_all("X-Kilos-Admin-Token", [])
                if len(tokens) != 1:
                    self._error(403, "admin_authorization_required", "Local administrator authorization required")
                    return
                admin_token = tokens[0]
            body = None
            if self.command in {"POST", "PATCH"}:
                if self.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() != "application/json":
                    self._error(415, "invalid_content_type", "Use application/json")
                    return
                length_header = self.headers.get("Content-Length", "")
                if not re.fullmatch(r"[0-9]{1,6}", length_header):
                    self._error(400, "invalid_body", "Invalid JSON body length")
                    return
                length = int(length_header)
                max_length = MAX_JSON_BODY_BYTES if self.path == "/data/import" else 16_384
                if length < 2 or length > max_length:
                    self._error(413, "invalid_body", "JSON body exceeds the allowed size")
                    return
                try:
                    body = json.loads(self.rfile.read(length).decode("utf-8"))
                except (UnicodeError, json.JSONDecodeError):
                    self._error(400, "invalid_json", "Request body must be valid JSON")
                    return
            status, result = api.dispatch(self.command, self.path, body, admin_token=admin_token)
            self._json_response(status, result)

        def _error(self, status: int, code: str, message: str) -> None:
            self._json_response(status, {"ok": False, "data": None, "error": {"code": code, "message": message}})

        def do_GET(self) -> None:
            self._request()

        def do_POST(self) -> None:
            self._request()

        def do_PATCH(self) -> None:
            self._request()

        def do_OPTIONS(self) -> None:
            # Browser CORS preflight never receives an allow-origin header.
            if self._valid_local_request():
                self._error(405, "method_not_allowed", "OPTIONS is not supported")

        def log_message(self, _format: str, *args: object) -> None:
            # Do not log student IDs/URLs, authorization data, or request bodies.
            return

    return Handler


class ExclusiveLoopbackHTTPServer(ThreadingHTTPServer):
    """Bind one local API per port, including on Windows.

    The default HTTPServer reuse-address option permits two concurrent
    listeners on Windows. Both could then rotate the user's admin token and
    randomly service requests, making legitimate leaderboard transfers fail
    with 403. SO_EXCLUSIVEADDRUSE rejects a second listener before any token
    file is opened; ordinary score records are entirely unaffected.
    """

    allow_reuse_address = False

    def server_bind(self) -> None:
        if os.name == "nt":
            flag = getattr(socket, "SO_EXCLUSIVEADDRUSE", None)
            if flag is None:
                raise RuntimeError("Safe exclusive Windows loopback binding is unavailable")
            self.socket.setsockopt(socket.SOL_SOCKET, flag, 1)
        super().server_bind()


def main() -> None:
    config = Config.from_env()
    recovery = RecoveryStore(PostgreSQLStore(config))
    api = API(recovery)
    with ExclusiveLoopbackHTTPServer(("127.0.0.1", config.http_port), make_handler(api)) as server:
        # Exclusive bind BEFORE reading/creating the token file. A second
        # accidental startup on the same Windows port cannot start serving.
        api._admin_token = _create_admin_token()
        api._admin_token_file = _admin_token_path()
        print(f"KILOS GRAMMAR database API listening at http://127.0.0.1:{config.http_port}")
        stop_retry = threading.Event()

        def retry_recovery() -> None:
            # No user requests are necessary for an offline queue to drain.
            # The lock inside RecoveryStore prevents concurrent replay.
            while not stop_retry.wait(3.0):
                recovery.sync()

        retry_thread = threading.Thread(target=retry_recovery, name="KilosRecoveryRetry", daemon=True)
        retry_thread.start()
        try:
            server.serve_forever(poll_interval=0.5)
        except KeyboardInterrupt:
            pass
        finally:
            stop_retry.set()
            retry_thread.join(timeout=4.0)


if __name__ == "__main__":
    main()
