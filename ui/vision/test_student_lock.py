"""Deterministic crowd/occlusion regression tests; never opens a camera."""
import unittest

from student_lock import StudentLock


def person(track_id: int, x: float, height: float = 0.6) -> dict:
    return {"track_id": track_id, "x": x, "height": height}


def enroll(lock: StudentLock, tracked: list[dict], t: float = 0) -> None:
    for n in range(9):
        chosen, _, _ = lock.update(tracked, t + n * 0.2)
    assert chosen is not None


class StudentLockTest(unittest.TestCase):
    def test_locks_nearest_center_student_not_background(self):
        lock = StudentLock()
        enroll(lock, [person(12, 0.51, 0.67), person(3, 0.55, 0.26)])
        self.assertEqual(lock.locked_id, 12)
        target, state, _ = lock.update([person(12, 0.54, 0.67), person(3, 0.55, 0.26)], 2)
        self.assertEqual(state, "locked")
        self.assertEqual(target["track_id"], 12)

    def test_people_walking_into_background_do_not_interrupt(self):
        lock = StudentLock()
        enroll(lock, [person(5, 0.50)])
        target, state, _ = lock.update([person(6, 0.42, 0.69), person(5, 0.55)], 2)
        self.assertEqual((target["track_id"], state), (5, "locked"))

    def test_ambiguous_crowd_does_not_enroll_random_person(self):
        lock = StudentLock()
        for n in range(12):
            person_seen, state, _ = lock.update([person(5, 0.47, 0.60), person(8, 0.58, 0.55)], n * 0.2)
            self.assertIsNone(person_seen)
            self.assertEqual(state, "ambiguous")
        self.assertIsNone(lock.locked_id)

    def test_player_outside_enrollment_zone_is_not_selected(self):
        lock = StudentLock()
        for n in range(12):
            chosen, state, _ = lock.update([person(5, 0.1, 0.80)], n * 0.2)
            self.assertIsNone(chosen)
            self.assertEqual(state, "waiting")

    def test_lost_student_never_replaced_automatically(self):
        lock = StudentLock()
        enroll(lock, [person(11, 0.5)])
        target, state, _ = lock.update([person(12, 0.48)], 2)
        self.assertIsNone(target)
        self.assertEqual(state, "occluded")
        target, state, _ = lock.update([person(12, 0.48)], 2.85)
        self.assertIsNone(target)
        self.assertEqual(state, "lost")
        target, state, _ = lock.update([person(11, 0.51)], 3)
        self.assertIsNone(target)
        self.assertEqual(state, "lost")

    def test_short_occlusion_same_track_can_resume(self):
        lock = StudentLock()
        enroll(lock, [person(4, 0.5)])
        self.assertEqual(lock.update([], 2)[1], "occluded")
        target, state, _ = lock.update([person(4, 0.55)], 2.3)
        self.assertEqual(state, "locked")
        self.assertEqual(target["track_id"], 4)

    def test_track_id_jump_is_rejected(self):
        lock = StudentLock()
        enroll(lock, [person(1, 0.5)])
        target, state, _ = lock.update([person(1, 0.92)], 2.0)
        self.assertIsNone(target)
        self.assertEqual(state, "lost")

    def test_abrupt_size_change_is_rejected(self):
        lock = StudentLock()
        enroll(lock, [person(1, 0.5, 0.6)])
        target, state, _ = lock.update([person(1, 0.53, 0.2)], 2)
        self.assertIsNone(target)
        self.assertEqual(state, "lost")

    def test_reset_requires_new_lock(self):
        lock = StudentLock()
        enroll(lock, [person(7, 0.50)])
        lock = StudentLock()  # Explicit student reset starts a new worker.
        self.assertIsNone(lock.locked_id)
        self.assertEqual(lock.update([person(9, 0.50)], 0)[1], "enrolling")


if __name__ == "__main__":
    unittest.main()
