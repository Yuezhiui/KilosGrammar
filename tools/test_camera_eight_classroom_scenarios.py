"""Eight synthetic raw-SOLO classroom acceptance scenarios.

Run without weights, image hardware, sockets, DB or OpenCV:
    py -3.11 -m unittest discover -s tools -p test_camera_eight_classroom_scenarios.py -v

Inputs stand in for the *outputs* of YOLO inference, not genuine YOLO
predictions. Bright/dim exercises high-/low-confidence keypoint packets; it
is not a scientifically valid lighting robustness or real-world FPS test.
"""

from __future__ import annotations

import math
from pathlib import Path
import sys
import unittest

VISION = Path(__file__).resolve().parents[1] / "ui" / "vision"
sys.path.insert(0, str(VISION))
from student_lock import StudentLock  # noqa: E402
from pose_worker import (  # noqa: E402
    PlaneSteeringTracker, preview_people, draw_skeleton_preview,
    resilient_body_position, stationary_plane_steering,
)


def joints(x: float, confidence: float = 0.97, *, left_wrist=True,
           right_wrist=True, torso=True) -> list[list[float]]:
    values = [[0.5, 0.5, 0.0] for _ in range(17)]
    pose = {5: (x - 0.08, 0.3), 6: (x + 0.08, 0.3),
            7: (x - 0.11, 0.43), 8: (x + 0.11, 0.43),
            9: (x - 0.13, 0.58), 10: (x + 0.13, 0.58),
            11: (x - 0.065, 0.63), 12: (x + 0.065, 0.63),
            13: (x - 0.06, 0.77), 14: (x + 0.06, 0.77),
            15: (x - 0.06, 0.91), 16: (x + 0.06, 0.91)}
    for index, (px, py) in pose.items():
        valid = (index not in (9, 10) or
                 (left_wrist if index == 9 else right_wrist))
        valid = valid and (torso or index not in (5, 6, 11, 12))
        values[index] = [px, py, confidence if valid else 0.0]
    return values


def person(track: int, x: float = 0.5, height: float = 0.62,
           confidence: float = 0.97, *, box_width=0.22, eligible=True,
           left_wrist=True, right_wrist=True, torso=True) -> dict:
    return {"track_id": track, "x": x, "height": height, "eligible": eligible,
            "keypoints": joints(x, confidence, left_wrist=left_wrist,
                                right_wrist=right_wrist, torso=torso),
            "box": ((x - box_width / 2) * 640, 80,
                    (x + box_width / 2) * 640, 80 + height * 480)}


def enroll(lock: StudentLock, track=7, *, start=0., x=0.50) -> float:
    selected = None
    now = start
    for frame in range(10):
        now = start + 0.16 * frame
        selected, _, _ = lock.update([person(track, x)], now)
    if selected is None or lock.tracking_epoch < 1:
        raise AssertionError("synthetic solo student did not pass stable pose hold")
    return now


class FakeFrame:
    shape = (480, 640, 3)


class FakeDrawing:
    def __init__(self):
        self.lines: list[tuple] = []
        self.circles: list[tuple] = []

    def resize(self, frame, _size):
        return frame

    def line(self, _frame, first, second, color, thickness):
        self.lines.append((first, second, color, thickness))

    def circle(self, _frame, xy, radius, color, thickness):
        self.circles.append((xy, radius, color, thickness))


class EightClassroomScenarios(unittest.TestCase):
    def test_01_solo_enroll_and_no_premature_control(self):
        lock = StudentLock()
        for i in range(4):
            chosen, state, _ = lock.update([person(7)], i * 0.16)
            self.assertIsNone(chosen, "shorter than 0.65s cannot enroll")
            self.assertEqual(state, "enrolling")
        chosen, state, _ = lock.update([person(99)], 0.80)
        self.assertEqual(state, "locked")
        self.assertIsNotNone(chosen)
        self.assertIsNone(lock.locked_id, "no registered ByteTrack identity")
        self.assertEqual(lock.physical_track_id, 99)  # diagnostic only
        chosen, state, _ = lock.update([person(-1, 0.70)], 0.96)
        self.assertEqual(state, "locked", "motion and missing IDs do not pause valid solo")
        self.assertIsNotNone(chosen)

    def test_02_passerby_visible_as_passive_skeleton_never_steals(self):
        lock = StudentLock()
        enroll(lock)
        for step in range(1, 10):
            background = person(55, 0.12 + step * 0.012, height=0.46,
                                box_width=0.11)
            owner = person(7, 0.5, height=0.64)
            selected, state, _ = lock.update([background, owner],
                                             1.5 + step * 0.15)
            self.assertIsNone(selected)
            self.assertEqual(state, "ambiguous", "any raw 2+ freezes all controls")
            roles = preview_people([background, owner], selected)
            self.assertEqual([p["preview_role"] for p in roles],
                             ["candidate", "candidate"])
        self.assertIsNone(lock.locked_id)

    def test_03_partial_overlap_keeps_identity_or_safely_suspends(self):
        lock = StudentLock()
        enroll(lock)
        owner = person(7, 0.5, height=0.65)
        for other in (person(9, 0.718, height=0.62),
                      person(9, 0.54, height=0.65)):
            selected, state, _ = lock.update([owner, other], 1.7)
            self.assertIsNone(selected)
            self.assertEqual(state, "ambiguous", "box separation cannot waive raw count")
        selected, state, _ = lock.update([owner], 1.9, detected_count=2)
        self.assertIsNone(selected)
        self.assertEqual(state, "ambiguous", "raw count outranks parsed candidates")
        selected, state, _ = lock.update([owner], 2.1)
        self.assertIsNone(selected)
        self.assertEqual(state, "enrolling", "solo reacquisition needs fresh hold")
        for i in range(1, 6):
            selected, state, _ = lock.update([person(400 + i)], 2.1 + i * 0.16)
        self.assertEqual(state, "locked")
        self.assertIsNotNone(selected)

    def test_04_full_occlusion_freezes_no_ghost_bones_and_safe_return(self):
        lock = StudentLock()
        enroll(lock)
        selected, state, _ = lock.update([person(7)], 1.6)
        self.assertEqual(state, "locked")
        owner_hidden = person(7, 0.50, eligible=False, torso=False,
                              left_wrist=False, right_wrist=False)
        selected, state, _ = lock.update([owner_hidden, person(88, 0.52)], 1.8)
        self.assertIsNone(selected)
        self.assertEqual(state, "ambiguous")
        roles = preview_people([owner_hidden, person(88, 0.52)], None)
        self.assertTrue(all(p["preview_role"] == "candidate" for p in roles))
        render = FakeDrawing()
        draw_skeleton_preview(render, FakeFrame(), roles)
        self.assertTrue(render.circles, "only current real keypoints draw")
        render.circles.clear()
        render.lines.clear()
        draw_skeleton_preview(render, FakeFrame(), [])
        self.assertEqual(render.circles, [])
        self.assertEqual(render.lines, [])
        for i in range(6):
            selected, state, _ = lock.update([person(88, 0.50)], 2.1 + i * 0.17)
            if i == 0:
                self.assertIsNone(selected, "first reacquisition frame cannot steer")
        self.assertEqual(state, "locked", "stable new solo may resume without identity")
        lock.update([], 3.8)
        lock.update([], 4.20)
        for i in range(6):
            selected, state, _ = lock.update([person(700 + i, 0.5)], 4.36 + 0.17 * i)
        self.assertEqual(state, "locked")
        self.assertIsNotNone(selected)

    def test_05_two_stationary_equal_people_never_enroll_spuriously(self):
        lock = StudentLock()
        for i in range(36):
            selected, state, _ = lock.update([person(7, 0.41),
                                              person(8, 0.59)], i * 0.17)
            self.assertIsNone(selected)
            self.assertEqual(state, "ambiguous")
        self.assertIsNone(lock.locked_id)

    def test_06_player_return_requires_fresh_solo_not_original_id(self):
        lock = StudentLock()
        enroll(lock)
        selected, state, _ = lock.update([], 1.65)
        self.assertEqual(state, "lost")
        self.assertIsNone(selected)
        for i in range(6):
            selected, state, _ = lock.update([person(97, 0.51)], 1.92 + i * 0.17)
            if i == 0:
                self.assertIsNone(selected)
                self.assertEqual(state, "enrolling")
        self.assertEqual(state, "locked")
        self.assertIsNotNone(selected)
        self.assertIsNone(lock.locked_id)
        selected, state, _ = lock.update([person(-1, 0.52)], 3.0)
        self.assertEqual(state, "locked", "diagnostic ID loss cannot revoke solo")
        self.assertIsNotNone(selected)
        selected, state, _ = lock.update([person(3, 0.5), person(4, 0.6)], 3.2)
        self.assertIsNone(selected)
        self.assertEqual(state, "ambiguous")
        for i in range(6):
            selected, state, _ = lock.update([person(-1, 0.5)], 3.4 + i * 0.17)
        self.assertEqual(state, "locked")
        self.assertIsNotNone(selected)

    def test_07_bright_and_dim_synthetic_keypoint_confidence(self):
        # These are NOT pixel-based synthetic inference; low confidence simply
        # models how a dim frame may be delivered by YOLO. Real lighting must
        # be tested on a device. Never turn bad keypoints into valid steering.
        bright = person(7, 0.54, confidence=0.95)
        dim = person(7, 0.54, confidence=0.22)
        self.assertAlmostEqual(resilient_body_position(bright["keypoints"]), 0.54)
        self.assertAlmostEqual(stationary_plane_steering(bright["keypoints"]), 0.54)
        self.assertIsNone(resilient_body_position(dim["keypoints"]))
        self.assertIsNone(stationary_plane_steering(dim["keypoints"]))
        self.assertAlmostEqual(stationary_plane_steering(
            person(7, 0.54, left_wrist=False)["keypoints"]), 0.54)
        self.assertIsNone(stationary_plane_steering(
            person(7, 0.54, left_wrist=False, right_wrist=False)["keypoints"]))
        frame = FakeFrame()
        for candidate, expected_draw in ((bright, True), (dim, False)):
            painter = FakeDrawing()
            draw_skeleton_preview(painter, frame, preview_people([candidate], candidate))
            self.assertEqual(bool(painter.circles), expected_draw)

    def test_08_repeated_rounds_clear_old_controller_and_stale_steering(self):
        lock = StudentLock()
        tracker = PlaneSteeringTracker()
        for round_index in range(5):
            if round_index:
                lock = StudentLock()
                self.assertIsNone(tracker.update(None, None, 100 + round_index))
            start = 10 * round_index
            for i in range(6):
                chosen, state, _ = lock.update([person(-1 if i % 2 else 7 + i, 0.5)],
                                               start + i * 0.16)
                if i == 0:
                    self.assertIsNone(chosen)
            self.assertEqual(state, "locked")
            self.assertIsNotNone(chosen)
            self.assertIsNone(lock.locked_id)
            self.assertIsNone(tracker.update(None, None, start + 2.0))
            self.assertIsNone(tracker.update(1, 0.50, start + 2.16))
            self.assertAlmostEqual(tracker.update(1, 0.50, start + 2.32), 0.5)
            self.assertIsNone(tracker.update(None, None, start + 2.48))
            self.assertIsNone(lock.update([], start + 3.0)[0])
            self.assertIsNone(lock.update([person(97)], start + 3.16)[0])
        lock.require_clear_reenrollment()
        self.assertIsNone(lock.update([person(-1, 0.5)], 60)[0])


if __name__ == "__main__":
    unittest.main()
