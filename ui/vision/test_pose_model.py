"""Optional model-only smoke test with an in-memory blank frame; no webcam."""
import os
import sys
import time


def main() -> None:
    import numpy as np
    from ultralytics import YOLO

    directory = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")),
                             "Godot", "app_userdata", "KilosGrammar", "pose_models")
    os.makedirs(directory, exist_ok=True)
    os.chdir(directory)

    print("MODEL PROBE: loading YOLO26n-Pose. First-time weights download may require internet.", flush=True)
    started = time.monotonic()
    try:
        model = YOLO("yolo26n-pose.pt")
        frame = np.zeros((360, 640, 3), dtype=np.uint8)
        result = model.predict(frame, imgsz=320, device="cpu", verbose=False)[0]
    except Exception as error:
        print("MODEL PROBE: FAILED:", str(error)[:400], flush=True)
        sys.exit(1)
    print("MODEL PROBE: PASS; model=", model.task,
          " boxes=", len(result.boxes) if result.boxes is not None else 0,
          " seconds=", round(time.monotonic() - started, 2),
          " weights_dir=", directory, flush=True)

if __name__ == "__main__":
    main()
