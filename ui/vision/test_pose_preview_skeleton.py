"""Camera-free synthetic image tests for the on-screen YOLO pose preview."""

import unittest

from pose_worker import (
    PREVIEW_SIZE,
    PREVIEW_JPEG_MAX_BYTES,
    SKELETON_EDGES,
    draw_skeleton_preview,
    encode_preview_jpeg,
)

try:
    import cv2
    import numpy as np
except ImportError:
    cv2 = None
    np = None


class SkeletonOnlyCV2:
    """Fail if a renderer draws bounding boxes, instructions, or labels."""

    def __init__(self):
        self.lines = 0
        self.joints = 0
        self.connections = []
        self.positions = []

    def resize(self, image, size):
        return cv2.resize(image, size)

    def line(self, image, start, end, color, thickness):
        self.lines += 1
        self.connections.append((start, end))
        return cv2.line(image, start, end, color, thickness)

    def circle(self, image, center, radius, color, thickness):
        self.joints += 1
        self.positions.append(center)
        return cv2.circle(image, center, radius, color, thickness)

    def __getattr__(self, forbidden):
        raise AssertionError(f"Preview must draw bones/keypoints only: {forbidden}")


def sample_person():
    points = [[0.5, 0.5, 0.0] for _ in range(17)]
    measured = {
        0: (0.50, 0.12), 5: (0.40, 0.30), 6: (0.60, 0.30),
        7: (0.36, 0.47), 8: (0.64, 0.47),
        9: (0.33, 0.62), 10: (0.67, 0.62),
        11: (0.43, 0.60), 12: (0.57, 0.60),
        13: (0.41, 0.75), 14: (0.59, 0.75),
        15: (0.39, 0.90), 16: (0.61, 0.90),
    }
    for index, (x, y) in measured.items():
        points[index] = [x, y, 0.98]
    return {
        "track_id": 17, "x": 0.5, "height": 0.8,
        "box": [0.2, 0.08, 0.8, 0.95],
        "keypoints": points,
    }


@unittest.skipIf(cv2 is None or np is None, "OpenCV/NumPy not installed")
class SkeletonPreviewTest(unittest.TestCase):
    def setUp(self):
        self.camera_image = np.zeros((480, 640, 3), dtype=np.uint8)
        self.camera_image[:] = (21, 36, 52)
        self.plain_preview = cv2.resize(self.camera_image, PREVIEW_SIZE)

    def test_visible_student_draws_only_bones_and_measured_keypoints(self):
        drawing = SkeletonOnlyCV2()
        output = draw_skeleton_preview(drawing, self.camera_image, [sample_person()])
        self.assertEqual(output.shape, (480, 640, 3))
        self.assertGreaterEqual(drawing.lines, 10)
        self.assertEqual(drawing.joints, 12)
        self.assertFalse(np.array_equal(output, self.plain_preview))

        # The center/range and detector bounding-box edges used to cross these
        # pixels. Only interior measured joints/segments should change them.
        for y, x in [(5, 80), (240, 80), (475, 80),
                     (5, 560), (240, 560), (475, 560),
                     (17, 70), (100, 70), (450, 580),
                     (4, 4), (17, 12)]:
            self.assertTrue(np.array_equal(output[y, x], self.plain_preview[y, x]),
                            f"Unexpected rectangle/text pixel at {(x, y)}")

    def test_body_bones_align_with_detected_torso_not_the_face(self):
        person = sample_person()
        # YOLO can also confidently locate nose, eyes, and ears (indices 0..4).
        # Facial landmarks are not *body* bones and should never paint lines
        # across a child's head just because they were detected.
        for index, x, y in ((0, 0.5, 0.09), (1, 0.46, 0.10),
                            (2, 0.54, 0.10), (3, 0.43, 0.13),
                            (4, 0.57, 0.13)):
            person["keypoints"][index] = [x, y, 0.99]
        self.assertTrue(all(a >= 5 and b >= 5 for a, b in SKELETON_EDGES))
        drawing = SkeletonOnlyCV2()
        image = draw_skeleton_preview(drawing, self.camera_image, [person])
        self.assertEqual(drawing.joints, 12)
        self.assertTrue(all(y >= round(0.30 * 479) for _, y in drawing.positions))
        self.assertTrue(np.array_equal(image[:110], self.plain_preview[:110]),
                        "The head/face must be clear of body-bone strokes")
        self.assertIn((round(0.4 * 639), round(0.30 * 479)), drawing.positions)
        self.assertIn((round(0.43 * 639), round(0.60 * 479)), drawing.positions)
        self.assertIn((round(0.39 * 639), round(0.90 * 479)), drawing.positions)

    def test_preview_source_dimensions_are_not_godot_ui_dimensions(self):
        self.assertEqual(PREVIEW_SIZE, (640, 480))
        drawing = SkeletonOnlyCV2()
        image = draw_skeleton_preview(drawing, self.camera_image, [sample_person()])
        self.assertEqual(image.shape, self.camera_image.shape)
        # The edited LiveCameraInset is much wider (1007x446), but Godot
        # stretches image + bones together; the Python preview should not.
        shoulder_x = round(0.40 * (image.shape[1] - 1))
        shoulder_y = round(0.30 * (image.shape[0] - 1))
        self.assertIn((shoulder_x, shoulder_y), drawing.positions)

    def test_editor_authored_visual_offset_and_scale_move_only_bones(self):
        person = sample_person()
        drawing = SkeletonOnlyCV2()
        default = draw_skeleton_preview(drawing, self.camera_image, [person])
        offset, scale = (0.10, -0.04), (0.80, 0.86)
        moved_drawing = SkeletonOnlyCV2()
        moved = draw_skeleton_preview(moved_drawing, self.camera_image, [person], offset, scale)
        x, y, confidence = person["keypoints"][5]
        self.assertGreater(confidence, 0.9)
        expected = (round((offset[0] + x * scale[0]) * 639),
                    round((offset[1] + y * scale[1]) * 479))
        self.assertIn(expected, moved_drawing.positions)
        self.assertNotIn(expected, drawing.positions)
        self.assertFalse(np.array_equal(default, moved))
        self.assertEqual(person["keypoints"][5], [x, y, confidence],
                         "Visual offsets may never change YOLO calibration inputs")

    def test_skeleton_remains_on_body_when_live_camera_inset_stretches_to_widescreen(self):
        person = sample_person()
        source_with_skeleton = draw_skeleton_preview(
            SkeletonOnlyCV2(), self.camera_image, [person]
        )
        # Godot's TextureRect.STRETCH_SCALE applies to the *whole texture*.
        # It must scale the camera picture and its already-aligned bones
        # together, never leave a skeleton stuck near the student's head.
        display = cv2.resize(source_with_skeleton, (1007, 446))
        plain_display = cv2.resize(self.camera_image, (1007, 446))
        self.assertTrue(np.array_equal(display[:95], plain_display[:95]))
        for point in (5, 6, 11, 12, 13, 14):
            x, y, _confidence = person["keypoints"][point]
            pixel_x = round(x * (1007 - 1))
            pixel_y = round(y * (446 - 1))
            self.assertFalse(np.array_equal(display[pixel_y, pixel_x],
                                            plain_display[pixel_y, pixel_x]),
                             f"Body landmark {point} was displaced after UI scaling")

    def test_without_detected_person_preview_has_no_annotations(self):
        drawing = SkeletonOnlyCV2()
        output = draw_skeleton_preview(drawing, self.camera_image, [])
        self.assertTrue(np.array_equal(output, self.plain_preview))
        self.assertEqual((drawing.lines, drawing.joints), (0, 0))

    def test_real_source_aspect_is_preserved_for_wide_cameras(self):
        wide_image = np.zeros((360, 640, 3), dtype=np.uint8)
        wide_image[:] = (21, 36, 52)
        drawing = SkeletonOnlyCV2()
        output = draw_skeleton_preview(drawing, wide_image, [])
        self.assertEqual(output.shape, (360, 640, 3))
        self.assertTrue(np.array_equal(output, wide_image))

    def test_encoded_preview_prefers_full_resolution_for_ordinary_camera(self):
        canvas = np.zeros((480, 640, 3), dtype=np.uint8)
        canvas[:] = (50, 80, 140)
        canvas[::8] = (12, 190, 240)
        jpg = encode_preview_jpeg(cv2, canvas)
        self.assertIsNotNone(jpg)
        self.assertLess(len(jpg), PREVIEW_JPEG_MAX_BYTES)
        result = cv2.imdecode(np.frombuffer(jpg, np.uint8), cv2.IMREAD_COLOR)
        self.assertEqual(result.shape[:2], (480, 640))

    def test_noisy_frames_fit_udp_limit_without_disappearing(self):
        noisy = np.random.default_rng(2026).integers(
            0, 256, size=(480, 640, 3), dtype=np.uint8
        )
        jpg = encode_preview_jpeg(cv2, noisy)
        self.assertIsNotNone(jpg)
        self.assertLess(len(jpg), PREVIEW_JPEG_MAX_BYTES)
        result = cv2.imdecode(np.frombuffer(jpg, np.uint8), cv2.IMREAD_COLOR)
        self.assertGreaterEqual(result.shape[1], 400)
        self.assertEqual(result.shape[1] * 3, result.shape[0] * 4)

    def test_top_and_bottom_camera_rows_are_not_cropped(self):
        image = self.camera_image.copy()
        image[:10] = (5, 150, 250)
        image[-10:] = (200, 15, 90)
        output = draw_skeleton_preview(SkeletonOnlyCV2(), image, [])
        self.assertTrue(np.array_equal(output[0, 0], image[0, 0]))
        self.assertTrue(np.array_equal(output[-1, 0], image[-1, 0]))

    def test_unconfident_or_invalid_joints_never_draw_fake_bones(self):
        person = sample_person()
        for point in person["keypoints"]:
            point[2] = 0.3
        person["keypoints"][5] = [float("nan"), 0.3, 0.99]
        person["keypoints"][6] = [1.4, 0.3, 0.99]
        drawing = SkeletonOnlyCV2()
        output = draw_skeleton_preview(drawing, self.camera_image, [person])
        self.assertTrue(np.array_equal(output, self.plain_preview))
        self.assertEqual((drawing.lines, drawing.joints), (0, 0))


if __name__ == "__main__":
    unittest.main()
