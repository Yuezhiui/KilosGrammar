"""Isolated recovery tests: never opens a webcam or imports YOLO."""
import unittest

from pose_worker import resilient_body_position
from student_lock import StudentLock


def person(track_id, x=0.5, height=0.6):
    return {"track_id": track_id, "x": x, "height": height}


def enroll(lock):
    for n in range(9):
        selected, _, _ = lock.update([person(7)], n * 0.2)
    assert selected is not None


class RecoveryTests(unittest.TestCase):
    def test_forward_back_motion_preserves_original_track(self):
        lock = StudentLock()
        enroll(lock)
        for t, height in [(2.0, 0.7), (2.2, 0.86), (2.4, 0.72), (2.6, 0.6)]:
            selected, state, _ = lock.update([person(7, 0.515, height)], t)
            self.assertEqual(state, "locked")
            self.assertEqual(selected["track_id"], 7)

    def test_missing_pose_can_return_after_loss_notice(self):
        lock = StudentLock()
        enroll(lock)
        self.assertEqual(lock.update([], 2)[1], "occluded")
        self.assertEqual(lock.update([], 2.6)[1], "occluded")
        self.assertEqual(lock.update([], 3.3)[1], "lost")
        selected, state, _ = lock.update([person(7, 0.52, 0.74)], 4)
        self.assertEqual(state, "locked")
        self.assertEqual(selected["track_id"], 7)

    def test_bystander_not_automatically_substituted(self):
        lock = StudentLock()
        enroll(lock)
        for step in range(35):
            chosen, state, detail = lock.update([person(12, 0.5, 0.62)], 2 + step * 0.2)
            self.assertIsNone(chosen, (state, detail))
        self.assertEqual(lock.locked_id, 7)

    def test_new_id_reacquires_after_empty_view_and_solo_hold(self):
        lock = StudentLock()
        enroll(lock)
        lock.update([], 2.0)
        lock.update([], 2.4)  # Empty camera area verified for 0.4s.
        for step in range(13):
            chosen, _, _ = lock.update([person(22, 0.51, 0.63)], 3.0 + step * 0.2)
            if step < 12:
                self.assertIsNone(chosen)
        self.assertIsNotNone(chosen)
        self.assertEqual(chosen["track_id"], 22)
        self.assertEqual(lock.locked_id, 22)

    def test_two_people_block_recovery_even_after_clear_view(self):
        lock = StudentLock()
        enroll(lock)
        lock.update([], 2)
        lock.update([], 2.5)
        for step in range(18):
            selected, _, _ = lock.update([person(31), person(32, 0.61, 0.38)], 3 + step * 0.2)
            self.assertIsNone(selected)

    def test_missing_keypoints_never_invent_position(self):
        low = [[0.5, 0.5, 0.1] for _ in range(17)]
        self.assertIsNone(resilient_body_position(low))
        low[5] = [0.35, 0.4, 0.9]
        self.assertIsNone(resilient_body_position(low))
        low[6] = [0.55, 0.4, 0.9]
        self.assertAlmostEqual(resilient_body_position(low), 0.45)

    def test_restarted_worker_requires_clear_camera_then_solo_player(self):
        lock = StudentLock()
        lock.require_clear_reenrollment()
        for step in range(25):
            selected, _, _ = lock.update([person(18)], step * 0.2)
            self.assertIsNone(selected)  # Previous identity is unknown.
        lock.update([], 5.0)
        lock.update([], 5.4)
        for step in range(13):
            selected, _, _ = lock.update([person(18)], 6.0 + step * 0.2)
        self.assertEqual(selected["track_id"], 18)


if __name__ == "__main__":
    unittest.main()
