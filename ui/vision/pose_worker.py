"""Opt-in, on-device YOLO26 webcam worker for KilosGrammar.

No frames or student identifiers are saved or uploaded. Packets are delivered
only to a Godot-owned UDP socket on 127.0.0.1. The process is terminated when
the live camera session ends.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import threading
import time

from student_lock import StudentLock


def body_position(keypoints: list[list[float]], minimum: float = 0.45) -> float | None:
    """Return camera-mirrored horizontal torso center using confident landmarks."""
    if len(keypoints) < 13:
        return None
    selected = [keypoints[i] for i in (5, 6, 11, 12)]
    if any(len(k) < 3 or k[2] < minimum for k in selected):
        return None
    return sum(k[0] for k in selected) / 4.0


def arms_raised(keypoints: list[list[float]], minimum: float = 0.45) -> bool:
    """Raw gesture observation only; game action requires a separate edge/cooldown."""
    if len(keypoints) < 11:
        return False
    if any(len(keypoints[i]) < 3 or keypoints[i][2] < minimum for i in (5, 6, 9, 10)):
        return False
    return keypoints[9][1] + 0.08 < keypoints[5][1] and keypoints[10][1] + 0.08 < keypoints[6][1]


def send_status(sock: socket.socket, destination: tuple[str, int], token: str, **fields: object) -> None:
    message = {"kind": "pose", "token": token, "when": time.monotonic(), **fields}
    sock.sendto(json.dumps(message, separators=(",", ":")).encode("utf-8"), destination)


def open_camera(cv2: object, camera_index: int):
    """Try supported Windows backends in order; never fall back to files/URLs."""
    backends = ([cv2.CAP_MSMF, cv2.CAP_DSHOW, cv2.CAP_ANY]
                if sys.platform == "win32" else [cv2.CAP_ANY])
    for backend in backends:
        camera = cv2.VideoCapture(camera_index, backend)
        if camera.isOpened():
            return camera
        camera.release()
    return None


class LatestCamera:
    """Capture constantly and provide the newest frame without a growing queue."""

    def __init__(self, capture: object):
        self.capture = capture
        self.lock = threading.Lock()
        self.stopping = threading.Event()
        self.frame = None
        self.sequence = 0
        self.read_failures = 0
        self.camera_fps = 0.0
        self.thread = threading.Thread(target=self._read, name="KilosWebcam", daemon=True)

    def start(self) -> None:
        self.thread.start()

    def _read(self) -> None:
        recent_count = 0
        recent_start = time.monotonic()
        while not self.stopping.is_set():
            ok, frame = self.capture.read()
            if not ok:
                self.read_failures += 1
                if self.read_failures >= 25:
                    return
                time.sleep(0.025)
                continue
            self.read_failures = 0
            with self.lock:
                self.frame = frame
                self.sequence += 1
            recent_count += 1
            now = time.monotonic()
            if now - recent_start >= 1.0:
                self.camera_fps = recent_count / (now - recent_start)
                recent_start = now
                recent_count = 0

    def newest(self, previous_sequence: int):
        with self.lock:
            if self.sequence == previous_sequence or self.frame is None:
                return None, previous_sequence
            return self.frame, self.sequence

    def close(self) -> None:
        self.stopping.set()
        # Releasing the stream can unblock an in-progress Windows camera read.
        self.capture.release()
        self.thread.join(timeout=0.8)


def run(port: int, token: str, camera_index: int, model_path: str, preview: bool) -> int:
    target = ("127.0.0.1", port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cap = None
    camera_reader = None
    try:
        send_status(sock, target, token, state="loading", detail="Importing OpenCV and YOLO...")
        try:
            import cv2
            from ultralytics import YOLO
        except ImportError as exc:
            send_status(sock, target, token, state="error", detail=f"Missing Python package: {exc}. Install requirements-pose.txt.")
            return 2

        # Explicit user action in Godot is required before this code is started.
        cap = open_camera(cv2, camera_index)
        if cap is None:
            send_status(sock, target, token, state="error", detail=f"Cannot open webcam index {camera_index}; check permissions or another app.")
            return 3
        cv2.setNumThreads(1)
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        cap.set(cv2.CAP_PROP_FPS, 60)
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        camera_reader = LatestCamera(cap)
        camera_reader.start()
        send_status(sock, target, token, state="loading", detail="Webcam open; loading YOLO26n pose model on GPU when available...")

        try:
            # No YOLO model or inference request is sent to a hosted API.
            # Ultralytics may download its publicly hosted weights ONCE if
            # the model is not already cached (see README).
            model = YOLO(model_path)
            import torch
            gpu = bool(torch.cuda.is_available())
            device = 0 if gpu else "cpu"
            # Warm up the chosen device before the live preview appears.
            import numpy as np
            model.predict(np.zeros((320, 320, 3), dtype=np.uint8),
                          imgsz=320, device=device, verbose=False, max_det=3)
        except Exception as exc:
            send_status(sock, target, token, state="error", detail=f"Cannot load model: {str(exc)[:200]}")
            return 4

        last_preview = 0.0
        inferred_count = 0
        inferred_start = time.monotonic()
        pose_fps = 0.0
        previous_sequence = -1
        student = StudentLock()
        while True:
            frame, sequence = camera_reader.newest(previous_sequence)
            if frame is None:
                if camera_reader.read_failures >= 25:
                    send_status(sock, target, token, state="error", detail="Camera stopped returning frames.")
                    return 5
                time.sleep(0.002)
                continue
            previous_sequence = sequence
            frame = cv2.flip(frame, 1)  # Looking left moves the avatar left.
            height, width = frame.shape[:2]
            try:
                # Stable ByteTrack IDs let us reject BYSTANDERS after one
                # student holds CENTER. Detection only is not sufficient for
                # a crowded classroom because prediction order can change.
                prediction = model.track(
                    frame, persist=True, tracker="bytetrack.yaml",
                    imgsz=320, conf=0.25, device=device, classes=[0],
                    verbose=False, max_det=12
                )[0]
            except Exception as exc:
                send_status(sock, target, token, state="error", detail=f"YOLO inference failed: {str(exc)[:200]}")
                return 6

            number = len(prediction.boxes) if prediction.boxes is not None else 0
            valid = False
            torso_x = -1.0
            gesture = False
            people = []
            if prediction.boxes is not None and prediction.keypoints is not None and prediction.boxes.id is not None:
                tracks = prediction.boxes.id.int().cpu().tolist()
                boxes = prediction.boxes.xyxy.cpu().tolist()
                landmarks = prediction.keypoints.data.cpu().tolist()
                for track_id, box, point_array in zip(tracks, boxes, landmarks):
                    keypoints = [
                        [float(k[0]) / width, float(k[1]) / height,
                         float(k[2]) if len(k) > 2 else 1.0]
                        for k in point_array
                    ]
                    value = body_position(keypoints)
                    if value is None:
                        continue
                    people.append({
                        "track_id": int(track_id),
                        "x": max(0.0, min(value, 1.0)),
                        "height": max(0.0, (float(box[3]) - float(box[1])) / height),
                        "box": box,
                        "keypoints": keypoints,
                    })
            selected, lock_state, reason = student.update(people, time.monotonic())
            if selected is not None:
                torso_x = selected["x"]
                gesture = arms_raised(selected["keypoints"])
                valid = True
            locked_id = student.locked_id if student.locked_id is not None else -1

            now = time.monotonic()
            inferred_count += 1
            if now - inferred_start >= 1.0:
                pose_fps = inferred_count / (now - inferred_start)
                inferred_count = 0
                inferred_start = now
            send_status(sock, target, token, state="tracking", camera=True, pose=valid,
                        people=number, x=round(torso_x, 5), raised=gesture,
                        lock_state=lock_state, locked_id=locked_id,
                        fps=round(pose_fps, 1), camera_fps=round(camera_reader.camera_fps, 1),
                        device="CUDA" if gpu else "CPU", detail=reason)

            # Preview is intentionally a compressed low-res stream. Godot
            # movement interpolation runs independently at display refresh.
            if preview and now - last_preview >= (1.0 / 24.0):
                last_preview = now
                canvas = cv2.resize(frame, (384, 216))
                if student.locked_id is None:
                    # Student enrollment zone; children behind this box
                    # are ignored if one clear foreground target is present.
                    cv2.rectangle(canvas, (int(StudentLock.CENTER_MIN * 384), 5),
                                  (int(StudentLock.CENTER_MAX * 384), 211), (0, 205, 240), 2)
                if valid:
                    box = selected["box"]
                    cv2.rectangle(canvas, (int(box[0] * 384 / width), int(box[1] * 216 / height)),
                                  (int(box[2] * 384 / width), int(box[3] * 216 / height)),
                                  (65, 230, 60), 2)
                    keypoints = selected["keypoints"]
                    for first, second in ((5, 6), (5, 7), (7, 9), (6, 8), (8, 10), (5, 11), (6, 12), (11, 12)):
                        if keypoints[first][2] >= 0.45 and keypoints[second][2] >= 0.45:
                            a = (int(keypoints[first][0] * 384), int(keypoints[first][1] * 216))
                            b = (int(keypoints[second][0] * 384), int(keypoints[second][1] * 216))
                            cv2.line(canvas, a, b, (80, 240, 120), 2)
                    cv2.circle(canvas, (int(torso_x * 384), int((keypoints[5][1] + keypoints[11][1]) * 108)), 6, (20, 235, 235), -1)
                    cv2.putText(canvas, f"PLAYER #{locked_id} LOCKED", (10, 20),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.50, (65, 230, 60), 2)
                else:
                    cv2.putText(canvas, lock_state.upper()[:20], (10, 20),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (40, 230, 230), 2)
                success, jpg = cv2.imencode(".jpg", canvas, [cv2.IMWRITE_JPEG_QUALITY, 48])
                if success and len(jpg) < 55000:
                    sock.sendto(b"\x01" + jpg.tobytes(), target)
    finally:
        if camera_reader is not None:
            camera_reader.close()
        elif cap is not None:
            cap.release()
        sock.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--model", default="yolo26n-pose.pt")
    parser.add_argument("--weights-dir", default="")
    parser.add_argument("--no-preview", action="store_true")
    arguments = parser.parse_args()
    if not 1024 <= arguments.port <= 65535 or len(arguments.token) < 16:
        return 2
    if arguments.weights_dir:
        os.makedirs(arguments.weights_dir, exist_ok=True)
        os.chdir(arguments.weights_dir)
    return run(arguments.port, arguments.token, arguments.camera, arguments.model, not arguments.no_preview)


if __name__ == "__main__":
    sys.exit(main())
