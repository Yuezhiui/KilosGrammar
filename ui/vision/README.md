# KilosGrammar — live webcam / YOLO26 calibration test

> **Current calibration behavior was updated October 28, 2026.** The numbered
> setup notes below describe an older prototype and include obsolete ByteTrack
> ID, neon-guide, 1.5-second cooldown, and torso-steered Human Plane details.
> For the actual five-PNG calibration, 3-second T-pose, 18-second Balloon six
> holds, 500 ms shoot edge, ID-free one-person occupancy and continuous arm
> banking, consult the dated override at the top of
> `docs/cloud-flight/calibration.md` and the focused five-PNG calibration QA.

This is a **local Windows prototype** using Python, Ultralytics YOLO26n-Pose
and Godot 4.7.2. Camera-play selection automatically starts the webcam;
keyboard-only Play never does. Webcam frames are not saved, and scores are
still unsaved until local PostgreSQL integration.

## How to run

1. Install Python **3.11**, OpenCV and Ultralytics:

   ```powershell
   & 'C:\Espressif\tools\python\python.exe' -m pip install -r ui\vision\requirements-pose.txt
   ```

   On this development PC the existing Espressif Python already has these
   modules. For another PC, set the environment variable
   `KILOSGRAMMAR_PYTHON` to the **full path** of the Python executable
   containing the packages. Python launcher fallback is provided.

2. Open `project.godot` in **Godot 4.7.2** and run the main scene.
3. Select **Play → Student Setup → Activity → NEXT: AUTO CALIBRATION**.
   The screen automatically starts camera 0; no **Check Camera** or
   **Capture** button is needed. The old separate **Camera Check** diagnostic
   has been deleted; Play and Guided Tutorial use Calibration directly.
4. The first run may need internet **once** to download
   `yolo26n-pose.pt` weights into Godot `user://pose_models/`.
5. Stand fully visible in the **CENTER** box. YOLO and ByteTrack will
   automatically lock the closest clear foreground student there after
   roughly 1.2 seconds of stable tracking. **Other classmates may remain
   visible** behind or beside that student, and their movements will not
   control the game. If two similar-size people overlap in the enrollment
   box, reposition the active pupil nearer to the camera.
   Follow the highlighted **CENTER → RIGHT → LEFT** position boxes. The moving
   white marker represents the mirrored camera's measured torso center.
6. **Stay still for 3 seconds** inside each zone. The timer restarts on
   tracking loss or excessive movement, and each hold requires at least
   eight fresh pose frames. Move to the next zone when the new box lights
   up. No mouse clicks are needed.
7. After all three holds, the game validates the recorded positions and
   automatically enters the 3-2-1 gameplay countdown.
8. In camera mode, the minigame uses smoothed body position for horizontal
   movement. **Balloon Popping:** raise either LEFT or RIGHT hand to fire
   one shot, with a 1.5-second reload. Hold it down briefly and raise again
   for the next shot; continuously holding a hand up never auto-fires.
   **Human Plane:** after CENTER/RIGHT/LEFT calibration, spread BOTH arms
   sideways like wings to enable body-position steering. Step left/right to
   fly smoothly across the whole path; CENTER moves the plane to the middle.
   Lower either arm to freeze, and raise both again to resume. Arm TILT and
   gyroscope-style controls are no longer used. Gesture
   classification uses the SAME locked player and survives brief tracking
   interruptions without changing the saved CENTER/RIGHT/LEFT calibration.
   Teachers can use **BACK TO MAIN** or exit gameplay to restart setup;
   there is no keyboard, STOP/RESET or SKIP calibration bypass.
   If the locked student is lost for longer than 0.8 seconds or appears
   to switch identity, the game stops accepting pose controls rather
   than silently handing control to a bystander.

If your camera is unavailable, Windows **Settings → Privacy & security →
Camera** must permit desktop apps to use it, and no other application should
hold an exclusive camera lock. The testing scripts do not require a real
person or collect student data. The YOLO test on a public photo is available:

```powershell
& 'C:\Espressif\tools\python\python.exe' -B ui\vision\test_pose_public_image.py
```

### What is and isn't implemented

**Implemented:** Auto-start for camera-selected play, asynchronous latest-frame
camera thread, YOLO on CUDA when available (CPU fallback), mirrored compressed
preview, localhost UDP, ByteTrack temporary player IDs, torso-confidence
checks, one foreground student enrollment even with classroom bystanders,
stale-frame
guard, five-second guided zone calibration, smoothed 60-Hz Godot movement
targets, hand-raise firing with cooldown, explicit camera shutdown.

**Not yet implemented:** Guaranteed 60-FPS **sensor/inference** throughput,
persistent calibration and per-player identity association, robust biometric
recognition, full classroom benchmarks, model packaging/export,
database persistence, and adaptive difficulty. The current arm gesture is
an initial both-hands-up edge detector, not a validated classroom gesture
recognizer.

The player lock is **temporary pose/box tracking, not face recognition**.
Tracker IDs can become unreliable if students overlap or cross directly
in front of the camera. A lock loss requires **RESET PLAYER** in the
calibration screen. Tracking continuity and crowded-classroom reliability
still need tests with consenting participants before classroom deployment.

The image stream is used only for a live preview. Camera frames are
never written to disk or intentionally uploaded. The **first model
download** uses Ultralytics' public model host; afterward, on-device
inference runs without an internet service. The camera is only started
automatically for an explicitly selected camera-play session, not on launch
or in keyboard-only mode.

### Frame rate: what 60 FPS means

The engine updates/interpolates the body-controlled character on every
game frame, targeting **60 render updates per second**. Real sensor and YOLO
pose updates depend on hardware. Initial development-machine measurements
with an NVIDIA RTX 3050 were approximately **29.5 FPS webcam capture and
19.5 FPS CUDA pose inference** with a 640×480 input. A webcam advertising
60 FPS may still supply only 30 FPS in its chosen mode; interpolation is
not a substitute for real additional observations. Preview JPEG updates
are separately capped around 24 FPS to avoid rendering overhead.

### Tests

```powershell
& 'C:\Espressif\tools\python\python.exe' -B -m unittest discover -s ui\vision -p test_pose_worker.py -v
& 'C:\Espressif\tools\python\python.exe' -B -m unittest discover -s ui\vision -p test_student_lock.py -v
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_pose_calibration.gd
```

Run these without enabling the actual camera. A separate human-in-the-loop
webcam test is necessary to verify your device, model, lighting, pose
confidence and motion mapping. Ultralytics model redistribution is subject
to its licensing requirements (including AGPL-3.0 for applicable weights);
review this before packaging an academic or classroom build.
