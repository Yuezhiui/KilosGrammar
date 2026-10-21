"""Session-only lock onto the one classroom player enrolled at CENTER.

This is deliberately NOT face recognition or biometric identification.
It relies on YOLO/ByteTrack's temporary video track IDs. If the track
disappears or appears to jump to a different person, gameplay freezes
until a teacher/player explicitly resets the camera session.
"""

from __future__ import annotations


class StudentLock:
    ENROLL_SECONDS = 1.2
    ENROLL_FRAMES = 8
    MIN_BOX_HEIGHT = 0.20
    CENTER_MIN = 0.28
    CENTER_MAX = 0.72
    DOMINANCE_RATIO = 1.45
    MAX_LOST_SECONDS = 0.8
    MAX_DELTA_X = 0.18
    MAX_SIZE_RATIO = 1.9

    def __init__(self) -> None:
        self.locked_id: int | None = None
        self.candidate_id: int | None = None
        self.candidate_since = 0.0
        self.candidate_frames = 0
        self.lost_since: float | None = None
        self.blocked = False
        self.previous_x: float | None = None
        self.previous_height: float | None = None
        self.previous_seen = 0.0

    def update(self, people: list[dict], now: float) -> tuple[dict | None, str, str]:
        """Return selected person, lock state and a user-facing instruction.

        People must be already filtered for confident torso keypoints and
        carry track_id, x, and normalized bbox height. No silent reassignment
        to another person is permitted once locked.
        """
        if self.blocked:
            return None, "lost", "PLAYER LOCK LOST. Choose RESET PLAYER to enroll again."

        if self.locked_id is not None:
            target = next((p for p in people if p["track_id"] == self.locked_id), None)
            if target is None:
                if self.lost_since is None:
                    self.lost_since = now
                if now - self.lost_since > self.MAX_LOST_SECONDS:
                    self.blocked = True
                    return None, "lost", "PLAYER LOCK LOST. Choose RESET PLAYER to enroll again."
                return None, "occluded", "Player temporarily obscured; controls paused."
            if self.lost_since is not None and now - self.lost_since > self.MAX_LOST_SECONDS:
                self.blocked = True
                return None, "lost", "Player tracking timed out. Choose RESET PLAYER."
            height = float(target["height"])
            x = float(target["x"])
            elapsed = max(now - self.previous_seen, 0.0)
            # A sudden position or apparent-distance jump can indicate that
            # the tracker assigned the player's ID to somebody else.
            if self.previous_x is not None and abs(x - self.previous_x) > self.MAX_DELTA_X + elapsed * 0.25:
                self.blocked = True
                return None, "lost", "Unexpected player swap detected. Choose RESET PLAYER."
            if self.previous_height is not None and self.previous_height > 0.0:
                ratio = height / self.previous_height
                if ratio < 1.0 / self.MAX_SIZE_RATIO or ratio > self.MAX_SIZE_RATIO:
                    self.blocked = True
                    return None, "lost", "Player changed unexpectedly. Choose RESET PLAYER."
            self.lost_since = None
            self.previous_x = x
            self.previous_height = height
            self.previous_seen = now
            return target, "locked", f"PLAYER LOCKED (#{self.locked_id}) - other people ignored"

        choices = [
            person for person in people
            if self.CENTER_MIN <= person["x"] <= self.CENTER_MAX
            and person["height"] >= self.MIN_BOX_HEIGHT
        ]
        if not choices:
            self._clear_enrollment()
            return None, "waiting", "Stand near the camera inside the CENTER box to enroll."
        ranked = sorted(choices, key=lambda p: p["height"], reverse=True)
        # If similarly sized classmates overlap in the center zone, do not
        # arbitrarily select one of them.
        if len(ranked) > 1 and ranked[0]["height"] < ranked[1]["height"] * self.DOMINANCE_RATIO:
            self._clear_enrollment()
            return None, "ambiguous", "Two players in CENTER. Move the player closer or clear the box."

        selected = ranked[0]
        person_id = int(selected["track_id"])
        if self.candidate_id != person_id:
            self.candidate_id = person_id
            self.candidate_since = now
            self.candidate_frames = 1
        else:
            self.candidate_frames += 1
        if now - self.candidate_since < self.ENROLL_SECONDS or self.candidate_frames < self.ENROLL_FRAMES:
            remaining = max(0.0, self.ENROLL_SECONDS - (now - self.candidate_since))
            return None, "enrolling", f"LOCKING PLAYER: stand still in CENTER ({remaining:.1f}s)"

        self.locked_id = person_id
        self.previous_x = float(selected["x"])
        self.previous_height = float(selected["height"])
        self.previous_seen = now
        self.lost_since = None
        return selected, "locked", f"PLAYER LOCKED (#{person_id}) - other people ignored"

    def _clear_enrollment(self) -> None:
        self.candidate_id = None
        self.candidate_frames = 0
        self.candidate_since = 0.0
