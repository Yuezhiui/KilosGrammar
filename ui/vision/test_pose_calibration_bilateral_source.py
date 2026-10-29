"""Calibration-only bilateral YOLO evidence, with no camera or database.

One selected SOLO source frame can resume a held physical calibration pose
after brief wrist loss, without rearming Balloon's independent shooting latch.
"""

import json
import unittest

from gesture_detector import GestureDetector
from pose_worker import calibration_bilateral_packet_fields, send_status


def body(left="down", right="down"):
    points = [[0.5, 0.5, 0.0] for _ in range(17)]
    for index, (x, y) in {
        5: (0.39, 0.33), 6: (0.61, 0.33),
        9: (0.34, 0.61), 10: (0.66, 0.61),
        11: (0.43, 0.65), 12: (0.57, 0.65),
    }.items():
        points[index] = [x, y, 0.99]
    for wrist, posture in ((9, left), (10, right)):
        if posture == "up":
            points[wrist][1] = 0.13
        elif posture == "level":
            points[wrist][1] = 0.33
        elif posture == "missing":
            points[wrist][2] = 0.01
    return points


def fields(state, selected=None, count=1, lock="locked"):
    if selected is None:
        selected = {"keypoints": body()}
    return calibration_bilateral_packet_fields(state, selected, lock, count)


class RawBilateralCalibrationTests(unittest.TestCase):
    def test_held_both_up_recovers_after_lost_source_without_new_shot(self):
        detector = GestureDetector()
        detector.update(body("up", "up"), 0.00, 7)
        raised = detector.update(body("up", "up"), 0.15, 7)
        self.assertTrue(raised.hand_up)
        self.assertTrue(fields(raised)["calibration_both_hands_up"])

        missing = detector.update(None, 0.20)
        self.assertEqual(fields(missing), {
            "calibration_hand_observation_valid": False,
            "calibration_both_hands_up": False,
            "calibration_both_hands_down": False,
        })
        for when in (0.28, 0.48, 0.64):
            resumed = detector.update(body("up", "up"), when, 7)
            self.assertFalse(resumed.hand_up, "The same held hand cannot re-fire")
            self.assertFalse(resumed.hand_observation_valid, "Shot release latch stays set")
            self.assertFalse(resumed.both_hands_up, "Legacy shooting flag stays latched")
            self.assertEqual(fields(resumed), {
                "calibration_hand_observation_valid": True,
                "calibration_both_hands_up": True,
                "calibration_both_hands_down": False,
            }, "Fresh real bilateral raised evidence resumes the physical hold")

    def test_fresh_both_down_recovers_without_fake_shot_release(self):
        detector = GestureDetector()
        detector.update(body("up", "up"), 0.00, 7)
        detector.update(body("up", "up"), 0.15, 7)
        detector.update(None, 0.20)
        first_lower = detector.update(body(), 0.25, 7)
        self.assertFalse(first_lower.hand_up)
        self.assertFalse(first_lower.hand_observation_valid,
                         "Release cannot re-arm on one observation")
        self.assertFalse(first_lower.both_hands_down)
        self.assertTrue(fields(first_lower)["calibration_both_hands_down"],
                        "Fresh source evidence does not wait for shooting debounce")
        confirmed_lower = detector.update(body(), 0.40, 7)
        self.assertTrue(confirmed_lower.hand_observation_valid)
        self.assertTrue(fields(confirmed_lower)["calibration_both_hands_down"])

    def test_wrong_real_postures_are_observed_but_not_bilateral_holds(self):
        detector = GestureDetector()
        for i, posture in enumerate((("level", "level"), ("up", "down"),
                                     ("down", "up"), ("up", "level"))):
            state = detector.update(body(*posture), i * 0.03, 7)
            result = fields(state)
            self.assertTrue(result["calibration_hand_observation_valid"])
            self.assertFalse(result["calibration_both_hands_up"])
            self.assertFalse(result["calibration_both_hands_down"])

    def test_invalid_wrist_or_shoulder_fails_closed_on_same_frame(self):
        for joint in (5, 6, 9, 10):
            for invalid in (0.44, 0.0, float("nan")):
                with self.subTest(joint=joint, invalid=invalid):
                    points = body("up", "up")
                    points[joint][2] = invalid
                    state = GestureDetector().update(points, 0.1, 7)
                    result = fields(state)
                    self.assertFalse(result["calibration_hand_observation_valid"])
                    self.assertFalse(result["calibration_both_hands_up"])
                    self.assertFalse(result["calibration_both_hands_down"])
        out_of_frame = body()
        out_of_frame[10][0] = 1.3
        self.assertFalse(fields(GestureDetector().update(out_of_frame, 0.1, 7))
                         ["calibration_hand_observation_valid"])

    def test_zero_crowd_and_unlocked_never_publish_bilateral_calibration(self):
        raised = GestureDetector().update(body("up", "up"), 0.0, 7)
        self.assertTrue(raised.calibration_both_hands_up)
        for number, lock, selected in ((0, "lost", None), (2, "ambiguous", None),
                                       (2, "locked", {"keypoints": body()}),
                                       (1, "enrolling", {"keypoints": body()}),
                                       (1, "locked", None)):
            with self.subTest(count=number, lock=lock, selected=selected):
                result = calibration_bilateral_packet_fields(raised, selected, lock, number)
                self.assertFalse(any(result.values()))
        self.assertTrue(fields(raised)["calibration_both_hands_up"])

    def test_nontracking_worker_packets_default_to_no_calibration_authority(self):
        class Socket:
            def __init__(self):
                self.packets = []

            def sendto(self, packet, _destination):
                self.packets.append(json.loads(packet))

        sock = Socket()
        for state in ("loading", "recovering", "error", "stale"):
            send_status(sock, ("127.0.0.1", 10000), "test-only", state=state,
                        camera=False, pose=False)
        for packet in sock.packets:
            self.assertFalse(packet["calibration_hand_observation_valid"])
            self.assertFalse(packet["calibration_both_hands_up"])
            self.assertFalse(packet["calibration_both_hands_down"])


if __name__ == "__main__":
    unittest.main()
