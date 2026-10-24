"""Deterministic, webcam-free tests for hand and airplane pose controls."""

import json
import unittest

from gesture_detector import GestureDetector
from pose_worker import arms_raised, send_status


def standing():
    joints = [[0.5, 0.5, 0.0] for _ in range(17)]
    for index, xy in {
        5: (0.39, 0.33), 6: (0.61, 0.33),
        7: (0.34, 0.46), 8: (0.66, 0.46),
        9: (0.34, 0.61), 10: (0.66, 0.61),
        11: (0.43, 0.65), 12: (0.57, 0.65),
    }.items():
        joints[index] = [*xy, 0.99]
    return joints


def hand(which="left"):
    points = standing()
    points[9 if which == "left" else 10][1] = 0.13
    return points


def airplane():
    points = standing()
    for index, xy in {7: (0.30, 0.34), 8: (0.70, 0.34),
                      9: (0.15, 0.36), 10: (0.85, 0.36)}.items():
        points[index][:2] = xy
    return points


class _Socket:
    def __init__(self):
        self.messages = []

    def sendto(self, content, destination):
        self.messages.append((json.loads(content), destination))


class GestureTests(unittest.TestCase):
    def test_left_and_right_hand_both_work_with_debounce(self):
        for side in ("left", "right"):
            with self.subTest(side=side):
                detector = GestureDetector()
                self.assertFalse(detector.update(standing(), 0, 7).hand_up)
                self.assertFalse(detector.update(hand(side), 0.02, 7).hand_up)
                self.assertFalse(detector.update(hand(side), 0.10, 7).hand_up)
                result = detector.update(hand(side), 0.13, 7)
                self.assertTrue(result.hand_up)
                self.assertEqual(result.left_hand_up, side == "left")
                self.assertEqual(result.right_hand_up, side == "right")
                self.assertFalse(result.airplane_pose)

    def test_held_hand_never_generates_new_edges_until_lowered(self):
        detector = GestureDetector()
        detector.update(hand(), 0.0, 7)
        self.assertTrue(detector.update(hand(), 0.13, 7).hand_up)
        for index in range(40):
            self.assertTrue(detector.update(hand(), 0.2 + index * 0.15, 7).hand_up)
        self.assertTrue(detector.update(standing(), 6.3, 7).hand_up)
        self.assertFalse(detector.update(standing(), 6.45, 7).hand_up)
        self.assertFalse(detector.update(hand(), 6.47, 7).hand_up)
        self.assertTrue(detector.update(hand(), 6.61, 7).hand_up)

    def test_raising_other_hand_during_hold_does_not_drop_aggregate(self):
        detector = GestureDetector()
        detector.update(hand("left"), 0.0, 1)
        self.assertTrue(detector.update(hand("left"), 0.15, 1).hand_up)
        both = hand("left")
        both[10][1] = 0.13
        self.assertTrue(detector.update(both, 0.20, 1).hand_up)
        self.assertTrue(detector.update(hand("right"), 0.35, 1).hand_up)

    def test_random_frame_jitter_does_not_shoot_or_drop_a_hold(self):
        detector = GestureDetector()
        for i in range(25):
            points = standing()
            points[9][1] = 0.26 if i % 2 else 0.28
            self.assertFalse(detector.update(points, i * 0.05, 4).hand_up)
        points = hand()
        detector.update(points, 1.30, 4)
        self.assertTrue(detector.update(points, 1.45, 4).hand_up)
        for i in range(20):
            points = hand()
            points[9][1] = 0.26 if i % 2 else 0.13
            self.assertTrue(detector.update(points, 1.5 + i * 0.05, 4).hand_up)

    def test_tracking_loss_returns_false_without_retriggering_held_hand(self):
        detector = GestureDetector()
        detector.update(hand(), 0, 7)
        self.assertTrue(detector.update(hand(), 0.15, 7).hand_up)
        self.assertFalse(detector.update(None, 0.20).hand_up)
        self.assertFalse(detector.update(hand(), 0.25, 7).hand_up)
        self.assertFalse(detector.update(hand(), 0.55, 7).hand_up)
        self.assertFalse(detector.update(standing(), 0.60, 7).hand_up)
        self.assertFalse(detector.update(standing(), 0.75, 7).hand_up)
        self.assertFalse(detector.update(hand(), 0.80, 7).hand_up)
        self.assertTrue(detector.update(hand(), 0.95, 7).hand_up)

    def test_long_inference_stall_requires_a_new_release(self):
        detector = GestureDetector()
        detector.update(hand(), 0, 7)
        self.assertTrue(detector.update(hand(), 0.15, 7).hand_up)
        self.assertFalse(detector.update(hand(), 2.05, 7).hand_up)
        self.assertFalse(detector.update(standing(), 2.10, 7).hand_up)
        self.assertFalse(detector.update(standing(), 2.25, 7).hand_up)
        detector.update(hand(), 2.30, 7)
        self.assertTrue(detector.update(hand(), 2.45, 7).hand_up)

    def test_unconfirmed_raise_can_retry_after_one_lost_observation(self):
        detector = GestureDetector()
        self.assertFalse(detector.update(hand(), 0.0, 7).hand_up)
        self.assertFalse(detector.update(None, 0.05).hand_up)
        self.assertFalse(detector.update(hand(), 0.12, 7).hand_up)
        self.assertTrue(detector.update(hand(), 0.25, 7).hand_up)

    def test_new_student_track_cannot_inherit_an_old_shot(self):
        detector = GestureDetector()
        detector.update(hand(), 0, 7)
        self.assertTrue(detector.update(hand(), 0.15, 7).hand_up)
        self.assertFalse(detector.update(hand(), 0.3, 22).hand_up)
        self.assertFalse(detector.update(standing(), 0.4, 22).hand_up)
        self.assertFalse(detector.update(standing(), 0.6, 22).hand_up)
        detector.update(hand(), 0.7, 22)
        self.assertTrue(detector.update(hand(), 0.85, 22).hand_up)

    def test_one_unreliable_arm_can_raise_the_other_reliably(self):
        detector = GestureDetector()
        right = hand("right")
        right[9][2] = 0.01
        detector.update(right, 0.0, 7)
        confirmed = detector.update(right, 0.14, 7)
        self.assertTrue(confirmed.hand_up)
        self.assertTrue(confirmed.hand_observation_valid)
        self.assertFalse(detector.update(None, 0.2).hand_up)
        # A missing wrist is never counted as proof that the raised hand fell.
        missing = standing()
        missing[9][2] = 0.0
        unknown = detector.update(missing, 0.4, 7)
        self.assertFalse(unknown.hand_up)
        self.assertFalse(unknown.hand_observation_valid)

    def test_occluded_wrists_are_unknown_not_a_lowered_hand(self):
        detector = GestureDetector()
        start = detector.update(standing(), 0.0, 7)
        self.assertTrue(start.hand_observation_valid)
        detector.update(hand("left"), 0.05, 7)
        self.assertTrue(detector.update(hand("left"), 0.18, 7).hand_up)
        lost = standing()
        lost[9][2] = 0.01
        lost[10][2] = 0.01
        for when in (0.22, 0.40, 0.70, 1.10):
            state = detector.update(lost, when, 7)
            self.assertFalse(state.hand_up)
            self.assertFalse(state.hand_observation_valid)
        held = detector.update(hand("left"), 1.25, 7)
        self.assertFalse(held.hand_up)
        self.assertFalse(held.hand_observation_valid)
        first_down = detector.update(standing(), 1.35, 7)
        self.assertFalse(first_down.hand_observation_valid)
        confirmed_down = detector.update(standing(), 1.50, 7)
        self.assertTrue(confirmed_down.hand_observation_valid)
        self.assertFalse(confirmed_down.hand_up)
        self.assertFalse(detector.update(hand("right"), 1.55, 7).hand_up)
        raised = detector.update(hand("right"), 1.70, 7)
        self.assertTrue(raised.hand_observation_valid)
        self.assertTrue(raised.hand_up)

    def test_ambiguous_track_switch_never_emits_a_false_release(self):
        detector = GestureDetector()
        detector.update(hand("left"), 0.0, 4)
        self.assertTrue(detector.update(hand("left"), 0.15, 4).hand_up)
        switched = detector.update(hand("left"), 0.20, 9)
        self.assertFalse(switched.hand_up)
        self.assertFalse(switched.hand_observation_valid)
        self.assertFalse(detector.update(hand("left"), 0.55, 9).hand_observation_valid)
        self.assertFalse(detector.update(standing(), 0.60, 9).hand_observation_valid)
        self.assertTrue(detector.update(standing(), 0.75, 9).hand_observation_valid)

    def test_airplane_requires_both_complete_outward_level_arms(self):
        detector = GestureDetector()
        self.assertFalse(detector.update(airplane(), 0.0, 4).airplane_pose)
        self.assertTrue(detector.update(airplane(), 0.12, 4).airplane_pose)
        self.assertFalse(detector.update(airplane(), 0.15, 4).hand_up)
        folded = airplane()
        folded[10][0] = folded[8][0] + 0.005
        detector.update(folded, 0.20, 4)
        self.assertFalse(detector.update(folded, 0.34, 4).airplane_pose)
        detector.update(airplane(), 0.40, 4)
        self.assertTrue(detector.update(airplane(), 0.52, 4).airplane_pose)
        lowered = airplane()
        lowered[9][1] = 0.64
        lowered[10][1] = 0.64
        detector.update(lowered, 0.57, 4)
        self.assertFalse(detector.update(lowered, 0.72, 4).airplane_pose)

    def test_airplane_freezes_on_tracking_loss_then_reacquires(self):
        detector = GestureDetector()
        detector.update(airplane(), 0.0, 7)
        self.assertTrue(detector.update(airplane(), 0.15, 7).airplane_pose)
        self.assertFalse(detector.update(None, 0.17).airplane_pose)
        self.assertFalse(detector.update(airplane(), 0.20, 7).airplane_pose)
        self.assertTrue(detector.update(airplane(), 0.35, 7).airplane_pose)

    def test_raising_both_arms_overhead_does_not_count_as_airplane(self):
        both = hand("left")
        both[10][1] = 0.13
        detector = GestureDetector()
        detector.update(both, 0.0, 7)
        state = detector.update(both, 0.15, 7)
        self.assertTrue(state.hand_up)
        self.assertFalse(state.airplane_pose)

    def test_thirty_full_raise_lower_cycles_without_stuck_state(self):
        detector = GestureDetector()
        now = 0.0
        for i in range(30):
            raised = hand("left" if i % 2 == 0 else "right")
            self.assertFalse(detector.update(raised, now, 7).hand_up)
            self.assertTrue(detector.update(raised, now + 0.14, 7).hand_up)
            self.assertTrue(detector.update(raised, now + 0.20, 7).hand_up)
            self.assertTrue(detector.update(standing(), now + 0.26, 7).hand_up)
            self.assertFalse(detector.update(standing(), now + 0.40, 7).hand_up)
            now += 0.50

    def test_mirrored_and_rescaled_poses(self):
        for mirror in (False, True):
            for scale in (0.7, 1.0, 1.1):
                with self.subTest(mirror=mirror, scale=scale):
                    points = airplane()
                    for joint in points:
                        joint[0] = (0.5 - (joint[0] - 0.5) * scale if mirror
                                    else 0.5 + (joint[0] - 0.5) * scale)
                        joint[1] = 0.4 + (joint[1] - 0.4) * scale
                    detector = GestureDetector()
                    detector.update(points, 0.0, 1)
                    self.assertTrue(detector.update(points, 0.15, 1).airplane_pose)

    def test_low_confidence_and_nonfinite_joints_are_rejected(self):
        for bad in (0.0, float("nan"), float("inf")):
            with self.subTest(confidence=bad):
                points = hand("left")
                points[9][2] = bad
                detector = GestureDetector()
                detector.update(points, 0.0, 1)
                self.assertFalse(detector.update(points, 0.15, 1).hand_up)
        points = airplane()
        points[7][0] = 1.5
        detector = GestureDetector()
        detector.update(points, 0.0, 1)
        self.assertFalse(detector.update(points, 0.15, 1).airplane_pose)

    def test_legacy_both_hands_field_keeps_its_original_contract(self):
        self.assertFalse(arms_raised(hand("left")))
        both = hand("left")
        both[10][1] = 0.13
        self.assertTrue(arms_raised(both))

    def test_nontracking_packets_include_false_flags(self):
        fake = _Socket()
        send_status(fake, ("127.0.0.1", 10000), "token", state="recovering", pose=False)
        data = fake.messages[0][0]
        self.assertFalse(data["hand_up"])
        self.assertFalse(data["airplane_pose"])
        self.assertFalse(data["left_hand_up"])
        self.assertFalse(data["right_hand_up"])
        self.assertFalse(data["hand_observation_valid"])


if __name__ == "__main__":
    unittest.main()
