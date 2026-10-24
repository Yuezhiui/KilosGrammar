"""Temporary, camera-local single-student tracking with automatic recovery.

ByteTrack IDs are not biometric identities. Never hand control to a different
visible track without a new, unambiguous CENTER hold. A short absence alone
does not erase the student's calibrated movement range.
"""

from __future__ import annotations

import math


class StudentLock:
    ENROLL_SECONDS = 1.2
    ENROLL_FRAMES = 8
    RECOVER_SECONDS = 2.4
    RECOVER_FRAMES = 12
    MIN_BOX_HEIGHT = 0.20
    CENTER_MIN = 0.28
    CENTER_MAX = 0.72
    DOMINANCE_RATIO = 1.45
    MAX_LOST_SECONDS = 0.8
    SAME_ID_GRACE_SECONDS = 10.0
    MAX_DELTA_X = 0.18
    MAX_SIZE_RATIO = 1.9
    CLEAR_VIEW_SECONDS = 0.35

    def __init__(self) -> None:
        self.locked_id: int | None = None
        self.candidate_id: int | None = None
        self.candidate_since = 0.0
        self.candidate_frames = 0
        self.lost_since: float | None = None
        self.needs_reenrollment = False
        self.empty_since: float | None = None
        self.view_was_clear = False
        self.previous_x: float | None = None
        self.previous_height: float | None = None
        self.previous_seen = 0.0

    def require_clear_reenrollment(self) -> None:
        """Used after worker restart, when prior ByteTrack IDs are all invalid."""
        self.locked_id = -1  # Sentinel; real ByteTrack IDs are nonnegative.
        self.needs_reenrollment = True
        self.view_was_clear = False
        self.empty_since = None
        self._clear_enrollment()

    @staticmethod
    def _valid(person: dict) -> bool:
        try:
            x = float(person["x"])
            height = float(person["height"])
            return math.isfinite(x) and math.isfinite(height) and 0 <= x <= 1 and height > 0
        except (ValueError, TypeError, KeyError):
            return False

    def _continuous(self, target: dict, now: float) -> bool:
        elapsed = min(max(now - self.previous_seen, 0.0), 1.0)
        x = float(target["x"])
        height = float(target["height"])
        if self.previous_x is not None and abs(x - self.previous_x) > self.MAX_DELTA_X + elapsed * 0.25:
            return False
        if self.previous_height is not None and self.previous_height > 0:
            ratio = height / self.previous_height
            if not (1.0 / self.MAX_SIZE_RATIO <= ratio <= self.MAX_SIZE_RATIO):
                return False
        return True

    def _record(self, target: dict, now: float) -> None:
        self.locked_id = int(target["track_id"])
        self.previous_x = float(target["x"])
        self.previous_height = float(target["height"])
        self.previous_seen = now
        self.lost_since = None
        self.needs_reenrollment = False
        self.empty_since = None
        self.view_was_clear = False
        self._clear_enrollment()

    def update(self, people: list[dict], now: float) -> tuple[dict | None, str, str]:
        """Select a real detected student, or None with a child-friendly hint."""
        people = [p for p in people if self._valid(p)]

        if self.locked_id is not None and not self.needs_reenrollment:
            target = next((p for p in people if p["track_id"] == self.locked_id), None)
            if target is not None:
                if now - self.previous_seen <= self.SAME_ID_GRACE_SECONDS and self._continuous(target, now):
                    self._record(target, now)
                    return target, "locked", "PLAYER FOUND! Keep playing."
                self.needs_reenrollment = True
                self.lost_since = self.lost_since if self.lost_since is not None else now
                return None, "lost", "Please stand alone in CENTER so the camera can find you again."

            if self.lost_since is None:
                self.lost_since = now
            if not people:
                if self.empty_since is None:
                    self.empty_since = now
                if now - self.empty_since >= self.CLEAR_VIEW_SECONDS:
                    self.view_was_clear = True
            # Another track appeared while our student was hidden. It may be
            # a classmate or a changed ByteTrack ID; neither can be trusted.
            if people:
                self.empty_since = None
                self.needs_reenrollment = True
            if now - self.lost_since <= self.MAX_LOST_SECONDS:
                return None, "occluded", "I can't see you. Step back into the camera view."
            if not self.needs_reenrollment:
                return None, "lost", "Come back into view. Your game position is saved."

        # Fresh enrollment and recovery both require an unobstructed student
        # in CENTER. A previously lost lock requires a longer steady hold.
        recovering = self.locked_id is not None
        if recovering and not people:
            if self.empty_since is None:
                self.empty_since = now
            if now - self.empty_since >= self.CLEAR_VIEW_SECONDS:
                self.view_was_clear = True
        if recovering and not self.view_was_clear:
            self._clear_enrollment()
            return None, "lost", "Step out of view briefly, then stand alone in CENTER."
        choices = [p for p in people if self.CENTER_MIN <= p["x"] <= self.CENTER_MAX
                   and p["height"] >= self.MIN_BOX_HEIGHT]
        if not choices:
            self._clear_enrollment()
            return None, "lost" if recovering else "waiting", (
                "Stand alone in the CENTER box to reconnect." if recovering
                else "Stand inside the CENTER box so I can find you.")

        ranked = sorted(choices, key=lambda p: p["height"], reverse=True)
        if len(ranked) > 1 and ranked[0]["height"] < ranked[1]["height"] * self.DOMINANCE_RATIO:
            self._clear_enrollment()
            return None, "ambiguous", "One student at a time, please! Clear the CENTER box."

        # Recovery must be solo across the WHOLE view, not just the center;
        # a nearby bystander with a different track must not gain control.
        if recovering and len(people) != 1:
            self._clear_enrollment()
            return None, "lost", "Ask classmates to step aside while we reconnect."

        selected = ranked[0]
        person_id = int(selected["track_id"])
        if self.candidate_id != person_id:
            self.candidate_id = person_id
            self.candidate_since = now
            self.candidate_frames = 1
        else:
            self.candidate_frames += 1

        required_seconds = self.RECOVER_SECONDS if recovering else self.ENROLL_SECONDS
        required_frames = self.RECOVER_FRAMES if recovering else self.ENROLL_FRAMES
        remaining = max(0.0, required_seconds - (now - self.candidate_since))
        if remaining > 0 or self.candidate_frames < required_frames:
            instruction = ("RECONNECTING" if recovering else "FINDING PLAYER")
            return None, "lost" if recovering else "enrolling", (
                f"{instruction}: stay still in CENTER ({remaining:.1f}s)")

        self._record(selected, now)
        return selected, "locked", "PLAYER FOUND! Keep playing."

    def _clear_enrollment(self) -> None:
        self.candidate_id = None
        self.candidate_frames = 0
        self.candidate_since = 0.0
