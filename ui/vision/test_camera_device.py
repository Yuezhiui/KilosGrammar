"""Optional camera-only probe. Never saves a frame, runs YOLO or streams data."""
import sys

from pose_worker import open_camera


def main() -> None:
    try:
        import cv2
    except ImportError as error:
        print("CAMERA PROBE: OpenCV missing:", error)
        sys.exit(2)

    print("CAMERA PROBE: checking local camera index 0 (no files created)", flush=True)
    capture = open_camera(cv2, 0)
    if capture is None:
        print("CAMERA PROBE: NO OPENABLE DEVICE. Check Windows camera privacy settings or device availability.", flush=True)
        sys.exit(3)
    try:
        ok, frame = capture.read()
        if ok:
            print("CAMERA PROBE: PASS; frame dimensions:", frame.shape, flush=True)
        else:
            print("CAMERA PROBE: Camera opened but returned no frame.", flush=True)
    finally:
        capture.release()
    print("CAMERA PROBE: Camera released; frame not stored or transmitted.", flush=True)
    sys.exit(0 if ok else 4)

if __name__ == "__main__":
    main()
