"""Camera-free foreground-student filtering, preview protocol and recovery.

These are normalized image-space inputs, NOT ground-truth physical distances.
No camera, YOLO model, database or network socket is opened.
"""

import unittest
from unittest.mock import patch

from pose_worker import PreviewPublisher, foreground_preview_people, preview_people
from student_lock import StudentLock


def person(x=.5, height=.70, width=.26, index=0, eligible=True):
    return {
        "track_id": -1, "detection_index": index,
        "x": x, "height": height, "eligible": eligible,
        "keypoints": [[x, .25 + i * .025, .95] for i in range(17)],
        "box": [(x - width / 2) * 640, 50,
                (x + width / 2) * 640, 50 + height * 480],
    }


def enroll(gate, start=0., active=None):
    body = active or person()
    selected = None
    for i in range(8):
        selected, _, _ = gate.update([body], start + i * .16, 1)
    assert selected is not None
    return selected


class ForegroundLockTest(unittest.TestCase):
    def test_small_separate_seated_spectator_never_blinks_foreground_lock(self):
        gate = StudentLock()
        enroll(gate)
        for i in range(80):
            student = person(x=.50 + .20 * ((i % 17) / 16), index=1)
            spectator = person(x=.10, height=.21, width=.09, index=0)
            selected, state, _ = gate.update([spectator, student], 2 + i * .1, 2)
            self.assertIs(selected, student)
            self.assertEqual(state, "locked")
            self.assertEqual(gate.raw_people, 2)
            self.assertEqual(gate.foreground_people, 1)
            self.assertFalse(gate.foreground_ambiguous)
            self.assertEqual(gate.player_lock_epoch, 1)

    def test_far_only_spectator_is_never_promoted_after_player_leaves(self):
        gate = StudentLock()
        main = person()
        back = person(.10, .21, .09, 1)
        enroll(gate, active=main)
        self.assertEqual(gate.update([main, back], 1.6, 2)[1], "locked")
        for i in range(18):
            chosen, state, _ = gate.update([back], 2 + i * .16, 1)
            self.assertIsNone(chosen)
            self.assertEqual(state, "lost")
            self.assertEqual(gate.foreground_people, 0)
            self.assertFalse(gate.foreground_ambiguous)
        # The previously identified spectator walking closer is still barred
        # while they are the only person visible.
        enlarged = person(.11, .75, .24, 1)
        self.assertEqual(gate.update([enlarged], 5.2, 1)[1], "lost")
        self.assertEqual(gate.player_lock_epoch, 1)

    def test_player_returns_to_occupied_classroom_after_fresh_hold(self):
        gate = StudentLock()
        main = person()
        back = person(.10, .21, .09, 1)
        enroll(gate, active=main)
        gate.update([main, back], 2., 2)
        gate.update([back], 2.2, 1)
        states = []
        for i in range(8):
            chosen, state, _ = gate.update([back, main], 3 + i * .16, 2)
            states.append(state)
        self.assertEqual(states[0], "enrolling")
        self.assertEqual(states[-1], "locked")
        self.assertIs(chosen, main)
        self.assertEqual(gate.player_lock_epoch, 1)

    def test_similar_size_people_freeze_even_if_separated(self):
        gate = StudentLock()
        enroll(gate)
        a = person(.32, .70, .20, 0)
        b = person(.77, .63, .20, 1)
        self.assertEqual(gate.update([a, b], 2., 2)[1], "ambiguous")
        self.assertEqual(gate.foreground_people, 2)
        self.assertTrue(gate.foreground_ambiguous)

    def test_small_overlapping_spectator_freezes(self):
        gate = StudentLock()
        enroll(gate)
        a = person(.5, .70, .28, 0)
        b = person(.52, .22, .11, 1)
        self.assertEqual(gate.update([a, b], 2., 2)[1], "ambiguous")
        self.assertEqual(gate.foreground_people, 2)

    def test_crouching_student_remains_foreground_with_background_flicker(self):
        gate = StudentLock()
        main = person(.52, .70, .28, 0)
        back = person(.09, .20, .08, 1)
        enroll(gate, active=main)
        self.assertEqual(gate.update([main, back], 2., 2)[1], "locked")
        crouching = person(.53, .40, .25, 0)
        chosen, state, _ = gate.update([crouching], 2.15, 1)
        self.assertEqual(state, "locked")
        self.assertIs(chosen, crouching)

    def test_larger_arrival_cannot_replace_smaller_current_student(self):
        gate = StudentLock()
        current = person(.30, .40, .17, 0)
        enroll(gate, active=current)
        visitor = person(.75, .90, .26, 1)
        chosen, state, _ = gate.update([current, visitor], 2., 2)
        self.assertIsNone(chosen)
        self.assertEqual(state, "ambiguous")
        self.assertTrue(gate.foreground_ambiguous)

    def test_missing_second_box_never_counts_as_safe_background(self):
        gate = StudentLock()
        enroll(gate)
        foreground = person()
        spectator = person(.10, .2)
        del spectator["box"]
        self.assertEqual(gate.update([foreground, spectator], 2., 2)[1], "ambiguous")
        self.assertTrue(gate.foreground_ambiguous)

    def test_one_unusable_pose_still_reports_single_foreground(self):
        gate = StudentLock()
        enroll(gate)
        uncertain = person(eligible=False)
        chosen, state, _ = gate.update([uncertain], 2., 1)
        self.assertIsNone(chosen)
        self.assertEqual(state, "occluded")
        self.assertEqual(gate.foreground_people, 1)

    def test_first_lock_and_short_recovery_keep_epoch(self):
        gate = StudentLock()
        self.assertEqual(gate.player_lock_epoch, 0)
        enroll(gate)
        self.assertEqual(gate.player_lock_epoch, 1)
        gate.update([], 2.0, 0)
        enroll(gate, start=2.5)
        self.assertEqual(gate.player_lock_epoch, 1)

    def test_strong_size_change_after_loss_advances_suspected_replacement_epoch(self):
        gate = StudentLock()
        enroll(gate, active=person(height=.34))
        gate.update([], 2., 0)
        enroll(gate, start=3., active=person(height=.72))
        self.assertEqual(gate.player_lock_epoch, 2)

    def test_two_idless_people_preview_highlights_only_selected_detection(self):
        back, main = person(.1, .21, .09, 0), person(.6, .7, .26, 1)
        roles = preview_people([back, main], main)
        self.assertEqual([p["preview_role"] for p in roles], ["candidate", "active"])
        self.assertEqual([p["preview_role"] for p in
                          preview_people([back, main], None,
                                         highlight_solo_candidate=True,
                                         foreground_candidate=main)],
                         ["candidate", "solo_pending"])
        self.assertEqual([p["detection_index"] for p in
                          foreground_preview_people([back, main], main, main, 1, False)],
                         [1], "Only one verified foreground skeleton is drawn")
        self.assertEqual(foreground_preview_people([back, main], None, main, 2, True),
                         [], "Ambiguous near people never display active bones")

    def test_jpeg_preview_header_preserves_raw_count_and_appends_foreground(self):
        class MemorySocket:
            def __init__(self):
                self.payloads = []

            def sendto(self, payload, _dest):
                self.payloads.append(payload)

        sock = MemorySocket()
        with patch("pose_worker.time.monotonic", return_value=101.):
            sender = PreviewPublisher(sock, ("127.0.0.1", 1))
            self.assertTrue(sender.publish(b"JPEG", 100.8, True, 2, 1))
        prefix, data = sock.payloads[0][1:].split(b";", 1)
        self.assertEqual(data, b"JPEG")
        fields = prefix.decode("ascii").split(",")
        self.assertEqual(len(fields), 5)
        self.assertEqual(fields[1:3], ["1", "2"])
        self.assertEqual(fields[4], "1")


if __name__ == "__main__":
    unittest.main()
