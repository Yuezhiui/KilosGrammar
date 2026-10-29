"""Deterministic calibration-latency probes; no actual camera, YOLO or database.

Run: python -m unittest -v test_pose_latency_offline.py from ui/vision.
These exercise the real LatestCamera and StudentLock implementation with
controlled timestamps. The worker's real model import/warmup is instrumented
separately; synthetic timing is not a hardware FPS benchmark.
"""
from __future__ import annotations

import threading
import time
import unittest

from pose_worker import LatestCamera, resilient_body_position
from student_lock import StudentLock


def person(identifier: int, position: float = 0.50, height: float = 0.65):
    return {"track_id": identifier, "x": position, "height": height}


class FrameSource:
    def __init__(self, interval_seconds=0.005):
        self.interval_seconds = interval_seconds
        self.counter = 0
        self.closed = threading.Event()

    def read(self):
        self.closed.wait(self.interval_seconds)
        if self.closed.is_set():
            return False, None
        self.counter += 1
        return True, self.counter

    def release(self):
        self.closed.set()


class CameraLatestFrameTests(unittest.TestCase):
    def test_inference_backpressure_discards_old_captured_frames(self):
        camera = FrameSource()
        reader = LatestCamera(camera)
        reader.start()
        try:
            deadline = time.monotonic() + 1.0
            while reader.sequence < 5 and time.monotonic() < deadline:
                time.sleep(0.002)
            original_frame, original_seq = reader.newest(-1)
            self.assertIsNotNone(original_frame)
            # Wait for actual source-sequence progress; Windows camera threads
            # may be scheduled unpredictably under concurrent Godot builds.
            deadline = time.monotonic() + 0.8
            while reader.sequence < original_seq + 5 and time.monotonic() < deadline:
                time.sleep(0.002)
            newest_frame, newest_seq = reader.newest(original_seq)
            self.assertGreaterEqual(newest_seq - original_seq, 5,
                                    "a slow inference must skip 5+ obsolete frames")
            self.assertEqual(newest_frame, newest_seq,
                             "latest camera reading must correspond to newest sequence")
            self.assertEqual(reader.newest(newest_seq), (None, newest_seq),
                             "unconsumed backlog must not reappear after inference")
        finally:
            reader.close()
        self.assertFalse(reader.thread.is_alive(), "reader shuts down cleanly")

    def test_dropped_consecutive_reads_never_invent_body_position(self):
        weak = [[0.5, 0.6, 0.2] for _ in range(17)]
        self.assertIsNone(resilient_body_position(weak))
        weak[5] = [0.4, 0.35, 0.85]
        self.assertIsNone(resilient_body_position(weak))
        weak[6] = [0.6, 0.35, 0.85]
        self.assertAlmostEqual(resilient_body_position(weak), 0.5)


class PersonEnrollmentTimingTests(unittest.TestCase):
    def test_first_lock_needs_enrollment_time_and_frames(self):
        for fps in (1, 2, 4, 8, 15, 30):
            with self.subTest(fps=fps):
                lock = StudentLock()
                dt = 1.0 / fps
                first_lock_at = None
                for index in range(int(9.0 * fps) + 1):
                    chosen, _, _ = lock.update([person(17)], index * dt)
                    if chosen is not None:
                        first_lock_at = index * dt
                        break
                self.assertIsNotNone(first_lock_at)
                self.assertGreaterEqual(first_lock_at + 1e-6, lock.ENROLL_SECONDS)
                self.assertGreaterEqual(index + 1, lock.ENROLL_FRAMES)
                # New occupancy gate requires 4 actual source frames and a
                # modest steady hold, never 8 ByteTrack registration packets.
                if fps == 4:
                    self.assertGreaterEqual(first_lock_at, 0.75)
                if fps == 1:
                    self.assertGreaterEqual(first_lock_at, 3.0,
                                            "4 unique poses at 1 FPS impose 3s lower bound")
                if fps == 2:
                    self.assertGreaterEqual(first_lock_at, 1.5,
                                            "4 unique poses at 2 FPS impose 1.5s lower bound")

    def test_bystander_presence_pauses_all_control_immediately(self):
        lock = StudentLock()
        for index in range(14):
            lock.update([person(17)], index * 0.12)
        self.assertEqual(lock.tracking_epoch, 1)
        for index in range(10):
            chosen, state, _ = lock.update(
                [person(17, 0.48), person(99, 0.52, 0.7)], 2.0 + index * 0.1)
            self.assertIsNone(chosen)
            self.assertEqual(state, "ambiguous")
        self.assertFalse(lock.needs_recalibration)

    def test_recovery_requires_only_fresh_solo_hold_after_restart(self):
        lock = StudentLock()
        for index in range(14):
            lock.update([person(17)], index * 0.12)
        self.assertEqual(lock.tracking_epoch, 1)
        lock.require_clear_reenrollment()
        selected = None
        for index in range(32):
            selected, _, _ = lock.update([person(21)], 2.0 + index * 0.12)
            if selected is not None:
                self.assertGreaterEqual(index + 1, lock.RECOVER_FRAMES)
                self.assertGreaterEqual(index * 0.12 + 1e-6, lock.RECOVER_SECONDS)
                break
        self.assertIsNotNone(selected)
        self.assertEqual(lock.tracking_epoch, 1)
        self.assertFalse(lock.needs_recalibration)


if __name__ == "__main__":
    unittest.main()
