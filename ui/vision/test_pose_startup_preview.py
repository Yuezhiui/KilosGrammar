"""Offline camera-speed regression: early webcam pixels precede YOLO loading.

No hardware camera is opened, no real model or external network is touched.
"""

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


@unittest.skipIf(cv2 is None or np is None, "OpenCV/NumPy required")
class StartupPreviewTest(unittest.TestCase):
    def test_webcam_preview_arrives_before_slow_yolo_model(self):
        token = "0123456789abcdef0123456789abcdef"
        listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        listener.bind(("127.0.0.1", 0))
        listener.settimeout(0.15)
        port = listener.getsockname()[1]

        class SyntheticCamera:
            def __init__(self):
                self.closed = False
                self.image = np.zeros((480, 640, 3), np.uint8)
                self.image[:8] = (10, 120, 200)
                self.image[-8:] = (200, 80, 10)

            def read(self):
                time.sleep(0.018)
                return (False, None) if self.closed else (True, self.image)

            def set(self, *_args):
                return True

            def release(self):
                self.closed = True

        camera = SyntheticCamera()
        model_ready = threading.Event()

        class SlowModel:
            def __init__(self, _weights):
                time.sleep(0.85)
                model_ready.set()
                raise RuntimeError("synthetic model initialization ends here")

        fake_ultralytics = types.ModuleType("ultralytics")
        fake_ultralytics.YOLO = SlowModel
        result = {}

        def run_worker():
            result["code"] = pose_worker.run(port, token, 0, "unused.pt", True)

        try:
            with patch.object(pose_worker, "open_camera", return_value=camera), patch.dict(
                    sys.modules, {"ultralytics": fake_ultralytics}):
                worker = threading.Thread(target=run_worker, daemon=True)
                worker.start()
                previews = []
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline and not model_ready.is_set():
                    try:
                        packet, _ = listener.recvfrom(65535)
                    except socket.timeout:
                        continue
                    if packet[:1] == b"\x01":
                        previews.append(packet[1:])
                worker.join(timeout=4)
            self.assertFalse(worker.is_alive(), "Synthetic model failure ends worker")
            self.assertEqual(result.get("code"), 4)
            self.assertGreaterEqual(len(previews), 1,
                                    "Student should see real webcam frames while the model loads")
            image = cv2.imdecode(np.frombuffer(previews[0], np.uint8), cv2.IMREAD_COLOR)
            self.assertEqual(image.shape[:2], (480, 640), "Native full-resolution 4:3 webcam preview is preserved")
        finally:
            listener.close()


if __name__ == "__main__":
    unittest.main()
