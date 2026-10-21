"""Optional YOLO pose test on a PUBLIC photo, not on your private webcam."""
import os
import sys
import time
from urllib.request import urlopen


def main() -> None:
    import cv2
    import numpy as np
    from ultralytics import YOLO

    from pose_worker import body_position

    weights_dir = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")),
                               "Godot", "app_userdata", "KilosGrammar", "pose_models")
    os.chdir(weights_dir)

    try:
        with urlopen("https://ultralytics.com/images/bus.jpg", timeout=15) as response:
            image_bytes = response.read(2_000_000)
        frame = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
        if frame is None:
            raise RuntimeError("Cannot decode public image")
        model = YOLO("yolo26n-pose.pt")
        started = time.monotonic()
        result = model.predict(frame, imgsz=640, device="cpu", verbose=False)[0]
        if result.keypoints is None or len(result.keypoints.data) == 0:
            raise RuntimeError("No poses returned by YOLO on public test image")
        landmarks = result.keypoints.data.cpu().tolist()
        width, height = frame.shape[1], frame.shape[0]
        samples = [
            body_position([[float(p[0]) / width, float(p[1]) / height,
                            float(p[2]) if len(p) > 2 else 1.0] for p in person])
            for person in landmarks
        ]
        if not any(x is not None for x in samples):
            raise RuntimeError("Detected people but could not read confident torso landmarks")
        print("PUBLIC POSE PROBE: PASS, people=", len(landmarks),
              " keypoints=", len(landmarks[0]),
              " usable_torso_positions=", sum(x is not None for x in samples),
              " inference_seconds=", round(time.monotonic() - started, 2), flush=True)
    except Exception as error:
        print("PUBLIC POSE PROBE: FAILED:", error, flush=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
