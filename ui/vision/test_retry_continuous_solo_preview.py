"""Offline Retry regression: solo child NEVER exits camera between two rounds.

Runs actual Python UDP worker + async skeleton preview with synthetic constant
camera and YOLO raw detections. No real webcam, student DB, UI or model weights.
"""

import json
import socket
import threading
import time
import unittest
from unittest.mock import patch

import pose_worker
from test_solo_occupancy_worker_packets import SyntheticPrediction


class ConstantSoloCamera:
    """Returns only one stationary child-sized frame, then disconnects."""

    def __init__(self, pixels, *, max_frames=65, interval=.030):
        self.pixels = pixels
        self.max_frames = max_frames
        self.interval = interval
        self.count = 0
        self.closed = False

    def read(self):
        time.sleep(self.interval)
        self.count += 1
        if self.count > self.max_frames or self.closed:
            return False, None
        return True, self.pixels

    def set(self, *_args):
        return True

    def release(self):
        self.closed = True


class RawSoloModel:
    """Always detects the child even if a ByteTrack tracker would be stale."""

    def __init__(self):
        self.calls = 0
        self.track_calls = 0

    def predict(self, *_args, **kwargs):
        self.calls += 1
        assert "tracker" not in kwargs and "persist" not in kwargs
        # Fresh raw predictions contain no tracker ID, by design.
        return [SyntheticPrediction(1, with_ids=False)]

    def track(self, *_args, **_kwargs):
        self.track_calls += 1
        # This is the old behavior that may filter visible people after Retry.
        raise AssertionError("ByteTrack must not gate the current visible person")


class ContinuousRetryPreviewTest(unittest.TestCase):
    @staticmethod
    def play_synthetic_round(model, pixels, recovery=False):
        listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        listener.bind(("127.0.0.1", 0))
        listener.settimeout(.12)
        camera = ConstantSoloCamera(pixels)
        packets, rendered_roles = [], []
        result = {}
        original_draw = pose_worker.draw_skeleton_preview

        def spy_draw(cv2, frame, preview_people, *args, **kwargs):
            if preview_people:
                rendered_roles.append(tuple(p.get("preview_role") for p in preview_people))
            return original_draw(cv2, frame, preview_people, *args, **kwargs)

        def run_worker():
            result["exit"] = pose_worker.run(
                listener.getsockname()[1], "retry-solo-not-a-student-id",
                0, "fake-local-model.pt", True, recovery=recovery,
                prepared_model=(model, "cpu", False))

        worker = threading.Thread(target=run_worker, daemon=True)
        try:
            with patch.object(pose_worker, "open_camera", return_value=camera), \
                    patch.object(pose_worker, "draw_skeleton_preview", side_effect=spy_draw), \
                    patch.object(pose_worker, "encode_preview_jpeg", return_value=b"raw-solo-jpeg"):
                worker.start()
                deadline = time.monotonic() + 6.3
                while time.monotonic() < deadline:
                    try:
                        payload, _ = listener.recvfrom(65535)
                        if payload[:1] == b"{":
                            packets.append(json.loads(payload))
                    except socket.timeout:
                        pass
                    if not worker.is_alive():
                        break
                worker.join(timeout=.5)
            assert not worker.is_alive(), "Synthetic worker must exit after bounded camera stall"
            return packets, rendered_roles
        finally:
            camera.release()
            listener.close()

    def test_retry_with_student_standing_throughout_shows_green_again(self):
        try:
            import numpy as np
        except ImportError:
            self.skipTest("NumPy not installed; in-memory frame required")
        pixels = np.zeros((480, 640, 3), dtype=np.uint8)
        # Reuse ONE prepared model across both runs, including the recovery
        # path, to stress warmed inference and predictor persistence.
        model = RawSoloModel()
        for attempt, recovery in ((1, False), (2, True)):
            with self.subTest(round=attempt, recovery=recovery):
                packets, roles = self.play_synthetic_round(model, pixels, recovery=recovery)
                live = [p for p in packets if p.get("camera_phase") == "tracking"]
                self.assertTrue(live, "Every Retry must begin yielding real fresh pose packets")
                self.assertTrue(any(p.get("pose") and p.get("lock_state") == "locked"
                                    for p in live), "Standing still must complete the solo hold")
                self.assertTrue(any(p.get("occupancy_verified") and p.get("people") == 1
                                    for p in live))
                self.assertTrue(any(role == ("active",) for role in roles),
                                "Actual async preview must draw one green skeleton on Retry")
                self.assertTrue(all(p.get("locked_id") == -1 for p in live))
                self.assertTrue(all(not p.get("needs_recalibration", False) for p in live))
                self.assertTrue(all(p.get("tracking_epoch", 0) in (0, 1) for p in live))
        self.assertEqual(model.track_calls, 0)
        self.assertGreater(model.calls, 10)

    def test_idless_two_people_both_remain_passive_on_preview(self):
        from pose_worker import observed_pose_people, preview_people
        people, preview = observed_pose_people(SyntheticPrediction(2, False), 640, 480)
        self.assertEqual(len(people), 2)
        self.assertEqual(len(preview), 2)
        self.assertEqual([p["preview_role"] for p in preview_people(preview, None)],
                         ["candidate", "candidate"])


if __name__ == "__main__":
    unittest.main()
