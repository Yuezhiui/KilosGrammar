"""Synthetic 2-zone safety regressions: no camera, YOLO, network or database.

Run: py -3.11 -B -m unittest ui.vision.test_two_player_lock_20261102 -v
"""
from __future__ import annotations

import json
import socket
import sys
import threading
import time
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

try:
    from .two_player_lock import TwoPlayerLock
except ImportError:
    from two_player_lock import TwoPlayerLock


def person(x, height=.55, index=0, valid=True, track_id=-1):
    # Synthetic points have trustworthy current-frame shoulders and hips.
    joints = [[x, .5, .95] for _ in range(17)] if valid else []
    return {"x": x, "height": height, "keypoints": joints,
            "detection_index": index, "track_id": track_id, "eligible": valid}


class TwoPlayerSpatialTests(unittest.TestCase):
    def hold(self, tracker, bodies, start=0, duration=1.1, dt=.1):
        output = None
        for j in range(int(round(duration / dt)) + 1):
            output = tracker.update(bodies, start + dt * j)
        return output

    def assert_active(self, output, left=False, right=False):
        self.assertEqual([p["active"] for p in output], [left, right], output)
        if output[0]["active"] and output[1]["active"]:
            self.assertNotEqual(
                output[0]["index"], output[1]["index"],
                "A single live detection must never drive both slots")
        for entry in output:
            if not entry["active"]:
                self.assertEqual(entry["index"], -1)
                self.assertEqual(entry["x"], -1.0)

    def test_p1_left_alone_can_enroll_without_waiting_for_p2(self):
        lock = TwoPlayerLock()
        out = self.hold(lock, [person(.25, index=0)])
        self.assert_active(out, True, False)
        self.assertTrue(out[0]["enrolled"])
        self.assertFalse(out[1]["enrolled"])
        self.assertAlmostEqual(lock.slots[0]["reference_x"], .25)

    def test_p2_right_alone_can_enroll_independently(self):
        lock = TwoPlayerLock()
        out = self.hold(lock, [person(.75, index=0)])
        self.assert_active(out, False, True)
        self.assertTrue(out[1]["enrolled"])

    def test_p1_walks_to_p2_right_with_no_ghost_or_dual_control(self):
        lock = TwoPlayerLock()
        self.assert_active(self.hold(lock, [person(.25)]), True, False)
        timeline = [(.35, 1.2), (.44, 1.3), (.48, 1.4),
                    (.50, 1.5), (.53, 1.6), (.60, 1.7)]
        seen_center = False
        for x, now in timeline:
            out = lock.update([person(x)], now)
            self.assertLessEqual(sum(int(p["active"]) for p in out), 1)
            if .49 < x < .51:
                self.assert_active(out, False, False)
                seen_center = True
        self.assertTrue(seen_center)
        out = self.hold(lock, [person(.74)], start=1.8)
        self.assert_active(out, False, True)
        self.assertTrue(out[0]["enrolled"], "P1 retains neutral/session enrollment")
        self.assertAlmostEqual(lock.slots[0]["reference_x"], .25)

    def test_after_both_enrolled_one_body_switches_zones(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.24, index=0), person(.75, index=1)])
        self.assert_active(lock.update([person(.24, index=0)], 1.2), True, False)
        self.assert_active(lock.update([person(.5, index=0)], 1.3), False, False)
        out = self.hold(lock, [person(.73, index=4)], start=1.4)
        self.assert_active(out, False, True)
        self.assertEqual(out[1]["index"], 4)
        self.assertEqual(lock.slots[0]["reference_x"], .24)

    def test_existing_two_person_simultaneous_tracking_preserved(self):
        lock = TwoPlayerLock()
        initial = self.hold(lock, [person(.22, .55, 0), person(.78, .61, 1)])
        self.assert_active(initial, True, True)
        moved = lock.update([person(.31, .57, 9), person(.69, .59, 4)], 1.2)
        self.assert_active(moved, True, True)
        self.assertEqual([p["index"] for p in moved], [9, 4])

    def test_track_ids_do_not_define_or_switch_identity(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25, index=1, track_id=44),
                         person(.75, index=2, track_id=99)])
        out = lock.update([person(.26, index=7, track_id=99),
                           person(.73, index=8, track_id=44)], 1.2)
        self.assert_active(out, True, True)
        self.assertEqual([p["index"] for p in out], [7, 8])

    def test_empty_camera_never_emits_previous_body(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25), person(.75, index=1)])
        self.assert_active(lock.update([], 1.2), False, False)
        self.assert_active(lock.update([], 2.1), False, False)

    def test_short_dropout_reuses_spatial_slot_only_on_fresh_frame(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25)])
        out = lock.update([], 1.2)
        self.assert_active(out, False, False)
        out = lock.update([person(.26, index=55)], 1.3)
        self.assert_active(out, True, False)
        self.assertEqual(out[0]["index"], 55)

    def test_long_dropout_requires_stable_recovery_hold(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.24)])
        lock.update([], 2.0)
        out = lock.update([person(.25, index=11)], 2.1)
        self.assert_active(out, False, False)
        for i in range(1, 8):
            out = lock.update([person(.25, index=11)], 2.1 + i * .1)
        self.assert_active(out, True, False)

    def test_same_zone_two_prominent_people_are_ambiguous(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.23)])
        out = lock.update([person(.2, index=3), person(.35, index=4)], 1.2)
        self.assert_active(out, False, False)
        self.assertIn(out[0]["reason"], ("ambiguous", "crossing_ambiguous"))

    def test_close_two_person_crossing_disables_both(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25, index=0), person(.73, index=1)])
        out = lock.update([person(.48, index=0), person(.52, index=1)], 1.2)
        self.assert_active(out, False, False)
        self.assertEqual(out[0]["reason"], "teacher_recalibration_required")
        self.assertTrue(lock.requires_teacher_recalibration)

    def test_two_students_cross_swap_both_scores_stay_blocked_until_teacher_reset(self):
        lock = TwoPlayerLock()
        self.assert_active(self.hold(
            lock, [person(.25, index=0), person(.75, index=1)]), True, True)
        first = lock.update([person(.48, index=0), person(.52, index=1)], 1.2)
        self.assert_active(first, False, False)
        self.assertTrue(lock.requires_teacher_recalibration)
        # Even after distinct people swap positions and stand quietly for two
        # seconds, their different score IDs CANNOT silently be reassigned.
        for j in range(24):
            out = lock.update([person(.75, index=0), person(.25, index=1)],
                              1.3 + j * .1)
            self.assert_active(out, False, False)
            self.assertEqual(out[0]["reason"], "teacher_recalibration_required")
            self.assertEqual(out[1]["reason"], "teacher_recalibration_required")
        # Only a deliberate new teacher calibration clears this latch.
        lock.reset_for_teacher_calibration()
        self.assertFalse(lock.requires_teacher_recalibration)
        self.assertFalse(any(s["enrolled"] for s in lock.slots))
        self.assert_active(self.hold(lock, [
            person(.25, index=1), person(.75, index=0)], start=4.0),
            True, True)

    def test_both_students_to_one_side_requires_teacher_calibration(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25, index=0), person(.75, index=1)])
        out = lock.update([person(.22, index=0), person(.38, index=1)], 1.2)
        self.assert_active(out, False, False)
        self.assertTrue(lock.requires_teacher_recalibration)

    def test_both_registered_students_disappear_long_then_pair_returns(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25, index=0), person(.75, index=1)])
        self.assert_active(lock.update([], 1.2), False, False)
        out = lock.update([person(.23, index=1), person(.78, index=0)], 2.1)
        self.assert_active(out, False, False)
        self.assertTrue(lock.requires_teacher_recalibration)

    def test_sequential_solo_calibration_remains_recoverable_after_gap(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25)], start=0.0)
        self.hold(lock, [person(.75)], start=1.5)
        self.assertTrue(all(s["enrolled"] for s in lock.slots))
        self.assertFalse(lock.ever_simultaneous,
                         "one person cannot be counted as two simultaneous bodies")
        self.assert_active(lock.update([], 2.7), False, False)
        self.assert_active(lock.update([], 3.8), False, False)
        self.assertFalse(lock.requires_teacher_recalibration,
                         "solo staged teaching may step away for a camera recovery")
        out = self.hold(lock, [person(.24, index=1),
                               person(.76, index=2)], start=4.0)
        self.assert_active(out, True, True)
        self.assertTrue(lock.ever_simultaneous)

    def test_staged_solo_switch_preserves_both_enrollments_without_teacher_latch(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25, index=0), person(.75, index=1)])
        lock.update([person(.25, index=0)], 1.2)
        lock.update([person(.50, index=0)], 1.3)
        out = self.hold(lock, [person(.73, index=0)], start=1.4)
        self.assert_active(out, False, True)
        self.assertFalse(lock.requires_teacher_recalibration,
                         "single-person staged crossing is an allowed workflow")

    def test_center_single_body_is_never_a_player(self):
        lock = TwoPlayerLock()
        out = self.hold(lock, [person(.5)])
        self.assert_active(out, False, False)
        self.assertFalse(any(s["enrolled"] for s in lock.slots))

    def test_far_small_background_spectator_is_ignored(self):
        lock = TwoPlayerLock()
        out = self.hold(lock, [person(.25, .62, 0), person(.9, .12, 1)])
        self.assert_active(out, True, False)

    def test_comparable_third_spectator_disarms_all_players(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.2, index=0), person(.8, index=1)])
        out = lock.update([person(.2, index=0), person(.8, index=1),
                           person(.5, .55, 2)], 1.2)
        self.assert_active(out, False, False)
        self.assertEqual(out[0]["reason"], "spectator_ambiguous")

    def test_untrusted_pose_or_occluding_body_never_controls_zone(self):
        lock = TwoPlayerLock()
        out = self.hold(lock, [person(.25, valid=False), person(.75, index=1)])
        self.assert_active(out, False, True)
        self.assertFalse(out[0]["enrolled"])

    def test_one_body_with_no_keypoints_cannot_enroll(self):
        lock = TwoPlayerLock()
        self.assert_active(self.hold(lock, [person(.25, valid=False)]),
                           False, False)

    def test_sudden_spatial_jump_requires_recovery(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.2)])
        out = lock.update([person(.445)], 1.2)
        self.assert_active(out, False, False)
        self.assertEqual(out[0]["reason"], "holding")

    def test_duplicate_or_replayed_source_timestamp_inactive(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25)])
        self.assert_active(lock.update([person(.25)], 1.1), False, False)
        self.assert_active(lock.update([person(.25)], 1.05), False, False)

    def test_new_right_slot_does_not_overwrite_p1_reference(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.24)])
        original = lock.slots[0]["reference_x"]
        self.hold(lock, [person(.76)], start=1.5)
        self.assertEqual(lock.slots[0]["reference_x"], original)
        self.assertAlmostEqual(lock.slots[1]["reference_x"], .76)


class MultiplayerWorkerPacketTests(unittest.TestCase):
    """Run the ACTUAL camera worker branch with entirely synthetic YOLO frames."""

    def test_one_yolo_frame_per_tick_separate_slots_and_no_ghost_hands(self):
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import pose_worker

        class FakeArray:
            def __init__(self, values):
                self.values = values
            def cpu(self):
                return self
            def tolist(self):
                return self.values

        class FakePrediction:
            def __init__(self, bodies):
                class Boxes:
                    def __init__(self):
                        self.xyxy = FakeArray([])
                        self.id = None
                    def __len__(self):
                        return len(self.xyxy.values)
                self.boxes = Boxes()
                self.keypoints = SimpleNamespace(data=FakeArray([]))
                for x, hands in bodies:
                    self.boxes.xyxy.values.append(
                        [(x - .12) * 640, .14 * 480,
                         (x + .12) * 640, .77 * 480])
                    points = [[x * 640, .48 * 480, .03] for _ in range(17)]
                    shoulder_y = .31
                    wrist_y = .11 if hands == "up" else .70
                    for joint, jx, jy in [
                        (5, x - .07, shoulder_y), (6, x + .07, shoulder_y),
                        (7, x - .09, .45), (8, x + .09, .45),
                        (9, x - .12, wrist_y), (10, x + .12, wrist_y),
                        (11, x - .06, .62), (12, x + .06, .62),
                    ]:
                        points[joint] = [jx * 640, jy * 480, .98]
                    self.keypoints.data.values.append(points)

        class FakeModel:
            def __init__(self):
                self.calls = 0
            def predict(self, *_args, **_kwargs):
                self.calls += 1
                c = self.calls
                if c <= 19:
                    bodies = [(.25, "down")]   # P1 alone
                elif c <= 24:
                    bodies = [(.50, "down")]   # nobody active in center
                elif c <= 44:
                    bodies = [(.73, "up")]     # P2 enrolls with raised hand
                elif c <= 58:
                    bodies = [(.73, "down")]   # P2 visibly releases
                elif c <= 73:
                    bodies = [(.73, "up")]     # P2 may now fire
                elif c <= 81:
                    bodies = []               # no skeleton/gesture at all
                elif c <= 100:
                    bodies = [(.24, "down"), (.76, "down")]
                elif c <= 107:
                    bodies = [(.48, "down"), (.52, "down")]  # overlapping crossing
                elif c <= 121:
                    bodies = [(.76, "down"), (.24, "down")]  # swapped, stay blocked
                else:
                    # Terminate the scripted finite fake camera run.
                    raise RuntimeError("Synthetic end of camera stream")
                return [FakePrediction(bodies)]

        class FakeReader:
            def __init__(self):
                self.counter = 0
                self.frame = SimpleNamespace(shape=(480, 640, 3))
                self.camera_fps = 15.0
                self.read_failures = 0
                self.last_frame_time = time.monotonic()
            def newest_with_timestamp(self, _seq):
                time.sleep(.058)
                self.counter += 1
                self.last_frame_time = time.monotonic()
                return self.frame, self.counter, self.last_frame_time
            def close(self):
                pass

        reader = FakeReader()
        model = FakeModel()
        result = {}
        packets = []
        receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        receiver.bind(("127.0.0.1", 0))
        receiver.settimeout(.12)
        cv_stub = SimpleNamespace(flip=lambda frame, _axis: frame)
        try:
            with patch.dict(sys.modules, {"cv2": cv_stub}), patch.object(
                    pose_worker, "open_live_camera",
                    return_value=(object(), reader, {})):
                def drive_worker():
                    result["exit"] = pose_worker.run(
                        receiver.getsockname()[1], "synthetic-two-zone",
                        0, "unused.pt", False,
                        prepared_model=(model, "cpu", False), players=2)
                thread = threading.Thread(target=drive_worker, daemon=True)
                thread.start()
                deadline = time.monotonic() + 9.0
                while time.monotonic() < deadline and thread.is_alive():
                    try:
                        blob, _source = receiver.recvfrom(65535)
                        if blob[:1] == b"{":
                            data = json.loads(blob.decode("utf-8"))
                            if data.get("mode") == "multiplayer" and "players" in data:
                                packets.append(data)
                    except socket.timeout:
                        pass
                thread.join(timeout=1.0)
                self.assertFalse(thread.is_alive(), "finite fake worker exits")
            self.assertEqual(result.get("exit"), 6,
                             "script deliberately ends at synthetic inference error")
        finally:
            receiver.close()

        self.assertGreaterEqual(len(packets), 80)
        self.assertTrue(all(len(p["players"]) == 2 for p in packets))
        self.assertTrue(all(
            len({s["index"] for s in p["players"] if s["active"]})
            == sum(bool(s["active"]) for s in p["players"])
            for p in packets), "no single detection controls both slots")
        self.assertTrue(all(
            not s["hand_up"] and not s["hand_observation_valid"]
            and not s["left_hand_up"] and not s["right_hand_up"]
            and not s["calibration_both_hands_up"]
            and not s["calibration_both_hands_down"]
            for p in packets for s in p["players"] if not s["active"]),
            "no inactive slot retains hands/calibration from an earlier frame")
        self.assertTrue(any(
            p["players"][0]["active"] and not p["players"][1]["active"]
            for p in packets if p["people"] == 1))
        self.assertTrue(any(
            p["players"][1]["active"] and not p["players"][0]["active"]
            for p in packets if p["people"] == 1))
        # Initial P2 hand raised during enrollment is NOT allowed to shoot;
        # fresh calibration evidence may still observe the raised arms.
        self.assertTrue(any(
            s["active"] and s["calibration_both_hands_up"] and not s["hand_up"]
            for p in packets for s in [p["players"][1]]),
            "P2 cannot fire simply by entering their slot with an arm raised")
        self.assertTrue(any(
            s["active"] and s["hand_observation_valid"] and s["both_hands_down"]
            for p in packets for s in [p["players"][1]]),
            "P2 can rearm with BOTH hands visibly down after locking")
        self.assertTrue(any(
            s["active"] and s["hand_observation_valid"] and s["hand_up"]
            and s["left_hand_up"] and s["right_hand_up"]
            for p in packets for s in [p["players"][1]]),
            "P2 sends a real hand-up shot only after the released/raised gesture")
        self.assertTrue(any(p["people"] == 0 for p in packets))
        self.assertTrue(all(
            not s["active"] and not s["hand_up"]
            for p in packets if p["people"] == 0 for s in p["players"]))
        self.assertTrue(any(
            p["people"] == 2 and all(s["active"] for s in p["players"])
            for p in packets), "normal two-person left/right camera remains active")
        self.assertTrue(any(
            p.get("requires_teacher_recalibration")
            and all(not s["active"]
                    and s["reason"] == "teacher_recalibration_required"
                    for s in p["players"])
            for p in packets), "observed two-body crossing latches BOTH score owners inactive")
        self.assertTrue(all(
            not any(s["active"] for s in p["players"])
            for p in packets if p.get("requires_teacher_recalibration")),
            "swapped detections NEVER regain scoring authority without a teacher reset")


if __name__ == "__main__":
    unittest.main()
