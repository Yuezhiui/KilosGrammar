"""Human Plane calibration accepts realistic near-level arms, not ghost poses.

No webcam is used; 3-second physical holds still belong to Godot calibration.
"""
import unittest

from pose_worker import plane_arm_bank


def points(wrist_y=0.33, elbow_y=0.33, missing=None, folded=False):
    keypoints = [[0.5, 0.5, 0.0] for _ in range(17)]
    xy = {
        5: (0.40, 0.33), 6: (0.60, 0.33),
        7: (0.30 if not folded else 0.48, elbow_y),
        8: (0.70 if not folded else 0.52, elbow_y),
        9: (0.16 if not folded else 0.50, wrist_y),
        10: (0.84 if not folded else 0.50, wrist_y),
        11: (0.43, 0.65), 12: (0.57, 0.65),
    }
    for i, p in xy.items():
        keypoints[i] = [*p, 0.99]
    if missing is not None:
        keypoints[missing][2] = 0.01
    return keypoints


class PlaneCalibrationToleranceTests(unittest.TestCase):
    def test_neutral_wings_valid(self):
        self.assertEqual(plane_arm_bank(points()), (True, True, 0.0))

    def test_natural_small_wrist_and_elbow_tilt_valid(self):
        # atan((.40-.33)/(.40-.16)) =~ 16.3 degrees and elbows
        # atan((.36-.33)/(.40-.30)) =~ 16.7 degrees.
        t_pose, bank_valid, bank = plane_arm_bank(points(0.40, 0.36))
        self.assertTrue(t_pose)
        self.assertTrue(bank_valid)
        self.assertAlmostEqual(bank, 0.0, delta=0.01)

    def test_down_arms_rejected(self):
        self.assertFalse(plane_arm_bank(points(0.62, 0.52))[0])

    def test_folded_arms_not_t_pose(self):
        self.assertFalse(plane_arm_bank(points(folded=True))[0])

    def test_missing_any_required_joint_rejects_t_pose(self):
        for missing in (5, 6, 7, 8, 9, 10):
            with self.subTest(missing=missing):
                self.assertEqual(plane_arm_bank(points(missing=missing)), (False, False, 0.0))


if __name__ == "__main__":
    unittest.main()
