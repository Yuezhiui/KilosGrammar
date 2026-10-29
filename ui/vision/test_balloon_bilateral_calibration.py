"""Fresh wrist evidence for six physically timed Balloon calibration holds.

The ordinary minigame's one-hand shooting behavior remains unchanged.
No camera or network is opened by this deterministic vision test.
"""
import unittest

from gesture_detector import GestureDetector


def pose(left: str = "down", right: str = "down"):
    points = [[0.5, 0.5, 0.0] for _ in range(17)]
    for idx, coords in {
        5: (0.39, 0.33), 6: (0.61, 0.33),
        7: (0.34, 0.46), 8: (0.66, 0.46),
        9: (0.34, 0.61), 10: (0.66, 0.61),
        11: (0.43, 0.65), 12: (0.57, 0.65),
    }.items():
        points[idx] = [*coords, 0.99]
    for key, side in ((9, left), (10, right)):
        if side == "up":
            points[key][1] = 0.13
        elif side == "horizontal":
            points[key][1] = 0.33
        elif side == "occluded":
            points[key][2] = 0.02
    return points


class BilateralCalibrationTests(unittest.TestCase):
    def test_both_hands_down_stay_source_fresh_and_require_both_wrists(self):
        d = GestureDetector()
        low = d.update(pose(), 0.0)
        self.assertTrue(low.both_hands_down)
        self.assertFalse(low.both_hands_up)
        self.assertFalse(d.update(pose(right="occluded"), 0.04).both_hands_down)
        self.assertFalse(d.update(pose(left="occluded"), 0.08).both_hands_down)
        self.assertFalse(d.update(None, 0.10).both_hands_down)

    def test_one_hand_is_legal_gameplay_shot_but_not_bilateral_calibration(self):
        d = GestureDetector()
        d.update(pose(left="up"), 0.0)
        active = d.update(pose(left="up"), 0.16)
        self.assertTrue(active.hand_up)
        self.assertTrue(active.left_hand_up)
        self.assertFalse(active.right_hand_up)
        self.assertFalse(active.both_hands_up)
        self.assertFalse(active.both_hands_down)

    def test_both_hands_up_required_on_same_fresh_keypoint_frame(self):
        d = GestureDetector()
        d.update(pose(), 0.0)
        d.update(pose(left="up", right="up"), 0.02)
        state = d.update(pose(left="up", right="up"), 0.20)
        self.assertTrue(state.hand_up)
        self.assertTrue(state.both_hands_up)
        self.assertFalse(state.both_hands_down)
        self.assertFalse(d.update(pose(left="up", right="down"), 0.24).both_hands_up)
        self.assertFalse(d.update(pose(left="occluded", right="up"), 0.28).both_hands_up)
        self.assertFalse(d.update(None, 0.30).both_hands_up)

    def test_t_pose_horizontal_not_mistaken_for_both_hands_overhead(self):
        d = GestureDetector()
        d.update(pose(left="horizontal", right="horizontal"), 0.0)
        state = d.update(pose(left="horizontal", right="horizontal"), 0.2)
        self.assertFalse(state.both_hands_up)
        self.assertFalse(state.both_hands_down)

    def test_new_round_requires_new_fresh_pose_no_ghost_bilateral_state(self):
        d = GestureDetector()
        d.update(pose(left="up", right="up"), 0.0)
        self.assertTrue(d.update(pose(left="up", right="up"), 0.15).both_hands_up)
        self.assertFalse(d.update(None, 0.18).both_hands_up)
        self.assertFalse(d.update(pose(left="up", right="up"), 0.22).both_hands_up)
        d.update(pose(), 0.25)
        self.assertTrue(d.update(pose(), 0.48).both_hands_down)
        d.update(pose(left="up", right="up"), 0.55)
        self.assertTrue(d.update(pose(left="up", right="up"), 0.70).both_hands_up)


if __name__ == "__main__":
    unittest.main()
