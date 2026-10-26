"""Hardware-free webcam startup/Windows backend and freshness regressions.

Run in ui/vision/: python -m unittest -v test_pose_camera_startup.py
Never calls a real cv2.VideoCapture, camera device, YOLO, or database.
"""
from __future__ import annotations

import sys
import json
import socket
import threading
import time
import types
import unittest
from unittest.mock import patch

import pose_worker


class FakeCapture:
    def __init__(self, *, opened=True, frames=10, interval=0.006,
                 open_latency=0.0, set_ok=True):
        self.opened = opened
        self.frames = frames
        self.interval = interval
        self.open_latency = open_latency
        self.properties = []
        self.released = False
        self.read_count = 0
        self.set_ok = set_ok

    def isOpened(self):
        return self.opened

    def read(self):
        # Waiting on an event allows close() to wake blocked reads.
        time.sleep(self.interval)
        if self.released or self.frames <= 0:
            return False, None
        self.read_count += 1
        self.frames -= 1
        return True, ("frame", self.read_count)

    def set(self, property_id, value):
        self.properties.append((property_id, value))
        return self.set_ok

    def release(self):
        self.released = True


class FakeCV2(types.SimpleNamespace):
    CAP_ANY = 0
    CAP_DSHOW = 700
    CAP_MSMF = 1400
    CAP_PROP_FRAME_WIDTH = 3
    CAP_PROP_FRAME_HEIGHT = 4
    CAP_PROP_FPS = 5
    CAP_PROP_FOURCC = 6
    CAP_PROP_BUFFERSIZE = 38

    def __init__(self, configured):
        super().__init__()
        self.configured = configured
        self.open_calls = []
        self.set_threads = []

    def VideoCapture(self, index, backend):
        self.open_calls.append((index, backend))
        result = self.configured[backend]
        if isinstance(result, BaseException):
            raise result
        if callable(result):
            result = result()
        if result.open_latency:
            time.sleep(result.open_latency)
        return result

    def VideoWriter_fourcc(self, *characters):
        assert tuple(characters) == ("M", "J", "P", "G")
        return 1196444237

    def setNumThreads(self, threads):
        self.set_threads.append(threads)


class CameraBackendTests(unittest.TestCase):
    def test_dshow_first_on_windows_without_opencv_device(self):
        cv2 = FakeCV2({FakeCV2.CAP_DSHOW: FakeCapture(frames=50)})
        with patch.object(pose_worker.sys, "platform", "win32"):
            capture, reader, stats = pose_worker.open_live_camera(
                cv2, 0, first_frame_timeout=0.2)
        try:
            self.assertIsNotNone(capture)
            self.assertEqual(cv2.open_calls, [(0, FakeCV2.CAP_DSHOW)])
            self.assertEqual(stats["camera_backend"], "DSHOW")
            self.assertEqual(stats["camera_attempts"], 1)
            self.assertGreaterEqual(stats["camera_first_frame_ms"], 0)
            self.assertGreaterEqual(stats["camera_startup_ms"], 0)
            self.assertEqual(cv2.set_threads, [1])
            self.assertEqual(
                [prop for prop, _ in capture.properties],
                [cv2.CAP_PROP_FOURCC, cv2.CAP_PROP_FRAME_WIDTH,
                 cv2.CAP_PROP_FRAME_HEIGHT, cv2.CAP_PROP_FPS,
                 cv2.CAP_PROP_BUFFERSIZE])
            frame, seq, stamp = reader.newest_with_timestamp(-1)
            self.assertIsNotNone(frame)
            self.assertGreaterEqual(seq, 1)
            self.assertGreaterEqual(stamp, reader.started_at)
        finally:
            reader.close()
        self.assertTrue(capture.released)
        self.assertFalse(reader.thread.is_alive())

    def test_dshow_fails_msmf_succeeds_with_timing_and_release(self):
        first = FakeCapture(opened=False)
        second = FakeCapture(frames=50, interval=0.009)
        cv2 = FakeCV2({
            FakeCV2.CAP_DSHOW: first,
            FakeCV2.CAP_MSMF: second,
        })
        phases = []
        with patch.object(pose_worker.sys, "platform", "win32"):
            capture, reader, stats = pose_worker.open_live_camera(
                cv2, 1, first_frame_timeout=0.2, progress=phases.append)
        try:
            self.assertIs(capture, second)
            self.assertTrue(first.released)
            self.assertEqual(cv2.open_calls,
                             [(1, cv2.CAP_DSHOW), (1, cv2.CAP_MSMF)])
            self.assertEqual(stats["camera_backend"], "MSMF")
            self.assertEqual(stats["camera_attempts"], 2)
            self.assertEqual(phases[0]["camera_phase"], "opening")
            self.assertTrue(any(phase["camera_phase"] == "awaiting_frame" for phase in phases))
            self.assertGreaterEqual(stats["camera_startup_ms"], 0)
            self.assertGreaterEqual(stats["camera_first_frame_ms"], 0)
        finally:
            reader.close()

    def test_open_but_empty_backend_is_released_and_retried(self):
        # isOpened() succeeds, but first backend returns zero actual images.
        stale = FakeCapture(opened=True, frames=0)
        working = FakeCapture(opened=True, frames=100)
        cv2 = FakeCV2({
            cv2_backend: cap for cv2_backend, cap in
            ((FakeCV2.CAP_DSHOW, stale), (FakeCV2.CAP_MSMF, working))
        })
        events = []
        with patch.object(pose_worker.sys, "platform", "win32"):
            cap, reader, stats = pose_worker.open_live_camera(
                cv2, 0, progress=events.append, first_frame_timeout=0.08)
        try:
            self.assertIs(cap, working)
            self.assertTrue(stale.released)
            self.assertEqual(stats["camera_backend"], "MSMF")
            self.assertEqual(stats["camera_attempts"], 2)
            self.assertTrue(any(data["camera_phase"] == "no_frames" for data in events))
            self.assertGreaterEqual(stats["camera_startup_ms"], 80)
        finally:
            reader.close()

    def test_all_backends_fail_without_camera_and_no_orphan_read_threads(self):
        unopened = [FakeCapture(opened=False) for _ in range(3)]
        cv2 = FakeCV2(dict(zip(
            [FakeCV2.CAP_DSHOW, FakeCV2.CAP_MSMF, FakeCV2.CAP_ANY], unopened)))
        with patch.object(pose_worker.sys, "platform", "win32"):
            cap, reader, stats = pose_worker.open_live_camera(
                cv2, 0, first_frame_timeout=0.05)
        self.assertIsNone(cap)
        self.assertIsNone(reader)
        self.assertTrue(all(camera.released for camera in unopened))
        self.assertEqual(stats["camera_first_frame_ms"], -1)
        self.assertEqual(stats["camera_attempts"], 3)

    def test_non_windows_uses_only_system_backend(self):
        camera = FakeCapture(frames=50)
        cv2 = FakeCV2({FakeCV2.CAP_ANY: camera})
        with patch.object(pose_worker.sys, "platform", "linux"):
            cap, reader, report = pose_worker.open_live_camera(
                cv2, 2, first_frame_timeout=0.2)
        try:
            self.assertIs(cap, camera)
            self.assertEqual(cv2.open_calls, [(2, cv2.CAP_ANY)])
            self.assertEqual(report["camera_backend"], "ANY")
        finally:
            reader.close()

    def test_open_cv_exception_releases_failed_backend_and_falls_back(self):
        working = FakeCapture(frames=50)
        cv2 = FakeCV2({
            FakeCV2.CAP_DSHOW: RuntimeError("DSHOW temporarily unavailable"),
            FakeCV2.CAP_MSMF: working,
        })
        with patch.object(pose_worker.sys, "platform", "win32"):
            cap, reader, stats = pose_worker.open_live_camera(
                cv2, 0, first_frame_timeout=0.2)
        try:
            self.assertIs(cap, working)
            self.assertEqual(stats["camera_backend"], "MSMF")
        finally:
            reader.close()


class TimestampTests(unittest.TestCase):
    def test_latest_sample_returns_its_own_capture_timestamp(self):
        camera = FakeCapture(frames=50)
        reader = pose_worker.LatestCamera(camera)
        reader.start()
        try:
            self.assertTrue(reader.wait_for_first_frame(0.3))
            first_frame, first_sequence, first_at = reader.newest_with_timestamp(-1)
            self.assertIsNotNone(first_frame)
            self.assertGreaterEqual(first_at, reader.started_at)
            # Inference can become blocked while camera overwrites old samples.
            time.sleep(0.08)
            newest, sequence, at = reader.newest_with_timestamp(first_sequence)
            self.assertGreater(sequence, first_sequence + 5)
            self.assertGreater(at, first_at)
            self.assertLess(time.monotonic() - at, 0.09)
            self.assertEqual(reader.newest_with_timestamp(sequence),
                             (None, sequence, None))
        finally:
            reader.close()

    def test_empty_reader_expires_and_joins_without_fake_image(self):
        capture = FakeCapture(frames=0, interval=0.007)
        reader = pose_worker.LatestCamera(capture)
        reader.start()
        self.assertFalse(reader.wait_for_first_frame(0.04))
        self.assertEqual(reader.newest_with_timestamp(-1), (None, -1, None))
        reader.close()
        self.assertFalse(reader.thread.is_alive())
        self.assertTrue(capture.released)


class WorkerStaleInferenceTests(unittest.TestCase):
    def test_slow_yolo_inference_does_not_publish_old_player_pose(self):
        """A delayed detection is never accepted as a fresh movement sample."""
        try:
            import cv2
            import numpy as np
        except ImportError:
            self.skipTest("OpenCV/NumPy not installed on test runner")

        class SyntheticCamera:
            def __init__(self):
                self.released = False
                self.count = 0
                self.frame = np.zeros((480, 640, 3), dtype=np.uint8)

            def read(self):
                time.sleep(0.013)
                self.count += 1
                if self.released or self.count > 35:
                    return False, None
                return True, self.frame

            def set(self, *_args):
                return True

            def release(self):
                self.released = True

        class SlowModel:
            def __init__(self):
                self.calls = 0

            def track(self, *_args, **_kwargs):
                self.calls += 1
                time.sleep(pose_worker.MAX_CAMERA_SAMPLE_AGE_SECONDS + 0.15)
                return [types.SimpleNamespace(boxes=None, keypoints=None)]

        receiving = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        receiving.bind(("127.0.0.1", 0))
        receiving.settimeout(0.1)
        camera = SyntheticCamera()
        model = SlowModel()
        worker_result = {}
        received = []

        def launch():
            worker_result["code"] = pose_worker.run(
                receiving.getsockname()[1],
                "offline-test-session", 0, "never-used.pt", False,
                prepared_model=(model, "cpu", False))

        try:
            with patch.object(pose_worker, "open_camera", return_value=camera):
                worker = threading.Thread(target=launch, daemon=True)
                worker.start()
                deadline = time.monotonic() + 4.5
                while time.monotonic() < deadline:
                    try:
                        packet, _ = receiving.recvfrom(65535)
                        parsed = json.loads(packet)
                        received.append(parsed)
                    except socket.timeout:
                        pass
                    if not worker.is_alive():
                        break
                worker.join(timeout=1.0)
            self.assertFalse(worker.is_alive(), "mock camera worker stops after read failures")
            self.assertEqual(worker_result.get("code"), 5)
            self.assertGreaterEqual(model.calls, 1)
            rejected = [message for message in received
                        if message.get("camera_phase") == "stale_inference"]
            self.assertTrue(rejected, "slow YOLO result becomes stale_inference")
            self.assertTrue(all(not message.get("pose", False) for message in rejected))
            self.assertTrue(all(message["camera_frame_age_ms"] >=
                                pose_worker.MAX_CAMERA_SAMPLE_AGE_SECONDS * 1000
                                for message in rejected))
            self.assertFalse(any(message.get("state") == "tracking" for message in received),
                             "old inference cannot create valid tracking packet")
            self.assertTrue(any(message.get("camera_phase") == "streaming" and
                                message.get("camera_backend") == "DSHOW"
                                for message in received))
        finally:
            camera.release()
            receiving.close()


if __name__ == "__main__":
    unittest.main()
