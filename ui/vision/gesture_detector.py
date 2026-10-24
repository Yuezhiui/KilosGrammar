"""Camera-independent COCO-17 gesture detection for a single locked student.

All distances are relative to the student's measured shoulder width or torso
height, so changing the student's distance from the camera does not change
the intended gesture. The caller supplies monotonic timestamps for testability.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Sequence


MIN_CONFIDENCE = 0.45


@dataclass(frozen=True)
class GestureState:
    hand_up: bool = False
    airplane_pose: bool = False
    left_hand_up: bool = False
    right_hand_up: bool = False
    # False means the hand signal is unknown, NOT deliberately lowered.
    # A missing/occluded wrist must not re-arm a Balloon Popping shot.
    hand_observation_valid: bool = False
    # Legacy optional banking diagnostic (-1..1). Human Plane now moves
    # horizontally using torso position while airplane_pose gates movement.
    wing_roll: float = 0.0


@dataclass(frozen=True)
class _Measurements:
    left_rise: bool | None = None
    left_hold: bool | None = None
    right_rise: bool | None = None
    right_hold: bool | None = None
    plane_rise: bool = False
    plane_hold: bool = False
    wing_roll: float = 0.0


def _joint(points: Sequence[Sequence[float]], index: int) -> tuple[float, float] | None:
    if index >= len(points) or len(points[index]) < 3:
        return None
    try:
        x, y, confidence = (float(v) for v in points[index][:3])
    except (ValueError, TypeError, OverflowError):
        return None
    if not all(math.isfinite(v) for v in (x, y, confidence)):
        return None
    if confidence < MIN_CONFIDENCE or not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
        return None
    return x, y


def _measure(points: Sequence[Sequence[float]]) -> _Measurements:
    shoulders = (_joint(points, 5), _joint(points, 6))
    elbows = (_joint(points, 7), _joint(points, 8))
    wrists = (_joint(points, 9), _joint(points, 10))
    hips = (_joint(points, 11), _joint(points, 12))

    shoulder_width = (abs(shoulders[1][0] - shoulders[0][0])
                      if shoulders[0] is not None and shoulders[1] is not None else 0.0)
    torso = shoulder_width * 1.25
    if all(p is not None for p in (*shoulders, *hips)):
        measured_torso = (hips[0][1] + hips[1][1] - shoulders[0][1] - shoulders[1][1]) * 0.5
        if 0.12 <= measured_torso <= 0.70:
            torso = measured_torso
    torso = max(0.14, min(torso, 0.46))

    on_height = max(0.06, 0.24 * torso)
    keep_height = max(0.02, 0.08 * torso)
    hand = []
    for shoulder, wrist in zip(shoulders, wrists):
        if shoulder is None or wrist is None:
            hand.append((None, None))
        else:
            height = shoulder[1] - wrist[1]
            hand.append((height >= on_height, height >= keep_height))

    plane_on = plane_keep = False
    if shoulder_width >= 0.065 and all(p is not None for p in (*shoulders, *elbows, *wrists)):
        # Anatomical left/right is independent of the mirrored camera image.
        left_direction = -1 if shoulders[0][0] < shoulders[1][0] else 1
        def side_extended(side: int, keep: bool) -> bool:
            shoulder = shoulders[side]
            elbow = elbows[side]
            wrist = wrists[side]
            direction = left_direction if side == 0 else -left_direction
            elbow_out = direction * (elbow[0] - shoulder[0]) / shoulder_width
            wrist_out = direction * (wrist[0] - shoulder[0]) / shoulder_width
            wrist_after_elbow = direction * (wrist[0] - elbow[0]) / shoulder_width
            if keep:
                # Slight elbow/wrist drift is fine while already extended,
                # but hands near waist level must immediately close the flight
                # permission gate. Movement itself comes from torso X.
                return (elbow_out >= 0.10 and wrist_out >= 0.53
                        and wrist_after_elbow >= 0.10
                        and abs(elbow[1] - shoulder[1]) <= torso * 0.58
                        and abs(wrist[1] - shoulder[1]) <= torso * 0.65)
            return (elbow_out >= 0.22 and wrist_out >= 0.70
                    and wrist_after_elbow >= 0.22
                    and abs(elbow[1] - shoulder[1]) <= torso * 0.45
                    and abs(wrist[1] - shoulder[1]) <= torso * 0.50)

        plane_on = side_extended(0, False) and side_extended(1, False)
        plane_keep = side_extended(0, True) and side_extended(1, True)

    roll = 0.0
    if plane_keep:
        # Keep the old wing-roll diagnostic for protocol compatibility. The
        # live worker mirrors the selfie camera BEFORE YOLO inference, so the
        # optional signed value uses visible screen-left/right shoulder X.
        # It does not determine horizontal movement in Human Plane.
        screen_left = 0 if shoulders[0][0] < shoulders[1][0] else 1
        screen_right = 1 - screen_left
        left_drop = wrists[screen_left][1] - shoulders[screen_left][1]
        right_drop = wrists[screen_right][1] - shoulders[screen_right][1]
        signed = (right_drop - left_drop) / max(torso * 1.10, 0.1)
        # A level, slightly shaky pair of arms must not drift the airplane.
        magnitude = abs(signed)
        if magnitude > 0.10:
            roll = math.copysign(min((magnitude - 0.10) / 0.65, 1.0), signed)

    return _Measurements(hand[0][0], hand[0][1], hand[1][0], hand[1][1],
                         plane_on, plane_keep, roll)


class _DebouncedFlag:
    def __init__(self, rise_seconds: float, fall_seconds: float):
        self.rise_seconds = rise_seconds
        self.fall_seconds = fall_seconds
        self.active = False
        self._candidate_since: float | None = None
        self._candidate_value: bool | None = None

    def reset(self) -> None:
        self.active = False
        self._candidate_since = None
        self._candidate_value = None

    @property
    def rising(self) -> bool:
        return self._candidate_value is True

    def update(self, rise: bool, keep: bool, now: float) -> bool:
        desired = keep if self.active else rise
        if desired == self.active:
            self._candidate_since = None
            self._candidate_value = None
        else:
            if self._candidate_value != desired:
                self._candidate_since = now
                self._candidate_value = desired
            delay = self.fall_seconds if self.active else self.rise_seconds
            if now - self._candidate_since >= delay:
                self.active = desired
                self._candidate_since = None
                self._candidate_value = None
        return self.active


class GestureDetector:
    """Debounced gesture state, with a held-hand latch across tracking gaps.

    A raised hand must be visibly lowered before shooting can be rearmed after
    losing its pose. Airplane movement permission instead resumes automatically
    when both arms are confidently extended again; torso X determines direction.
    No movement or firing signal is exposed on an invalid/unselected frame.
    """

    def __init__(self, rise_seconds: float = 0.10, fall_seconds: float = 0.12):
        self._hand = _DebouncedFlag(rise_seconds, fall_seconds)
        self._plane = _DebouncedFlag(rise_seconds, fall_seconds)
        self._require_hand_release = False
        self._release_since: float | None = None
        self._last_track_id: int | None = None
        self._last_time: float | None = None

    def update(self, keypoints: Sequence[Sequence[float]] | None,
               now: float, track_id: int | None = None) -> GestureState:
        if not math.isfinite(now):
            raise ValueError("Gesture timestamps must be finite")
        # Restart a pending debounce after a timebase reset; no negative age.
        if self._last_time is not None and (now < self._last_time or now - self._last_time > 1.75):
            self._missing()
        self._last_time = now

        if keypoints is None:
            self._missing()
            return GestureState()

        if track_id is not None:
            if self._last_track_id is not None and track_id != self._last_track_id:
                self._missing()
                self._require_hand_release = True
            self._last_track_id = track_id

        measured = _measure(keypoints)
        left_valid = measured.left_rise is not None
        right_valid = measured.right_rise is not None
        hand_rise = measured.left_rise is True or measured.right_rise is True
        hand_keep = measured.left_hold is True or measured.right_hold is True
        # One good wrist can prove an up gesture; only TWO good, lowered wrists
        # can prove the student has released the gesture.
        known = hand_rise or hand_keep or (left_valid and right_valid)
        if not known:
            self._missing_hand()

        # The internal debounce limits false activations and reactivation
        # chatter. The public gate closes immediately when even one required
        # elbow/wrist is down or unobserved, without waiting for fall debounce.
        airplane = (self._plane.update(measured.plane_rise, measured.plane_hold, now)
                    and measured.plane_hold)

        if self._require_hand_release:
            if left_valid and right_valid and not hand_keep:
                if self._release_since is None:
                    self._release_since = now
                if now - self._release_since >= self._hand.fall_seconds:
                    self._require_hand_release = False
                    self._release_since = None
            else:
                self._release_since = None
            # Only a confirmed, fully observed release can reach Godot as
            # "hands lowered". Suppressed high poses are not down events.
            return GestureState(airplane_pose=airplane,
                                wing_roll=measured.wing_roll if airplane else 0.0,
                                hand_observation_valid=not self._require_hand_release)

        if not known:
            return GestureState(airplane_pose=airplane,
                                wing_roll=measured.wing_roll if airplane else 0.0)

        active = self._hand.update(hand_rise, hand_keep, now)
        return GestureState(
            hand_up=active, airplane_pose=airplane,
            left_hand_up=active and measured.left_hold is True,
            right_hand_up=active and measured.right_hold is True,
            hand_observation_valid=True,
            wing_roll=measured.wing_roll if airplane else 0.0,
        )

    def _missing_hand(self) -> None:
        # A pending raise has not fired yet: losing one observation should
        # allow a later stable raise, without forcing a release first.
        # A confirmed held raise HAS already fired and must remain latched.
        if self._hand.active:
            self._require_hand_release = True
        self._hand.reset()
        self._release_since = None

    def _missing(self) -> None:
        self._missing_hand()
        self._plane.reset()
