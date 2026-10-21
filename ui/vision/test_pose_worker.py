"""No-camera, no-model smoke tests for the pose protocol and geometry."""
import unittest
from pose_worker import body_position, arms_raised


def pose() -> list[list[float]]:
    values = [[0.5, 0.6, 0.9] for _ in range(17)]
    values[5] = [0.4, 0.3, 0.9]
    values[6] = [0.6, 0.3, 0.9]
    values[11] = [0.44, 0.62, 0.9]
    values[12] = [0.56, 0.62, 0.9]
    values[9] = [0.35, 0.15, 0.9]
    values[10] = [0.65, 0.15, 0.9]
    return values


class PoseTests(unittest.TestCase):
    def test_center(self):
        self.assertAlmostEqual(body_position(pose()), 0.5)

    def test_missing_hips(self):
        data = pose()
        data[11][2] = 0.1
        self.assertIsNone(body_position(data))

    def test_raise_requires_both_arms(self):
        data = pose()
        self.assertTrue(arms_raised(data))
        data[10][1] = 0.5
        self.assertFalse(arms_raised(data))

    def test_raise_requires_confidence(self):
        data = pose()
        data[9][2] = 0.0
        self.assertFalse(arms_raised(data))


if __name__ == "__main__":
    unittest.main()
