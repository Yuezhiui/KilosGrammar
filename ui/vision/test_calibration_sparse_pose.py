"""Offline timing/identity regressions for real camera calibration packets.

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
                # At 2.0fps, teacher may see a live preview for >3.5s before
                # StudentLock emits its very first valid tracked student packet.
                if fps == 2.0:
                    self.assertGreaterEqual(first_valid, 3.5)

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
    def test_sparse_bystander_never_steals_existing_student_in_right_or_left(self):
        lock = StudentLock()
        for index in range(12):
            lock.update([person(17, 0.50)], index * 0.4)
        self.assertEqual(lock.locked_id, 17)
        # Student 17 is walking RIGHT then LEFT. Bystander 99 may cross the
        # CENTER enrollment region; the old locked_id remains authoritative.
        for index, x in enumerate([0.57, 0.64, 0.72, 0.80, 0.73, 0.61, 0.48,
                                   0.37, 0.29, 0.20]):
            selected, state, _ = lock.update(
                [person(17, x), person(99, 0.5, 0.74)],
                5.0 + index * 0.4)
            self.assertIsNotNone(selected)
            self.assertEqual(state, "locked")
            self.assertEqual(selected["track_id"], 17)
            self.assertEqual(lock.locked_id, 17)

    def test_bystander_only_frames_force_reenrollment_not_ghost_movement(self):
        lock = StudentLock()
        for index in range(10):
            lock.update([person(17)], index * 0.4)
        self.assertEqual(lock.locked_id, 17)
        for index in range(12):
            selected, state, _ = lock.update(
                [person(99, 0.48, 0.75)], 4.1 + index * 0.4)
            self.assertIsNone(selected, "Bystander never gets the prior player's pose")
            self.assertIn(state, ("lost", "occluded"))
        self.assertEqual(lock.locked_id, 17)
        self.assertTrue(lock.needs_reenrollment)

    def test_empty_view_and_unambiguous_center_needed_for_new_lock(self):
        lock = StudentLock()
        for index in range(10):
            lock.update([person(17)], index * 0.4)
        lock.require_clear_reenrollment()
        # Reconnection cannot happen with even a stationary single bystander
        # until the whole view was clearly empty for >=0.35s.
        for index in range(12):
            selected, _, _ = lock.update([person(99, 0.50)], 4.1 + index * 0.4)
            self.assertIsNone(selected)
        lock.update([], 10.0)
        lock.update([], 10.4)
        seen_recovered = False
        for index in range(12):
            chosen, state, _ = lock.update([person(99, 0.50)], 11.0 + index * 0.4)
            if chosen is not None:
                self.assertEqual(state, "locked")
                self.assertEqual(chosen["track_id"], 99)
                seen_recovered = True
                break
        self.assertTrue(seen_recovered)


if __name__ == "__main__":
    unittest.main()
