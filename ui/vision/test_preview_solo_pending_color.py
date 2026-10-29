"""Camera-free visual-role tests for newly reacquired SOLO YOLO skeletons.

Preview tint never grants gameplay authority, invents keypoints, or promotes
crowd skeletons to the bright active controller role.
"""

import unittest

from pose_worker import draw_skeleton_preview, preview_people


class DummyFrame:
    shape = (480, 640, 3)


class DrawingRecorder:
    def __init__(self):
        self.lines = []
        self.joints = []

    def resize(self, frame, _dimensions):
        return frame

    def line(self, _canvas, _start, _end, color, thickness):
        self.lines.append((color, thickness))

    def circle(self, _canvas, _point, radius, color, _fill):
        self.joints.append((color, radius))


def person(identifier: int, x: float = 0.5):
    landmarks = [[x, 0.2 + i * 0.02, 0.9] for i in range(17)]
    return {"track_id": identifier, "keypoints": landmarks,
            "eligible": True, "x": x, "height": 0.75}


class SoloPreviewColorTest(unittest.TestCase):
    def test_fresh_solo_candidate_uses_soft_green_without_active_role(self):
        body = person(-1)
        painted = preview_people([body], None, highlight_solo_candidate=True)
        self.assertEqual(painted[0]["preview_role"], "solo_pending")
        self.assertIs(painted[0]["keypoints"], body["keypoints"])
        self.assertNotIn("preview_role", body, "Preview must not modify source")
        drawing = DrawingRecorder()
        draw_skeleton_preview(drawing, DummyFrame(), painted)
        self.assertTrue(drawing.lines)
        self.assertTrue(all(c == (75, 230, 105) and width == 2
                            for c, width in drawing.lines))
        self.assertTrue(all(c == (65, 235, 130) for c, _ in drawing.joints))

    def test_locked_still_uses_bright_green(self):
        body = person(-1)
        painted = preview_people([body], body, highlight_solo_candidate=True)
        self.assertEqual(painted[0]["preview_role"], "active")
        drawing = DrawingRecorder()
        draw_skeleton_preview(drawing, DummyFrame(), painted)
        self.assertTrue(all(c == (65, 255, 80) and width == 3
                            for c, width in drawing.lines))

    def test_partial_solo_joints_are_green_without_granting_gameplay_authority(self):
        # Only a visual signal; a missing/low-confidence torso never passes
        # StudentLock's actual _valid() and must not advance calibration.
        from student_lock import StudentLock
        partial = person(-1)
        partial["eligible"] = False
        partial["keypoints"][11][2] = 0.38
        painted = preview_people([partial], None, highlight_solo_candidate=True)
        self.assertEqual(painted[0]["preview_role"], "solo_pending")
        drawing = DrawingRecorder()
        draw_skeleton_preview(drawing, DummyFrame(), painted)
        self.assertTrue(drawing.lines)
        self.assertTrue(any(c == (75, 230, 105) and thickness == 2
                            for c, thickness in drawing.lines))
        self.assertFalse(StudentLock._valid(partial),
                         "Visual green cannot authorize invalid controller")

    def test_crowd_must_remain_muted_even_if_flag_is_set(self):
        painted = preview_people([person(-1, 0.3), person(-1, 0.7)], None,
                                 highlight_solo_candidate=True)
        self.assertEqual([p["preview_role"] for p in painted],
                         ["candidate", "candidate"])
        drawing = DrawingRecorder()
        draw_skeleton_preview(drawing, DummyFrame(), painted)
        self.assertTrue(all(c == (145, 125, 85) and width == 1
                            for c, width in drawing.lines))

    def test_no_person_and_unverified_single_remain_unhighlighted(self):
        self.assertEqual(preview_people([], None, highlight_solo_candidate=True), [])
        self.assertEqual(preview_people([person(-1)], None)[0]["preview_role"],
                         "candidate")
        drawing = DrawingRecorder()
        draw_skeleton_preview(drawing, DummyFrame(), [])
        self.assertFalse(drawing.lines)
        self.assertFalse(drawing.joints)


if __name__ == "__main__":
    unittest.main()
