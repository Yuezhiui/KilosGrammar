"""Synthetic crowd, crossing, live preview and permanent-stall regressions.

No physical webcam, YOLO weights, external service, or database is accessed.
Run: py -3.11 -m unittest ui.vision.test_pose_multi_person_resilience
"""
from __future__ import annotations

import socket
from pathlib import Path
import sys
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from student_lock import StudentLock
from pose_worker import LatestPreview, draw_skeleton_preview, preview_people

def person(track: int, x: float, height: float = 0.65) -> dict:
    joints = [[0.5, 0.5, 0.0] for _ in range(17)]
    for index, jx, jy in ((5, x-0.07, 0.31), (6, x+0.07, 0.31),
                          (7, x-0.12, 0.45), (8, x+0.12, 0.45),
                          (9, x-0.14, 0.61), (10, x+0.14, 0.61),
                          (11, x-0.06, 0.62), (12, x+0.06, 0.62)):
        joints[index] = [jx, jy, 0.98]
    return {"track_id": track, "x": x, "height": height, "keypoints": joints,
            "box": [(x-0.13)*640, 0.22*480, (x+0.13)*640, 0.84*480]}


def enroll(lock, target_id=7):
    for n in range(9):
        candidate, _, _ = lock.update([person(target_id, 0.5)], n * 0.2)
    assert candidate is not None


class PersistentOwnerTests(unittest.TestCase):
    def test_bystander_can_be_seen_but_all_control_pauses(self):
        lock = StudentLock()
        enroll(lock)
        active, state, _ = lock.update(
            [person(8, 0.28, 0.7), person(7, 0.54, 0.65)], 2.0)
        self.assertEqual(state, "ambiguous")
        self.assertIsNone(active)
        showing = preview_people([person(8, 0.28), person(7, 0.54)], active)
        self.assertEqual([(p["track_id"], p["preview_role"]) for p in showing],
                         [(8, "candidate"), (7, "candidate")])

    def test_crossing_suspends_player_until_one_solo_hold(self):
        lock = StudentLock()
        enroll(lock)
        active, state, _ = lock.update(
            [person(7, 0.5), person(8, 0.535, 0.62)], 2)
        self.assertIsNone(active)
        self.assertEqual(state, "ambiguous")
        self.assertTrue(lock.needs_reenrollment)
        shown = preview_people([person(7, 0.5), person(8, 0.535)], active)
        self.assertEqual([p["preview_role"] for p in shown],
                         ["candidate", "candidate"])
        # No need to step out of frame. One stable person after crossing
        # resumes the same round WITHOUT another physical calibration.
        for index in range(14):
            active, state, _ = lock.update([person(7, 0.5)], 2.2+0.2*index)
        self.assertEqual(state, "locked")
        self.assertEqual(active["track_id"], 7)
        self.assertEqual(lock.tracking_epoch, 1)
        self.assertFalse(lock.needs_recalibration)

    def test_short_uncontested_occlusion_recovers_new_id_with_solo_hold(self):
        lock = StudentLock()
        enroll(lock)
        self.assertEqual(lock.update([], 2.0)[1], "lost")
        for index in range(7):
            active, state, _ = lock.update([person(17, 0.51)], 2.4 + .2*index)
        self.assertEqual(state, "locked")
        self.assertEqual(active["track_id"], 17)

    def test_swapped_id_is_ignored_and_duplicate_two_boxes_pause(self):
        lock = StudentLock()
        enroll(lock)
        self.assertIsNotNone(lock.update([person(9, 0.5)], 2.0)[0])
        lock = StudentLock()
        enroll(lock)
        active, state, _ = lock.update(
            [person(7, 0.50), person(7, 0.53)], 2)
        self.assertIsNone(active)
        self.assertEqual(state, "ambiguous")
        self.assertTrue(lock.needs_reenrollment)

    def test_occluder_without_torso_keypoints_blocks_all_gameplay(self):
        lock = StudentLock()
        enroll(lock)
        # A camera box remains visible but shoulders/hips are hidden:
        # StudentLock must treat it as crossing evidence, not a play input.
        occluder = {"track_id": 14, "x": 0.51, "height": 0.64,
                    "eligible": False,
                    "box": [(0.51-0.13)*640, 0.22*480,
                            (0.51+0.13)*640, 0.84*480]}
        chosen, state, _ = lock.update([person(7, 0.5), occluder], 2.0)
        self.assertIsNone(chosen)
        self.assertEqual(state, "ambiguous")
        lock = StudentLock()
        for n in range(12):
            chosen, state, _ = lock.update([occluder], n*0.2)
            self.assertIsNone(chosen)
        self.assertEqual(lock.tracking_epoch, 0)


class PreviewRecoveryTests(unittest.TestCase):
    class FakeFrame:
        shape = (480, 640, 3)

    class SyntheticDrawing:
        def __init__(self):
            self.lines = []
            self.joints = []

        def resize(self, frame, _size):
            return frame

        def line(self, _frame, first, second, color, thickness):
            self.lines.append((first, second, color, thickness))

        def circle(self, _frame, center, radius, color, thickness):
            self.joints.append((center, radius, color, thickness))

    def test_real_passive_skeletons_draw_distinct_from_player(self):
        original = self.FakeFrame()
        cv = self.SyntheticDrawing()
        people = [person(7, 0.34), person(9, 0.68)]
        roles = preview_people(people, people[0])
        frame = draw_skeleton_preview(cv, original, roles)
        self.assertIs(frame, original)
        self.assertGreaterEqual(len(cv.lines), 6)
        self.assertIn((65, 255, 80), [line[2] for line in cv.lines])
        self.assertIn((145, 125, 85), [line[2] for line in cv.lines])
        self.assertIn(1, [line[3] for line in cv.lines])
        self.assertIn(3, [line[3] for line in cv.lines])

    def test_missing_person_never_displays_remembered_bones(self):
        canvas = self.FakeFrame()
        cv = self.SyntheticDrawing()
        no_active = preview_people([person(8, 0.5)], None)
        self.assertEqual(no_active[0]["preview_role"], "candidate")
        draw_skeleton_preview(cv, canvas, no_active)
        self.assertTrue(cv.joints)
        cv.joints.clear()
        cv.lines.clear()
        draw_skeleton_preview(cv, canvas, [])
        self.assertFalse(cv.joints)
        self.assertFalse(cv.lines)

    def test_transient_preview_sender_exception_does_not_kill_thread(self):
        class FlakySocket:
            def __init__(self):
                self.attempts = 0
                self.packets = []

            def sendto(self, packet, _destination):
                self.attempts += 1
                if self.attempts == 1:
                    raise OSError("synthetic dropped JPEG datagram")
                self.packets.append(packet)

        sender = FlakySocket()
        worker = LatestPreview(self.SyntheticDrawing(), sender, ("127.0.0.1", 49123),
                               (0.0, 0.0), (1.0, 1.0))
        worker.start()
        frame = self.FakeFrame()
        try:
            with patch("pose_worker.encode_preview_jpeg", return_value=b"real-fake-jpeg"):
                deadline = time.monotonic() + 1.5
                while time.monotonic() < deadline:
                    worker.submit(frame, preview_people([person(7, 0.5)], None))
                    if sender.packets:
                        break
                    time.sleep(0.03)
            self.assertGreaterEqual(sender.attempts, 2)
            self.assertTrue(sender.packets, "live previews resume after failure")
            self.assertTrue(worker.thread.is_alive())
            self.assertGreater(worker.total_failures, 0)
        finally:
            worker.close()
        self.assertFalse(worker.thread.is_alive())


if __name__ == "__main__":
    unittest.main()
