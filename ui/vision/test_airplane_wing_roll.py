"""Camera-free airplane gesture regression: arm spread gates torso movement.

Analog wing roll remains covered for compatibility, but is not the Human
Plane movement direction. Its movement direction comes from the torso.
"""
from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from gesture_detector import GestureDetector
from test_gesture_detector import airplane, standing


def bank(left_drop: float = 0.0, right_drop: float = 0.0, mirror: bool = False):
    points = airplane()
    # Drop positive = towards feet (image Y increases down).
    points[7][1] += left_drop * 0.5
    points[9][1] += left_drop
    points[8][1] += right_drop * 0.5
    points[10][1] += right_drop
    if mirror:
        for joint in points:
            joint[0] = 1.0 - joint[0]
    return points


def observed(points, who=12):
    detector = GestureDetector()
    detector.update(points, 0.0, who)
    return detector.update(points, 0.15, who)


class WingRollTests(unittest.TestCase):
    def test_level_arms_are_neutral_regardless_of_mirror(self):
        for mirror in (False, True):
            for y in (-0.02, 0.0, 0.02):
                state = observed(bank(y, y, mirror))
                self.assertTrue(state.airplane_pose)
                self.assertAlmostEqual(state.wing_roll, 0.0)

    def test_screen_left_dip_goes_left_even_when_camera_mirrored(self):
        for mirror in (False, True):
            # Pixel LEFT/RIGHT, not anatomical COCO side labels, are the
            # player's visual controls on the mirrored selfie camera.
            left = observed(bank(0.12, -0.12, mirror)
                            if not mirror else bank(-0.12, 0.12, mirror))
            right = observed(bank(-0.12, 0.12, mirror)
                             if not mirror else bank(0.12, -0.12, mirror))
            self.assertTrue(left.airplane_pose)
            self.assertTrue(right.airplane_pose)
            self.assertLess(left.wing_roll, -0.28)
            self.assertGreater(right.wing_roll, 0.28)
            self.assertAlmostEqual(left.wing_roll, -right.wing_roll, delta=0.05)

    def test_flipping_same_labeled_keypoints_flips_visual_steering(self):
        ordinary = observed(bank(0.09, -0.09, False))
        mirror = observed(bank(0.09, -0.09, True))
        self.assertLess(ordinary.wing_roll, -0.1)
        self.assertGreater(mirror.wing_roll, 0.1)

    def test_gradual_tilt_is_analog_and_saturates(self):
        values = [observed(bank(d, -d)).wing_roll for d in (0, 0.025, 0.060, 0.115)]
        self.assertEqual(values[0], 0)
        self.assertTrue(all(a >= b for a, b in zip(values, values[1:])))
        self.assertLess(values[-1], -0.2)
        for result in values:
            self.assertTrue(math.isfinite(result))
            self.assertLessEqual(abs(result), 1)

    def test_deep_bank_drops_airplane_gate_when_hand_is_lowered(self):
        for mirror in (False, True):
            left = observed(bank(0.20, -0.20, mirror))
            right = observed(bank(-0.20, 0.20, mirror))
            # Deep tilting used to steer with wrists. Human Plane now steers
            # with the player's calibrated torso; visibly dropping one wing
            # removes the arms-wide permission gate.
            self.assertFalse(left.airplane_pose)
            self.assertFalse(right.airplane_pose)
            self.assertEqual(left.wing_roll, 0.0)
            self.assertEqual(right.wing_roll, 0.0)

    def test_pose_loss_and_low_confidence_never_hold_stale_bank(self):
        detector = GestureDetector()
        leaning = bank(0.12, -0.12)
        detector.update(leaning, 0.0, 14)
        self.assertLess(detector.update(leaning, 0.15, 14).wing_roll, 0)
        self.assertEqual(detector.update(None, 0.2, 14).wing_roll, 0)
        self.assertFalse(detector.update(standing(), 0.3, 14).airplane_pose)
        low_confidence = bank(0.12, -0.12)
        low_confidence[9][2] = 0.1
        self.assertEqual(detector.update(low_confidence, 0.5, 14).wing_roll, 0)


class AirplaneMovementGateTests(unittest.TestCase):
    """Only two clearly outstretched arms allow torso steering."""

    def test_only_one_wide_arm_cannot_enter_gate(self):
        for mirror in (False, True):
            for side in ("left", "right"):
                with self.subTest(mirror=mirror, side=side):
                    one_arm = airplane()
                    points_down = standing()
                    for index in ((8, 10) if side == "left" else (7, 9)):
                        one_arm[index][:2] = points_down[index][:2]
                    if mirror:
                        for joint in one_arm:
                            joint[0] = 1.0 - joint[0]
                    detector = GestureDetector()
                    for i in range(8):
                        self.assertFalse(detector.update(one_arm, i * 0.05, 77).airplane_pose)

    def test_gate_immediately_blocks_when_one_arm_drops_or_is_occluded(self):
        for mirror in (False, True):
            for missing in (False, True):
                with self.subTest(mirror=mirror, missing=missing):
                    both = airplane()
                    if mirror:
                        for joint in both:
                            joint[0] = 1.0 - joint[0]
                    detector = GestureDetector()
                    detector.update(both, 0.0, 18)
                    self.assertTrue(detector.update(both, 0.15, 18).airplane_pose)
                    invalid = [list(joint) for joint in both]
                    if missing:
                        invalid[10][2] = 0.10
                    else:
                        invalid[10][1] = 0.64
                        invalid[8][1] = 0.50
                    self.assertFalse(detector.update(invalid, 0.18, 18).airplane_pose)
                    # Full spread can be resumed once both arms are visible;
                    # never require a fresh center/right/left calibration.
                    self.assertTrue(detector.update(both, 0.22, 18).airplane_pose)

    def test_arms_wide_but_hanging_below_shoulders_are_not_flight(self):
        for mirror in (False, True):
            pose = airplane()
            # Elbows and wrists keep a wide x spread, but hands have dropped
            # well below the shoulder line and no longer represent a plane.
            for joint in (7, 8):
                pose[joint][1] = 0.51
            for joint in (9, 10):
                pose[joint][1] = 0.58
            if mirror:
                for joint in pose:
                    joint[0] = 1.0 - joint[0]
            detector = GestureDetector()
            for n in range(8):
                self.assertFalse(detector.update(pose, n * 0.05, 18).airplane_pose)

    def test_body_position_side_steps_never_change_flight_gate(self):
        for offset in (-0.10, 0.0, 0.10):
            with self.subTest(offset=offset):
                moved = airplane()
                for joint in moved:
                    joint[0] += offset
                detector = GestureDetector()
                self.assertFalse(detector.update(moved, 0.0, 18).airplane_pose)
                self.assertTrue(detector.update(moved, 0.14, 18).airplane_pose)

    def test_lower_then_open_wide_again_after_pause_and_track_loss(self):
        detector = GestureDetector()
        wide = airplane()
        down = standing()
        detector.update(wide, 0.0, 18)
        self.assertTrue(detector.update(wide, 0.14, 18).airplane_pose)
        self.assertFalse(detector.update(down, 0.16, 18).airplane_pose)
        self.assertFalse(detector.update(down, 0.31, 18).airplane_pose)
        self.assertFalse(detector.update(wide, 0.33, 18).airplane_pose)
        self.assertTrue(detector.update(wide, 0.47, 18).airplane_pose)
        self.assertFalse(detector.update(None, 0.48, 18).airplane_pose)
        self.assertFalse(detector.update(wide, 0.54, 18).airplane_pose)
        self.assertTrue(detector.update(wide, 0.68, 18).airplane_pose)
        self.assertFalse(detector.update(None, 0.70, 18).airplane_pose)
        self.assertFalse(detector.update(wide, 0.80, 91).airplane_pose)
        self.assertTrue(detector.update(wide, 0.94, 91).airplane_pose)


if __name__ == "__main__":
    unittest.main()
