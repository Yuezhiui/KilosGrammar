"""Parameterized PostgreSQL queries and transactional completed-score upserts."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from .config import Config

Record = dict[str, Any]


def json_record(record: Record | None) -> Record | None:
    if record is None:
        return None
    return {
        key: (value.isoformat() if isinstance(value, (datetime, date)) else value)
        for key, value in record.items()
    }


class PostgreSQLStore:
    """One short-lived connection per request, with a transaction per write."""

    def __init__(self, config: Config) -> None:
        self.config = config

    def _connect(self):
        import psycopg
        from psycopg.rows import dict_row

        return psycopg.connect(**self.config.connection_kwargs(), row_factory=dict_row)

    def health(self) -> Record:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT to_regclass('students') IS NOT NULL AS has_students, "
                "to_regclass('student_scores') IS NOT NULL AS has_scores, "
                "EXISTS (SELECT 1 FROM information_schema.columns "
                "WHERE table_schema = current_schema() AND table_name = 'student_scores' "
                "AND column_name = 'minigame') AS has_minigame, "
                "EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = to_regclass('student_scores') "
                "AND conname = 'uq_student_scores_minigame_identity') AS has_minigame_identity"
            ).fetchone()
            if not row or not all(row[field] for field in (
                "has_students", "has_scores", "has_minigame", "has_minigame_identity"
            )):
                raise SchemaNotReady("Explicit minigame schema migration required")
        return {"status": "ok", "database": "connected"}

    def find_student(self, student_id: str) -> Record | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT student_id, student_name, grade_section, created_at, updated_at "
                "FROM students WHERE student_id = %s",
                (student_id,),
            ).fetchone()
        return json_record(row)

    def register_student(self, student_id: str, student_name: str, grade_section: str) -> tuple[Record, bool]:
        with self._connect() as connection:
            row = connection.execute(
                "INSERT INTO students (student_id, student_name, grade_section) "
                "VALUES (%s, %s, %s) ON CONFLICT (student_id) DO NOTHING "
                "RETURNING student_id, student_name, grade_section, created_at, updated_at",
                (student_id, student_name, grade_section),
            ).fetchone()
            if row is not None:
                return json_record(row), True  # type: ignore[return-value]
            # Lock the existing identity so an identical registration is idempotent
            # without racing a concurrent explicit teacher update.
            existing = connection.execute(
                "SELECT student_id, student_name, grade_section, created_at, updated_at "
                "FROM students WHERE student_id = %s FOR UPDATE", (student_id,)
            ).fetchone()
            if existing is None or existing["student_name"] != student_name or existing["grade_section"] != grade_section:
                raise StudentIdentityConflict("Existing student identity differs")
            return json_record(existing), False  # type: ignore[return-value]

    def update_student(self, student_id: str, changes: dict[str, str]) -> Record | None:
        # Whitelisted identifiers; values are always bound parameters.
        columns = [column for column in ("student_name", "grade_section") if column in changes]
        assignments = ", ".join(f"{column} = %s" for column in columns)
        params = tuple(changes[column] for column in columns) + (student_id,)
        with self._connect() as connection:
            row = connection.execute(
                f"UPDATE students SET {assignments}, updated_at = now() "
                "WHERE student_id = %s "
                "RETURNING student_id, student_name, grade_section, created_at, updated_at",
                params,
            ).fetchone()
        return json_record(row)

    def find_score(
        self, student_id: str, game_style: str, game_mode: str, difficulty: str, minigame: str = "Legacy"
    ) -> Record | None:
        with self._connect() as connection:
            row = connection.execute(
                "SELECT score_id, student_id, minigame, game_style, game_mode, difficulty, score, completed_at, updated_at "
                "FROM student_scores WHERE student_id = %s AND minigame = %s AND game_style = %s "
                "AND game_mode = %s AND difficulty = %s",
                (student_id, minigame, game_style, game_mode, difficulty),
            ).fetchone()
        return json_record(row)

    def complete_round_and_replace_score(
        self, student_id: str, game_style: str, game_mode: str, difficulty: str, score: int,
        minigame: str = "Legacy",
    ) -> Record:
        # One atomic transaction: a finished round *always* becomes the current score.
        # A rejected/failed transaction leaves the previous completed score intact.
        with self._connect() as connection:
            row = connection.execute(
                "INSERT INTO student_scores (student_id, minigame, game_style, game_mode, difficulty, score) "
                "VALUES (%s, %s, %s, %s, %s, %s) "
                "ON CONFLICT (student_id, minigame, game_style, game_mode, difficulty) DO UPDATE "
                "SET score = EXCLUDED.score, completed_at = now(), updated_at = now() "
                "RETURNING score_id, student_id, minigame, game_style, game_mode, difficulty, score, completed_at, updated_at",
                (student_id, minigame, game_style, game_mode, difficulty, score),
            ).fetchone()
        return json_record(row)  # type: ignore[return-value]

    def get_leaderboard(
        self,
        game_style: str | None,
        game_mode: str | None,
        difficulty: str | None,
        grade_section: str | None,
        limit: int,
        minigame: str | None = None,
    ) -> list[Record]:
        conditions: list[str] = []
        params: tuple[object, ...] = ()
        for column, value in (("minigame", minigame), ("game_style", game_style), ("game_mode", game_mode), ("difficulty", difficulty)):
            if value is not None:
                conditions.append(f"sc.{column} = %s")
                params += (value,)
        if grade_section is not None:
            conditions.append("st.grade_section = %s")
            params += (grade_section,)
        where_clause = "WHERE " + " AND ".join(conditions) if conditions else ""
        params += (limit,)
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT sc.student_id, st.student_name, st.grade_section, "
                "sc.minigame, sc.game_style, sc.game_mode, sc.difficulty, sc.score, sc.completed_at "
                "FROM student_scores AS sc JOIN students AS st ON st.student_id = sc.student_id "
                f"{where_clause} "
                "ORDER BY sc.score DESC, sc.completed_at ASC, sc.student_id ASC, sc.minigame ASC LIMIT %s",
                params,
            ).fetchall()
        return [{"rank": index, **json_record(row)} for index, row in enumerate(rows, 1)]  # type: ignore[misc]


class SchemaNotReady(Exception):
    """The database has not been explicitly migrated."""


class StudentIdentityConflict(Exception):
    """Registration cannot implicitly change a previously registered student."""


class BulkLimitExceeded(Exception):
    """The CSV export exceeds the maximum safe rows/size."""


class BulkScoreConflict(Exception):
    """A CSV file includes incompatible rows for the same current score."""


MAX_BULK_ROWS = 5000


def _export_snapshot(self: PostgreSQLStore) -> tuple[list[Record], list[Record]]:
    """A consistent, complete (bounded) snapshot, independent of leaderboard limits."""
    with self._connect() as connection:
        connection.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        students = connection.execute(
            "SELECT student_id, student_name, grade_section FROM students "
            "ORDER BY student_id LIMIT %s", (MAX_BULK_ROWS + 1,)
        ).fetchall()
        if len(students) > MAX_BULK_ROWS:
            raise BulkLimitExceeded("CSV exceeds maximum rows")
        scores = connection.execute(
            "SELECT student_id, minigame, game_style, game_mode, difficulty, score "
            "FROM student_scores ORDER BY student_id, minigame, game_style, game_mode, difficulty LIMIT %s",
            (MAX_BULK_ROWS + 1,),
        ).fetchall()
        if len(scores) > MAX_BULK_ROWS:
            raise BulkLimitExceeded("CSV exceeds maximum rows")
        scored_students = {entry["student_id"] for entry in scores}
        if len(scores) + sum(student["student_id"] not in scored_students for student in students) > MAX_BULK_ROWS:
            raise BulkLimitExceeded("CSV exceeds maximum rows")
        return students, scores


def _import_snapshot(self: PostgreSQLStore, students: list[Record], scores: list[Record]) -> Record:
    """One transaction, never implicitly updates an existing student identity.

    If a score already exists with the same value, importing again is a no-op;
    a different imported score replaces the latest completed score even lower.
    """
    counters = {
        "students_created": 0, "students_existing": 0,
        "scores_imported": len(scores), "scores_created": 0,
        "scores_updated": 0, "scores_unchanged": 0,
    }
    with self._connect() as connection:
        for student in students:
            student_id = student["student_id"]
            new_row = connection.execute(
                "INSERT INTO students (student_id, student_name, grade_section) "
                "VALUES (%s, %s, %s) ON CONFLICT (student_id) DO NOTHING RETURNING student_id",
                (student_id, student["student_name"], student["grade_section"]),
            ).fetchone()
            if new_row is not None:
                counters["students_created"] += 1
            else:
                existing = connection.execute(
                    "SELECT student_name, grade_section FROM students WHERE student_id = %s FOR UPDATE",
                    (student_id,),
                ).fetchone()
                if existing is None or (existing["student_name"], existing["grade_section"]) != (
                    student["student_name"], student["grade_section"]
                ):
                    raise StudentIdentityConflict("Conflicting student identity in CSV")
                counters["students_existing"] += 1

        for entry in scores:
            fields = (
                entry["student_id"], entry.get("minigame", "Legacy"),
                entry["game_style"], entry["game_mode"], entry["difficulty"],
            )
            existing = connection.execute(
                "SELECT score FROM student_scores WHERE student_id = %s AND minigame = %s "
                "AND game_style = %s AND game_mode = %s AND difficulty = %s FOR UPDATE",
                fields,
            ).fetchone()
            if existing is not None and existing["score"] == entry["score"]:
                counters["scores_unchanged"] += 1
                continue
            connection.execute(
                "INSERT INTO student_scores (student_id, minigame, game_style, game_mode, difficulty, score) "
                "VALUES (%s, %s, %s, %s, %s, %s) ON CONFLICT "
                "(student_id, minigame, game_style, game_mode, difficulty) DO UPDATE "
                "SET score = EXCLUDED.score, completed_at = now(), updated_at = now() "
                "WHERE student_scores.score IS DISTINCT FROM EXCLUDED.score",
                (*fields, entry["score"]),
            )
            if existing is None:
                counters["scores_created"] += 1
            else:
                counters["scores_updated"] += 1
    return counters


def _delete_all(self: PostgreSQLStore) -> Record:
    """Delete current scores first, then student profiles, in ONE transaction."""
    with self._connect() as connection:
        score_result = connection.execute("DELETE FROM student_scores")
        student_result = connection.execute("DELETE FROM students")
        return {
            "scores_deleted": score_result.rowcount,
            "students_deleted": student_result.rowcount,
        }


PostgreSQLStore.export_snapshot = _export_snapshot
PostgreSQLStore.import_snapshot = _import_snapshot
PostgreSQLStore.delete_all = _delete_all
