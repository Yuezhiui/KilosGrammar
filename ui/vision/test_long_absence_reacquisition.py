"""Full synthetic occupied-camera return checks; NO webcam/YOLO/DB access."""
import time
import unittest
from pose_worker import LatestCamera, observed_pose_people, preview_people
from student_lock import StudentLock


def person(pid=None, x=.5, height=.65, eligible=True):
    return {"track_id": pid, "x": x, "height": height, "eligible": eligible}


def begin(gate):
    selected = None
    for i in range(9):
        selected, _, _ = gate.update([person(7)], i * .2)
    assert selected is not None


class LongAbsentSoloTests(unittest.TestCase):
    def test_5_15_60_second_departures_keep_calibration_and_round_epoch(self):
        for delay in (5, 15, 60):
            with self.subTest(delay=delay):
                gate = StudentLock()
                begin(gate)
                for i in range(int(delay * 5)):
                    selected, state, _ = gate.update([], 2.0 + .2 * i)
                    self.assertIsNone(selected)
                    self.assertEqual(state, "lost")
                events = 0
                for i in range(12):
                    selected, state, _ = gate.update(
                        [person(None, .7, .65)], 2.0 + delay + .2 * i)
                    events += int(gate.lock_reacquired)
                self.assertIsNotNone(selected)
                self.assertEqual(state, "locked")
                self.assertEqual(events, 1)
                self.assertEqual(gate.tracking_epoch, 1)
                self.assertFalse(gate.needs_recalibration)
                self.assertIsNone(gate.locked_id)

    def test_every_frame_different_id_still_continuous_one_person(self):
        gate = StudentLock()
        begin(gate)
        for i in range(90):
            selected, state, _ = gate.update([person(i if i % 3 else None)], 2 + i * .1)
            self.assertEqual(state, "locked")
            self.assertIsNotNone(selected)
            self.assertFalse(gate.needs_recalibration)

    def test_absence_followed_by_two_then_one_requires_fresh_solo_hold(self):
        gate = StudentLock()
        begin(gate)
        gate.update([], 2)
        for i in range(110):
            chosen, state, _ = gate.update(
                [person(81), person(82, .7, .32)], 3 + i * .15)
            self.assertIsNone(chosen)
            self.assertEqual(state, "ambiguous")
        first, _, _ = gate.update([person(91, .62)], 20)
        self.assertIsNone(first)
        for i in range(1, 9):
            first, _, _ = gate.update([person(None, .62)], 20 + .2 * i)
        self.assertIsNotNone(first)
        self.assertFalse(gate.needs_recalibration)

    def test_two_people_even_same_or_absent_bytetrack_id_never_control(self):
        gate = StudentLock()
        begin(gate)
        for ids in ((7, 7), (7, None), (None, None), (99, 100)):
            for i in range(5):
                chosen, state, _ = gate.update(
                    [person(ids[0]), person(ids[1], .8, .32)], 2 + .1 * i)
                self.assertIsNone(chosen)
                self.assertEqual(state, "ambiguous")

    def test_one_idless_valid_pose_succeeds_without_fake_tracking_identity(self):
        gate = StudentLock()
        begin(gate)
        gate.update([], 2)
        for i in range(10):
            chosen, state, _ = gate.update([person(None, .59)], 2.2 + .2*i)
        self.assertIsNotNone(chosen)
        self.assertEqual(state, "locked")
        self.assertEqual(gate.physical_track_id, -1)
        self.assertIsNone(gate.locked_id)

    def test_malformed_extra_box_count_blocks_lone_valid_person(self):
        gate = StudentLock()
        begin(gate)
        selected, state, _ = gate.update([person(7)], 2, detected_count=2)
        self.assertIsNone(selected)
        self.assertEqual(state, "ambiguous")
        selected, state, _ = gate.update([], 2.2, detected_count=1)
        self.assertIsNone(selected)
        self.assertEqual(state, "ambiguous")


class CameraAndNoIDTest(unittest.TestCase):
    def test_real_one_person_no_tracker_id_is_eligible_if_pose_measured(self):
        class Array:
            def __init__(self, values):
                self.values = values
            def cpu(self): return self
            def tolist(self): return self.values
        class Box:
            id = None
            xyxy = Array([[150, 70, 450, 452]])
            def __len__(self): return 1
        class Keypoints:
            pts = [[0, 0, 0] for _ in range(17)]
            for idx, x, y in ((5, 250, 150), (6, 380, 150), (11, 265, 300),
                              (12, 365, 300), (9, 240, 220), (10, 390, 220)):
                pts[idx] = [x, y, .98]
            data = Array([pts])
        class Prediction:
            boxes = Box()
            keypoints = Keypoints()
        detected, shown = observed_pose_people(Prediction(), 640, 480)
        self.assertEqual(len(detected), 1)
        self.assertTrue(detected[0]["eligible"])
        self.assertEqual(detected[0]["track_id"], -1)
        self.assertEqual(shown[0]["track_id"], -1)
        gate = StudentLock()
        for i in range(8):
            chosen, state, _ = gate.update(detected, i*.2, detected_count=1)
        self.assertIsNotNone(chosen)
        self.assertEqual(state, "locked")
        self.assertEqual(preview_people(shown, chosen)[0]["preview_role"], "active")

    def test_32_failed_camera_reads_then_fresh_frames_work(self):
        class Camera:
            def __init__(self): self.calls = 0; self.closed = False
            def read(self):
                self.calls += 1
                if self.calls <= 32 or self.closed:
                    return False, None
                time.sleep(.008)
                return True, {"frame": self.calls}
            def release(self): self.closed = True
        source = Camera()
        reader = LatestCamera(source)
        reader.start()
        try:
            self.assertTrue(reader.wait_for_first_frame(2.0))
            frame, seq, captured = reader.newest_with_timestamp(-1)
            self.assertIsNotNone(frame)
            self.assertGreater(seq, 0)
            self.assertIsInstance(captured, float)
        finally:
            reader.close()
        self.assertFalse(reader.thread.is_alive())

    def test_no_actual_people_no_remembered_skeletons(self):
        class Arr:
            def __init__(self, values): self.values = values
            def cpu(self): return self
            def tolist(self): return self.values
        class Box:
            id = None
            xyxy = Arr([])
            def __len__(self): return 0
        class Prediction:
            boxes = Box()
            keypoints = None
        p, shown = observed_pose_people(Prediction(), 640, 480)
        self.assertEqual(p, [])
        self.assertEqual(shown, [])


if __name__ == "__main__":
    unittest.main()
