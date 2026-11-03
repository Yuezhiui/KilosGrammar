"""Safe anonymous two-zone spatial controller for ONE shared YOLO frame.

P1 is the left image zone and P2 the right; never infer a face/track identity.
One moving body may enroll each zone in succession, but the center deadband
disarms the first controller before the second can begin its stable hold.
No predicted or previously seen detection is ever emitted as active. Student
identity beyond spatial placement needs the teacher's verification.
"""
from __future__ import annotations

import math


class TwoPlayerLock:
    # Match Godot's sequential calibration target x<=.45 and x>=.55.
    # The narrow (0.49,0.51) keep gap still prevents dual authority.
    LEFT_ENTER = 0.45
    RIGHT_ENTER = 0.55
    LEFT_KEEP = 0.49
    RIGHT_KEEP = 0.51
    MIN_SEPARATION = 0.16
    MIN_HEIGHT = 0.17
    MIN_PROMINENCE = 0.52
    ENROLL_SECONDS = 0.60
    RECOVER_SECONDS = 0.45
    HOLD_FRAMES = 4
    MAX_GAP = 0.75
    MAX_STABLE_X = 0.095
    MAX_STABLE_HEIGHT_RATIO = 1.38
    MAX_CONTINUOUS_X = 0.23

    def __init__(self):
        self.slots = [self._new_slot(), self._new_slot()]
        self.last_frame_at = None
        self.ever_simultaneous = False
        # After two enrolled students cross/merge in the same frame, spatial
        # evidence alone cannot tell which Student ID returned to which side.
        # Hold both inactive until a teacher deliberately starts a NEW session.
        self.requires_teacher_recalibration = False

    def reset_for_teacher_calibration(self):
        """Explicit teacher action only; NEVER called on a tracking timeout."""
        self.slots = [self._new_slot(), self._new_slot()]
        self.last_frame_at = None
        self.ever_simultaneous = False
        self.requires_teacher_recalibration = False

    def _latch_teacher_recalibration(self):
        self.requires_teacher_recalibration = True
        for index in (0, 1):
            self._suspend(index)
        return [self._off(i, "teacher_recalibration_required", s["enrolled"])
                for i, s in enumerate(self.slots)]

    @staticmethod
    def _new_slot():
        return dict(enrolled=False, reference_x=None, x=None, height=None,
                    seen=None, ready=False, candidate_x=None,
                    candidate_height=None, candidate_since=None,
                    candidate_last=None, candidate_frames=0)

    @staticmethod
    def _position(person):
        try:
            x, h = float(person["x"]), float(person["height"])
            if not all(map(math.isfinite, (x, h))) or not (0 <= x <= 1) or h < 0.17:
                return None
            return x, h
        except (KeyError, ValueError, TypeError, OverflowError):
            return None

    @classmethod
    def _eligible(cls, person):
        if not isinstance(person, dict) or person.get("eligible", True) is False:
            return False
        if cls._position(person) is None:
            return False
        try:
            points = person["keypoints"]
            if len(points) < 13:
                return False
            count = 0
            for i in (5, 6, 11, 12):
                joint = points[i]
                if (len(joint) >= 3 and all(math.isfinite(float(t)) for t in joint[:3])
                        and float(joint[2]) >= 0.45):
                    count += 1
            return count >= 2
        except (KeyError, IndexError, TypeError, ValueError, OverflowError):
            return False

    @classmethod
    def _in_zone(cls, index, x, keep=False):
        return x <= (cls.LEFT_KEEP if keep else cls.LEFT_ENTER) if index == 0 else (
            x >= (cls.RIGHT_KEEP if keep else cls.RIGHT_ENTER))

    @staticmethod
    def _clear_candidate(slot):
        slot.update(candidate_x=None, candidate_height=None,
                    candidate_since=None, candidate_last=None, candidate_frames=0)

    def _suspend(self, index):
        slot = self.slots[index]
        slot["ready"] = False
        self._clear_candidate(slot)

    def _observe(self, index, person, now):
        slot = self.slots[index]
        x, height = self._position(person)
        prior = slot["seen"]
        interrupted = (prior is None or now - prior > self.MAX_GAP
                       or (slot["x"] is not None and abs(x - slot["x"]) > self.MAX_CONTINUOUS_X)
                       or (slot["height"] is not None and not 0.58 <= height / slot["height"] <= 1.48))
        if interrupted:
            self._suspend(index)
        if not slot["ready"]:
            steady = (
                slot["candidate_x"] is not None and slot["candidate_last"] is not None
                and 0 <= now - slot["candidate_last"] <= self.MAX_GAP
                and abs(x - slot["candidate_x"]) <= self.MAX_STABLE_X
                and 1 / self.MAX_STABLE_HEIGHT_RATIO
                <= height / slot["candidate_height"] <= self.MAX_STABLE_HEIGHT_RATIO)
            if not steady:
                slot.update(candidate_x=x, candidate_height=height,
                            candidate_since=now, candidate_frames=1)
            else:
                slot["candidate_frames"] += 1
            slot["candidate_last"] = now
            duration = self.RECOVER_SECONDS if slot["enrolled"] else self.ENROLL_SECONDS
            if (slot["candidate_frames"] >= self.HOLD_FRAMES
                    and now - slot["candidate_since"] >= duration):
                slot["ready"] = True
                if not slot["enrolled"]:
                    slot["reference_x"] = x
                    slot["enrolled"] = True
                self._clear_candidate(slot)
        slot.update(x=x, height=height, seen=now)
        return slot["ready"]

    @staticmethod
    def _off(index, reason, enrolled):
        return dict(slot=index, active=False, x=-1.0, index=-1,
                    enrolled=enrolled, reason=reason)

    def update(self, people, now):
        """One-to-one fresh detection binding; inactive slots have no live index."""
        if not math.isfinite(now):
            raise ValueError("Invalid source timestamp")
        if self.requires_teacher_recalibration:
            return [self._off(i, "teacher_recalibration_required", s["enrolled"])
                    for i, s in enumerate(self.slots)]
        if self.last_frame_at is not None and now <= self.last_frame_at:
            return [self._off(i, "stale_frame", s["enrolled"])
                    for i, s in enumerate(self.slots)]
        self.last_frame_at = now
        out = [self._off(i, "not_visible", s["enrolled"])
               for i, s in enumerate(self.slots)]
        observed = [p for p in people
                    if isinstance(p, dict) and self._position(p) is not None]
        both_enrolled = all(slot["enrolled"] for slot in self.slots)
        if not observed:
            if (both_enrolled and self.ever_simultaneous and all(
                    slot["seen"] is not None and now - slot["seen"] > self.MAX_GAP
                    for slot in self.slots)):
                # Both student identities vanished together for long enough
                # that an entirely different pair could have entered view.
                return self._latch_teacher_recalibration()
            for i, slot in enumerate(self.slots):
                if slot["seen"] is None or now - slot["seen"] > self.MAX_GAP:
                    self._suspend(i)
            return out
        tallest = max(float(p["height"]) for p in observed)
        # A small far spectator is ignored; a comparable third body is unsafe.
        prominent = [p for p in observed
                     if float(p["height"]) >= tallest * self.MIN_PROMINENCE]
        if both_enrolled and len(prominent) == 2:
            xs = [float(p["x"]) for p in prominent]
            # One person can freely change zones when alone. With TWO
            # comparable bodies in view, center crossing/merged ownership,
            # disappearance of both owners, or both in one side means two
            # Student IDs can no longer be attributed reliably.
            at_center = any(0.47 <= x <= 0.53 for x in xs)
            same_zone = (all(x <= self.LEFT_ENTER for x in xs)
                         or all(x >= self.RIGHT_ENTER for x in xs))
            both_stale = self.ever_simultaneous and all(
                s["seen"] is not None and now - s["seen"] > self.MAX_GAP
                for s in self.slots)
            if (at_center or same_zone or both_stale
                    or abs(xs[0] - xs[1]) < self.MIN_SEPARATION):
                return self._latch_teacher_recalibration()
        if len(prominent) > 2:
            for i in range(2):
                self._suspend(i)
                out[i]["reason"] = "spectator_ambiguous"
            return out
        if (len(prominent) == 2
                and abs(float(prominent[0]["x"]) - float(prominent[1]["x"]))
                < self.MIN_SEPARATION):
            for i in range(2):
                self._suspend(i)
                out[i]["reason"] = "crossing_ambiguous"
            return out

        used = set()
        for i, slot in enumerate(self.slots):
            keep = (slot["ready"] and slot["seen"] is not None
                    and now - slot["seen"] <= self.MAX_GAP)
            occupants = [p for p in prominent
                         if self._in_zone(i, float(p["x"]), keep)]
            if len(occupants) != 1:
                # Absence makes this frame inactive but a short dropout does
                # not erase the last genuine hold. A crossing through center,
                # however, requires a new stable hold on returning.
                if len(occupants) > 1 or any(
                        self._in_zone(i, float(p["x"]), keep=True) for p in prominent):
                    self._suspend(i)
                elif slot["seen"] is None or now - slot["seen"] > self.MAX_GAP:
                    self._suspend(i)
                out[i]["reason"] = "ambiguous" if len(occupants) > 1 else "not_visible"
                continue
            person = occupants[0]
            if not self._eligible(person):
                self._suspend(i)
                out[i]["reason"] = "untrusted_pose"
                continue
            source_index = int(person.get("detection_index", -1))
            if source_index < 0 or source_index in used:
                self._suspend(i)
                out[i]["reason"] = "invalid_detection"
                continue
            ready = self._observe(i, person, now)
            used.add(source_index)
            out[i] = dict(slot=i, active=ready, x=float(person["x"]) if ready else -1.0,
                          index=source_index if ready else -1,
                          enrolled=slot["enrolled"],
                          reason="locked" if ready else "holding")
        if all(entry["active"] for entry in out):
            self.ever_simultaneous = True
        return out
