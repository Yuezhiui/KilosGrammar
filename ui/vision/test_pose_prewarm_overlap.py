"""Synthetic regression: Play camera permission can overlap cold YOLO warmup.

Run with: python -m unittest -v test_pose_prewarm_overlap.py
Never opens VideoCapture, uses model weights, or accesses a live database.
"""
import json
import socket
import sys
import threading
import time
import types
import unittest
from unittest.mock import patch

import pose_worker

try:
    import cv2
    import numpy as np
except ImportError:
    cv2 = None
    np = None


class PlayPrewarmOverlapTests(unittest.TestCase):
    def test_cpu_tracking_reserves_cores_for_live_godot_countdown(self):
        # Real CPU-only classrooms previously inherited torch's sometimes
        # excessive inference thread count, competing with the renderer.
        threads = []
        inference = []

        class FakeModel:
            def __init__(self, _path):
                pass

            def predict(self, *_args, **_kwargs):
                inference.append(tuple(threads))
                return []

            def track(self, *_args, **_kwargs):
                raise AssertionError("No ByteTrack initialization during raw pose warmup")

        fake_torch = types.ModuleType("torch")
        fake_torch.cuda = types.SimpleNamespace(is_available=lambda: False)
        fake_torch.set_num_threads = threads.append
        fake_numpy = types.ModuleType("numpy")
        fake_numpy.uint8 = "uint8"
        fake_numpy.zeros = lambda shape, dtype: (shape, dtype)
        fake_ultralytics = types.ModuleType("ultralytics")
        fake_ultralytics.YOLO = FakeModel
        with patch.dict(sys.modules, {"torch": fake_torch, "numpy": fake_numpy,
                                      "ultralytics": fake_ultralytics}), \
                patch.object(pose_worker.os, "cpu_count", return_value=16):
            _model, device, gpu = pose_worker.prepare_pose_model("local.pt")
        self.assertEqual((device, gpu), ("cpu", False))
        self.assertEqual(threads, [4])
        self.assertEqual(inference, [(4,)],
                         "CPU contention must be limited before first YOLO warmup")

    @unittest.skipIf(cv2 is None or np is None, "OpenCV/NumPy required for synthetic image")
    def test_real_worker_sends_camera_preview_before_prewarm_finishes(self):
        listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        listener.bind(("127.0.0.1", 0))
        listener.settimeout(0.1)
        sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        token = "abcdef0123456789abcdef0123456789"
        warmup_entered = threading.Event()
        release_warmup = threading.Event()
        outcome = {}

        class SyntheticCamera:
            def __init__(self):
                self.released = False
                self.frame = np.zeros((480, 640, 3), dtype=np.uint8)
                self.frame[:, :20] = (30, 80, 180)

            def read(self):
                time.sleep(0.018)
                return (False, None) if self.released else (True, self.frame)

            def set(self, *_args):
                return True

            def release(self):
                self.released = True

        fake_camera = SyntheticCamera()

        def slow_preparation(_model_path, _callback):
            warmup_entered.set()
            release_warmup.wait(3)
            raise ValueError("synthetic warmup stops after first live preview")

        def run_worker():
            outcome["code"] = pose_worker.prewarm_worker(
                listener.getsockname()[1], token, 0, "no-real-model.pt",
                True, False, (0.0, 0.0), (1.0, 1.0))

        try:
            with patch.object(pose_worker, "prepare_pose_model", side_effect=slow_preparation), \
                    patch.object(pose_worker, "open_camera", return_value=fake_camera):
                worker = threading.Thread(target=run_worker, daemon=True)
                worker.start()
                self.assertTrue(warmup_entered.wait(1))
                ready_port = None
                before_auth_preview = False
                deadline = time.monotonic() + 1.5
                while time.monotonic() < deadline and ready_port is None:
                    try:
                        payload, _ = listener.recvfrom(65535)
                    except socket.timeout:
                        continue
                    if payload[:1] == b"\x01":
                        before_auth_preview = True
                    else:
                        ready_port = json.loads(payload).get("control_port")
                self.assertIsInstance(ready_port, int)
                self.assertFalse(before_auth_preview,
                                 "No student image leaves worker before permission")
                sender.sendto(json.dumps({"command": "start_camera", "token": token}).encode(),
                              ("127.0.0.1", ready_port))
                saw_preview = False
                saw_ack = False
                deadline = time.monotonic() + 1.6
                while time.monotonic() < deadline and not saw_preview:
                    try:
                        payload, _ = listener.recvfrom(65535)
                    except socket.timeout:
                        continue
                    if payload[:1] == b"\x01":
                        image = cv2.imdecode(np.frombuffer(payload[1:], dtype=np.uint8),
                                             cv2.IMREAD_COLOR)
                        saw_preview = image is not None and image.shape[:2] == (480, 640)
                    else:
                        parsed = json.loads(payload)
                        saw_ack |= parsed.get("camera_phase") == "start_ack"
                self.assertTrue(saw_ack, "Authenticated camera start acknowledged")
                self.assertTrue(saw_preview, "Full-res live camera appears during cold YOLO warmup")
                self.assertFalse(release_warmup.is_set(),
                                 "Image is available before background model has finished")
                release_warmup.set()
                worker.join(timeout=3)
                self.assertFalse(worker.is_alive())
                self.assertEqual(outcome.get("code"), 4)
                self.assertTrue(fake_camera.released)
        finally:
            release_warmup.set()
            sender.close()
            listener.close()

    def test_authorized_camera_start_does_not_wait_for_cold_model(self):
        receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        receiver.bind(("127.0.0.1", 0))
        receiver.settimeout(0.08)
        sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        token = "0123456789abcdef0123456789abcdef"
        preparing = threading.Event()
        permit_model = threading.Event()
        camera_opened = threading.Event()
        finished = {}
        preparations = []
        model = (object(), "cpu", False)
        statuses = []

        def slow_model(_path, status):
            preparations.append(time.monotonic())
            preparing.set()
            self.assertTrue(permit_model.wait(timeout=3))
            status("Finishing synthetic warmup")
            return model

        def fake_camera_first(*_args, **options):
            # run() is invoked while the model is STILL loading: this is the
            # point where the real run() opens VideoCapture and starts preview.
            self.assertFalse(permit_model.is_set())
            self.assertIsNone(options.get("prepared_model"))
            self.assertEqual(options["bones_offset"], (0.08, -0.02))
            self.assertEqual(options["bones_scale"], (0.93, 1.0))
            camera_opened.set()
            self.assertIs(options["prepared_model_loader"](), model)
            return 0

        def worker():
            finished["code"] = pose_worker.prewarm_worker(
                receiver.getsockname()[1], token, 0, "unused-local.pt",
                True, False, (0.0, 0.0), (1.0, 1.0))

        try:
            with patch.object(pose_worker, "prepare_pose_model", side_effect=slow_model), \
                    patch.object(pose_worker, "run", side_effect=fake_camera_first), \
                    patch.object(pose_worker, "open_live_camera",
                                 side_effect=AssertionError("No real camera permitted in test")):
                thread = threading.Thread(target=worker, daemon=True)
                thread.start()
                self.assertTrue(preparing.wait(1))
                deadline = time.monotonic() + 1.5
                control_port = None
                while time.monotonic() < deadline and control_port is None:
                    try:
                        packet, _ = receiver.recvfrom(8192)
                    except socket.timeout:
                        continue
                    parsed = json.loads(packet)
                    statuses.append(parsed)
                    control_port = parsed.get("control_port")
                self.assertIsInstance(control_port, int)
                self.assertFalse(camera_opened.is_set(),
                                 "Prewarm must never access a camera before permission")

                # An invalid/missing token cannot start even while CUDA waits.
                sender.sendto(json.dumps({"command": "start_camera", "token": "wrong"}).encode(),
                              ("127.0.0.1", control_port))
                time.sleep(0.09)
                self.assertFalse(camera_opened.is_set())

                authorized_at = time.monotonic()
                sender.sendto(json.dumps({
                    "command": "start_camera", "token": token,
                    "bones_offset": [0.08, -0.02], "bones_scale": [0.93, 1.0],
                }).encode(),
                              ("127.0.0.1", control_port))
                self.assertTrue(camera_opened.wait(0.8),
                                "Play starts camera before slow model/CUDA warmup completes")
                self.assertLess(time.monotonic() - authorized_at, 0.8)
                self.assertEqual(len(preparations), 1,
                                 "The same prewarmed model must be reused exactly once")
                self.assertFalse(permit_model.is_set())

                permit_model.set()
                thread.join(2)
                self.assertFalse(thread.is_alive())
                self.assertEqual(finished.get("code"), 0)
                self.assertEqual(len(preparations), 1)
                while True:
                    try:
                        packet, _ = receiver.recvfrom(8192)
                    except socket.timeout:
                        break
                    statuses.append(json.loads(packet))
                acknowledgements = [s for s in statuses
                                    if s.get("camera_phase") == "start_ack"]
                self.assertEqual(len(acknowledgements), 1)
                self.assertTrue(acknowledgements[0]["camera"])
                self.assertFalse(acknowledgements[0]["model_ready"])
                self.assertFalse(any(s.get("state") == "prewarming" and
                                     s.get("when", 0) > acknowledgements[0]["when"]
                                     for s in statuses),
                                 "Late model progress must not override camera ACK")
        finally:
            permit_model.set()
            sender.close()
            receiver.close()


if __name__ == "__main__":
    unittest.main()
