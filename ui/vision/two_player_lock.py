"""Conservative, anonymous two-player association for a single YOLO image.

Camera pixels are analyzed once. P1 and P2 are immutable session slots, not
face-recognition identities or spatial boxes that every wrist must stay in.
The teacher associates the left/right initial slots with student profiles.
If identity becomes ambiguous, an affected controller is deactivated rather
than silently assigned to another student. No predicted skeleton is emitted.

The output x is absolute mirrored-camera torso X (0..1); Godot subtracts each
slot's separately measured neutral X to derive movement.
"""

from __future__ import annotations

import itertools
import math


class TwoPlayerLock:
    ENROLL_FRAMES = 4
    RECOVER_FRAMES = 4
    RECOVER_SECONDS = 0.45
    MAX_GAP = 0.75
    MAX_MOVEMENT_X = 0.25
    MIN_SEPARATION_X = 0.16
    MIN_HEIGHT = 0.17
    MAX_RELATIVE_HEIGHT = 1.9
    SIZE_DEVIATION = 0.42
    MIN_MATCH_MARGIN = 0.035

    def __init__(self) -> None:
        self.slots = [
            {"reference_x": None, "x": None, "height": None,
             "seen": None, "candidate_x": None, "candidate_since": None,
             "candidate_frames": 0, "ready": False},
            {"reference_x": None, "x": None, "height": None,
             "seen": None, "candidate_x": None, "candidate_since": None,
             "candidate_frames": 0, "ready": False},
        ]

    @staticmethod
    def _eligible(person: dict) -> bool:
        try:
            x = float(person["x"])
            height = float(person["height"])
            points = person["keypoints"]
            if not math.isfinite(x) or not math.isfinite(height) or not 0 <= x <= 1:
                return False
            if height < TwoPlayerLock.MIN_HEIGHT or len(points) < 13:
                return False
            torso = [points[i] for i in (5, 6, 11, 12)]
            return sum(len(p) >= 3 and float(p[2]) >= 0.45 for p in torso) >= 2
        except (KeyError, IndexError, TypeError, ValueError, OverflowError):
            return False

    @staticmethod
    def _score(slot: dict, person: dict, now: float) -> float | None:
        previous_x = slot["x"] if slot["x"] is not None else slot["reference_x"]
        previous_size = slot["height"]
        if previous_x is None or previous_size is None:
            return None
        dx = abs(float(person["x"]) - float(previous_x))
        # After a gap, do NOT grant a broad search across another player's
        # standing area; that could assign a passing stranger.
        if dx > TwoPlayerLock.MAX_MOVEMENT_X:
            return None
        ratio = float(person["height"]) / float(previous_size)
        if not 1 - TwoPlayerLock.SIZE_DEVIATION <= ratio <= 1 + TwoPlayerLock.SIZE_DEVIATION:
            return None
        return dx + abs(math.log(ratio)) * 0.09

    def _observe(self, index: int, person: dict, now: float) -> None:
        slot = self.slots[index]
        prior_seen = slot["seen"]
        gap = prior_seen is None or now - prior_seen > self.MAX_GAP
        x = float(person["x"])
        if gap or not slot["ready"]:
            if (slot["candidate_x"] is None or
                    abs(x - slot["candidate_x"]) > 0.08):
                slot["candidate_x"] = x
                slot["candidate_since"] = now
                slot["candidate_frames"] = 1
            else:
                slot["candidate_frames"] += 1
            slot["ready"] = (slot["candidate_frames"] >= self.RECOVER_FRAMES
                             and now - slot["candidate_since"] >= self.RECOVER_SECONDS)
        # A stable continuous track can move quickly; a broken one cannot
        # take over via a single matching frame.
        slot["x"] = x
        slot["height"] = float(person["height"])
        slot["seen"] = now
        if slot["reference_x"] is None:
            slot["reference_x"] = x
        if slot["ready"]:
            slot["candidate_x"] = None
            slot["candidate_since"] = None
            slot["candidate_frames"] = 0

    def update(self, people: list[dict], now: float) -> list[dict]:
        """Return two slots, each active only when clearly source-observed."""
        if not math.isfinite(now):
            raise ValueError("Invalid source timestamp")
        candidates = [p for p in people if self._eligible(p)]
        result = [{"active": False, "x": -1.0, "index": -1, "reason": "not_visible"}
                  for _ in range(2)]
        for slot in self.slots:
            if slot["seen"] is not None and now - slot["seen"] > self.MAX_GAP:
                slot["ready"] = False
                slot["candidate_x"] = None
                slot["candidate_since"] = None
                slot["candidate_frames"] = 0

        if any(slot["reference_x"] is None for slot in self.slots):
            # Do not initialize with exactly one child plus an unknown
            # spectator. Both bodies must be prominent and safely separated.
            if len(candidates) < 2:
                return result
            two = sorted(candidates, key=lambda p: float(p["height"]), reverse=True)[:2]
            if (max(float(p["height"]) for p in two) /
                    min(float(p["height"]) for p in two) > self.MAX_RELATIVE_HEIGHT
                    or abs(float(two[0]["x"]) - float(two[1]["x"])) < self.MIN_SEPARATION_X):
                return result
            two.sort(key=lambda p: float(p["x"]))
            for i, candidate in enumerate(two):
                self._observe(i, candidate, now)
                if self.slots[i]["ready"]:
                    result[i] = {"active": True, "x": self.slots[i]["x"],
                                 "index": int(candidate.get("detection_index", -1)),
                                 "reason": "locked"}
            return result

        # One-to-one assignment. Missing bodies do not cause automatic P2/P1
        # replacement; the absent slot retains its identity and neutral ref.
        costs = [[self._score(slot, p, now) for p in candidates]
                 for slot in self.slots]
        pairings = []
        for i, j in itertools.product(range(len(candidates)), repeat=2):
            if i == j or costs[0][i] is None or costs[1][j] is None:
                continue
            pairings.append((costs[0][i] + costs[1][j], i, j))
        pairings.sort()
        if pairings:
            _, left, right = pairings[0]
            if len(pairings) > 1 and pairings[1][0] - pairings[0][0] < self.MIN_MATCH_MARGIN:
                return result
            assignments = {0: left, 1: right}
        else:
            assignments = {}
            for slot_index in range(2):
                sorted_costs = sorted((score, idx) for idx, score in enumerate(costs[slot_index])
                                      if score is not None)
                if sorted_costs and (len(sorted_costs) == 1 or
                                     sorted_costs[1][0] - sorted_costs[0][0] > self.MIN_MATCH_MARGIN):
                    assignments[slot_index] = sorted_costs[0][1]
            if len(assignments) == 2 and assignments[0] == assignments[1]:
                return result

        for slot_index, detection_index in assignments.items():
            # Any comparable-size candidate overlapping the slot's location
            # makes attribution uncertain: don't control an avatar with them.
            chosen = candidates[detection_index]
            x = float(chosen["x"])
            size = float(chosen["height"])
            cluttered = any(idx != detection_index
                            and abs(float(other["x"]) - x) < 0.10
                            and 0.6 <= float(other["height"]) / size <= 1.7
                            for idx, other in enumerate(candidates))
            if cluttered:
                self.slots[slot_index]["ready"] = False
                result[slot_index]["reason"] = "ambiguous"
                continue
            self._observe(slot_index, chosen, now)
            if self.slots[slot_index]["ready"]:
                result[slot_index] = {
                    "active": True, "x": self.slots[slot_index]["x"],
                    "index": int(chosen.get("detection_index", -1)),
                    "reason": "locked",
                }
            else:
                result[slot_index]["reason"] = "recovering"
        return result
