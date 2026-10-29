"""Synthetic camera occupancy recovery (no webcam or YOLO imports)."""
import unittest
from pose_worker import resilient_body_position
from student_lock import StudentLock


def person(track_id=-1, x=.5, height=.65):
    return {"track_id": track_id, "x": x, "height": height}


def ready(gate):
    for i in range(10):
        found, _, _ = gate.update([person(7)], i*.2)
    assert found


class RecoveryTests(unittest.TestCase):
    def test_forward_back_motion_preserves_live_single_person(self):
        gate = StudentLock()
        ready(gate)
        for t, height in ((2, .7), (2.2, .86), (2.4, .72), (2.6, .6)):
            found, state, _ = gate.update([person(9, .52, height)], t)
            self.assertEqual(state, "locked")
            self.assertIsNotNone(found)
        self.assertEqual(gate.tracking_epoch, 1)

    def test_missing_pose_can_return_after_loss_notice_without_recalibration(self):
        gate = StudentLock()
        ready(gate)
        for timestamp in (2, 2.6, 3.3):
            self.assertEqual(gate.update([], timestamp)[1], "lost")
        for i in range(8):
            selected, state, _ = gate.update([person(100, .52)], 4 + .2*i)
        self.assertEqual(state, "locked")
        self.assertIsNotNone(selected)
        self.assertFalse(gate.needs_recalibration)

    def test_bystander_means_second_visible_person_pause(self):
        gate = StudentLock()
        ready(gate)
        for i in range(20):
            selected, state, _ = gate.update(
                [person(7), person(12, .55, .35)], 2 + i*.2)
            self.assertIsNone(selected)
            self.assertEqual(state, "ambiguous")

    def test_no_person_rejoin_new_id_fresh_hold(self):
        gate = StudentLock()
        ready(gate)
        for i in range(50):
            gate.update([], 2 + i*.2)
        for i in range(8):
            selected, state, _ = gate.update([person(22, .51)], 12.4+i*.2)
        self.assertIsNotNone(selected)
        self.assertEqual(state, "locked")
        self.assertEqual(gate.tracking_epoch, 1)

    def test_two_people_block_recovery_even_after_empty(self):
        gate = StudentLock()
        ready(gate)
        gate.update([], 2)
        for i in range(18):
            selected, state, _ = gate.update(
                [person(31), person(32, .61, .38)], 3+i*.2)
            self.assertIsNone(selected)
            self.assertEqual(state, "ambiguous")

    def test_missing_keypoints_never_invent_position(self):
        low = [[.5, .5, .1] for _ in range(17)]
        self.assertIsNone(resilient_body_position(low))
        low[5] = [.35, .4, .9]
        self.assertIsNone(resilient_body_position(low))
        low[6] = [.55, .4, .9]
        self.assertAlmostEqual(resilient_body_position(low), .45)

    def test_restarted_worker_requires_only_stable_single(self):
        gate = StudentLock()
        gate.require_clear_reenrollment()
        for i in range(8):
            selected, state, _ = gate.update([person(18)], i*.2)
        self.assertIsNotNone(selected)
        self.assertEqual(state, "locked")


if __name__ == "__main__":
    unittest.main()
