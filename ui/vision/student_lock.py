"""Single-occupant, fresh-pose gate for the classroom webcam.

ByteTrack ID is ONLY a diagnostic. It cannot authenticate a child, and is not
used to select, enroll, stop, resume, or bind calibration. During a round:

* NO person: no controller, pause until a fresh solo hold.
* TWO OR MORE detected persons: no controller, regardless of relative size,
  physical tracker ID or whether all keypoints are currently visible.
* EXACTLY ONE real, eligible body: allow controls after a short consecutive,
  spatially steady source-pose hold; keep the existing game's calibration.

This explicitly does not promise to recognize the same human who left a
completely empty classroom; occupancy cannot establish identity. The game
should use the teacher-verified round/session if identity matters.
"""

from __future__ import annotations

import math


class StudentLock:
    ENROLL_SECONDS = 0.65
    ENROLL_FRAMES = 4
    RECOVER_SECONDS = 0.65
    RECOVER_FRAMES = 4
    # Sparse but genuinely fresh 1-2 FPS inference should still finish a hold.
    # This is a gap between new real YOLO source frames, never redraws.
    MAX_SOURCE_GAP = 1.25
    MAX_STABLE_X_SPREAD = 0.115
    MAX_STABLE_SIZE_RATIO = 1.38
    # A *confirmed* solo occupant is allowed to MOVE while playing. Treating
    # a large between-inference X/box jump as loss forced another .65s hold,
    # making classroom gameplay alternate PAUSE / PLAY on fast body motion.
    # Spatial stability is checked when enrolling/recovering, not while active.
    MIN_BOX_HEIGHT = 0.20

    def __init__(self) -> None:
        # Legacy property retained as an always-unassigned diagnostic. This
        # system NEVER registers a camera identity for the human.
        self.locked_id: int | None = None
        self.physical_track_id = -1
        self.tracking_epoch = 0
        self.needs_recalibration = False
        self.lock_reacquired = False
        self.previous_locked_id: int | None = None
        self.view_was_clear = False
        self.needs_reenrollment = False
        self.lost_since: float | None = None
        self.empty_since: float | None = None
        self.previous_seen: float | None = None
        self.previous_x: float | None = None
        self.previous_height: float | None = None
        self.candidate_since: float | None = None
        self.candidate_last_seen: float | None = None
        self.candidate_frames = 0
        self.candidate_x: float | None = None
        self.candidate_height: float | None = None

    def require_clear_reenrollment(self) -> None:
        """Worker restart: require a new solo hold, NOT an empty-camera ritual."""
        self._suspend(None)

    @staticmethod
    def _valid(person: dict) -> bool:
        """Only actual observed, trustworthy torso/box coordinates can steer."""
        if not isinstance(person, dict) or person.get("eligible", True) is False:
            return False
        try:
            x = float(person["x"])
            height = float(person["height"])
            return (math.isfinite(x) and math.isfinite(height)
                    and 0 <= x <= 1 and height >= StudentLock.MIN_BOX_HEIGHT)
        except (ValueError, TypeError, KeyError, OverflowError):
            return False

    @staticmethod
    def _physical_id(person: dict) -> int:
        """Diagnostics only. Missing/invalid ByteTrack IDs never block play."""
        try:
            value = person.get("track_id", -1)
            if value is None or isinstance(value, bool):
                return -1
            raw = float(value)
            if not math.isfinite(raw) or raw < 0 or not raw.is_integer():
                return -1
            return int(raw)
        except (TypeError, ValueError, OverflowError):
            return -1

    def _clear_candidate(self) -> None:
        self.candidate_since = None
        self.candidate_last_seen = None
        self.candidate_frames = 0
        self.candidate_x = None
        self.candidate_height = None

    def _suspend(self, now: float | None) -> None:
        self.needs_reenrollment = True
        if self.lost_since is None:
            self.lost_since = now
        self.previous_seen = None
        self.physical_track_id = -1
        self._clear_candidate()

    def _continuous(self, person: dict, now: float) -> bool:
        if (self.previous_seen is None or self.previous_x is None
                or self.previous_height is None):
            return False
        elapsed = now - self.previous_seen
        return 0.0 <= elapsed <= self.MAX_SOURCE_GAP

    def _temporarily_unusable_torso(self, now: float) -> None:
        """One real person, but this frame has no trustworthy torso geometry.

        Never return a controller for that frame. Retain a *recent* confirmed
        solo hold so one poor-confidence frame does not trigger another .65s
        enrollment. A prolonged run of bad torso frames is a genuine tracking
        loss and requires fresh stable re-enrollment.
        """
        self.physical_track_id = -1
        if self.previous_seen is None or now - self.previous_seen > self.MAX_SOURCE_GAP:
            self._suspend(now)

    def _start_or_continue_hold(self, person: dict, now: float) -> float:
        x = float(person["x"])
        height = float(person["height"])
        still = (
            self.candidate_since is not None
            and self.candidate_last_seen is not None
            and self.candidate_x is not None
            and self.candidate_height is not None
            and 0 <= now - self.candidate_last_seen <= self.MAX_SOURCE_GAP
            and abs(x - self.candidate_x) <= self.MAX_STABLE_X_SPREAD
            and 1.0 / self.MAX_STABLE_SIZE_RATIO
            <= height / self.candidate_height <= self.MAX_STABLE_SIZE_RATIO
        )
        if not still:
            self.candidate_since = now
            self.candidate_frames = 1
            self.candidate_x = x
            self.candidate_height = height
        else:
            self.candidate_frames += 1
        self.candidate_last_seen = now
        return now - self.candidate_since

    def update(self, people: list[dict], now: float,
               detected_count: int | None = None) -> tuple[dict | None, str, str]:
        """Return a controller only for one fresh, stable REAL detected body.

        The caller supplies exactly one update per genuinely fresh inference
        frame (never once per Godot draw). detected_count is YOLO's raw
        observed person count and takes precedence over missing tracker IDs
        or unprocessable keypoints in people.
        """
        self.lock_reacquired = False
        try:
            count = len(people) if detected_count is None else int(detected_count)
        except (TypeError, ValueError, OverflowError):
            count = -1
        if count < 0:
            self._suspend(now)
            return None, "ambiguous", "Camera detection unavailable. Wait for a fresh frame."
        if count == 0:
            self._suspend(now)
            self.view_was_clear = True
            if self.empty_since is None:
                self.empty_since = now
            return None, "lost", "Come back into the camera view. Your round is paused."
        self.empty_since = None
        self.view_was_clear = False
        if count >= 2 or len(people) != 1:
            self._suspend(now)
            return None, "ambiguous", "Multiple people detected. One person at a time."

        single = people[0]
        if not self._valid(single):
            self._temporarily_unusable_torso(now)
            return None, "occluded", "One person visible. Show your torso clearly."

        # A valid body may have a different/new/missing ByteTrack ID every
        # frame. It never invalidates the same round's calibrated positions.
        if not self.needs_reenrollment and self.tracking_epoch > 0 \
                and self._continuous(single, now):
            self._record(single, now)
            return single, "locked", "ONE PLAYER FOUND. Keep playing."

        # A real interruption (or old source position jump) must earn a modest
        # new solo, steady pose hold, then gameplay resumes WITHOUT calibrating.
        self.needs_reenrollment = True
        elapsed = self._start_or_continue_hold(single, now)
        seconds = self.RECOVER_SECONDS if self.tracking_epoch > 0 else self.ENROLL_SECONDS
        frames = self.RECOVER_FRAMES if self.tracking_epoch > 0 else self.ENROLL_FRAMES
        if elapsed < seconds or self.candidate_frames < frames:
            return None, "enrolling", (
                f"One person detected. Stand still ({max(0.0, seconds - elapsed):.1f}s).")
        recovered = self.tracking_epoch > 0
        self._record(single, now)
        if not recovered:
            self.tracking_epoch = 1
        else:
            self.lock_reacquired = True
        return single, "locked", "ONE PLAYER READY. Round resumed." if recovered \
            else "ONE PLAYER READY. Begin calibration."

    def _record(self, person: dict, now: float) -> None:
        self.previous_x = float(person["x"])
        self.previous_height = float(person["height"])
        self.previous_seen = now
        self.physical_track_id = self._physical_id(person)
        self.needs_reenrollment = False
        self.lost_since = None
        self._clear_candidate()
