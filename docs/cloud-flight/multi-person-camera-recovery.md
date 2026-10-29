# Multi-person YOLO preview and exclusive player control

The live camera may detect several real people. Every **currently inferred**
COCO body skeleton can appear in the preview. The **single StudentLock-selected
student** is drawn in bright green/yellow; all other genuine candidates are
drawn with thinner muted tan strokes. Skeletons appear only when a real YOLO
joint has sufficient confidence, and are never propagated to future video
frames or generated from stale coordinates. The native UI layout remains
unchanged; this is solely the Python pose preview.

The worker maintains two separate collections from each real YOLO frame:

- **Preview people:** all reported tracked bodies and visible valid body joints,
  even if the torso center is hidden. These people can have passive skeletons,
  but are never eligible for gameplay simply by appearing in the video.
- **StudentLock candidates:** detections with actually measured torso positions.
  A bounding box whose body center is unreliable is tagged `eligible=False`.
  Its observed box center/height can warn the lock of crowd occlusion without
  being misused as a pose-controlled body position.

StudentLock enrolls one centered/dominant student after its established
fresh confidence hold. While their **same real track ID** remains continuous
and uncontested, background people can pass without taking over. A short
uncontested occlusion freezes control, then permits continuous-ID resume.
Overlapping bodies of similar size, duplicate IDs, abrupt movement/size jumps,
or different tracks make the lock conservative: it stops gameplay immediately
and requires a clear camera view followed by a new solo hold. Passive skeletons
remain visible during these states. ByteTrack IDs are temporary track IDs,
not biometric identities; the program does not recognize faces.

## Why skeletons could disappear or freeze

Previously the preview received only the gameplay-selected student. If the
lock became ambiguous, all bones vanished although other real people were
detected. Worse, one OpenCV JPEG or UDP sender exception returned from the
only preview thread permanently. The worker now draws all real skeletons with
active/passive colors and retries JPEG encoding after recoverable errors.

If inference itself pauses while the webcam still delivers new frames, the
latest-frame fallback paints **only a fresh raw camera image, with zero old
skeleton joints**. The normal detector regains the preview as soon as new
inference finishes. This fallback cannot deliver gesture/gameplay control,
calibrate from synthetic packets or select a bystander.

## Freshness, startup and safe recovery

The worker rejects inference whose captured source frame is older than
**650 ms**. The Godot service independently rejects pose packets with
`camera_frame_age_ms > 650`. Packets retain the authenticated session token
and strictly increasing monotonic source timestamps; duplicates never earn
calibration holds. Lost student poses freeze input and preserve game position.

Tutorial and Play reuse the same PoseService prewarmed YOLO/CUDA worker.
Prewarm does not open the webcam. The permitted calibration route separately
sends an authenticated local `start_camera` command. A ready model can safely
wait for user permission; unready model warmup has a 60-second watchdog.
Native webcam open with no live frames has a 30-second watchdog and a
controlled single-worker restart. Previously tracked feeds with no worker
packets for 5.5 seconds, or streaming processes without any messages for
20 seconds, invoke the same bounded restart. Camera reopen waits for the
old worker process to release the device, with a hard 4.5-second deadline.
At most two automatic restarts are allowed.

After a full worker restart, prior ByteTrack IDs are untrustworthy. The
new worker therefore requires a clear view and a fresh solo enrollment.
No facial/biometric identity is inferred. If two students swap IDs while
crossing, the game cannot securely recover their original identities
without a new solo hold.

## Calibration compatibility

No calibration .tscn or design files were edited. Human Plane still requires
exactly one neutral wrist/shoulder pose, held for **2.5 seconds** with
**eight distinct valid source detections**. The public APIs
`has_stationary_plane_pose()`, `normalized_plane_steering()` and
`plane_calibration` are retained. Catch Word and Balloon Popping still
require all three physical CENTER/RIGHT/LEFT holds.

## Offline verification

```powershell
py -3.11 -m unittest ui.vision.test_pose_multi_person_resilience
py -3.11 -m unittest discover -s ui/vision -p 'test_student_lock.py'
py -3.11 -m unittest discover -s ui/vision -p 'test_pose_recovery.py'
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_pose_multi_person_bridge.gd
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_human_plane_stationary_calibration.gd
```

All added tests use synthetic packets, skeleton landmarks and mock preview
encoders. They open **no physical webcam** and run no YOLO/DB workload.
Driver-specific reopening and crowded classroom detection still require
a supervised test with the actual school hardware.
