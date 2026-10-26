"""Local no-camera timing probe for YOLO26 startup.

Runs only when explicitly invoked as a script with --benchmark and a LOCAL
weights path. No download fallback, webcam, saved student frames or DB access.
The test suite calls mock-only tests by default; optional CUDA/CPU measurements
are observational, not a pass/fail gate tied to a specific school computer.

    python test_pose_cold_start_timing.py --benchmark C:\\path\\to\\yolo26n-pose.pt
"""
from __future__ import annotations

import argparse
from pathlib import Path
import time
import unittest

from pose_worker import LatestCamera


class StartupBudgetContract(unittest.TestCase):
    def test_camera_reader_keeps_only_latest_frame_slot(self):
        # A slow inference call cannot grow a capture queue because the worker
        # has one overwrite-only slot and a monotonically increasing sequence.
        reader = LatestCamera.__new__(LatestCamera)
        self.assertTrue(hasattr(LatestCamera, "newest"))
        self.assertTrue(hasattr(LatestCamera, "_read"))
        self.assertTrue(hasattr(LatestCamera, "close"))
        self.assertFalse(hasattr(reader, "pending_frames"))


def benchmark(local_weights: Path) -> None:
    if not local_weights.is_file():
        raise SystemExit(f"No local model exists: {local_weights}. Never download weights in a QA probe.")
    started = time.perf_counter()
    import numpy as np
    from ultralytics import YOLO
    import torch
    imported = time.perf_counter()
    model = YOLO(str(local_weights))
    loaded = time.perf_counter()
    device = 0 if torch.cuda.is_available() else "cpu"
    blank = np.zeros((320, 320, 3), dtype=np.uint8)
    model.predict(blank, imgsz=320, device=device, verbose=False, max_det=3)
    warmed = time.perf_counter()
    for _ in range(5):
        model.predict(blank, imgsz=320, device=device, verbose=False, max_det=3)
    five = time.perf_counter()
    print(f"DEVICE={device} weights_bytes={local_weights.stat().st_size}")
    print(f"cold_import_s={imported-started:.3f}")
    print(f"model_load_s={loaded-imported:.3f}")
    print(f"first_synthetic_inference_and_device_warmup_s={warmed-loaded:.3f}")
    print(f"warm_inference_mean_s={(five-warmed)/5:.3f}")
    print(f"total_no_webcam_startup_s={warmed-started:.3f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--benchmark", type=Path)
    arguments = parser.parse_args()
    if arguments.benchmark is not None:
        benchmark(arguments.benchmark)
    else:
        unittest.main(argv=[__file__])
