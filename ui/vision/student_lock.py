"""Conservative foreground-student, fresh-pose gate for the classroom webcam.

ByteTrack ID is ONLY a diagnostic. It cannot authenticate a child, and is not
used to select, enroll, stop, resume, or bind calibration. During a round:

* NO person: no controller, pause until a fresh solo hold.
* A clearly smaller, separated background spectator may remain visible without
  entering the foreground count. Other two-person views suspend controls.
* EXACTLY ONE foreground body: allow controls after a fresh, stable hold.
* A spectator already identified as background cannot take control when the
  foreground player leaves, even if that spectator stays in the picture.

Apparent box size is an image heuristic, NOT measured camera distance or human
identity. A completely empty view cannot prove who later returned; the teacher
must verify the student if identity matters.
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
    # Conservative image-space proportions; these are NEVER metric meters.
    MIN_FOREGROUND_HEIGHT = 0.32
    MAX_BACKGROUND_HEIGHT_RATIO = 0.48
    MAX_BACKGROUND_OVERLAP = 0.08
    MAX_BACKGROUND_MATCH_X = 0.18
    MAX_BACKGROUND_MATCH_HEIGHT_RATIO = 1.45
    REPLACEMENT_MIN_HEIGHT_RATIO = 0.55
    REPLACEMENT_MAX_HEIGHT_RATIO = 1.8

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
        # Current, source-frame-only worker protocol. `raw_people` is truthful
        # YOLO occupancy; `foreground_people` excludes proven far spectators.
        self.raw_people = -1
        self.foreground_people = -1
        self.foreground_ambiguous = True
        self.foreground_candidate: dict | None = None
        self.reference_height: float | None = None
        self.background_observations: list[tuple[float, float]] = []
        self.background_only_latched = False
        # Generation is evidence of a new foreground enrollment, never a
        # biometric identity guarantee. Stable across ordinary occlusions.
        self.player_lock_epoch = 0

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

    @staticmethod
    def _box(person: dict) -> tuple[float, float, float, float] | None:
        """Validate actual source-pixel rectangles, never invent geometry."""
        try:
            coords = person["box"]
            if len(coords) != 4:
                return None
            x1, y1, x2, y2 = (float(v) for v in coords)
            if not all(math.isfinite(v) for v in (x1, y1, x2, y2)):
                return None
            if x2 <= x1 or y2 <= y1:
                return None
            return x1, y1, x2, y2
        except (KeyError, ValueError, TypeError, OverflowError):
            return None

    @staticmethod
    def _height(person: dict) -> float:
        try:
            value = float(person["height"])
            return value if math.isfinite(value) and value > 0 else 0.
        except (KeyError, ValueError, TypeError, OverflowError):
            return 0.

    @staticmethod
    def _small_box_overlap(a: tuple[float, float, float, float],
                           b: tuple[float, float, float, float]) -> float:
        x = max(0., min(a[2], b[2]) - max(a[0], b[0]))
        y = max(0., min(a[3], b[3]) - max(a[1], b[1]))
        smaller = min((a[2] - a[0]) * (a[3] - a[1]),
                      (b[2] - b[0]) * (b[3] - b[1]))
        return x * y / smaller if smaller > 0 else 1.

    def _looks_like_background(self, person: dict) -> bool:
        """Guard a previously observed spectator after the player disappears."""
        if self.reference_height is None:
            return False
        try:
            height, x = float(person["height"]), float(person["x"])
        except (KeyError, TypeError, ValueError, OverflowError):
            return True
        if not math.isfinite(height) or not math.isfinite(x):
            return True
        if any(abs(x - last_x) <= self.MAX_BACKGROUND_MATCH_X
               and 1 / self.MAX_BACKGROUND_MATCH_HEIGHT_RATIO
               <= height / old_height <= self.MAX_BACKGROUND_MATCH_HEIGHT_RATIO
               for last_x, old_height in self.background_observations
               if old_height > 0):
            return True
        # A crouching student can briefly shrink its YOLO box. Require both
        # strong shrinkage AND a spatial break before treating it as background.
        return (height < self.reference_height * self.MAX_BACKGROUND_HEIGHT_RATIO
                and self.previous_x is not None
                and abs(x - self.previous_x) > self.MAX_BACKGROUND_MATCH_X)

    def _classify(self, people: list[dict], count: int) -> tuple[dict | None, int, bool]:
        """Separate a dominant student only when EVERY other box is safely far.

        The method fails closed if boxes are malformed or candidate sizes are
        comparable. It never uses a tracker ID or assumes physical meters.
        """
        if count != len(people) or count < 0:
            return None, max(count, 0), True
        if count == 0:
            return None, 0, False
        if count == 1:
            single = people[0]
            if self.background_only_latched:
                return None, 0, False
            if (self.reference_height is not None
                    and self.background_observations
                    and self._looks_like_background(single)):
                self.background_only_latched = True
                return None, 0, False
            if self._height(single) < self.MIN_FOREGROUND_HEIGHT:
                return None, 0, False
            return single, 1, False

        if any(self._box(person) is None for person in people):
            return None, count, True
        ordered = sorted(people, key=self._height, reverse=True)
        dominant = ordered[0]
        major_height = self._height(dominant)
        if major_height < self.MIN_FOREGROUND_HEIGHT:
            return None, count, True
        if (self.previous_seen is not None and not self.needs_reenrollment
                and self.previous_height is not None
                and major_height > self.previous_height * 1.55
                and any(self.previous_height / 1.38 <= self._height(other)
                        <= self.previous_height * 1.38 for other in ordered[1:])):
            # The previous foreground is still visible when a much larger
            # person arrives: never quietly switch the controller.
            return None, count, True
        major_box = self._box(dominant)
        background: list[tuple[float, float]] = []
        for other in ordered[1:]:
            try:
                height, x = float(other["height"]), float(other["x"])
            except (KeyError, TypeError, ValueError, OverflowError):
                return None, count, True
            if (not math.isfinite(height) or not math.isfinite(x)
                    or height <= 0 or height / major_height > self.MAX_BACKGROUND_HEIGHT_RATIO
                    or self._small_box_overlap(major_box, self._box(other))
                    > self.MAX_BACKGROUND_OVERLAP):
                return None, count, True
            background.append((x, height))
        self.background_observations = background
        self.background_only_latched = False
        return dominant, 1, False

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
        self.raw_people = count
        self.foreground_candidate = None
        self.foreground_people = -1
        self.foreground_ambiguous = True
        if count < 0:
            self._suspend(now)
            return None, "ambiguous", "Camera detection unavailable. Wait for a fresh frame."
        if count == 0:
            self.foreground_people = 0
            self.foreground_ambiguous = False
            # A briefly missed background YOLO box must not erase proof that
            # the remaining spectator was previously a passive background.
            # A fresh camera worker/new physical calibration creates a new
            # StudentLock instance; this round's known spectators remain known.
            self._suspend(now)
            self.view_was_clear = True
            if self.empty_since is None:
                self.empty_since = now
            return None, "lost", "Come back into the camera view. Your round is paused."
        self.empty_since = None
        self.view_was_clear = False
        single, foreground_count, ambiguous = self._classify(people, count)
        self.foreground_people = foreground_count
        self.foreground_ambiguous = ambiguous
        self.foreground_candidate = single
        if ambiguous:
            self._suspend(now)
            return None, "ambiguous", "Nearby or overlapping people detected. One student at a time."

        if single is None:
            if count == 1 and not self.background_observations \
                    and not self.background_only_latched:
                # A sole too-small/invalid box is an unusable foreground
                # observation; keep the original "occluded" diagnostic.
                self._temporarily_unusable_torso(now)
                return None, "occluded", "Move closer and show your torso clearly."
            self._suspend(now)
            return None, "lost", "Foreground student missing. Come back into the camera view."

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
        if recovered and self.reference_height is not None:
            # A radically different apparent silhouette after a suspended
            # enrollment suggests possible substitution. Consumers can then
            # demand fresh teacher verification; this is image-space evidence.
            ratio = self._height(single) / self.reference_height
            if (ratio < self.REPLACEMENT_MIN_HEIGHT_RATIO
                    or ratio > self.REPLACEMENT_MAX_HEIGHT_RATIO):
                self.player_lock_epoch += 1
        self._record(single, now)
        if not recovered:
            self.tracking_epoch = 1
            self.player_lock_epoch = 1
            self.reference_height = float(single["height"])
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
