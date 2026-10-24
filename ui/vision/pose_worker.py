"""Opt-in, on-device YOLO26 webcam worker for KilosGrammar.

No frames or student identifiers are saved or uploaded. Packets are delivered
only to a Godot-owned UDP socket on 127.0.0.1. The process is terminated when
the live camera session ends.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import socket
import sys
import threading
import time

from student_lock import StudentLock
from gesture_detector import GestureDetector


# COCO 17-keypoint indices. The live *body* skeleton uses shoulders, elbows,
# wrists, hips, knees and ankles (5..16). Facial points (0..4) must never
# draw "bones" over the student's head. These are display-only choices;
# all original 17 detected keypoints remain intact for tracking/calibration.
SKELETON_EDGES = (
    (5, 6), (5, 7), (7, 9), (6, 8), (8, 10),
    (5, 11), (6, 12), (11, 12), (11, 13), (13, 15),
    (12, 14), (14, 16),
)
BODY_KEYPOINT_INDICES = range(5, 17)
# Keep up to the camera's full requested 640x480 image in the Godot preview.
# The older 384x288/JPEG-48 path looked very blurry when scaled up to the
# student's large on-screen camera window. Preserve the camera aspect ratio.
# IMPORTANT: UI Size 1007x446 is ONLY configured on LiveCameraInset in
# calibration.tscn. Do not copy those dimensions here or distort camera bones.
PREVIEW_SIZE = (640, 480)
PREVIEW_JPEG_MAX_BYTES = 55000  # Local single-UDP-datagram safety margin.
PREVIEW_JPEG_QUALITIES = (78, 68, 58, 48, 38)
MIN_VISIBLE_KEYPOINT_CONFIDENCE = 0.45


def draw_skeleton_preview(cv2: object, frame: object, visible_people: list[dict],
                          visual_offset: tuple[float, float] = (0.0, 0.0),
                          visual_scale: tuple[float, float] = (1.0, 1.0)):
    """Draw only real, confident YOLO joints and their connecting bones.

    ``frame`` is already mirrored for gameplay. Person boxes and track IDs
    remain available to the lock logic, but never appear in preview pixels.
    When no confident keypoints exist, the camera image is left unannotated.
    """
    source_height, source_width = frame.shape[:2]
    scale = min(PREVIEW_SIZE[0] / max(source_width, 1),
                PREVIEW_SIZE[1] / max(source_height, 1))
    width = max(1, round(source_width * scale))
    height = max(1, round(source_height * scale))
    canvas = cv2.resize(frame, (width, height))
    for person in visible_people:
        points = person.get("keypoints", [])
        visible: dict[int, tuple[int, int]] = {}
        for index in BODY_KEYPOINT_INDICES:
            if len(points) <= index:
                continue
            point = points[index]
            if len(point) < 3:
                continue
            x, y, confidence = (float(component) for component in point[:3])
            if (not all(math.isfinite(v) for v in (x, y, confidence))
                    or confidence < MIN_VISIBLE_KEYPOINT_CONFIDENCE
                    or not 0.0 <= x <= 1.0 or not 0.0 <= y <= 1.0):
                continue
            # Godot's editor-authored SkeletonPlacement ReferenceRect supplies
            # this VISUAL transform. Actual keypoints, locks and calibration
            # measurements remain in original camera-normalized coordinates.
            x = visual_offset[0] + x * visual_scale[0]
            y = visual_offset[1] + y * visual_scale[1]
            visible[index] = (round(x * (width - 1)), round(y * (height - 1)))
        for first, second in SKELETON_EDGES:
            if first in visible and second in visible:
                cv2.line(canvas, visible[first], visible[second], (80, 240, 120), 2)
        for point in visible.values():
            cv2.circle(canvas, point, 3, (20, 235, 235), -1)
    return canvas


def encode_preview_jpeg(cv2: object, canvas: object) -> bytes | None:
    """Prefer sharp full-size preview; compress/downscale only if needed.

    A UDP JPEG over the supported size used to disappear entirely. Try better
    quality first, then successively lower encoding quality, and only shrink
    resolution as a last resort. This affects preview pixels, not YOLO poses.
    """
    frame = canvas
    for size_scale in (1.0, 0.8, 0.65):
        if size_scale != 1.0:
            height, width = canvas.shape[:2]
            frame = cv2.resize(canvas, (
                max(1, round(width * size_scale)),
                max(1, round(height * size_scale)),
            ))
        for quality in PREVIEW_JPEG_QUALITIES:
            success, encoded = cv2.imencode(
                ".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, quality]
            )
            if success and len(encoded) < PREVIEW_JPEG_MAX_BYTES:
                return encoded.tobytes()
    return None


def body_position(keypoints: list[list[float]], minimum: float = 0.45) -> float | None:
    """Return camera-mirrored horizontal torso center using confident landmarks."""
    if len(keypoints) < 13:
        return None
    selected = [keypoints[i] for i in (5, 6, 11, 12)]
    if any(len(k) < 3 or k[2] < minimum for k in selected):
        return None
    return sum(k[0] for k in selected) / 4.0


def resilient_body_position(keypoints: list[list[float]], minimum: float = 0.45) -> float | None:
    """Use measured shoulder/hip pairs when depth briefly obscures a joint.

    This never invents a body position when YOLO has not supplied at least
    two confident landmarks from the same anatomical pair.
    """
    full = body_position(keypoints, minimum)
    if full is not None:
        return full
    if len(keypoints) < 13:
        return None
    for a, b in ((5, 6), (11, 12)):
        left, right = keypoints[a], keypoints[b]
        if all(len(point) >= 3 and point[2] >= minimum for point in (left, right)):
            return (left[0] + right[0]) * 0.5
    return None


def arms_raised(keypoints: list[list[float]], minimum: float = 0.45) -> bool:
    """Raw gesture observation only; game action requires a separate edge/cooldown."""
    if len(keypoints) < 11:
        return False
    if any(len(keypoints[i]) < 3 or keypoints[i][2] < minimum for i in (5, 6, 9, 10)):
        return False
    return keypoints[9][1] + 0.08 < keypoints[5][1] and keypoints[10][1] + 0.08 < keypoints[6][1]


def send_status(sock: socket.socket, destination: tuple[str, int], token: str, **fields: object) -> None:
    # A loading, recovering, error or missing-player packet must never leave
    # the last gesture latched in the Godot camera/gameplay bridge.
    message = {"kind": "pose", "token": token, "when": time.monotonic(),
               "hand_up": False, "airplane_pose": False,
               "left_hand_up": False, "right_hand_up": False,
               "hand_observation_valid": False,
               "wing_roll": 0.0, **fields}
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
        self.last_frame_time = time.monotonic()
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
                self.last_frame_time = time.monotonic()
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


def run(port: int, token: str, camera_index: int, model_path: str, preview: bool,
        recovery: bool = False,
        bones_offset: tuple[float, float] = (0.0, 0.0),
        bones_scale: tuple[float, float] = (1.0, 1.0)) -> int:
    target = ("127.0.0.1", port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cap = None
    camera_reader = None
    startup_preview_stop = threading.Event()
    startup_preview_thread = None
    try:
        send_status(sock, target, token, state="loading", detail="Opening the local webcam...")
        try:
            import cv2
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
        send_status(sock, target, token, state="loading", detail="Webcam is opening; preparing pose tracking...")

        # Ultralytics imports and model warmup can take multiple seconds on the
        # classroom PC. Show the latest *real* webcam pixels immediately while
        # tracking loads instead of forcing the student to stare at a black box.
        # This temporary sender uses no YOLO detections, does not draw a bounding
        # box, and stops before the normal skeleton-only pose loop takes over.
        if preview:
            def send_startup_camera() -> None:
                previous_sequence = -1
                last_sent = 0.0
                while not startup_preview_stop.wait(0.015):
                    frame, sequence = camera_reader.newest(previous_sequence)
                    if frame is None:
                        continue
                    previous_sequence = sequence
                    now = time.monotonic()
                    if now - last_sent < 1.0 / 15.0:
                        continue
                    try:
                        mirrored = cv2.flip(frame, 1)
                        canvas = draw_skeleton_preview(cv2, mirrored, [])
                        jpeg = encode_preview_jpeg(cv2, canvas)
                        if jpeg is not None:
                            sock.sendto(b"\x01" + jpeg, target)
                            last_sent = now
                    except (OSError, ValueError, RuntimeError):
                        # Camera read/reconnect status is owned by LatestCamera
                        # and the normal pose loop; a preview error isn't a
                        # reason to crash the detector or block calibration.
                        break

            startup_preview_thread = threading.Thread(
                target=send_startup_camera, name="KilosStartupPreview", daemon=True)
            startup_preview_thread.start()

        try:
            from ultralytics import YOLO
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
        except ImportError as exc:
            send_status(sock, target, token, state="error", detail=f"Missing Python package: {exc}. Install requirements-pose.txt.")
            return 2
        except Exception as exc:
            send_status(sock, target, token, state="error", detail=f"Cannot load model: {str(exc)[:200]}")
            return 4
        finally:
            startup_preview_stop.set()
            if startup_preview_thread is not None:
                startup_preview_thread.join(timeout=0.6)

        last_preview = 0.0
        inferred_count = 0
        inferred_start = time.monotonic()
        pose_fps = 0.0
        previous_sequence = -1
        student = StudentLock()
        gesture_detector = GestureDetector()
        if recovery:
            student.require_clear_reenrollment()
        frame_gap_reported = 0.0
        while True:
            frame, sequence = camera_reader.newest(previous_sequence)
            if frame is None:
                # Capture can stall without returning an explicit pose packet.
                # Preserve the hand's release latch across that gap so a
                # continuously raised arm cannot register a second shot.
                if time.monotonic() - camera_reader.last_frame_time >= 0.3:
                    gesture_detector.update(None, time.monotonic())
                if camera_reader.read_failures >= 25:
                    send_status(sock, target, token, state="error", pose=False,
                                recoverable=True, detail="Camera stopped returning frames. Reconnecting is safe.")
                    return 5
                missing_for = time.monotonic() - camera_reader.last_frame_time
                if missing_for >= 6.0:
                    send_status(sock, target, token, state="error", pose=False,
                                recoverable=True, detail="Camera frames have stopped. Trying a safe camera restart.")
                    return 5
                if missing_for >= 0.8 and time.monotonic() - frame_gap_reported >= 0.8:
                    frame_gap_reported = time.monotonic()
                    send_status(sock, target, token, state="recovering", pose=False,
                                lock_state="occluded", detail="Camera is catching up. Stand in view for a moment.")
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
                    value = resilient_body_position(keypoints)
                    if value is None:
                        continue
                    people.append({
                        "track_id": int(track_id),
                        "x": max(0.0, min(value, 1.0)),
                        "height": max(0.0, (float(box[3]) - float(box[1])) / height),
                        "box": box,
                        "keypoints": keypoints,
                    })
            now = time.monotonic()
            selected, lock_state, reason = student.update(people, now)
            gesture_flags = gesture_detector.update(
                selected["keypoints"] if selected is not None else None,
                now,
                track_id=selected["track_id"] if selected is not None else None,
            )
            if selected is not None:
                torso_x = selected["x"]
                gesture = arms_raised(selected["keypoints"])
                valid = True
            locked_id = student.locked_id if student.locked_id is not None else -1

            inferred_count += 1
            if now - inferred_start >= 1.0:
                pose_fps = inferred_count / (now - inferred_start)
                inferred_count = 0
                inferred_start = now
            send_status(sock, target, token, state="tracking", camera=True, pose=valid,
                        people=number, x=round(torso_x, 5), raised=gesture,
                        hand_up=gesture_flags.hand_up,
                        hand_observation_valid=gesture_flags.hand_observation_valid,
                        airplane_pose=gesture_flags.airplane_pose,
                        wing_roll=round(gesture_flags.wing_roll, 4),
                        left_hand_up=gesture_flags.left_hand_up,
                        right_hand_up=gesture_flags.right_hand_up,
                        lock_state=lock_state, locked_id=locked_id,
                        fps=round(pose_fps, 1), camera_fps=round(camera_reader.camera_fps, 1),
                        device="CUDA" if gpu else "CPU", detail=reason)

            # Send full camera-detail JPEG whenever it fits into one safe UDP
            # packet. Rendering/movement interpolation stays independent.
            if preview and now - last_preview >= (1.0 / 24.0):
                last_preview = now
                # Enrollment and player-position guidance are separate Godot
                # controls; drawing either as an image overlay would put a
                # visible box over the student's camera picture.
                # Never overlay a bystander, an unstable enrollment candidate,
                # or a transient misidentified pose on the student's picture.
                # Only the continuously verified camera-local player is shown.
                shown = [selected] if valid and selected is not None else []
                canvas = draw_skeleton_preview(cv2, frame, shown, bones_offset, bones_scale)
                jpg = encode_preview_jpeg(cv2, canvas)
                if jpg is not None:
                    sock.sendto(b"\x01" + jpg, target)
    finally:
        startup_preview_stop.set()
        if startup_preview_thread is not None and startup_preview_thread.is_alive():
            startup_preview_thread.join(timeout=0.6)
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
    parser.add_argument("--recovery", action="store_true",
                        help="Require a fresh, unambiguous player hold after sensor restart")
    parser.add_argument("--bones-offset-x", type=float, default=0.0)
    parser.add_argument("--bones-offset-y", type=float, default=0.0)
    parser.add_argument("--bones-scale-x", type=float, default=1.0)
    parser.add_argument("--bones-scale-y", type=float, default=1.0)
    arguments = parser.parse_args()
    if not 1024 <= arguments.port <= 65535 or len(arguments.token) < 16:
        return 2
    components = (arguments.bones_offset_x, arguments.bones_offset_y,
                  arguments.bones_scale_x, arguments.bones_scale_y)
    if not all(math.isfinite(component) for component in components) or min(components[2:]) <= 0.0:
        return 2
    if arguments.weights_dir:
        os.makedirs(arguments.weights_dir, exist_ok=True)
        os.chdir(arguments.weights_dir)
    return run(arguments.port, arguments.token, arguments.camera, arguments.model,
               not arguments.no_preview, recovery=arguments.recovery,
               bones_offset=components[:2], bones_scale=components[2:])


if __name__ == "__main__":
    sys.exit(main())
