# Calibration regression checks

Run from the KilosGrammar project root with Godot 4.7.2 (or the project's
compatible Godot 4 build):

```powershell
$godot = 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script res://tools/test_calibration_fullscreen_editor_layout.gd
& $godot --headless --path . --script res://tools/test_calibration_three_second_sequence.gd
& $godot --headless --path . --script res://tools/test_calibration_mode_countdown.gd
```

The three tests create their own screen and synthetic pose state. They do
**not** launch the webcam, YOLO model or Python worker, and leave no screenshots
or other generated files. They exercise the production scenes and controllers
directly instead of cloning calibration behavior inside a test-only fake.

## Intended user experience

1. Calibration uses the exact unmodified image
   `C:\Users\Yue\Downloads\PLAY\52c44321-00e4-4f07-92ce-012696fa4ce6.png`,
   copied into the Godot project as an independent, replaceable full-screen
   background. A **pure black overlay at 70% opacity** covers the whole
   background. Inside the screen is one large black-backed live camera window
   whose `TextureRect` fills the same area when video arrives. A missing
   camera displays a readable fallback message; never substitute a static
   screenshot of a student for a real live video frame.
2. Each position (CENTER, then RIGHT, then LEFT) has its own Godot-editor
   moveable guide Control, but **exactly one glowing standing box** is visible
   at any instant, geometrically inside the camera preview. Inactive controls
   remain available in the editor but are hidden in-game. There must be no
   three-column colored card layout or three simultaneously visible guides.
   The scene uses **Gochi Hand** for the calibration title, stage heading,
   large intro and instructional text. Layout fits 875×500, 1280×720 and
   1920×1080. The navigation button reads **Back to Main**.
3. During the **2.5-second full-screen introduction**, the only visible
   calibration content above the 70%-dimmed PLAY background is the large
   **CALIBRATION** title and **BACK TO MAIN** button. The script hides every
   sibling of `IntroOverlay` in `TutorialStage`, rather than relying on a dark
   cover over still-clickable controls. An extra intro tint must not darken
   the 70% overlay further. The intro Back button can receive keyboard focus
   and directly requests the Main route; hidden camera, Skip and Reset
   buttons cannot take user input. IntroDescription and IntroCountdown remain
   hidden. No part of the intro measures a pose or credits hold time.
4. Once the intro reaches 2.5 seconds, normal stage headers, bilingual
   instructions, **one CENTER standing guide**, camera window and footer
   buttons (Back, Start/Stop Camera, Reset Player, Skip) return to their
   scene-authored visible states. Keyboard focus moves to Start Camera.
   The editor-hidden extras, legacy cursor and **Continue** remain hidden;
   Continue remains locked without three measurements. A live camera frame
   received during intro stays hidden and is restored immediately afterward;
   camera-off mode displays the honest black/video-empty fallback.
5. The player starts in **CENTER**, holds still for **3 seconds**
   using multiple fresh frames, then moves to **RIGHT** for 3 seconds and
   finally **LEFT** for 3 seconds. Stage instructions give an English and
   Filipino instruction, including "MANATILI SA GITNA", "GUMALAW SA KANAN",
   and "GUMALAW SA KALIWA". There is one active target box, progress and
   a usable Back to Main.
6. Being outside the target zone, making a sudden lateral movement, losing
   the tracked pose, or losing pose packets invalidates the current hold.
   Old held values must never finish a step. The invisible compatibility
   Continue button unlocks only after three accepted measurements, while
   successful measurement automatically advances to gameplay.
7. With no camera or live tracked student, Continue remains blocked and the
   camera-off guidance is visible. **Skip** works with keyboard input and
   marks calibration as skipped, without claiming that the user was
   measured. Both Skip and successful calibration route into the shared
   gameplay wrapper.
8. Ordinary Play runs its **3–2–1** count-in directly. Guided Tutorial shows
   the in-game Spotlight first, then the same 3–2–1. During either countdown,
   score, game time, lives, collision logic and input remain paused. Only
   after 1 does the original game instance resume. Verify **Seconds** and
   **Lives** for both flows.

## What each script guards

| Script | Regression coverage |
| --- | --- |
| `test_calibration_fullscreen_editor_layout.gd` | Exact PLAY PNG (and byte equality when source is available), 70%-black overlay, Gochi Hand labels, camera slot without fake image, all non-intro stage siblings hidden for the introduction, only CALIBRATION + Back visible, no double tint, restored footer, Continue kept hidden, three editable guides inside preview, one visible CENTER guide after intro, all three resolutions |
| `test_calibration_three_second_sequence.gd` | Intro duration, intro Back click and keyboard focus, no footer interaction during intro, focus transferred to Start Camera after intro, cached live frame hidden until intro ends then restored, stage-specific single visible guide and bilingual instructions, CENTER→RIGHT→LEFT 3-second holds, fresh packet validation, loss and motion reset, no-camera fallback and route payload |
| `test_calibration_mode_countdown.gd` | No-camera Skip → actual gameplay wrapper, Seconds/Lives across normal and guided paths, Spotlight gate, 3→2→1 labels, frozen gameplay until finish, same live game resumed |

These checks specifically test **normalized horizontal camera positions**.
The instruction to stand roughly **1–2.5 meters** away is positioning advice:
the current PoseService exposes normalized X and pose validity, not an actual
depth sensor or measured camera distance. Do not interpret these tests as
verifying physical distance or actual webcam/YOLO tracking performance.

For a final design review, also open `ui/vision/calibration.tscn` graphically
at 1920×1080 with an actual camera and verify that the real live camera picture,
the single CENTER / RIGHT / LEFT outline, Gochi Hand titles, overlays and
avatar tracking are legible from classroom
distance. Automated headless geometry checks cannot judge visual balance or
webcam image quality.
