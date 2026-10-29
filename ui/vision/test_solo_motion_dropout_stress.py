"""One real solo body moving / brief poor landmark frames must not enroll-loop.

No camera, model weights, DB or network. Every call is one distinct YOLO frame.
Zero/two+ occupants and prolonged unusable poses must ALWAYS suspend control.
"""
import unittest
from types import SimpleNamespace

from student_lock import StudentLock
from pose_worker import (RAW_PREVIEW_FALLBACK_DELAY_SECONDS,
                         observed_pose_people, resilient_body_position)


def solo(x=.5, height=.64, *, eligible=True):
    return {"track_id": -1, "x": x, "height": height, "eligible": eligible}


def acquire(lock, start=0., x=.5):
    for i in range(7):
        lock.update([solo(x)], start + i * .16, detected_count=1)
    assert lock.tracking_epoch == 1


class VisibleStudentMotionStress(unittest.TestCase):
    def test_raw_yolo_box_still_counts_person_without_any_landmarks(self):
        # Python must publish people=1 even though usable pose=false. Godot
        # needs that *independent* box occupancy to continue an already
        # calibrated game while movement and shooting stay neutral.
        class CameraBoxes:
            id = None

            class Pixels:
                def cpu(self):
                    return self

                def tolist(self):
                    return [[180., 30., 460., 450.]]

            xyxy = Pixels()

        raw = SimpleNamespace(boxes=CameraBoxes(), keypoints=None)
        people, bones = observed_pose_people(raw, 640, 480)
        self.assertEqual(len(people), 1)
        self.assertFalse(people[0]["eligible"])
        self.assertEqual(bones, [])
        chosen, state, _ = StudentLock().update(people, 0., detected_count=1)
        self.assertIsNone(chosen)
        self.assertEqual(state, "occluded")

    def test_raw_camera_fallback_does_not_blank_fresh_bones_at_sparse_fps(self):
        # Old 0.6s fallback erased green bones before the next ~1Hz inference
        # preview arrived, despite the underlying camera remaining healthy.
        self.assertGreater(RAW_PREVIEW_FALLBACK_DELAY_SECONDS, 1.0)
        self.assertLess(RAW_PREVIEW_FALLBACK_DELAY_SECONDS, 1.4)

    def test_large_legitimate_motion_after_hold_never_reenrolls(self):
        lock = StudentLock()
        acquire(lock)
        # Sparse inference / quick physical movement can change measured X
        # by >24% of the frame between two valid, one-occupant source frames.
        # Initial calibration already proved one person was stable.
        for i, x in enumerate((.52, .87, .17, .91, .45, .04, .81, .42) * 20):
            chosen, state, _ = lock.update([solo(x)], 1.1 + .11 * i, 1)
            self.assertEqual(state, "locked", (i, x))
            self.assertIsNotNone(chosen)
        self.assertFalse(lock.needs_recalibration)

    def test_one_bad_torso_sample_does_not_force_new_solo_hold(self):
        lock = StudentLock()
        acquire(lock)
        for i in range(30):
            t = 1.10 + i * .33
            selected, state, _ = lock.update([solo(.55, eligible=False)], t, 1)
            self.assertIsNone(selected, "Invalid pose cannot steer")
            self.assertEqual(state, "occluded")
            selected, state, _ = lock.update([solo(.56)], t + .11, 1)
            self.assertEqual(state, "locked", (i, state))
            self.assertIsNotNone(selected)

    def test_long_torso_loss_requires_fresh_solo_recovery(self):
        lock = StudentLock()
        acquire(lock)
        for t in (1.1, 1.4, 1.7, 2.0, 2.3):
            selected, _, _ = lock.update([solo(eligible=False)], t, 1)
            self.assertIsNone(selected)
        resumed, state, _ = lock.update([solo(.77)], 2.42, 1)
        self.assertIsNone(resumed)
        self.assertEqual(state, "enrolling")
        for i in range(5):
            resumed, state, _ = lock.update([solo(.77)], 2.58 + i * .16, 1)
        self.assertEqual(state, "locked")
        self.assertIsNotNone(resumed)

    def test_zero_and_crowd_always_pause_on_exact_source_frame(self):
        lock = StudentLock()
        acquire(lock)
        selected, state, _ = lock.update([], 1.1, 0)
        self.assertIsNone(selected)
        self.assertEqual(state, "lost")
        selected, state, _ = lock.update([solo(.5)], 1.21, 1)
        self.assertIsNone(selected, "After empty, fresh re-enrollment required")
        for i in range(6):
            lock.update([solo(.5)], 1.37 + i * .16, 1)
        selected, state, _ = lock.update([solo(.5), solo(.9)], 2.5, 2)
        self.assertIsNone(selected)
        self.assertEqual(state, "ambiguous")
        selected, state, _ = lock.update([solo(.5)], 2.6, 1)
        self.assertIsNone(selected, "After crowd, fresh re-enrollment required")

    def test_real_same_side_shoulder_hip_pair_keeps_body_visible(self):
        points = [[.5, .5, .03] for _ in range(17)]
        points[5] = [.44, .31, .97]  # left shoulder
        points[11] = [.46, .70, .94]  # left hip
        self.assertAlmostEqual(resilient_body_position(points), .45)
        points[11][2] = .1
        self.assertIsNone(resilient_body_position(points))


if __name__ == "__main__":
    unittest.main()
