"""Durable, append-only SQLite write-ahead recovery for PostgreSQL.

Every successful client write is committed locally (synchronous=FULL) before
PostgreSQL is contacted. The ordered journal survives process/OS restart; no
entry is marked applied until PostgreSQL has confirmed its transaction.
"""

from __future__ import annotations

import json
import os
import sqlite3
import threading
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from .storage import StudentIdentityConflict, normalized_full_name


class RecoveryPendingError(Exception):
    """Administrative mutation cannot safely overtake unsynced writes."""


class RecoveryIdentityConflict(StudentIdentityConflict):
    """A replayed registration conflicts with an existing PostgreSQL identity."""


class RecoveryRequestConflict(Exception):
    """A reused idempotency key carries different score content."""


def default_recovery_path() -> Path:
    explicit = os.getenv("KILOS_RECOVERY_DB_PATH")
    if explicit:
        return Path(explicit).expanduser()
    base = os.getenv("LOCALAPPDATA") or os.getenv("XDG_DATA_HOME")
    if not base:
        base = str(Path.home() / ".local" / "share")
    return Path(base) / "KilosGrammar" / "recovery.sqlite3"


class RecoveryStore:
    """PostgreSQL-first reads, durable SQLite queue for all student/score writes.

    The global lock orders operations between HTTP worker threads and the retry
    thread. A missing database never causes the recovery file to be deleted or
    a pending event to be acknowledged early.
    """

    def __init__(self, primary: Any, path: str | Path | None = None) -> None:
        self.primary = primary
        self.path = Path(path) if path is not None else default_recovery_path()
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        self._lock = threading.RLock()
        self._init_db()

    @contextmanager
    def _connection(self):
        connection = sqlite3.connect(self.path, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA busy_timeout=10000")
        connection.execute("PRAGMA synchronous=FULL")
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def _init_db(self) -> None:
        with self._connection() as connection:
            connection.execute(
                "CREATE TABLE IF NOT EXISTS recovery_events ("
                "sequence INTEGER PRIMARY KEY AUTOINCREMENT, "
                "event_key TEXT NOT NULL UNIQUE, "
                "kind TEXT NOT NULL CHECK (kind IN ('register', 'score')), "
                "payload TEXT NOT NULL, "
                "state TEXT NOT NULL DEFAULT 'pending' "
                "CHECK (state IN ('pending', 'applied', 'conflict')), "
                "created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, "
                "applied_at TEXT, failure_code TEXT)"
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_recovery_pending "
                "ON recovery_events (state, sequence)"
            )
            # SQLite's rollback journal + synchronous FULL ensures a committed
            # event is durable before any success response is sent.

    @staticmethod
    def _serialize(payload: dict[str, Any]) -> str:
        return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))

    def _enqueue(self, kind: str, payload: dict[str, Any], key: str | None) -> tuple[int, str]:
        raw = self._serialize(payload)
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            if key is None:
                # For legacy score calls, collapse duplicate pending retries,
                # but allow a *new* legitimate round with an identical score
                # after the previous write has been committed.
                pending = connection.execute(
                    "SELECT sequence FROM recovery_events WHERE kind = 'score' "
                    "AND payload = ? AND state = 'pending' ORDER BY sequence DESC LIMIT 1",
                    (raw,),
                ).fetchone()
                if pending is not None:
                    return int(pending["sequence"]), "pending"
                key = "score:auto:" + uuid.uuid4().hex
            existing = connection.execute(
                "SELECT sequence, payload, state FROM recovery_events WHERE event_key = ?",
                (key,),
            ).fetchone()
            if existing is not None:
                if existing["payload"] != raw:
                    raise RecoveryRequestConflict("Idempotency key belongs to another request")
                return int(existing["sequence"]), str(existing["state"])
            result = connection.execute(
                "INSERT INTO recovery_events (event_key, kind, payload) VALUES (?, ?, ?)",
                (key, kind, raw),
            )
            return int(result.lastrowid), "pending"

    def _events(self, connection: sqlite3.Connection, state: str = "pending") -> list[sqlite3.Row]:
        return connection.execute(
            "SELECT sequence, kind, payload FROM recovery_events "
            "WHERE state = ? ORDER BY sequence", (state,),
        ).fetchall()

    def _event_state(self, sequence: int) -> str:
        with self._connection() as connection:
            row = connection.execute(
                "SELECT state FROM recovery_events WHERE sequence = ?", (sequence,)
            ).fetchone()
            return str(row["state"]) if row else "missing"

    def _counts(self) -> tuple[int, int]:
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT state, COUNT(*) AS count FROM recovery_events "
                "WHERE state != 'applied' GROUP BY state"
            ).fetchall()
        counts = {row["state"]: row["count"] for row in rows}
        return int(counts.get("pending", 0)), int(counts.get("conflict", 0))

    def _replay(self, *, check_health: bool = False) -> bool:
        """Return PostgreSQL reachability; never erase unacknowledged entries."""
        with self._lock:
            try:
                if check_health:
                    self.primary.health()
                with self._connection() as connection:
                    events = self._events(connection)
                    conflicted = connection.execute(
                        "SELECT payload FROM recovery_events WHERE state='conflict'"
                    ).fetchall()
                # A conflicting identity blocks only that student's events.
                # Unrelated students can safely recover; otherwise one bad
                # record permanently prevents the entire classroom from syncing.
                blocked_students = {
                    json.loads(row["payload"])["student_id"] for row in conflicted
                }
                # When PostgreSQL does not yet have the student for an offline
                # score, do not discard that score or replay later scores for
                # the same ID out of order. A later registration may unblock
                # that identity on the next sync pass.
                waiting_for_registration: set[str] = set()
                for event in events:
                    payload = json.loads(event["payload"])
                    student_id = payload["student_id"]
                    if student_id in blocked_students:
                        continue
                    if event["kind"] == "score" and student_id in waiting_for_registration:
                        continue
                    try:
                        if event["kind"] == "register":
                            self.primary.register_student(
                                payload["student_id"], payload["student_name"], payload["grade_section"]
                            )
                        else:
                            self.primary.complete_round_and_replace_score(
                                payload["student_id"], payload["game_style"],
                                payload["game_mode"], payload["difficulty"],
                                payload["score"], payload["minigame"],
                            )
                    except StudentIdentityConflict:
                        # Never attach a score to another student's identity.
                        # Keep the original payload permanently for resolution
                        # while allowing unrelated IDs to continue syncing.
                        with self._connection() as connection:
                            connection.execute(
                                "UPDATE recovery_events SET state='conflict', "
                                "failure_code='student_identity_conflict' WHERE sequence=?",
                                (event["sequence"],),
                            )
                        blocked_students.add(student_id)
                        continue
                    except Exception as error:
                        if event["kind"] == "score" and getattr(error, "sqlstate", None) == "23503":
                            # A real PostgreSQL foreign-key violation means
                            # this exact ID has not been registered yet.
                            # Preserve the event as pending and let a later
                            # registration apply, without starving other IDs.
                            waiting_for_registration.add(student_id)
                            continue
                        # Includes ambiguous commit success followed by network
                        # loss. The PostgreSQL score UNIQUE key makes replay
                        # idempotent; never mark this event applied on uncertainty.
                        return False
                    with self._connection() as connection:
                        connection.execute(
                            "UPDATE recovery_events SET state='applied', "
                            "applied_at=CURRENT_TIMESTAMP, failure_code=NULL "
                            "WHERE sequence=? AND state='pending'",
                            (event["sequence"],),
                        )
                return True
            except Exception:
                return False

    def sync(self) -> dict[str, Any]:
        with self._lock:
            connected = self._replay(check_health=True)
            pending, conflicts = self._counts()
            return {
                "status": "ok", "database": "connected" if connected else "recovery",
                "recovery_pending": pending, "recovery_conflicts": conflicts,
            }

    def health(self) -> dict[str, Any]:
        return self.sync()

    def _registered_profile(self, student_id: str) -> dict[str, Any] | None:
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT payload, state FROM recovery_events "
                "WHERE kind='register' AND event_key=? LIMIT 1",
                ("register:" + student_id,),
            ).fetchall()
        if rows:
            row = rows[0]
            if row["state"] == "conflict":
                raise RecoveryIdentityConflict("Recovery registration needs identity review")
            profile = json.loads(row["payload"])
            profile["recovery_pending"] = row["state"] != "applied"
            return profile
        return None

    def register_student(
        self, student_id: str, student_name: str, grade_section: str
    ) -> tuple[dict[str, Any], bool]:
        profile = {"student_id": student_id, "student_name": student_name,
                   "grade_section": grade_section}
        with self._lock:
            existing = self._registered_profile(student_id)
            if existing is not None and not existing["recovery_pending"]:
                # An applied journal event is not proof that the profile still
                # exists after an administrator's PostgreSQL DELETE. A crash
                # may interrupt delete_all() between the PostgreSQL commit
                # and clearing old applied SQLite records. Never pretend an
                # explicit re-registration succeeded based only on a stale
                # SQLite event.
                try:
                    remote = self.primary.find_student(student_id)
                except Exception:
                    pass  # Retain the existing durable record during an outage.
                else:
                    if remote is not None:
                        if any(remote[field] != profile[field] for field in profile):
                            raise StudentIdentityConflict("Existing PostgreSQL student details differ")
                        return {**remote, "recovery_pending": False}, False
                    # Only a NEW teacher POST after confirming PostgreSQL has
                    # no row may supersede a previously applied registration.
                    # Do not auto-recreate records after an intentional delete.
                    with self._connection() as connection:
                        connection.execute(
                            "DELETE FROM recovery_events "
                            "WHERE event_key=? AND kind='register' AND state='applied'",
                            ("register:" + student_id,),
                        )
                    existing = None
            if existing is not None and any(existing[field] != profile[field] for field in profile):
                raise StudentIdentityConflict("Existing queued student details differ")
            already_registered = existing is not None
            if existing is None:
                try:
                    remote = self.primary.find_student(student_id)
                    if remote is not None:
                        if any(remote[field] != profile[field] for field in profile):
                            raise StudentIdentityConflict("Existing PostgreSQL student details differ")
                        already_registered = True
                except StudentIdentityConflict:
                    raise
                except Exception:
                    # Offline: the pre-existing identity cannot be asserted yet.
                    pass
            sequence, state = self._enqueue("register", profile, "register:" + student_id)
            if state == "conflict":
                raise RecoveryIdentityConflict("Registration requires identity review")
            if state == "pending":
                self._replay(check_health=True)
            final = self._event_state(sequence)
            if final == "conflict":
                raise RecoveryIdentityConflict("Registration requires identity review")
            if final == "applied":
                try:
                    remote = self.primary.find_student(student_id)
                    if remote:
                        return {**remote, "recovery_pending": False}, not already_registered
                except Exception:
                    pass
            return {**profile, "recovery_pending": final != "applied"}, not already_registered

    def complete_round_and_replace_score(
        self, student_id: str, game_style: str, game_mode: str, difficulty: str,
        score: int, minigame: str = "Legacy", request_id: str | None = None,
    ) -> dict[str, Any]:
        payload = {
            "student_id": student_id, "minigame": minigame,
            "game_style": game_style, "game_mode": game_mode,
            "difficulty": difficulty, "score": score,
        }
        with self._lock:
            # A score cannot be accepted for an unknown ID unless registration
            # was recorded locally or PostgreSQL confirms that exact student.
            profile = self._registered_profile(student_id)
            if profile is None:
                try:
                    student = self.primary.find_student(student_id)
                except Exception:
                    # A previously registered PostgreSQL-only student cannot
                    # be checked during an outage. Accept its exact ID into
                    # recovery; the PostgreSQL foreign key will validate on
                    # replay. Never claim it is already durably in Postgres.
                    student = {"student_id": student_id}
                if student is None:
                    raise UnknownStudentForScore("Register the student before recording scores")
            key = ("score:request:" + request_id) if request_id else None
            sequence, state = self._enqueue("score", payload, key)
            if state == "conflict":
                raise RecoveryIdentityConflict("Score replay requires identity review")
            if state == "pending":
                self._replay(check_health=True)
            final = self._event_state(sequence)
            if final == "applied":
                # This journal event was confirmed at some point, but an
                # authorized PostgreSQL DELETE may since have removed it. A
                # crash between PostgreSQL's DELETE commit and our applied-
                # journal cleanup leaves a stale, still-applied tombstone.
                # Never replay the old round: that would resurrect a teacher-
                # deleted score or overwrite a newer completed round.
                #
                # The only safe acknowledgement is a *verified* PostgreSQL
                # current row. Do not swallow an offline/unreachable lookup
                # and accidentally report recovery_pending=false.
                found = self.primary.find_score(
                    student_id, game_style, game_mode, difficulty, minigame
                )
                if found is None:
                    raise RecoveryRequestConflict(
                        "Applied request ID has no current PostgreSQL score; "
                        "use a new ID for a genuinely new completed round"
                    )
                return {
                    **found,
                    "recovery_pending": False,
                    "idempotent_replay": True,
                    "score_superseded": found["score"] != score,
                }
            if final != "pending":
                raise RecoveryRequestConflict("Completed-round journal event is not replayable")
            return {**payload, "score_id": None, "recovery_pending": final != "applied"}

    def find_student(self, student_id: str) -> dict[str, Any] | None:
        with self._lock:
            self._replay(check_health=True)
            cached = self._registered_profile(student_id)
            if cached and cached["recovery_pending"]:
                return cached
            try:
                remote = self.primary.find_student(student_id)
            except Exception:
                # A previously *applied* registration is not a reliable
                # offline student profile: PostgreSQL may have had an explicit
                # teacher PATCH since this immutable journal entry. Refuse
                # stale autofill rather than returning an outdated identity.
                # Pending registrations were already handled above.
                raise
            return remote

    def find_students_by_name(self, name: str) -> list[dict[str, Any]]:
        with self._lock:
            # Offline local records are not a complete student directory.
            # Claiming a single full-name hit could silently select a different
            # person whose profile exists only in offline PostgreSQL.
            if not self._replay(check_health=True):
                raise LookupUnavailable("Cannot verify full-name uniqueness while PostgreSQL is offline")
            candidates = {
                row["student_id"]: row for row in self.primary.find_students_by_name(name)
            }
            normalized = normalized_full_name(name)
            with self._connection() as connection:
                rows = connection.execute(
                    "SELECT payload, state FROM recovery_events WHERE kind='register' "
                    "AND state='pending'"
                ).fetchall()
            for row in rows:
                profile = json.loads(row["payload"])
                if normalized_full_name(profile["student_name"]) == normalized:
                    candidates[profile["student_id"]] = {
                        **profile, "recovery_pending": row["state"] != "applied"
                    }
            return sorted(candidates.values(), key=lambda item: item["student_id"])[:2]

    def find_score(
        self, student_id: str, game_style: str, game_mode: str,
        difficulty: str, minigame: str = "Legacy",
    ) -> dict[str, Any] | None:
        with self._lock:
            self._replay(check_health=True)
            with self._connection() as connection:
                events = connection.execute(
                    "SELECT payload FROM recovery_events WHERE kind='score' "
                    "AND state='pending' ORDER BY sequence DESC"
                ).fetchall()
            for event in events:
                row = json.loads(event["payload"])
                if all(row[field] == expected for field, expected in (
                    ("student_id", student_id), ("game_style", game_style),
                    ("game_mode", game_mode), ("difficulty", difficulty),
                    ("minigame", minigame),
                )):
                    return {**row, "score_id": None, "recovery_pending": True}
            return self.primary.find_score(student_id, game_style, game_mode, difficulty, minigame)

    def update_student(self, student_id: str, changes: dict[str, str]) -> dict[str, Any] | None:
        with self._lock:
            self._require_clean()
            return self.primary.update_student(student_id, changes)

    def _require_clean(self) -> None:
        self._replay(check_health=True)
        if any(self._counts()):
            raise RecoveryPendingError("Resolve and sync recovery events before administration")

    def get_leaderboard(self, *args: Any, **kwargs: Any) -> list[dict[str, Any]]:
        with self._lock:
            self._replay(check_health=True)
            return self.primary.get_leaderboard(*args, **kwargs)

    def export_snapshot(self) -> Any:
        with self._lock:
            self._require_clean()
            return self.primary.export_snapshot()

    def import_snapshot(self, students: list[dict[str, Any]], scores: list[dict[str, Any]]) -> dict[str, Any]:
        with self._lock:
            self._require_clean()
            return self.primary.import_snapshot(students, scores)

    def delete_all(self) -> dict[str, int]:
        with self._lock:
            self._require_clean()
            result = self.primary.delete_all()
            # Applied event IDs must not block deliberate future re-registration
            # after an authorized reset. Pending data was refused above.
            with self._connection() as connection:
                connection.execute("DELETE FROM recovery_events WHERE state='applied'")
            return result


class UnknownStudentForScore(Exception):
    """Missing student ID, never fabricate an orphan score."""


class LookupUnavailable(Exception):
    """PostgreSQL is unreachable, so name uniqueness is unverifiable."""
