"""Fast offline regressions for pose model warmup and bounded preview latency.

Mocks synthetic CUDA, webcam and packet paths. It never opens a device, starts
YOLO inference, downloads weights, or persists real camera/student information.
"""

import json
import os
import socket
import sys
import threading
import time
import types
import unittest
from unittest.mock import patch

import pose_worker


class FakeTorch(types.ModuleType):
    def __init__(self, cuda=True):
        super().__init__("torch")
        self.cuda = types.SimpleNamespace(is_available=lambda: cuda)
        self.num_threads = []

    def set_num_threads(self, threads):
        self.num_threads.append(threads)


class FakeNumpy(types.ModuleType):
    uint8 = "uint8"

    def __init__(self):
        super().__init__("numpy")

    def zeros(self, shape, dtype):
        return (shape, dtype)


class WorkerPreparationTests(unittest.TestCase):
    def test_model_warmup_initializes_tracker_on_camera_shaped_image(self):
        models = []

        class Model:
            def __init__(self, weights):
                self.weights = weights
                self.calls = []
                models.append(self)

            def track(self, frame, **kwargs):
                self.calls.append((frame, kwargs))
                return []

        fake_ultralytics = types.ModuleType("ultralytics")
        fake_ultralytics.YOLO = Model
        with patch.dict(sys.modules, {
                "ultralytics": fake_ultralytics, "torch": FakeTorch(True),
                "numpy": FakeNumpy()}):
            model, device, gpu = pose_worker.prepare_pose_model("cached-local.pt")
        self.assertIs(model, models[0])
        self.assertEqual(model.weights, "cached-local.pt")
        self.assertEqual((device, gpu), (0, True))
        self.assertEqual(len(model.calls), 1)
        image, options = model.calls[0]
        self.assertEqual(image[0], (480, 640, 3))
        self.assertEqual(options["tracker"], "bytetrack.yaml")
        self.assertTrue(options["persist"])
        self.assertEqual(options["imgsz"], 320)
        self.assertEqual(options["classes"], [0])

    def test_cuda_startup_failure_retries_once_on_cpu(self):
        calls = []
        models = []

        class Model:
            def __init__(self, weights):
                models.append(self)

            def track(self, _frame, **kwargs):
                calls.append(kwargs["device"])
                if kwargs["device"] == 0:
                    raise RuntimeError("CUDA driver initialization failed")
                return []

        fake_ultralytics = types.ModuleType("ultralytics")
        fake_ultralytics.YOLO = Model
        torch = FakeTorch(True)
        messages = []
        with patch.dict(sys.modules, {
                "ultralytics": fake_ultralytics, "torch": torch,
                "numpy": FakeNumpy()}):
            model, device, gpu = pose_worker.prepare_pose_model(
                "cached-local.pt", messages.append)
        self.assertIs(model, models[1])
        self.assertEqual(calls, [0, "cpu"])
        self.assertEqual((device, gpu), ("cpu", False))
        self.assertEqual(len(torch.num_threads), 1)
        self.assertTrue(any("CPU" in text for text in messages))

    def test_model_errors_do_not_get_hidden_by_cpu_fallback(self):
        class Model:
            def __init__(self, _weights):
                pass

            def track(self, _frame, **_kwargs):
                raise ValueError("invalid model weights")

        fake_ultralytics = types.ModuleType("ultralytics")
        fake_ultralytics.YOLO = Model
        with patch.dict(sys.modules, {
                "ultralytics": fake_ultralytics, "torch": FakeTorch(True),
                "numpy": FakeNumpy()}):
            with self.assertRaisesRegex(ValueError, "invalid model weights"):
                pose_worker.prepare_pose_model("broken.pt")

    @unittest.skipUnless(os.environ.get("KILOSGRAMMAR_POSE_MODEL"),
                         "Optional real local-model cold-start probe; no camera is opened")
    def test_real_offline_tracker_warmup(self):
        from pathlib import Path
        model_path = Path(os.environ["KILOSGRAMMAR_POSE_MODEL"])
        self.assertTrue(model_path.is_file(), "A local model must already exist")
        started = time.perf_counter()
        model, device, _gpu = pose_worker.prepare_pose_model(str(model_path))
        elapsed = time.perf_counter() - started
        self.assertIsNotNone(model)
        self.assertIn(device, (0, "cpu"))
        print("COLD_MODEL_PREWARM_SECONDS: %.3f" % elapsed)


class PreviewAndProtocolTests(unittest.TestCase):
    def test_status_monotonic_and_student_lock_flags_unchanged(self):
        class Socket:
            def __init__(self):
                self.messages = []

            def sendto(self, data, target):
                self.messages.append((json.loads(data), target))

        sock = Socket()
        before = time.monotonic()
        pose_worker.send_status(sock, ("127.0.0.1", 54321), "testtoken",
                                state="loading", detail="Preparing tracker")
        after = time.monotonic()
        packet, target = sock.messages[0]
        self.assertEqual(target, ("127.0.0.1", 54321))
        self.assertEqual(packet["kind"], "pose")
        self.assertEqual(packet["token"], "testtoken")
        self.assertLessEqual(before, packet["when"])
        self.assertLessEqual(packet["when"], after)
        self.assertFalse(packet["hand_up"])
        self.assertFalse(packet["airplane_pose"])
        self.assertFalse(packet["hand_observation_valid"])

    def test_preview_slot_drops_old_frames_while_encoding(self):
        encode_started = threading.Event()
        release_encoder = threading.Event()

        class Socket:
            def __init__(self):
                self.payloads = []

            def sendto(self, packet, _target):
                self.payloads.append(packet)

        sock = Socket()

        def encode(_cv2, image):
            if image == b"first":
                encode_started.set()
                self.assertTrue(release_encoder.wait(timeout=2))
            return image

        with patch.object(pose_worker, "draw_skeleton_preview", side_effect=lambda _cv2, frame, *_: frame), \
                patch.object(pose_worker, "encode_preview_jpeg", side_effect=encode):
            preview = pose_worker.LatestPreview(None, sock, ("127.0.0.1", 12345),
                                                (0.0, 0.0), (1.0, 1.0))
            try:
                preview.submit(b"first", [])
                preview.start()
                self.assertTrue(encode_started.wait(timeout=2))
                for index in range(50):
                    preview.submit(str(index).encode("ascii"), [])
                release_encoder.set()
                deadline = time.monotonic() + 2
                while len(sock.payloads) < 2 and time.monotonic() < deadline:
                    time.sleep(0.005)
                self.assertEqual(sock.payloads, [b"\x01first", b"\x0149"])
            finally:
                release_encoder.set()
                preview.close()
            self.assertFalse(preview.thread.is_alive())
            self.assertIsNone(preview.latest)


class PrewarmAuthorizationTests(unittest.TestCase):
    def test_ready_worker_never_opens_camera_without_matching_loopback_token(self):
        token = "0123456789abcdef0123456789abcdef"
        receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        receiver.bind(("127.0.0.1", 0))
        receiver.settimeout(0.2)
        sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        prepared = (object(), 0, True)
        invoked = []
        result = {}
        try:
            def fake_run(*args, **kwargs):
                invoked.append((args, kwargs))
                return 0

            def worker():
                result["code"] = pose_worker.prewarm_worker(
                    receiver.getsockname()[1], token, 3, "local.pt", True,
                    False, (0.0, 0.0), (1.0, 1.0))

            with patch.object(pose_worker, "prepare_pose_model", return_value=prepared), \
                    patch.object(pose_worker, "open_camera", side_effect=AssertionError("opened before permission")), \
                    patch.object(pose_worker, "run", side_effect=fake_run):
                thread = threading.Thread(target=worker, daemon=True)
                thread.start()
                control_port = None
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    try:
                        packet, _ = receiver.recvfrom(8192)
                    except socket.timeout:
                        continue
                    status = json.loads(packet)
                    if status.get("state") == "ready":
                        control_port = status["control_port"]
                        self.assertTrue(status["model_ready"])
                        self.assertEqual(status["kind"], "pose")
                        self.assertEqual(status["token"], token)
                        break
                self.assertIsInstance(control_port, int)
                self.assertFalse(invoked)
                destination = ("127.0.0.1", control_port)
                sender.sendto(json.dumps({"command": "start_camera", "token": "bad"}).encode(), destination)
                sender.sendto(json.dumps({"command": "no_camera", "token": token}).encode(), destination)
                sender.sendto(b"invalid json", destination)
                time.sleep(0.1)
                self.assertFalse(invoked, "Invalid UDP messages cannot open the camera")
                sender.sendto(json.dumps({"command": "start_camera", "token": token}).encode(), destination)
                thread.join(timeout=2)
            self.assertFalse(thread.is_alive())
            self.assertEqual(result.get("code"), 0)
            self.assertEqual(len(invoked), 1)
            self.assertEqual(invoked[0][0][2], 3)
            self.assertIs(invoked[0][1]["prepared_model"], prepared)
            receiver.settimeout(0.2)
            acked = False
            while True:
                try:
                    packet, _ = receiver.recvfrom(8192)
                except socket.timeout:
                    break
                status = json.loads(packet)
                if status.get("state") == "loading" and status.get("camera") is True:
                    acked = True
                    break
            self.assertTrue(acked, "Accepted start command is acknowledged with camera=true")
        finally:
            sender.close()
            receiver.close()

    def test_loading_heartbeat_keeps_status_fresh_during_slow_cuda_init(self):
        token = "fedcba9876543210fedcba9876543210"
        receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        receiver.bind(("127.0.0.1", 0))
        receiver.settimeout(0.3)
        sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        warming = threading.Event()
        unblock = threading.Event()
        result = {}
        try:
            def slow_prepare(_model_path, _progress):
                warming.set()
                self.assertTrue(unblock.wait(timeout=3))
                return (object(), "cpu", False)

            def worker():
                result["code"] = pose_worker.prewarm_worker(
                    receiver.getsockname()[1], token, 0, "local.pt", False,
                    False, (0.0, 0.0), (1.0, 1.0))

            with patch.object(pose_worker, "prepare_pose_model", side_effect=slow_prepare), \
                    patch.object(pose_worker, "run", return_value=0):
                thread = threading.Thread(target=worker, daemon=True)
                thread.start()
                self.assertTrue(warming.wait(timeout=1))
                first_control = None
                prewarming_packets = 0
                until = time.monotonic() + 1.15
                while time.monotonic() < until:
                    try:
                        packet, _ = receiver.recvfrom(8192)
                    except socket.timeout:
                        continue
                    payload = json.loads(packet)
                    first_control = payload.get("control_port", first_control)
                    prewarming_packets += payload.get("state") == "prewarming"
                self.assertGreaterEqual(prewarming_packets, 2, "Prewarm sends heartbeat before watchdog timeout")
                self.assertIsInstance(first_control, int)
                unblock.set()
                dest = ("127.0.0.1", first_control)
                sender.sendto(json.dumps({"command": "start_camera", "token": token}).encode(), dest)
                thread.join(timeout=3)
                self.assertFalse(thread.is_alive())
                self.assertEqual(result.get("code"), 0)
        finally:
            unblock.set()
            sender.close()
            receiver.close()


if __name__ == "__main__":
    unittest.main()
