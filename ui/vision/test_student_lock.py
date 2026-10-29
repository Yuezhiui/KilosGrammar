"""Synthetic SINGLE OCCUPANT camera gate tests (no camera, YOLO or database)."""
import unittest
from student_lock import StudentLock


def person(track_id, x=0.5, height=0.65, eligible=True):
    return {"track_id": track_id, "x": x, "height": height, "eligible": eligible}


def enter(lock, t=0.0, id=4, x=.5):
    selected = None
    for i in range(12):
        selected, _, _ = lock.update([person(id, x)], t + i * .2)
    assert selected is not None
    return selected


class StudentLockTest(unittest.TestCase):
    def test_first_entry_needs_real_stable_frames_not_identity_registration(self):
        gate = StudentLock()
        self.assertIsNone(gate.locked_id)
        for i in range(4):
            target, _, _ = gate.update([person(None)], i * .2)
            self.assertIsNone(target)
        target, state, _ = gate.update([person(None)], .8)
        self.assertEqual(state, "locked")
        self.assertIsNotNone(target)
        self.assertEqual(gate.physical_track_id, -1)
        self.assertIsNone(gate.locked_id)
        self.assertEqual(gate.tracking_epoch, 1)

    def test_zero_people_immediately_revokes_control(self):
        gate = StudentLock()
        enter(gate)
        chosen, state, _ = gate.update([], 3.0)
        self.assertIsNone(chosen)
        self.assertEqual(state, "lost")
        self.assertTrue(gate.needs_reenrollment)

    def test_second_person_any_size_immediately_revokes_control(self):
        gate = StudentLock()
        enter(gate)
        for second in (.15, .5, .95):
            selected, state, _ = gate.update(
                [person(4, .5), person(-1, second, .21)], 3.0 + second)
            self.assertIsNone(selected)
            self.assertEqual(state, "ambiguous")
        self.assertEqual(gate.tracking_epoch, 1)

    def test_two_people_never_select_larger_nearer_or_old_id(self):
        gate = StudentLock()
        for index in range(16):
            chosen, state, _ = gate.update(
                [person(4, .5, .9), person(8, .94, .21)], index * .25)
            self.assertIsNone(chosen)
            self.assertEqual(state, "ambiguous")
        self.assertEqual(gate.tracking_epoch, 0)

    def test_full_position_range_permitted_after_initial_center(self):
        gate = StudentLock()
        enter(gate)
        t = 3.0
        x = .5
        for target_x in (.75, .95, .7, .4, .05, .5):
            while abs(target_x - x) > .1:
                x += .1 if target_x > x else -.1
                selected, state, _ = gate.update([person(-1, x)], t)
                self.assertEqual(state, "locked")
                self.assertIsNotNone(selected)
                t += .1
        self.assertIsNone(gate.locked_id)

    def test_corrupted_pose_cannot_become_game_input(self):
        gate = StudentLock()
        enter(gate)
        for invalid in (person(4, eligible=False), person(4, x=float("nan")),
                        person(4, height=0.03)):
            selected, state, _ = gate.update([invalid], 3.0)
            self.assertIsNone(selected)
            self.assertIn(state, ("occluded", "ambiguous"))

    def test_tracker_ids_may_churn_every_frame_without_interrupting_solo(self):
        gate = StudentLock()
        enter(gate)
        for i in range(140):
            selected, state, _ = gate.update([person(i if i % 3 else None, .5)], 3 + .1 * i)
            self.assertEqual(state, "locked")
            self.assertIsNotNone(selected)
        self.assertEqual(gate.tracking_epoch, 1)
        self.assertFalse(gate.needs_recalibration)

    def test_after_fifteen_or_sixty_seconds_absent_rejoins_without_recalibration(self):
        for absence in (5, 15, 60):
            with self.subTest(absence=absence):
                gate = StudentLock()
                enter(gate)
                gate.update([], 3)
                for i in range(1, int(absence * 5)):
                    gate.update([], 3 + i * .2)
                resumed = False
                for i in range(8):
                    person_now, state, _ = gate.update(
                        [person(None, .74, .63)], 3 + absence + 0.2 * (i + 1))
                    resumed = resumed or (person_now is not None)
                self.assertTrue(resumed)
                self.assertEqual(state, "locked")
                self.assertEqual(gate.tracking_epoch, 1)
                self.assertFalse(gate.needs_recalibration)

    def test_two_people_after_loss_never_resume_until_one_stable(self):
        gate = StudentLock()
        enter(gate)
        gate.update([], 3)
        for i in range(24):
            chosen, state, _ = gate.update(
                [person(10), person(11, .7)], 4 + .2 * i)
            self.assertIsNone(chosen)
            self.assertEqual(state, "ambiguous")
        resumed = False
        for i in range(8):
            chosen, state, _ = gate.update([person(12, .6)], 9 + i * .2)
            resumed = resumed or chosen is not None
        self.assertTrue(resumed)
        self.assertEqual(state, "locked")

    def test_detected_count_overrides_malformed_or_idless_boxes(self):
        gate = StudentLock()
        enter(gate)
        chosen, state, _ = gate.update([person(4)], 3.0, detected_count=2)
        self.assertIsNone(chosen)
        self.assertEqual(state, "ambiguous")
        chosen, state, _ = gate.update([person(4)], 3.2, detected_count=0)
        self.assertIsNone(chosen)
        self.assertEqual(state, "lost")


if __name__ == "__main__":
    unittest.main()
