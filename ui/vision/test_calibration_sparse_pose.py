"""Offline timing/occupancy regressions for real camera calibration packets.

Run from repo root:
  C:/Espressif/tools/python/python.exe -B -m unittest discover -s ui/vision -p test_calibration_sparse_pose.py -v

No webcams, model weights, real student images, database or network access.
"""
from __future__ import annotations

import unittest

from student_lock import StudentLock


def person(track_id: int, x: float = 0.50, height: float = 0.67) -> dict:
    return {"track_id": track_id, "x": x, "height": height}


class CalibrationSparseEnrollmentTest(unittest.TestCase):
    def test_real_frames_required_at_sparse_inference_rates(self):
        for fps in (2.0, 2.5, 3.0, 4.0, 8.0, 15.0):
            with self.subTest(fps=fps):
                lock = StudentLock()
                first_valid = None
                first_index = -1
                for frame_index in range(int(fps * 12)):
                    t = frame_index / fps
                    selected, state, _ = lock.update([person(17)], t)
                    if selected is not None:
                        first_valid = t
                        first_index = frame_index
                        self.assertEqual(state, "locked")
                        break
                    self.assertIn(state, ("enrolling", "waiting"))
                self.assertIsNotNone(first_valid)
                self.assertGreaterEqual(first_index + 1, lock.ENROLL_FRAMES,
                                        "Redraws cannot substitute for source frames")
                self.assertGreaterEqual(first_valid + 1e-6, lock.ENROLL_SECONDS)
                self.assertGreaterEqual(first_valid + 1e-6,
                                        (lock.ENROLL_FRAMES - 1) / fps)
                # New occupancy gate takes a modest hold; old ByteTrack
                # registration imposed an unnecessary 3.5+ second delay.
                if fps == 2.0:
                    self.assertGreaterEqual(first_valid, lock.ENROLL_SECONDS)
                    self.assertLessEqual(first_valid, 2.5)

    def test_3_second_hold_also_needs_8_distinct_real_student_frames(self):
        # Model StudentLock + calibration's independent 3 seconds and 8
        # accepted distinct inference frames. This is a lower bound, excluding
        # intro, webcam startup and frame loss.
        for fps in (2.0, 2.5, 3.0, 4.0, 8.0, 15.0):
            with self.subTest(fps=fps):
                lock = StudentLock()
                enrolled_at = None
                tracked_times = []
                for index in range(int(fps * 16)):
                    timestamp = index / fps
                    selected, _, _ = lock.update([person(22)], timestamp)
                    if selected is None:
                        continue
                    if enrolled_at is None:
                        enrolled_at = timestamp
                    tracked_times.append(timestamp)
                    elapsed = timestamp - enrolled_at
                    if elapsed + 1e-6 >= 3.0 and len(tracked_times) >= 8:
                        break
                self.assertIsNotNone(enrolled_at)
                self.assertGreaterEqual(len(tracked_times), 8)
                self.assertGreaterEqual(tracked_times[-1] - enrolled_at + 1e-6, 3.0)
                self.assertGreaterEqual(tracked_times[-1] - enrolled_at + 1e-6,
                                        7 / fps)
                self.assertEqual(len(set(tracked_times)), len(tracked_times),
                                 "Every accepted sample must have a unique source time")


class CalibrationCrowdAndRecoveryTest(unittest.TestCase):
    def test_two_people_pause_even_when_one_moves_right_or_left(self):
        lock = StudentLock()
        for index in range(12):
            lock.update([person(17, 0.50)], index * 0.4)
        self.assertEqual(lock.tracking_epoch, 1)
        # Both people are real occupants, even if the camera detects one more
        # confidently than the other. No one's pose can control gameplay.
        for index, x in enumerate([0.57, 0.64, 0.72, 0.80, 0.73, 0.61, 0.48,
                                   0.37, 0.29, 0.20]):
            selected, state, _ = lock.update(
                [person(17, x), person(99, 0.5, 0.74)],
                5.0 + index * 0.4)
            self.assertIsNone(selected)
            self.assertEqual(state, "ambiguous")
        self.assertEqual(lock.tracking_epoch, 1)

    def test_one_new_id_can_resume_after_hold_with_no_recalibration(self):
        lock = StudentLock()
        for index in range(10):
            lock.update([person(17)], index * 0.4)
        self.assertEqual(lock.tracking_epoch, 1)
        lock.update([], 4.0)
        self.assertTrue(lock.needs_reenrollment)
        active = None
        for index in range(12):
            active, state, _ = lock.update(
                [person(99, 0.48, 0.75)], 4.1 + index * 0.4)
        self.assertIsNotNone(active, "Single person resumes after brief stable hold")
        self.assertEqual(state, "locked")
        self.assertEqual(lock.tracking_epoch, 1)
        self.assertFalse(lock.needs_recalibration)

    def test_no_empty_view_ritual_required_after_worker_reconnect(self):
        lock = StudentLock()
        for index in range(10):
            lock.update([person(17)], index * 0.4)
        lock.require_clear_reenrollment()
        # A single stable visible person suffices. No ByteTrack ID registration
        # and no prescribed empty-camera dance before controls return.
        seen_recovered = False
        for index in range(12):
            chosen, state, _ = lock.update([person(99, 0.50)], 4.1 + index * 0.4)
            if chosen is not None:
                self.assertEqual(state, "locked")
                self.assertEqual(chosen["track_id"], 99)
                seen_recovered = True
                break
        self.assertTrue(seen_recovered)


if __name__ == "__main__":
    unittest.main()
