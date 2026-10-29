"""Exercise actual worker UDP pose packets using fake inference/camera frames.

No webcam, model download, physical YOLO inference, live database or UI scene.
"""
import json
import socket
import threading
import time
import unittest
from unittest.mock import patch

import pose_worker


class Array:
    def __init__(self, values):
        self.values = values
    def cpu(self):
        return self
    def int(self):
        return self
    def tolist(self):
        return self.values


class SyntheticPrediction:
    def __init__(self, people, with_ids):
        class Boxes:
            pass
        self.boxes = Boxes()
        self.boxes.xyxy = Array([[155 + n*100, 65, 455 + n*100, 448] for n in range(people)])
        self.boxes.id = Array([200 + n for n in range(people)]) if with_ids else None
        self.boxes.__class__.__len__ = lambda this: len(this.xyxy.values)
        class Keypoints:
            pass
        self.keypoints = Keypoints()
        positions = []
        for n in range(people):
            center = 290 + n * 90
            joints = [[center, 240, .05] for _ in range(17)]
            for index, x, y in ((5, center-50, 130), (6, center+50, 130),
                                (11, center-37, 295), (12, center+37, 295),
                                (9, center-75, 240), (10, center+75, 240)):
                joints[index] = [x, y, .98]
            positions.append(joints)
        self.keypoints.data = Array(positions)


class OfflinePacketsTests(unittest.TestCase):
    def test_two_people_pause_then_idless_solo_resumes_then_zero_pauses(self):
        try:
            import numpy as np
        except ImportError:
            self.skipTest("NumPy needed only for fake in-memory image buffer")

        class Camera:
            def __init__(self):
                self.count = 0
                self.closed = False
                self.frame = np.zeros((480, 640, 3), dtype=np.uint8)
            def read(self):
                time.sleep(.038)
                self.count += 1
                if self.closed or self.count > 86:
                    return False, None
                return True, self.frame
            def set(self, *_args): return True
            def release(self): self.closed = True

        class Model:
            def __init__(self): self.calls = 0
            def predict(self, *_args, **_kwargs):
                self.calls += 1
                # 2 valid people, then exactly one WITHOUT any ByteTrack ID,
                # then a genuinely empty view -- all from fresh frames.
                if self.calls <= 10: return [SyntheticPrediction(2, True)]
                if self.calls <= 35: return [SyntheticPrediction(1, False)]
                return [SyntheticPrediction(0, False)]

            def track(self, *_args, **_kwargs):
                raise AssertionError("Retry/gameplay must use raw YOLO predict")

        camera = Camera()
        model = Model()
        messages, result = [], {}
        receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        receiver.bind(("127.0.0.1", 0))
        receiver.settimeout(.1)

        def run_worker():
            result["exit"] = pose_worker.run(
                receiver.getsockname()[1], "synthetic-occupancy-only-test",
                0, "unused-synthetic.pt", False, prepared_model=(model, "cpu", False))
        worker = threading.Thread(target=run_worker, daemon=True)
        try:
            with patch.object(pose_worker, "open_camera", return_value=camera):
                worker.start()
                deadline = time.monotonic() + 7.5
                while time.monotonic() < deadline:
                    try:
                        packet, _ = receiver.recvfrom(65535)
                        if packet and packet[0] == 123:  # JSON begins with {
                            messages.append(json.loads(packet.decode("utf-8")))
                    except socket.timeout:
                        pass
                    if not worker.is_alive():
                        break
                worker.join(timeout=1.0)
            self.assertFalse(worker.is_alive(), "fake camera worker exits after bounded stall")
            tracked = [p for p in messages if p.get("state") == "tracking"
                       and p.get("camera_phase") == "tracking"]
            self.assertTrue(any(p.get("people") == 2 for p in tracked))
            self.assertTrue(all(not p["pose"] and p["lock_state"] == "ambiguous"
                                for p in tracked if p["people"] == 2),
                            "both valid people must block game even with one old tracker ID")
            self.assertTrue(all(not p.get("calibration_hand_observation_valid")
                                and not p.get("calibration_both_hands_up")
                                and not p.get("calibration_both_hands_down")
                                for p in tracked if p["people"] == 2),
                            "crowded source frames never claim bilateral calibration")
            solo = [p for p in tracked if p.get("people") == 1 and p.get("pose")]
            self.assertTrue(solo, "stable ID-less one-person poses must unlock movement")
            self.assertTrue(all(p.get("locked_id") == -1 and p.get("physical_track_id") == -1
                                and p.get("occupancy_verified") and not p.get("needs_recalibration")
                                for p in solo), "no physical or synthetic identity assigned")
            self.assertTrue(all(p.get("calibration_hand_observation_valid")
                                and p.get("calibration_both_hands_down")
                                and not p.get("calibration_both_hands_up") for p in solo),
                            "only fresh verified solo source packets report the two visible down wrists")
            empty = [p for p in tracked if p.get("people") == 0]
            self.assertTrue(empty, "mock worker must report observed zero people")
            self.assertTrue(all(not p.get("pose", False) for p in empty))
            self.assertTrue(all(not p.get("calibration_hand_observation_valid")
                                and not p.get("calibration_both_hands_up")
                                and not p.get("calibration_both_hands_down") for p in empty),
                            "an empty YOLO frame never inherits a prior student's wrists")
        finally:
            camera.release()
            receiver.close()


if __name__ == "__main__":
    unittest.main()
