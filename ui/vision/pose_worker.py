"""Opt-in, on-device YOLO26 webcam worker for KilosGrammar.

No frames or student identifiers are saved or uploaded. Packets are delivered
only to a Godot-owned UDP socket on 127.0.0.1. The process is terminated when
the live camera session ends.
"""

from __future__ import annotations

import argparse
import hmac
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
# A backend can report opened while never producing a frame (often MSMF on
# Windows). Probe reads on a separate capture thread, then fall back safely.
CAMERA_FIRST_FRAME_WAIT_SECONDS = 2.3
# Never let a queued/slowly inferred old picture enroll or move the student.
MAX_CAMERA_SAMPLE_AGE_SECONDS = 0.85


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


def stationary_plane_steering(
    keypoints: list[list[float]], minimum: float = 0.45,
) -> float | None:
    """Measured camera X for Catch-style, side-to-side Human Plane flight.

    The camera is mirrored before YOLO, so increasing X always moves toward
    the player's screen right. Require a real wrist AND a real torso pair from
    the selected locked track. Either wrist works during flight, including the
    opposite wrist when a child's outer hand goes offscreen. Both wrists are
    checked separately when the single neutral calibration is recorded.
    """
    if len(keypoints) < 13:
        return None
    def joint_at(index: int) -> tuple[float, float] | None:
        if index >= len(keypoints):
            return None
        joint = keypoints[index]
        if len(joint) < 3:
            return None
        try:
            x, y, confidence = (float(v) for v in joint[:3])
        except (TypeError, ValueError, OverflowError):
            return None
        if (not all(math.isfinite(value) for value in (x, y, confidence))
                or confidence < minimum
                or not 0.0 <= x <= 1.0 or not 0.0 <= y <= 1.0):
            return None
        return x, y

    left_wrist, right_wrist = joint_at(9), joint_at(10)
    if left_wrist is None and right_wrist is None:
        return None
    shoulders = (joint_at(5), joint_at(6))
    hips = (joint_at(11), joint_at(12))
    shoulder_pair = all(joint is not None for joint in shoulders)
    hip_pair = all(joint is not None for joint in hips)
    if not shoulder_pair and not hip_pair:
        return None
    centers = []
    if shoulder_pair and abs(shoulders[0][0] - shoulders[1][0]) >= 0.07:
        centers.append((shoulders[0][0] + shoulders[1][0]) * 0.5)
    if hip_pair and abs(hips[0][0] - hips[1][0]) >= 0.05:
        centers.append((hips[0][0] + hips[1][0]) * 0.5)
    if not centers:
        return None
    # A single shoulder or hand cannot establish a safe side position. Using
    # torso-only geometry prevents switching wrists from reversing the sign.
    return sum(centers) / len(centers)


class PlaneSteeringTracker:
    """Reject isolated joint glitches and require continuity after occlusion.

    No missing detection is synthesized. A rejected/occluded observation emits
    None; Godot freezes the plane until fresh locked-student observations agree.
    """

    MAX_GAP_SECONDS = 0.65
    MAX_SINGLE_FRAME_JUMP = 0.17
    CONFIRM_TOLERANCE = 0.07

    def __init__(self) -> None:
        self.track_id: int | None = None
        self.last_x: float | None = None
        self.last_time: float | None = None
        self.candidate: float | None = None

    def update(self, track_id: int | None, x: float | None,
               now: float) -> float | None:
        if (track_id is None or x is None or not math.isfinite(now)
                or not math.isfinite(x) or x < 0.0 or x > 1.0):
            self.candidate = None
            self.last_x = None
            self.last_time = None
            return None
        if self.track_id != track_id:
            self.track_id = track_id
            self.last_x = None
            self.last_time = None
            self.candidate = None
        elif self.last_time is not None and now <= self.last_time:
            # Reordered/duplicated inference must never become either of the
            # two independent observations used to resume steering.
            self.last_x = None
            self.candidate = None
            return None
        elif self.last_time is not None and now - self.last_time > self.MAX_GAP_SECONDS:
            self.last_x = None
            self.candidate = None
        if self.last_x is None:
            if self.candidate is None or abs(self.candidate - x) > self.CONFIRM_TOLERANCE:
                self.candidate = x
                self.last_time = now
                return None
            self.last_x = x
            self.candidate = None
            self.last_time = now
            return x
        if abs(x - self.last_x) > self.MAX_SINGLE_FRAME_JUMP:
            if self.candidate is None or abs(x - self.candidate) > self.CONFIRM_TOLERANCE:
                self.candidate = x
                self.last_time = now
                return None
            self.candidate = None
        else:
            self.candidate = None
        self.last_x = x
        self.last_time = now
        return x


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
               "wing_roll": 0.0, "plane_steering": 0.0,
               "plane_steering_valid": False, "plane_neutral_valid": False,
               **fields}
    sock.sendto(json.dumps(message, separators=(",", ":")).encode("utf-8"), destination)


def camera_backends(cv2: object, platform: str | None = None) -> list[tuple[str, int]]:
    """Prefer low-latency DSHOW; preserve MSMF and automatic fallback."""
    target = sys.platform if platform is None else platform
    choices = ([("DSHOW", cv2.CAP_DSHOW), ("MSMF", cv2.CAP_MSMF),
                ("ANY", cv2.CAP_ANY)] if target == "win32"
               else [("ANY", cv2.CAP_ANY)])
    return list(dict.fromkeys(choices))


def open_camera(cv2: object, camera_index: int, *, backends=None, on_attempt=None):
    """Open one physical camera only; report each synchronous backend latency.

    Capture startup is blocking inside OpenCV and cannot be safely cancelled
    once Windows owns the device. Trying DSHOW before MSMF avoids paying its
    often-slow initialization unless the first backend genuinely fails.
    """
    options = camera_backends(cv2) if backends is None else backends
    for name, backend in options:
        start = time.monotonic()
        camera = None
        opened = False
        try:
            camera = cv2.VideoCapture(camera_index, backend)
            opened = bool(camera is not None and camera.isOpened())
        except Exception:
            # Native Windows/OpenCV backends throw differing cv2.error types.
            opened = False
        duration_ms = round((time.monotonic() - start) * 1000)
        if on_attempt is not None:
            on_attempt(name, duration_ms, opened)
        if opened:
            return camera
        if camera is not None:
            try:
                camera.release()
            except Exception:
                pass
    return None


def configure_camera(cv2: object, camera: object) -> None:
    """Prefer low-bandwidth MJPG at 640×480 to unblock USB/Windows capture.

    Backends which cannot negotiate MJPG silently keep their native format.
    Never assume CAP_PROP_BUFFERSIZE is supported on Windows.
    """
    if hasattr(cv2, "setNumThreads"):
        cv2.setNumThreads(1)
    def safe_set(prop, value):
        try:
            camera.set(prop, value)
        except Exception:
            # An unsupported camera property is not an open failure; let
            # first-frame verification decide whether the backend is useful.
            pass
    if hasattr(cv2, "CAP_PROP_FOURCC") and hasattr(cv2, "VideoWriter_fourcc"):
        safe_set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    safe_set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    safe_set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    # Preserve the game's high-FPS preference when the camera can supply it;
    # FPS=60 is a request, never a claim of measured camera/inference FPS.
    safe_set(cv2.CAP_PROP_FPS, 60)
    if hasattr(cv2, "CAP_PROP_BUFFERSIZE"):
        safe_set(cv2.CAP_PROP_BUFFERSIZE, 1)


def open_live_camera(cv2: object, camera_index: int, *, progress=None,
                     first_frame_timeout: float = CAMERA_FIRST_FRAME_WAIT_SECONDS):
    """Return (capture, LatestCamera, metrics) only after a REAL image arrives.

    Each backend has one bounded first-frame wait; an 'opened but blank' backend
    is released and the next backend is tested, rather than holding calibration
    forever. No extra frame queue, synthetic pose, or camera process is made.
    """
    begun = time.monotonic()
    attempts: list[dict] = []
    for name, backend in camera_backends(cv2):
        if progress is not None:
            progress({"camera_phase": "opening", "camera_backend": name,
                      "camera_attempts": len(attempts) + 1})

        def attempted(attempt_name, elapsed_ms, opened):
            attempts.append({"backend": attempt_name, "open_ms": elapsed_ms,
                             "opened": opened})

        attempted_at = time.monotonic()
        capture = open_camera(cv2, camera_index, backends=[(name, backend)],
                              on_attempt=attempted)
        # Preserve compatibility with test shims and alternate camera wrappers
        # which return a capture but don't invoke the optional metric callback.
        if not attempts or attempts[-1]["backend"] != name:
            attempts.append({"backend": name, "open_ms": round(
                (time.monotonic() - attempted_at) * 1000),
                "opened": capture is not None})
        if capture is None:
            continue
        configuration_started = time.monotonic()
        configure_camera(cv2, capture)
        configuration_ms = round((time.monotonic() - configuration_started) * 1000)
        reader = LatestCamera(capture)
        reader.start()
        if progress is not None:
            progress({"camera_phase": "awaiting_frame", "camera_backend": name,
                      "camera_open_ms": attempts[-1]["open_ms"],
                      "camera_attempts": len(attempts)})
        if reader.wait_for_first_frame(first_frame_timeout):
            metrics = {"camera_backend": name,
                       "camera_open_ms": attempts[-1]["open_ms"],
                       "camera_configure_ms": configuration_ms,
                       "camera_first_frame_ms": round(
                           (reader.first_frame_time - reader.started_at) * 1000),
                       "camera_startup_ms": round(
                           (reader.first_frame_time - begun) * 1000),
                       "camera_attempts": len(attempts)}
            return capture, reader, metrics
        reader.close()
        if reader.thread.is_alive():
            # If Windows is still stuck inside VideoCapture.read(), opening a
            # second camera backend concurrently risks a permanent lock.
            # Report recoverable failure to Godot instead of leaking threads.
            if progress is not None:
                progress({"camera_phase": "driver_stalled", "camera_backend": name,
                          "camera_attempts": len(attempts)})
            break
        if progress is not None:
            progress({"camera_phase": "no_frames", "camera_backend": name,
                      "camera_attempts": len(attempts)})
    return None, None, {
        "camera_backend": attempts[-1]["backend"] if attempts else "unknown",
        "camera_open_ms": attempts[-1]["open_ms"] if attempts else -1,
        "camera_configure_ms": -1,
        "camera_first_frame_ms": -1,
        "camera_startup_ms": round((time.monotonic() - begun) * 1000),
        "camera_attempts": len(attempts),
    }


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
        self.started_at = time.monotonic()
        self.last_frame_time = self.started_at
        self.first_frame_time = -1.0
        self.first_frame_ready = threading.Event()
        self.thread = threading.Thread(target=self._read, name="KilosWebcam", daemon=True)

    def start(self) -> None:
        self.thread.start()

    def _read(self) -> None:
        recent_count = 0
        recent_start = time.monotonic()
        while not self.stopping.is_set():
            try:
                ok, frame = self.capture.read()
            except Exception:
                ok, frame = False, None
            if not ok:
                self.read_failures += 1
                if self.read_failures >= 25:
                    return
                time.sleep(0.025)
                continue
            self.read_failures = 0
            captured_at = time.monotonic()
            with self.lock:
                self.frame = frame
                self.sequence += 1
                self.last_frame_time = captured_at
                if self.first_frame_time < 0.0:
                    self.first_frame_time = captured_at
                    self.first_frame_ready.set()
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

    def newest_with_timestamp(self, previous_sequence: int):
        """Atomic frame/sequence/capture timestamp, not newest unrelated age."""
        with self.lock:
            if self.sequence == previous_sequence or self.frame is None:
                return None, previous_sequence, None
            return self.frame, self.sequence, self.last_frame_time

    def wait_for_first_frame(self, timeout: float) -> bool:
        deadline = time.monotonic() + max(0.0, timeout)
        while time.monotonic() < deadline:
            if self.first_frame_ready.wait(min(
                    0.04, max(0.0, deadline - time.monotonic()))):
                return True
            if not self.thread.is_alive():
                return False
        return self.first_frame_ready.is_set()

    def close(self) -> None:
        self.stopping.set()
        # Releasing the stream can unblock an in-progress Windows camera read.
        try:
            self.capture.release()
        except Exception:
            # A disconnected camera must still allow its reader to exit.
            pass
        self.thread.join(timeout=0.8)


def prepare_pose_model(model_path: str, status_callback=None):
    """Load once and warm the exact inference/tracker path used by gameplay.

    An empty camera-sized image primes CUDA, preprocessing and ByteTrack with
    no synthetic person/track. This makes the first real tracked frame cheap.
    If a machine advertises CUDA but fails to initialize it, retry on CPU.
    Bad/corrupt weights and other model errors still surface to the caller.
    """
    from ultralytics import YOLO
    import numpy as np
    import torch

    model = YOLO(model_path)
    gpu = bool(torch.cuda.is_available())
    device = 0 if gpu else "cpu"
    sample = np.zeros((480, 640, 3), dtype=np.uint8)

    def warmup(active_model, chosen_device):
        if status_callback is not None:
            status_callback(f"Preparing {'CUDA' if chosen_device == 0 else 'CPU'} pose tracker...")
        # Use track() rather than predict(): initial ByteTrack registration and
        # its predictor are now primed before the student's first live frame.
        active_model.track(
            sample, persist=True, tracker="bytetrack.yaml", imgsz=320,
            conf=0.25, device=chosen_device, classes=[0],
            verbose=False, max_det=12,
        )

    try:
        warmup(model, device)
    except (RuntimeError, AssertionError, ValueError) as exc:
        description = str(exc).lower()
        cuda_failure = any(marker in description for marker in (
            "cuda", "cudnn", "cublas", "nvidia", "device ordinal",
            "gpu driver", "out of memory",
        ))
        if not gpu or not cuda_failure:
            raise
        if status_callback is not None:
            status_callback("GPU pose initialization unavailable; trying CPU tracking...")
        # A failed CUDA predictor can retain its backend/device. Recreate the
        # lightweight wrapper to guarantee CPU model and tracker initialization.
        del model
        model = YOLO(model_path)
        device = "cpu"
        gpu = False
        # This worker is a standalone process: keep CPU inference responsive
        # and avoid over-subscribing camera JPEG, the game and OpenCV threads.
        if hasattr(torch, "set_num_threads"):
            torch.set_num_threads(min(4, max(1, os.cpu_count() or 1)))
        warmup(model, device)
    return model, device, gpu


class LatestPreview:
    """Asynchronously JPEG-encode only the newest already-inferred video frame.

    Inference and person lock must never wait for JPEG compression or network
    preview. This is a single replaceable slot, not a growing queue, and each
    pose overlay comes from the same frame on which YOLO actually ran.
    """

    def __init__(self, cv2: object, sock: socket.socket, destination: tuple[str, int],
                 bones_offset: tuple[float, float], bones_scale: tuple[float, float]):
        self.cv2 = cv2
        self.sock = sock
        self.destination = destination
        self.bones_offset = bones_offset
        self.bones_scale = bones_scale
        self.lock = threading.Lock()
        self.stop_event = threading.Event()
        self.latest = None
        self.thread = threading.Thread(target=self._send, name="KilosPosePreview", daemon=True)

    def start(self) -> None:
        self.thread.start()

    def submit(self, frame: object, people: list[dict]) -> None:
        with self.lock:
            self.latest = (frame, people)

    def _send(self) -> None:
        next_sent = 0.0
        while not self.stop_event.is_set():
            delay = max(0.0, next_sent - time.monotonic())
            if self.stop_event.wait(max(0.002, delay)):
                break
            with self.lock:
                item = self.latest
                self.latest = None
            if item is None:
                continue
            frame, people = item
            try:
                canvas = draw_skeleton_preview(
                    self.cv2, frame, people, self.bones_offset, self.bones_scale)
                jpeg = encode_preview_jpeg(self.cv2, canvas)
                if jpeg is not None:
                    self.sock.sendto(b"\x01" + jpeg, self.destination)
                # Even noisy, over-limit JPEGs must be rate-limited. Encoding
                # every rejected frame would steal CPU from pose inference.
                next_sent = time.monotonic() + 1.0 / 24.0
            except (OSError, ValueError, RuntimeError):
                # Pose/status processing stays alive if the preview fails.
                return

    def close(self) -> None:
        self.stop_event.set()
        self.thread.join(timeout=0.8)
        with self.lock:
            self.latest = None


def run(port: int, token: str, camera_index: int, model_path: str, preview: bool,
        recovery: bool = False,
        bones_offset: tuple[float, float] = (0.0, 0.0),
        bones_scale: tuple[float, float] = (1.0, 1.0),
        prepared_model: tuple | None = None) -> int:
    target = ("127.0.0.1", port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cap = None
    camera_reader = None
    startup_preview_stop = threading.Event()
    startup_preview_thread = None
    live_preview = None
    boot_started = time.monotonic()
    camera_timings: dict[str, object] = {}
    preview_first_sent_ms = -1
    try:
        send_status(sock, target, token, state="loading",
                    camera_phase="opening", detail="Opening the local webcam...")
        try:
            import cv2
        except ImportError as exc:
            send_status(sock, target, token, state="error", detail=f"Missing Python package: {exc}. Install requirements-pose.txt.")
            return 2

        # Explicit permission or an authenticated prewarm start is required.
        # A VideoCapture can claim isOpened() while still delivering no image;
        # bound that first-frame wait and try another backend if necessary.
        def camera_progress(info: dict) -> None:
            send_status(sock, target, token, state="loading", camera=False,
                        detail="Opening webcam (%s): %s..." %
                        (info.get("camera_backend", "auto"),
                         info.get("camera_phase", "waiting")),
                        **info)

        cap, camera_reader, camera_timings = open_live_camera(
            cv2, camera_index, progress=camera_progress)
        if cap is None or camera_reader is None:
            send_status(sock, target, token, state="error", camera=False,
                        recoverable=True, camera_phase="failed",
                        detail="Camera opened without usable frames, or no Windows "
                               "capture backend worked. Check privacy permissions "
                               "and close other camera apps.", **camera_timings)
            return 3
        send_status(sock, target, token, state="loading", camera=True,
                    camera_phase="streaming", detail="Webcam live; preparing pose tracking...",
                    **camera_timings)

        # Ultralytics imports and model warmup can take multiple seconds on the
        # classroom PC. Show the latest *real* webcam pixels immediately while
        # tracking loads instead of forcing the student to stare at a black box.
        # This temporary sender uses no YOLO detections, does not draw a bounding
        # box, and stops before the normal skeleton-only pose loop takes over.
        if preview:
            # Publish the first *real* captured frame synchronously before
            # starting any heavyweight Ultralytics import/model warmup. The
            # recurring sender below takes over subsequent fresh frames.
            first_preview_sequence = -1
            first_preview_at = 0.0
            initial_frame, initial_sequence = camera_reader.newest(-1)
            if initial_frame is not None:
                try:
                    jpeg = encode_preview_jpeg(
                        cv2, draw_skeleton_preview(cv2, cv2.flip(initial_frame, 1), []))
                    if jpeg is not None:
                        sock.sendto(b"\x01" + jpeg, target)
                        first_preview_sequence = initial_sequence
                        first_preview_at = time.monotonic()
                        preview_first_sent_ms = round(
                            (first_preview_at - boot_started) * 1000)
                        send_status(
                            sock, target, token, state="loading", camera=True,
                            camera_phase="preview",
                            camera_first_preview_ms=preview_first_sent_ms,
                            detail="Live webcam preview available; tracking is preparing...",
                            **camera_timings)
                except (OSError, ValueError, RuntimeError):
                    # A preview encoder cannot block the camera/pose path.
                    pass

            def send_startup_camera() -> None:
                nonlocal preview_first_sent_ms
                previous_sequence = first_preview_sequence
                last_sent = first_preview_at
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
                            if preview_first_sent_ms < 0:
                                preview_first_sent_ms = round((time.monotonic() - boot_started) * 1000)
                                send_status(
                                    sock, target, token, state="loading", camera=True,
                                    camera_phase="preview", camera_first_preview_ms=preview_first_sent_ms,
                                    detail="Live webcam preview available; tracking is preparing...",
                                    **camera_timings)
                    except (OSError, ValueError, RuntimeError):
                        # Camera read/reconnect status is owned by LatestCamera
                        # and the normal pose loop; a preview error isn't a
                        # reason to crash the detector or block calibration.
                        break

            startup_preview_thread = threading.Thread(
                target=send_startup_camera, name="KilosStartupPreview", daemon=True)
            startup_preview_thread.start()

        try:
            if prepared_model is None:
                # Full preview is already live during cold Ultralytics import.
                # Use the cached/bundled .pt provided by pose_service.gd.
                model, device, gpu = prepare_pose_model(
                    model_path, lambda text: send_status(
                        sock, target, token, state="loading", detail=text))
            else:
                # --prewarm loaded the identical model/tracker in this SAME
                # process before explicit camera permission. No second CUDA
                # initialization, weight load or ByteTrack warmup is needed.
                model, device, gpu = prepared_model
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

        if preview:
            live_preview = LatestPreview(cv2, sock, target, bones_offset, bones_scale)
            live_preview.start()
        inferred_count = 0
        ready_at = time.monotonic()
        inferred_start = ready_at
        pose_fps = 0.0
        previous_sequence = -1
        student = StudentLock()
        gesture_detector = GestureDetector()
        plane_tracker = PlaneSteeringTracker()
        if recovery:
            student.require_clear_reenrollment()
        frame_gap_reported = 0.0
        while True:
            frame, sequence, captured_at = camera_reader.newest_with_timestamp(previous_sequence)
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
            source_frame_age = time.monotonic() - captured_at
            if source_frame_age > MAX_CAMERA_SAMPLE_AGE_SECONDS:
                # An image delayed on the capture thread must not become a
                # supposedly fresh student/gesture sample.
                gesture_detector.update(None, time.monotonic())
                continue
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

            source_frame_age = time.monotonic() - captured_at
            if source_frame_age > MAX_CAMERA_SAMPLE_AGE_SECONDS:
                # Slow inference must not revalidate an expired pose. This
                # timestamp is measured INSIDE the Python worker, so it does
                # not incorrectly compare Python and Godot monotonic epochs.
                gesture_detector.update(None, time.monotonic())
                send_status(sock, target, token, state="recovering", camera=True,
                            camera_phase="stale_inference", pose=False,
                            camera_frame_age_ms=round(source_frame_age * 1000),
                            detail="Dropping delayed camera pose; awaiting a new frame.",
                            **camera_timings)
                continue

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
            measured_plane_x = (stationary_plane_steering(selected["keypoints"])
                                if valid and lock_state == "locked" and selected is not None
                                else None)
            plane_steering = plane_tracker.update(
                locked_id if valid and lock_state == "locked" else None,
                measured_plane_x, now)
            plane_neutral_valid = (
                plane_steering is not None and selected is not None
                and all(len(selected["keypoints"]) > i
                        and len(selected["keypoints"][i]) >= 3
                        and float(selected["keypoints"][i][2]) >= 0.45
                        for i in (5, 6, 9, 10))
            )

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
                        plane_steering=round(plane_steering, 5) if plane_steering is not None else 0.0,
                        plane_steering_valid=plane_steering is not None,
                        plane_neutral_valid=plane_neutral_valid,
                        left_hand_up=gesture_flags.left_hand_up,
                        right_hand_up=gesture_flags.right_hand_up,
                        lock_state=lock_state, locked_id=locked_id,
                        fps=round(pose_fps, 1), camera_fps=round(camera_reader.camera_fps, 1),
                        device="CUDA" if gpu else "CPU", detail=reason,
                        startup_ms=round((ready_at - boot_started) * 1000),
                        camera_phase="tracking",
                        camera_frame_age_ms=round(source_frame_age * 1000),
                        camera_first_preview_ms=preview_first_sent_ms,
                        **camera_timings)

            # Encode JPEG off the inference thread; the one-frame slot drops
            # obsolete previews when inference is faster than compression.
            if live_preview is not None:
                # Enrollment and player-position guidance are separate Godot
                # controls; drawing either as an image overlay would put a
                # visible box over the student's camera picture.
                # Never overlay a bystander, an unstable enrollment candidate,
                # or a transient misidentified pose on the student's picture.
                # Only the continuously verified camera-local player is shown.
                shown = [selected] if valid and selected is not None else []
                live_preview.submit(frame, shown)
    finally:
        startup_preview_stop.set()
        if startup_preview_thread is not None and startup_preview_thread.is_alive():
            startup_preview_thread.join(timeout=0.6)
        if live_preview is not None:
            live_preview.close()
        if camera_reader is not None:
            camera_reader.close()
        elif cap is not None:
            cap.release()
        sock.close()


def prewarm_worker(port: int, token: str, camera_index: int, model_path: str,
                   preview: bool, recovery: bool,
                   bones_offset: tuple[float, float],
                   bones_scale: tuple[float, float]) -> int:
    """Prepare YOLO ahead of calibration without ever opening a camera.

    The worker accepts precisely one authenticated, loopback-only UDP
    start_camera command. Sender uses the same session token as the pose
    status packets. A 0.7-second heartbeat keeps Godot's watchdog alive while
    cold torch/CUDA initialization blocks the preparation thread.
    """
    target = ("127.0.0.1", port)
    outbound = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    control = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    heartbeat_stop = threading.Event()
    heartbeat_thread = None
    phase = {"state": "prewarming", "detail": "Preparing the offline YOLO26 pose model..."}
    try:
        try:
            control.bind(("127.0.0.1", 0))
            control.settimeout(0.4)
        except OSError as exc:
            send_status(outbound, target, token, state="error", pose=False,
                        detail=f"Cannot open local pose control channel: {str(exc)[:120]}")
            return 3
        control_port = control.getsockname()[1]

        def status_update(state: str, detail: str, camera: bool = False) -> None:
            phase["state"] = state
            phase["detail"] = detail
            phase["camera"] = camera
            send_status(outbound, target, token, state=state, pose=False,
                        control_port=control_port, model_ready=state == "ready",
                        camera=camera, detail=detail)

        def heartbeat() -> None:
            while not heartbeat_stop.wait(0.7):
                send_status(outbound, target, token, state=phase["state"],
                            pose=False, control_port=control_port,
                            model_ready=phase["state"] == "ready",
                            camera=phase.get("camera", False),
                            detail=phase["detail"])

        status_update("prewarming", "Preparing the offline YOLO26 pose model...")
        heartbeat_thread = threading.Thread(
            target=heartbeat, name="KilosPosePrewarmHeartbeat", daemon=True)
        heartbeat_thread.start()

        try:
            prepared = prepare_pose_model(
                model_path, lambda detail: status_update("prewarming", detail))
        except ImportError as exc:
            status_update("error", f"Missing Python package: {exc}. Install requirements-pose.txt.")
            return 2
        except Exception as exc:
            status_update("error", f"Cannot load pose model: {str(exc)[:200]}")
            return 4

        status_update("ready", "Pose model is ready. Waiting for camera calibration...")
        while True:
            try:
                packet, address = control.recvfrom(512)
            except socket.timeout:
                continue
            except OSError:
                return 5
            if address[0] != "127.0.0.1":
                continue
            try:
                command = json.loads(packet)
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
            if not isinstance(command, dict):
                continue
            supplied_token = command.get("token")
            if (not isinstance(supplied_token, str)
                    or not hmac.compare_digest(supplied_token, token)
                    or command.get("command") != "start_camera"):
                continue
            # Never let a stale `ready` heartbeat overtake the authorized
            # camera-start acknowledgement in Godot's newest-packet drain.
            heartbeat_stop.set()
            if heartbeat_thread is not None:
                heartbeat_thread.join(timeout=0.8)
            # Bridge handshake acknowledgement: Godot stops resending the
            # authenticated command immediately, even if camera.open takes
            # several more seconds to complete on this Windows driver.
            status_update("loading", "Starting your webcam for calibration...", camera=True)
            break
    finally:
        heartbeat_stop.set()
        if heartbeat_thread is not None:
            heartbeat_thread.join(timeout=0.8)
        control.close()
        outbound.close()

    return run(port, token, camera_index, model_path, preview,
               recovery=recovery, bones_offset=bones_offset,
               bones_scale=bones_scale, prepared_model=prepared)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--model", default="yolo26n-pose.pt")
    parser.add_argument("--weights-dir", default="")
    parser.add_argument("--no-preview", action="store_true")
    parser.add_argument("--prewarm", action="store_true",
                        help="Warm offline model now; open webcam only on token-authenticated UDP start_camera")
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
    if arguments.prewarm:
        return prewarm_worker(arguments.port, arguments.token, arguments.camera,
                              arguments.model, not arguments.no_preview,
                              arguments.recovery, components[:2], components[2:])
    return run(arguments.port, arguments.token, arguments.camera, arguments.model,
               not arguments.no_preview, recovery=arguments.recovery,
               bones_offset=components[:2], bones_scale=components[2:])


if __name__ == "__main__":
    sys.exit(main())
