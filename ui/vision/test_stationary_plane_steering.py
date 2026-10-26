"""Offline Human Plane movement, joint confidence, and student-lock stress QA.

Run: python -m unittest ui/vision/test_stationary_plane_steering.py
No webcam, model, database, or production pose packets are generated.
"""

from __future__ import annotations

import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pose_worker import PlaneSteeringTracker, stationary_plane_steering
from student_lock import StudentLock


def joints(x: float = 0.5, bank: float = 0.0):
    """One student; actual camera torso X changes independently of hand heights."""
    points = [[x, 0.45, 0.98] for _ in range(17)]
    points[5] = [x - 0.10, 0.32, 0.98]
    points[6] = [x + 0.10, 0.32, 0.98]
    points[7] = [x - 0.14, 0.46, 0.98]
    points[8] = [x + 0.14, 0.46, 0.98]
    points[9] = [x - 0.14, 0.58 - bank, 0.98]
    points[10] = [x + 0.14, 0.58 + bank, 0.98]
    points[11] = [x - 0.07, 0.62, 0.98]
    points[12] = [x + 0.07, 0.62, 0.98]
    return points


def person(identifier: int, x: float):
    return {"track_id": identifier, "x": x, "height": 0.62}


class StationarySteeringTests(unittest.TestCase):
    def test_camera_mirror_sign_and_center_lane(self):
        right = joints(0.72)
        left = copy.deepcopy(right)
        for point in left:
            point[0] = 1.0 - point[0]
        self.assertAlmostEqual(stationary_plane_steering(joints(0.50)), 0.50)
        self.assertAlmostEqual(stationary_plane_steering(right), 0.72)
        self.assertAlmostEqual(stationary_plane_steering(left), 0.28)
        # Camera is flipped BEFORE inference; greater X means screen right.
        self.assertGreater(stationary_plane_steering(right), 0.50)
        self.assertLess(stationary_plane_steering(left), 0.50)

    def test_one_wrist_each_side_matches_both_wrists(self):
        for x, absent in ((0.30, 9), (0.70, 10), (0.30, 10), (0.70, 9)):
            with self.subTest(x=x, absent=absent):
                pose = joints(x)
                both = stationary_plane_steering(pose)
                pose[absent][2] = 0.05
                self.assertAlmostEqual(stationary_plane_steering(pose), both)
        # The hands may be relaxed rather than spread in a T-pose.
        self.assertAlmostEqual(stationary_plane_steering(joints(0.5, 0.09)), 0.5)
        self.assertAlmostEqual(stationary_plane_steering(joints(0.5, -0.09)), 0.5)

    def test_missing_and_low_confidence_keypoints_freeze(self):
        for missing in ((9, 10), (5, 6, 11, 12)):
            pose = joints(0.70)
            for index in missing:
                pose[index][2] = 0.05
            self.assertIsNone(stationary_plane_steering(pose))
        pose = joints(0.70)
        pose[5][2] = pose[6][2] = 0.05
        self.assertAlmostEqual(stationary_plane_steering(pose), 0.70,
                               msg="visible hips + one wrist can steer with hidden shoulders")
        pose[10][2] = 0.05
        self.assertAlmostEqual(stationary_plane_steering(pose), 0.70)
        pose[11][2] = 0.05
        self.assertIsNone(stationary_plane_steering(pose))
        malformed = joints()
        malformed[5][0] = float("nan")
        malformed[11][0] = float("nan")
        self.assertIsNone(stationary_plane_steering(malformed))
        self.assertIsNone(stationary_plane_steering(joints()[:10]))

    def test_switching_joint_visibility_never_jerks_lateral_signal(self):
        tracker = PlaneSteeringTracker()
        now = 10.0
        for frame in range(1100):  # 73.3 seconds at 15 inferred poses per sec
            # Repeat center/left/right motion with alternately cropped hands.
            phase = frame % 150
            x = 0.50 if phase < 25 else 0.30 if phase < 65 else 0.70 if phase < 110 else 0.50
            # Gradual measured movement, which stays below StudentLock's
            # continuity bounds; compare raw torso regardless of wrist side.
            if frame > 0:
                x = max(last_x - 0.045, min(last_x + 0.045, x))
            pose = joints(x)
            if frame % 4 == 0:
                pose[9][2] = 0.05
            elif frame % 4 == 1:
                pose[10][2] = 0.05
            elif frame % 4 == 2:
                pose[5][2] = pose[6][2] = 0.05
            raw = stationary_plane_steering(pose)
            result = tracker.update(17, raw, now)
            if frame >= 2:
                self.assertIsNotNone(result, msg=f"valid one-wrist frame={frame}")
                self.assertAlmostEqual(result, x, places=5)
            now += 1 / 15
            last_x = x

    def test_student_lock_rejects_bystander_and_recovery_requires_fresh_pair(self):
        student = StudentLock()
        tracker = PlaneSteeringTracker()
        for frame in range(22):
            chosen, _, _ = student.update([person(17, 0.5)], frame / 15)
        self.assertEqual(student.locked_id, 17)
        self.assertIsNotNone(chosen)
        for frame in range(1000):
            now = 2.0 + frame / 15
            x = 0.5 + ((frame % 20) - 10) * 0.002
            candidates = [person(17, x), person(99, 0.52)]
            chosen, state, _ = student.update(candidates, now)
            self.assertEqual(state, "locked")
            self.assertEqual(chosen["track_id"], 17)
            pose = joints(x)
            pose[9 if frame % 2 else 10][2] = 0.0
            raw = stationary_plane_steering(pose)
            result = tracker.update(chosen["track_id"], raw, now)
            if frame > 1:
                self.assertAlmostEqual(result, x)
        self.assertIsNone(tracker.update(None, None, 80.0))
        self.assertIsNone(tracker.update(99, 0.76, 80.067))
        self.assertAlmostEqual(tracker.update(99, 0.76, 80.134), 0.76)

    def test_occlusion_duplicate_late_and_outlier_frames_cannot_steer(self):
        tracker = PlaneSteeringTracker()
        self.assertIsNone(tracker.update(4, 0.50, 0.0))
        self.assertEqual(tracker.update(4, 0.50, 1 / 15), 0.5)
        self.assertIsNone(tracker.update(4, 0.95, 2 / 15), "single-frame spike freezes")
        self.assertAlmostEqual(tracker.update(4, 0.51, 3 / 15), 0.51)
        self.assertIsNone(tracker.update(4, 0.52, 3 / 15), "duplicate source time freezes")
        self.assertIsNone(tracker.update(4, 0.52, 4 / 15))
        self.assertEqual(tracker.update(4, 0.52, 5 / 15), 0.52)
        self.assertIsNone(tracker.update(4, None, 6 / 15))
        self.assertIsNone(tracker.update(4, 0.52, 7 / 15))
        self.assertEqual(tracker.update(4, 0.52, 8 / 15), 0.52)
        self.assertIsNone(tracker.update(4, 0.55, 2.0), "650ms stale gap freezes")
        self.assertEqual(tracker.update(4, 0.56, 2.0 + 1 / 15), 0.56)


if __name__ == "__main__":
    unittest.main()
