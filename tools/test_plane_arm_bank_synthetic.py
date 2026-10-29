"""Synthetic raw YOLO COCO-17 human-plane banks. No webcam/model/DB."""
from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ui" / "vision"))

from pose_worker import plane_arm_bank


def wings(left_height=0.0, right_height=0.0, confidence=0.99,
          flipped_anatomy=False):
    """Camera was mirrored BEFORE YOLO; drops are positive image Y."""
    points = [[0.5, 0.5, 0.0] for _ in range(17)]
    # Screen-left body and screen-right body. Swapping labels should NOT
    # reverse the positive screen-right bank sign.
    left = (5, 7, 9) if not flipped_anatomy else (6, 8, 10)
    right = (6, 8, 10) if not flipped_anatomy else (5, 7, 9)
    for indices, side, height in ((left, -1, left_height), (right, 1, right_height)):
        shoulder, elbow, wrist = indices
        points[shoulder] = [0.5 + side * 0.07, 0.32, confidence]
        points[elbow] = [0.5 + side * 0.185, 0.32 + height * 0.48, confidence]
        points[wrist] = [0.5 + side * 0.32, 0.32 + height, confidence]
    return points


class ContinuousHumanPlaneBank(unittest.TestCase):
    def test_centered_t_pose_is_neutral(self):
        tpose, valid, bank = plane_arm_bank(wings())
        self.assertTrue(tpose)
        self.assertTrue(valid)
        self.assertEqual(bank, 0)

    def test_right_wing_down_moves_screen_right(self):
        tpose, valid, bank = plane_arm_bank(wings(-0.14, +0.14))
        self.assertFalse(tpose)
        self.assertTrue(valid)
        self.assertGreater(bank, +0.50)
        self.assertLessEqual(bank, 1.0)

    def test_left_wing_down_moves_screen_left(self):
        tpose, valid, bank = plane_arm_bank(wings(+0.14, -0.14))
        self.assertFalse(tpose)
        self.assertTrue(valid)
        self.assertLess(bank, -0.50)
        self.assertGreaterEqual(bank, -1.0)

    def test_mirrored_anatomical_labels_do_not_flip_screen_direction(self):
        one = plane_arm_bank(wings(-0.14, 0.14))[2]
        two = plane_arm_bank(wings(-0.14, 0.14, flipped_anatomy=True))[2]
        self.assertGreater(one, 0)
        self.assertAlmostEqual(one, two, places=5)

    def test_proportional_not_three_lanes(self):
        values = [plane_arm_bank(wings(-v, v))[2] for v in (0.01, 0.04, 0.07, 0.14)]
        self.assertEqual(values[0], 0)
        self.assertTrue(all(a < b for a, b in zip(values, values[1:])))
        self.assertLess(values[2], 1)

    def test_small_shoulder_and_hand_noise_is_deadzone(self):
        self.assertEqual(plane_arm_bank(wings(0.008, -0.008))[2], 0)
        self.assertTrue(plane_arm_bank(wings(0.015, -0.015))[1])

    def test_both_arms_raised_same_amount_does_not_turn(self):
        result = plane_arm_bank(wings(-0.12, -0.12))
        self.assertTrue(result[1])
        self.assertAlmostEqual(result[2], 0.0, places=5)

    def test_both_arms_lowered_disables_wing(self):
        pose, valid, bank = plane_arm_bank(wings(0.20, 0.20))
        self.assertEqual((pose, valid, bank), (False, False, 0.0))

    def test_missing_occluded_weak_or_malformed_joint_disables_bank(self):
        indices = [5, 6, 7, 8, 9, 10]
        for joint in indices:
            points = wings(-0.12, 0.12)
            points[joint][2] = 0.12
            self.assertEqual(plane_arm_bank(points), (False, False, 0.0))
        for coordinate in (float("nan"), float("inf"), -0.5, 1.5):
            points = wings()
            points[9][0] = coordinate
            self.assertEqual(plane_arm_bank(points), (False, False, 0.0))

    def test_hanging_arm_and_folded_elbow_disallow_bank(self):
        points = wings(-0.10, 0.10)
        points[9][0] = points[5][0] - 0.02
        self.assertEqual(plane_arm_bank(points), (False, False, 0.0))
        points = wings(-0.10, 0.10)
        points[7][0] = points[5][0]
        self.assertEqual(plane_arm_bank(points), (False, False, 0.0))

    def test_full_bank_clamped_within_minus_one_to_one(self):
        for height in (0.14, 0.17, 0.19):
            result = plane_arm_bank(wings(-height, height))
            if result[1]:
                self.assertTrue(math.isfinite(result[2]))
                self.assertGreaterEqual(result[2], -1)
                self.assertLessEqual(result[2], 1)


if __name__ == "__main__":
    unittest.main()
