"""Independent, repeatable classroom-spectator stress test.

No camera, network, Godot, local database, or physical student is accessed.
Use: py -3.11 -B tools/test_camera_foreground_stress_20261030.py
"""

from __future__ import annotations

import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ui" / "vision"))
from student_lock import StudentLock


def _person(kind: str, track_id: int = -1) -> dict:
    if kind == "player":
        return dict(x=0.46, height=0.73, box=[195, 50, 435, 400],
                    eligible=True, track_id=track_id)
    if kind == "back":
        return dict(x=0.84, height=0.19, box=[515, 260, 600, 351],
                    eligible=True, track_id=track_id)
    if kind == "near":
        return dict(x=0.55, height=0.65, box=[290, 80, 500, 392],
                    eligible=True, track_id=track_id)
    raise ValueError(kind)


def _update(lock: StudentLock, people: list[dict], now: float):
    selected, state, _ = lock.update(people, now, detected_count=len(people))
    return selected, state


class ForegroundClassroomStress(unittest.TestCase):
    def test_distant_students_never_interrupt_or_take_over(self):
        for trial in range(100):
            lock = StudentLock()
            t = 0.0
            # Calibrate in a stable foreground with two small students behind.
            for step in range(22):
                t += 0.05
                people = [_person("player", -1 if step % 2 else 10 + trial),
                          _person("back", -1)]
                active, state = _update(lock, people, t)
            self.assertEqual(state, "locked", trial)
            self.assertIsNotNone(active, trial)
            self.assertEqual(lock.raw_people, 2, trial)
            self.assertEqual(lock.foreground_people, 1, trial)
            self.assertFalse(lock.foreground_ambiguous, trial)

            for step in range(75):
                t += 0.05
                active, state = _update(
                    lock, [_person("player", -1), _person("back", -1)], t)
                self.assertEqual(state, "locked", (trial, step))
                self.assertIsNotNone(active, (trial, step))
                self.assertEqual(lock.foreground_people, 1, (trial, step))

            # If the actual player leaves, a spectator may not auto-promote.
            for step in range(35):
                t += 0.05
                active, state = _update(lock, [_person("back")], t)
                self.assertIsNone(active, (trial, step))
                self.assertNotEqual(state, "locked", (trial, step))
                self.assertEqual(lock.foreground_people, 0, (trial, step))

            # Returning to the same camera lane resumes after fresh evidence.
            states = []
            for step in range(30):
                t += 0.05
                active, state = _update(
                    lock, [_person("player", -1), _person("back")], t)
                states.append(state)
            self.assertEqual(states[-1], "locked", trial)
            self.assertFalse(lock.foreground_ambiguous, trial)

    def test_near_or_overlapping_person_freezes_immediately(self):
        for trial in range(100):
            lock = StudentLock()
            t = 0.0
            for step in range(20):
                t += 0.05
                _update(lock, [_person("player")], t)
            self.assertEqual(_update(lock, [_person("player")], t + .05)[1],
                             "locked", trial)
            t += 0.1
            active, state = _update(
                lock, [_person("player"), _person("near")], t)
            self.assertIsNone(active, trial)
            self.assertEqual(state, "ambiguous", trial)
            self.assertTrue(lock.foreground_ambiguous, trial)
            self.assertGreaterEqual(lock.foreground_people, 2, trial)
            # Controls must not resume on the first safe frame.
            active, state = _update(lock, [_person("player")], t + .05)
            self.assertIsNone(active, trial)
            self.assertNotEqual(state, "locked", trial)

    def test_missing_detection_metadata_is_unsafe(self):
        lock = StudentLock()
        active, state, _ = lock.update(
            [_person("player")], 1.0, detected_count=2)
        self.assertIsNone(active)
        self.assertEqual(state, "ambiguous")
        self.assertTrue(lock.foreground_ambiguous)


if __name__ == "__main__":
    unittest.main(verbosity=2)
