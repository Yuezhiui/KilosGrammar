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
from two_player_lock import TwoPlayerLock
from gesture_detector import GestureDetector, GestureState


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
# Visual-only hint can show a real, moderately confident YOLO joint while the
# separate 0.45+ torso/gesture checks continue to decide gameplay authority.
# A child should not see a blank or gray guide simply because a wrist/hip
# briefly falls below the strict control threshold.
MIN_VISIBLE_KEYPOINT_CONFIDENCE = 0.30
# Raw-camera fallback keeps the webcam responsive when YOLO genuinely stalls.
# Do not erase fresh real skeleton artwork after only 0.6 s: slower classroom
# inference can otherwise alternate green-bones / empty-frame / green-bones.
# Stay below Godot PoseService's 1.4 s stale-preview limit: no ghost skeletons.
RAW_PREVIEW_FALLBACK_DELAY_SECONDS = 1.15
# A backend can report opened while never producing a frame (often MSMF on
# Windows). Probe reads on a separate capture thread, then fall back safely.
CAMERA_FIRST_FRAME_WAIT_SECONDS = 2.3
# Never let a queued/slowly inferred old picture enroll or move the student.
MAX_CAMERA_SAMPLE_AGE_SECONDS = 0.65


class PreviewPublisher:
    """Order raw and inferred camera JPEGs by their actual capture timestamps.

    Raw fallback is allowed after an inference stall, but never allowed to
    reorder an older skeleton over a newer camera image. The short ASCII
    header also lets Godot reject late SOLO artwork after a crowd/pose loss.
    It is visual metadata only: it cannot create any gameplay pose sample.
    """

    def __init__(self, sock: socket.socket, destination: tuple[str, int]):
        self.sock = sock
        self.destination = destination
        self.lock = threading.Lock()
        self.last_source_at = -1.0
        self.last_inferred_sent_at = time.monotonic()
        self.last_raw_sent_at = 0.0

    def raw_fallback_due(self, now: float) -> bool:
        with self.lock:
            return (now - self.last_inferred_sent_at >= RAW_PREVIEW_FALLBACK_DELAY_SECONDS
                    and now - self.last_raw_sent_at >= 0.15)

    def publish(self, jpeg: bytes | None, captured_at: float,
                inferred: bool, people_count: int = -1,
                foreground_count: int = -1) -> bool:
        if jpeg is None or not math.isfinite(captured_at):
            return False
        # A JPEG encoder may finish after the camera/inference that supplied
        # its pixels has expired. Never publish delayed bones as fresh.
        with self.lock:
            # Check INSIDE the send lock: waiting behind another JPEG sender
            # must not grant an already-old source image fresh authority.
            now = time.monotonic()
            if captured_at > now or now - captured_at > MAX_CAMERA_SAMPLE_AGE_SECONDS:
                return False
            if captured_at <= self.last_source_at:
                return False
            # 0x02: capture time / inference flag / RAW person count /
            # capture-to-send age / foreground candidate count, then the JPEG.
            # The fourth field stays at its original position; Godot may
            # use the appended fifth field to validate a real foreground pose.
            # Including source age stops
            # the recipient giving a late JPEG a second full stale lifetime.
            # The marker and bounded textual header avoid platform byte order
            # assumptions in Godot's PackedByteArray decoder.
            source_age_ms = round((now - captured_at) * 1000)
            heading = (f"{captured_at:.9f},{int(inferred)},{people_count},"
                       f"{source_age_ms},{foreground_count};").encode("ascii")
            self.sock.sendto(b"\x02" + heading + jpeg, self.destination)
            self.last_source_at = captured_at
            if inferred:
                self.last_inferred_sent_at = time.monotonic()
            else:
                self.last_raw_sent_at = time.monotonic()
            return True


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
        # Preserve the visual-only role on each *currently detected* skeleton.
        # Passive people can be seen while the selected student is occluded,
        # but their bodies can NEVER be passed to the movement/gesture APIs.
        role = person.get("preview_role", "active")
        passive = role != "active"
        # A real SOLO detected person is green immediately, even during the
        # initial physical-lock hold or a low-confidence torso observation.
        # The brighter/thicker stroke still identifies an authenticated SOLO
        # controller; multi-person candidates remain muted. These are ONLY
        # display pixels, never calibration or gameplay control data.
        bone_color = ((65, 255, 80) if role == "active" else
                      (75, 230, 105) if role == "solo_pending" else
                      (145, 125, 85))
        joint_color = ((30, 255, 120) if role == "active" else
                       (65, 235, 130) if role == "solo_pending" else
                       (185, 155, 95))
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
                cv2.line(canvas, visible[first], visible[second], bone_color,
                         3 if role == "active" else 2 if role == "solo_pending" else 1)
        for point in visible.values():
            cv2.circle(canvas, point, 4 if role == "active" else
                       3 if role == "solo_pending" else 2, joint_color, -1)
    return canvas


def preview_people(people: list[dict], selected: dict | None,
                   highlight_solo_candidate: bool = False,
                   foreground_candidate: dict | None = None) -> list[dict]:
    """Real visible candidates for preview, with exactly one active controller.

    Return new lightweight dictionaries: do not mutate the StudentLock's
    people, preserve actual keypoints and never draw a remembered skeleton.
    An explicitly verified raw-solo body still enrolling may use a softer
    green visual role; it is NEVER an active gameplay/controller role.
    """
    def same_source_detection(person: dict, target: dict | None) -> bool:
        if target is None:
            return False
        # A raw predict() result has no ByteTrack ID: every sighting is -1.
        # Only this frame's YOLO detection index can reliably map its own
        # torso selection to its own preview keypoints, regardless of ID churn.
        index = target.get("detection_index")
        if index is not None and person.get("detection_index") is not None:
            return person["detection_index"] == index
        if person is target:
            return True
        track = target.get("track_id", -1)
        return isinstance(track, int) and track >= 0 and person.get("track_id") == track \
            and sum(p.get("track_id") == track for p in people) == 1

    pending = foreground_candidate
    if pending is None and highlight_solo_candidate and len(people) == 1:
        pending = people[0]
    return [{**person, "preview_role": (
                "active" if same_source_detection(person, selected) else
                "solo_pending" if selected is None and highlight_solo_candidate
                and same_source_detection(person, pending) else "candidate")}
            for person in people]


def foreground_preview_people(visible_people: list[dict], selected: dict | None,
                              foreground_candidate: dict | None,
                              foreground_count: int,
                              foreground_ambiguous: bool) -> list[dict]:
    """Draw only the one source-matched foreground skeleton, never spectators."""
    if foreground_ambiguous or foreground_count != 1 or foreground_candidate is None:
        return []
    index = foreground_candidate.get("detection_index")
    if index is None:
        return []  # Never guess using a ByteTrack ID or spatial coincidence.
    matched = [p for p in visible_people if p.get("detection_index") == index]
    if len(matched) != 1:
        return []
    return preview_people(matched, selected,
                          highlight_solo_candidate=selected is None,
                          foreground_candidate=foreground_candidate)


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
    # Turning, stepping sideways or raising an arm can temporarily obscure a
    # shoulder or hip on the far side. A same-side shoulder+hip is still TWO
    # actual fresh torso landmarks, unlike estimating a pose from a box alone.
    for a, b in ((5, 6), (11, 12), (5, 11), (6, 12)):
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


def plane_arm_bank(keypoints: list[list[float]], minimum: float = 0.45) -> tuple[bool, bool, float]:
    """Measure live, *mirrored screen-space* T-pose and continuous wing banking.

    Returns (t_pose, bank_valid, signed_bank), where -1 is screen LEFT and
    +1 is screen RIGHT. The camera has already been cv2.flip(..., 1)'d.
    Requires both real shoulders, elbows and wrists on the CURRENT inference.
    Missing/weak joints cannot inherit a previous bank or fabricate control.
    """
    if len(keypoints) < 11:
        return False, False, 0.0

    def get_joint(index: int) -> tuple[float, float] | None:
        joint = keypoints[index]
        if len(joint) < 3:
            return None
        try:
            x, y, conf = (float(item) for item in joint[:3])
        except (ValueError, TypeError, OverflowError):
            return None
        if not all(math.isfinite(v) for v in (x, y, conf)) or conf < minimum:
            return None
        if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
            return None
        return x, y

    shoulders = (get_joint(5), get_joint(6))
    elbows = (get_joint(7), get_joint(8))
    wrists = (get_joint(9), get_joint(10))
    if any(joint is None for joint in (*shoulders, *elbows, *wrists)):
        return False, False, 0.0
    width = abs(shoulders[1][0] - shoulders[0][0])
    if width < 0.065:
        return False, False, 0.0
    # COCO indices refer to ANATOMICAL left/right; mirrored camera controls
    # must sort by screen X or their directions invert whenever camera flips.
    screen_left = 0 if shoulders[0][0] < shoulders[1][0] else 1
    screen_right = 1 - screen_left
    angles = []
    t_arm_level = []
    for side in (screen_left, screen_right):
        shoulder, elbow, wrist = shoulders[side], elbows[side], wrists[side]
        direction = -1.0 if side == screen_left else 1.0
        elbow_out = direction * (elbow[0] - shoulder[0]) / width
        wrist_out = direction * (wrist[0] - shoulder[0]) / width
        wrist_after_elbow = direction * (wrist[0] - elbow[0]) / width
        # A hanging or folded arm is not a wing. Strong horizontal extension
        # must still be visible even during a 45-degree tilted flight pose.
        if elbow_out < 0.14 or wrist_out < 0.58 or wrist_after_elbow < 0.13:
            return False, False, 0.0
        angle = math.atan2(wrist[1] - shoulder[1], abs(wrist[0] - shoulder[0]))
        elbow_angle = math.atan2(elbow[1] - shoulder[1], abs(elbow[0] - shoulder[0]))
        if abs(angle) > math.radians(62) or abs(elbow_angle) > math.radians(68):
            return False, False, 0.0
        angles.append(angle)
        # Classroom cameras see small children from different heights; even a
        # genuine arms-wide T-pose often tilts slightly. 12/18 degrees caused
        # the full three-second intro calibration to restart on a single
        # ordinary inference wobble. Permit modest 20/25-degree tilt while
        # still requiring two confidently observed OUTWARD shoulder/elbow/
        # wrist chains above, and never accept hanging/folded arms.
        t_arm_level.append(abs(angle) <= math.radians(20)
                           and abs(elbow_angle) <= math.radians(25))

    # Both down-tilted arms mean 'lowered arms', NOT permission to keep flying.
    if all(angle > math.radians(28) for angle in angles):
        return False, False, 0.0

    t_pose = all(t_arm_level)
    # Relative ANGLES, not torso X or shoulder position: level arms => zero,
    # right wing below left => positive screen-right motion, and vice versa.
    relative = angles[1] - angles[0]
    deadzone = math.radians(6)
    intensity = max(0.0, abs(relative) - deadzone) / math.radians(72)
    bank = math.copysign(min(1.0, intensity), relative) if intensity > 0 else 0.0
    return t_pose, True, bank


def arms_raised(keypoints: list[list[float]], minimum: float = 0.45) -> bool:
    """Raw gesture observation only; game action requires a separate edge/cooldown."""
    if len(keypoints) < 11:
        return False
    if any(len(keypoints[i]) < 3 or keypoints[i][2] < minimum for i in (5, 6, 9, 10)):
        return False
    return keypoints[9][1] + 0.08 < keypoints[5][1] and keypoints[10][1] + 0.08 < keypoints[6][1]


def calibration_bilateral_packet_fields(
    observation: GestureState, selected: dict | None,
    lock_state: str, detected_count: int,
) -> dict[str, bool]:
    """Expose current-frame bilateral evidence only for the locked SOLO body.

    Called after the worker has rejected stale camera/inference frames, run
    YOLO, and counted raw person boxes. Never use a remembered selected person,
    a second detected person, or the shooting latch for calibration samples.
    """
    verified_solo = (selected is not None and lock_state == "locked"
                     and detected_count == 1)
    valid = verified_solo and observation.calibration_hand_observation_valid
    return {
        "calibration_hand_observation_valid": valid,
        "calibration_both_hands_up": valid and observation.calibration_both_hands_up,
        "calibration_both_hands_down": valid and observation.calibration_both_hands_down,
    }


def send_status(sock: socket.socket, destination: tuple[str, int], token: str, **fields: object) -> None:
    # A loading, recovering, error or missing-player packet must never leave
    # the last gesture latched in the Godot camera/gameplay bridge.
    message = {"kind": "pose", "token": token, "when": time.monotonic(),
               "hand_up": False, "airplane_pose": False,
               "left_hand_up": False, "right_hand_up": False,
               "hand_observation_valid": False,
               "calibration_hand_observation_valid": False,
               "calibration_both_hands_up": False,
               "calibration_both_hands_down": False,
               "wing_roll": 0.0, "plane_steering": 0.0,
               "plane_t_pose_valid": False, "plane_bank_valid": False,
               "plane_bank": 0.0,
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
                # A Windows webcam can briefly return a burst of unsuccessful
                # reads during autofocus, reconnection or USB contention. The
                # old 25-attempt limit permanently killed the ONLY frame
                # reader after ~0.6 s; no later returning student could make
                # it restart. The supervising run loop owns the wall-clock
                # timeout/recoverable process restart instead.
                self.read_failures = min(self.read_failures + 1, 100000)
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
    """Load once and warm the exact raw pose inference path used by gameplay.

    An empty camera-sized image primes CUDA and raw pose preprocessing without
    creating a persistent ByteTrack tracker or its candidate association state.
    The game controls exactly one visually detected person, not a track ID.
    If a machine advertises CUDA but fails to initialize it, retry on CPU.
    Bad/corrupt weights and other model errors still surface to the caller.
    """
    from ultralytics import YOLO
    import numpy as np

    # Construct the YOLO wrapper as soon as Ultralytics is available. On
    # Windows, a separate lazy "import torch" can take several seconds even
    # after Ultralytics imported successfully; delaying model construction
    # until *after* that second import leaves the user seeing a bare camera
    # preview with no actionable startup result. YOLO itself brings in the
    # torch backend when it needs it; ask torch for CUDA only afterward.
    model = YOLO(model_path)
    import torch
    gpu = bool(torch.cuda.is_available())
    device = 0 if gpu else "cpu"
    if not gpu and hasattr(torch, "set_num_threads"):
        # CPU-only school PCs should leave cores available for Godot's game,
        # webcam capture, and JPEG delivery once the countdown completes.
        # Previously this cap ran only on a FAILED CUDA-to-CPU fallback.
        torch.set_num_threads(min(4, max(1, os.cpu_count() or 1)))
    sample = np.zeros((480, 640, 3), dtype=np.uint8)

    def warmup(active_model, chosen_device):
        if status_callback is not None:
            status_callback(f"Preparing {'CUDA' if chosen_device == 0 else 'CPU'} raw pose detector...")
        # Ultralytics track() installs postprocess callbacks that replace
        # raw detected people/keypoints with only ByteTrack-accepted tracks.
        # A camera restarted while a student never steps out of view can then
        # show no green bones until ByteTrack reacquires. Raw predict() does
        # not depend on track IDs or person motion at first Retry frame.
        active_model.predict(
            sample, imgsz=320,
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
        # lightweight wrapper for a clean CPU raw-prediction backend.
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


def observed_pose_people(prediction: object, width: int, height: int) -> tuple[list[dict], list[dict]]:
    """Real YOLO people and independently measured, single-person eligible poses.

    ByteTrack IDs are DIAGNOSTIC only. Even when ByteTrack has no ID, a real
    box with confident joint geometry is a fully eligible solo controller.
    No missing landmarks are invented or carried forward across source frames.
    """
    detected, preview = [], []
    boxes_object = getattr(prediction, "boxes", None)
    if boxes_object is None or width <= 0 or height <= 0:
        return detected, preview
    boxes = boxes_object.xyxy.cpu().tolist()
    ids = getattr(boxes_object, "id", None)
    tracks = ids.int().cpu().tolist() if ids is not None else []
    keypoint_object = getattr(prediction, "keypoints", None)
    landmarks = (keypoint_object.data.cpu().tolist()
                 if keypoint_object is not None else [])
    for index, raw_box in enumerate(boxes):
        if len(raw_box) < 4:
            continue
        try:
            box = [float(v) for v in raw_box[:4]]
        except (TypeError, ValueError, OverflowError):
            continue
        if not all(math.isfinite(v) for v in box):
            continue
        box_x = (box[0] + box[2]) / (2.0 * width)
        box_height = (box[3] - box[1]) / height
        if not (math.isfinite(box_x) and math.isfinite(box_height)
                and 0 <= box_x <= 1 and box_height > 0):
            continue
        real_id = tracks[index] if index < len(tracks) else None
        has_id = isinstance(real_id, int) and real_id >= 0
        sighting_id = real_id if has_id else -1
        keypoints = []
        if index < len(landmarks):
            try:
                keypoints = [
                    [float(k[0]) / width, float(k[1]) / height,
                     float(k[2]) if len(k) > 2 else 1.0]
                    for k in landmarks[index]
                ]
            except (TypeError, ValueError, IndexError, OverflowError):
                keypoints = []
        if keypoints:
            preview.append({"track_id": real_id if has_id else -1,
                            "detection_index": index, "keypoints": keypoints})
        x = resilient_body_position(keypoints)
        eligible = x is not None and math.isfinite(x) and 0 <= x <= 1
        detected.append({
            "track_id": sighting_id, "detection_index": index,
            "x": float(x) if eligible else box_x,
            "height": box_height, "box": box, "eligible": eligible,
            "keypoints": keypoints if eligible else [],
        })
    return detected, preview


class LatestPreview:
    """Asynchronously JPEG-encode only the newest already-inferred video frame.

    Inference and person lock must never wait for JPEG compression or network
    preview. This is a single replaceable slot, not a growing queue, and each
    pose overlay comes from the same frame on which YOLO actually ran.
    """

    def __init__(self, cv2: object, sock: socket.socket, destination: tuple[str, int],
                 bones_offset: tuple[float, float], bones_scale: tuple[float, float],
                 publisher: PreviewPublisher | None = None):
        self.cv2 = cv2
        self.sock = sock
        self.destination = destination
        self.publisher = publisher or PreviewPublisher(sock, destination)
        self.bones_offset = bones_offset
        self.bones_scale = bones_scale
        self.lock = threading.Lock()
        self.stop_event = threading.Event()
        self.latest = None
        self.last_sent_at = 0.0
        self.failure_count = 0
        self.total_failures = 0
        self.thread = threading.Thread(target=self._send, name="KilosPosePreview", daemon=True)

    def start(self) -> None:
        self.thread.start()

    def submit(self, frame: object, people: list[dict],
               captured_at: float | None = None, raw_person_count: int = -1,
               foreground_person_count: int = -1) -> None:
        if captured_at is None:
            captured_at = time.monotonic()
        with self.lock:
            self.latest = (frame, people, captured_at, raw_person_count,
                           foreground_person_count)

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
            frame, people, captured_at, raw_person_count, foreground_count = item
            try:
                canvas = draw_skeleton_preview(
                    self.cv2, frame, people, self.bones_offset, self.bones_scale)
                jpeg = encode_preview_jpeg(self.cv2, canvas)
                if self.publisher.publish(jpeg, captured_at, True,
                                          raw_person_count, foreground_count):
                    self.last_sent_at = time.monotonic()
                    self.failure_count = 0
                # Even noisy, over-limit JPEGs must be rate-limited. Encoding
                # every rejected frame would steal CPU from pose inference.
                next_sent = time.monotonic() + 1.0 / 24.0
            except Exception:
                # A transient OpenCV encode/network error used to terminate
                # this ONLY preview thread forever, hiding all new bones while
                # gameplay packets continued. Recover from the next fresh pose.
                self.total_failures += 1
                self.failure_count += 1
                next_sent = time.monotonic() + min(0.5, self.failure_count * 0.05)

    def close(self) -> None:
        self.stop_event.set()
        self.thread.join(timeout=0.8)
        with self.lock:
            self.latest = None


def run(port: int, token: str, camera_index: int, model_path: str, preview: bool,
        recovery: bool = False,
        bones_offset: tuple[float, float] = (0.0, 0.0),
        bones_scale: tuple[float, float] = (1.0, 1.0),
        prepared_model: tuple | None = None,
        prepared_model_loader=None, players: int = 1) -> int:
    target = ("127.0.0.1", port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cap = None
    camera_reader = None
    startup_preview_stop = threading.Event()
    startup_preview_thread = None
    fallback_preview_stop = threading.Event()
    fallback_preview_thread = None
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
            if prepared_model is None and prepared_model_loader is not None:
                # The teacher entered calibration while background prewarm was
                # still importing torch/CUDA. Open the camera and publish real
                # preview FIRST, then wait for that SAME model to finish.
                model, device, gpu = prepared_model_loader()
            elif prepared_model is None:
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
            # Both JPEG-producing threads share one capture-order gate. A raw
            # fallback can never overtake an older inference JPEG (or vice
            # versa), even if image encoding completes in a different order.
            preview_publisher = PreviewPublisher(sock, target)
            live_preview = LatestPreview(
                cv2, sock, target, bones_offset, bones_scale, preview_publisher)
            live_preview.start()

            def fresh_camera_fallback() -> None:
                """Real live image with NO cached skeleton if inference stalls."""
                previous_fallback_sequence = -1
                while not fallback_preview_stop.wait(0.045):
                    if not preview_publisher.raw_fallback_due(time.monotonic()):
                        continue
                    newest_frame, seq, captured = camera_reader.newest_with_timestamp(
                        previous_fallback_sequence)
                    if newest_frame is None:
                        continue
                    previous_fallback_sequence = seq
                    if captured is None or time.monotonic() - captured > MAX_CAMERA_SAMPLE_AGE_SECONDS:
                        continue
                    try:
                        canvas = draw_skeleton_preview(cv2, cv2.flip(newest_frame, 1), [])
                        jpeg = encode_preview_jpeg(cv2, canvas)
                        preview_publisher.publish(jpeg, captured, False)
                    except Exception:
                        # No stale bones or fatal preview worker failure.
                        pass

            fallback_preview_thread = threading.Thread(
                target=fresh_camera_fallback, name="KilosLiveRawFallback", daemon=True)
            fallback_preview_thread.start()
        inferred_count = 0
        ready_at = time.monotonic()
        inferred_start = ready_at
        pose_fps = 0.0
        previous_sequence = -1
        student = StudentLock()
        two_player = TwoPlayerLock() if players == 2 else None
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
                missing_for = time.monotonic() - camera_reader.last_frame_time
                # Keep retrying through short 25+-read failures (<2.2 sec),
                # but don't leave a genuinely disconnected camera running
                # indefinitely: return a recoverable status for Godot to
                # restart a single worker after the real wall-clock stall.
                if camera_reader.read_failures >= 25 and missing_for >= 2.2:
                    send_status(sock, target, token, state="error", pose=False,
                                recoverable=True,
                                detail="Camera stream stopped for over two seconds. Restarting safely.")
                    return 5
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
                # This game no longer uses ByteTrack identity. Ultralytics
                # track(persist=True) can filter visible YOLO poses until a
                # persistent tracker accepts a track; after Retry the student
                # would have to leave and return for green bones to appear.
                # Predict raw boxes + keypoints for EVERY genuinely fresh
                # frame, including a stationary student at camera startup.
                prediction = model.predict(
                    frame,
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
            people, visible_people = observed_pose_people(prediction, width, height)
            now = time.monotonic()
            if two_player is not None:
                # One full-frame YOLO inference, two anonymous *stable* slots.
                # No independent camera, tracker ID, or split-frame inference.
                # Missing players never inherit a remembered control skeleton.
                tracked = two_player.update(people, now)
                live_indices = {int(p["index"]) for p in tracked if p["active"]}
                source_preview = [
                    {**person, "preview_role": "active"}
                    for person in visible_people
                    if int(person.get("detection_index", -1)) in live_indices
                ]
                if live_preview is not None:
                    live_preview.submit(frame, source_preview, captured_at=captured_at,
                                        raw_person_count=number,
                                        foreground_person_count=len(live_indices))
                inferred_count += 1
                if now - inferred_start >= 1.0:
                    pose_fps = inferred_count / (now - inferred_start)
                    inferred_count = 0
                    inferred_start = now
                send_status(sock, target, token, state="tracking", camera=True,
                            mode="multiplayer", pose=any(p["active"] for p in tracked),
                            people=number, foreground_people=len(live_indices),
                            foreground_ambiguous=False, players=tracked,
                            fps=round(pose_fps, 1),
                            camera_fps=round(camera_reader.camera_fps, 1),
                            camera_source_timestamp=captured_at,
                            camera_frame_age_ms=round(source_frame_age * 1000),
                            camera_phase="tracking", device="CUDA" if gpu else "CPU",
                            detail="Two-player tracking; no automatic identity swap.",
                            **camera_timings)
                continue
            # Preserve truthful raw YOLO occupancy, including id-less boxes.
            # Ignore only unambiguously smaller, separated background bodies;
            # near or overlapping people always revoke foreground controls.
            selected, lock_state, reason = student.update(
                people, now, detected_count=number)
            gesture_flags = gesture_detector.update(
                selected["keypoints"] if selected is not None else None,
                now,
                track_id=0 if selected is not None else None,
            )
            calibration_bilateral = calibration_bilateral_packet_fields(
                gesture_flags, selected, lock_state, number)
            if selected is not None:
                torso_x = selected["x"]
                gesture = arms_raised(selected["keypoints"])
                valid = True
            # Camera NO LONGER registers a person ID. Old Godot fields remain
            # for diagnostics only; -1 means no per-person binding.
            locked_id = -1
            measured_plane_x = (stationary_plane_steering(selected["keypoints"])
                                if valid and lock_state == "locked" and selected is not None
                                else None)
            plane_steering = plane_tracker.update(
                0 if valid and lock_state == "locked" else None,
                measured_plane_x, now)
            plane_neutral_valid = (
                plane_steering is not None and selected is not None
                and all(len(selected["keypoints"]) > i
                        and len(selected["keypoints"][i]) >= 3
                        and float(selected["keypoints"][i][2]) >= 0.45
                        for i in (5, 6, 9, 10))
            )
            plane_t_pose_valid = False
            plane_bank_valid = False
            plane_bank = 0.0
            # A real fresh SOLO body can bank without requiring that BOTH
            # wrists stay level. No ByteTrack identifier is registered here.
            if (valid and lock_state == "locked"
                    and student.foreground_people == 1 and selected is not None):
                plane_t_pose_valid, plane_bank_valid, plane_bank = plane_arm_bank(
                    selected["keypoints"])

            inferred_count += 1
            if now - inferred_start >= 1.0:
                pose_fps = inferred_count / (now - inferred_start)
                inferred_count = 0
                inferred_start = now
            send_status(sock, target, token, state="tracking", camera=True, pose=valid,
                        people=number, foreground_people=student.foreground_people,
                        foreground_ambiguous=student.foreground_ambiguous,
                        player_lock_epoch=student.player_lock_epoch,
                        x=round(torso_x, 5), raised=gesture,
                        hand_up=gesture_flags.hand_up,
                        hand_observation_valid=gesture_flags.hand_observation_valid,
                        airplane_pose=gesture_flags.airplane_pose,
                        wing_roll=round(gesture_flags.wing_roll, 4),
                        plane_steering=round(plane_steering, 5) if plane_steering is not None else 0.0,
                        plane_steering_valid=plane_steering is not None,
                        plane_neutral_valid=plane_neutral_valid,
                        plane_t_pose_valid=plane_t_pose_valid,
                        plane_bank_valid=plane_bank_valid,
                        plane_bank=round(plane_bank, 5),
                        left_hand_up=gesture_flags.left_hand_up,
                        right_hand_up=gesture_flags.right_hand_up,
                        both_hands_up=gesture_flags.both_hands_up,
                        both_hands_down=gesture_flags.both_hands_down,
                        **calibration_bilateral,
                        lock_state=lock_state, locked_id=locked_id,
                        physical_track_id=student.physical_track_id,
                        occupancy_verified=valid and lock_state == "locked"
                                           and student.foreground_people == 1
                                           and not student.foreground_ambiguous,
                        occupancy_mode="single_foreground",
                        # Session/calibration retains one epoch regardless of
                        # ByteTrack churn or 5/15/60-second player absences.
                        tracking_epoch=student.tracking_epoch,
                        lock_reacquired=student.lock_reacquired,
                        needs_recalibration=student.needs_recalibration,
                        previous_locked_id=(student.previous_locked_id
                                            if student.previous_locked_id is not None else -1),
                        fps=round(pose_fps, 1), camera_fps=round(camera_reader.camera_fps, 1),
                        device="CUDA" if gpu else "CPU", detail=reason,
                        startup_ms=round((ready_at - boot_started) * 1000),
                        camera_phase="tracking",
                        camera_source_timestamp=captured_at,
                        camera_frame_age_ms=round(source_frame_age * 1000),
                        camera_first_preview_ms=preview_first_sent_ms,
                        **camera_timings)

            # Render only the actual selected foreground's source keypoints.
            # Background spectators must not receive distracting skeletons.
            # Ambiguous near/crossing people show raw webcam pixels alone.
            if live_preview is not None:
                live_preview.submit(frame, foreground_preview_people(
                    visible_people,
                    selected if valid and lock_state == "locked" else None,
                    student.foreground_candidate, student.foreground_people,
                    student.foreground_ambiguous),
                    captured_at=captured_at, raw_person_count=number,
                    foreground_person_count=student.foreground_people)
    finally:
        startup_preview_stop.set()
        fallback_preview_stop.set()
        if startup_preview_thread is not None and startup_preview_thread.is_alive():
            startup_preview_thread.join(timeout=0.6)
        if fallback_preview_thread is not None and fallback_preview_thread.is_alive():
            fallback_preview_thread.join(timeout=0.6)
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
                   bones_scale: tuple[float, float], players: int = 1) -> int:
    """Prepare YOLO ahead of calibration without opening a camera prematurely.

    The worker accepts precisely one authenticated, loopback-only UDP
    start_camera command, including DURING model loading. The same model
    prewarm thread is reused for gameplay; live camera preview can begin
    immediately after permission without waiting for YOLO/CUDA import.
    """
    target = ("127.0.0.1", port)
    outbound = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    control = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    heartbeat_stop = threading.Event()
    heartbeat_thread = None
    camera_started = threading.Event()
    status_lock = threading.Lock()
    model_ready = threading.Event()
    model_result: dict[str, object] = {}
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

        def status_update(state: str, detail: str, camera: bool = False,
                          camera_phase: str = "") -> None:
            with status_lock:
                # A slow import's final progress callback must never overtake
                # the camera-start ACK and revoke a live pose in Godot.
                if camera_started.is_set() and not camera:
                    return
                phase["state"] = state
                phase["detail"] = detail
                phase["camera"] = camera
                send_status(outbound, target, token, state=state, pose=False,
                            control_port=control_port, model_ready=state == "ready",
                            camera=camera, camera_phase=camera_phase, detail=detail)

        def heartbeat() -> None:
            while not heartbeat_stop.wait(0.7):
                with status_lock:
                    if camera_started.is_set():
                        return
                    send_status(outbound, target, token, state=phase["state"],
                                pose=False, control_port=control_port,
                                model_ready=phase["state"] == "ready",
                                camera=False, detail=phase["detail"])

        status_update("prewarming", "Preparing the offline YOLO26 pose model...")
        heartbeat_thread = threading.Thread(
            target=heartbeat, name="KilosPosePrewarmHeartbeat", daemon=True)
        heartbeat_thread.start()

        def prepare_in_background() -> None:
            try:
                model_result["prepared"] = prepare_pose_model(
                    model_path, lambda detail: status_update("prewarming", detail))
            except ImportError as exc:
                model_result["error"] = exc
                model_result["exit_code"] = 2
            except Exception as exc:
                model_result["error"] = exc
                model_result["exit_code"] = 4
            finally:
                model_ready.set()

        model_thread = threading.Thread(
            target=prepare_in_background, name="KilosPoseModelPrewarm", daemon=True)
        model_thread.start()
        announced_ready = False
        while True:
            if model_ready.is_set() and not announced_ready:
                if "error" in model_result:
                    exc = model_result["error"]
                    if isinstance(exc, ImportError):
                        status_update("error", f"Missing Python package: {exc}. Install requirements-pose.txt.")
                    else:
                        status_update("error", f"Cannot load pose model: {str(exc)[:200]}")
                    return int(model_result["exit_code"])
                status_update("ready", "Pose model is ready. Waiting for camera calibration...")
                announced_ready = True
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
            # Authenticate first; only now is the webcam permitted to open.
            # Camera preview must not wait for torch/CUDA initialization.
            # Godot's calibration scene may supply a NEW editor-authored
            # SkeletonPlacement after the model was prewarmed. Apply the
            # latest authenticated VISUAL transform to JPEG bones only;
            # measured YOLO joints and 3s holds keep raw source coordinates.
            try:
                raw_offset = command.get("bones_offset", bones_offset)
                raw_scale = command.get("bones_scale", bones_scale)
                if command.get("players") in (1, 2):
                    players = int(command["players"])
                if len(raw_offset) == 2 and len(raw_scale) == 2:
                    updated_offset = tuple(float(v) for v in raw_offset)
                    updated_scale = tuple(float(v) for v in raw_scale)
                    if (all(math.isfinite(v) and abs(v) <= 2.0 for v in updated_offset)
                            and all(math.isfinite(v) and 0.1 <= v <= 3.0
                                    for v in updated_scale)):
                        bones_offset = updated_offset
                        bones_scale = updated_scale
            except (TypeError, ValueError, OverflowError):
                pass
            with status_lock:
                camera_started.set()
                send_status(outbound, target, token, state="loading", pose=False,
                            camera=True, camera_phase="start_ack",
                            control_port=control_port,
                            model_ready=model_ready.is_set() and "error" not in model_result,
                            detail="Starting your webcam for calibration...")
            heartbeat_stop.set()
            if heartbeat_thread is not None:
                heartbeat_thread.join(timeout=0.8)
            break
    finally:
        heartbeat_stop.set()
        if heartbeat_thread is not None:
            heartbeat_thread.join(timeout=0.8)
        control.close()
        outbound.close()

    def wait_for_prepared_model():
        model_ready.wait()
        if "error" in model_result:
            raise model_result["error"]
        return model_result["prepared"]

    if model_ready.is_set() and "error" not in model_result:
        return run(port, token, camera_index, model_path, preview,
                   recovery=recovery, bones_offset=bones_offset,
                   bones_scale=bones_scale, prepared_model=model_result["prepared"],
                   players=players)
    return run(port, token, camera_index, model_path, preview,
               recovery=recovery, bones_offset=bones_offset,
               bones_scale=bones_scale, prepared_model_loader=wait_for_prepared_model,
               players=players)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--model", default="yolo26n-pose.pt")
    parser.add_argument("--weights-dir", default="")
    parser.add_argument("--no-preview", action="store_true")
    parser.add_argument("--players", type=int, choices=[1, 2], default=1)
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
                              arguments.recovery, components[:2], components[2:],
                              arguments.players)
    return run(arguments.port, arguments.token, arguments.camera, arguments.model,
               not arguments.no_preview, recovery=arguments.recovery,
               bones_offset=components[:2], bones_scale=components[2:],
               players=arguments.players)


if __name__ == "__main__":
    sys.exit(main())
