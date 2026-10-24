# KilosGrammar UI Flow

This directory contains the Godot 4 UI screens opened as overlays by
`main_menu.gd` while the original KilosGrammar animated background, music,
falling grammar words stay active. The normal operating-system cursor is
used throughout; no custom cat-shaped pointer overlays the UI.

## Main panel

- **Tutorial** → editable Tutorial Home with exactly three buttons:
  **START GUIDED TUTORIAL**, **GRAMMAR GUIDE**, and **BACK TO MAIN**.
  The guided path starts at **Choose Game** (Catch the Word / Balloon Popping /
  Human Plane), then asks for student/grammar setup, automatically starts
  Camera & Calibration (CENTER → RIGHT → LEFT, 5-second holds), shows the
  **in-game Spotlight guide**, and only then starts the **3–2–1 countdown**
  and live round. The old standalone Movement Practice / completion panels
  and their routes have been removed.
- **Play** → Student & Game Setup (Student ID / Name / Grade & Section /
  Grammar Style / Quiz or Activity / Difficulty) → Select Activity
  → **Play Keyboard Now** → Ready → Playable 2D Game → Game Over.
- Camera-based Play normally proceeds to auto calibration, with a keyboard
  fallback when a camera is unavailable; the separate Camera Check panel
  remains for earlier compatibility/tools, not a required guided step.
- **Game Over → Retry** returns to Student & Game Setup with previous
  selections ready to edit; **Main Menu** exits the keyboard-playable round.
- **Leaderboard**, **Settings**, **Credits** → standalone subpanels with Back.
- **Quit** → exit the application.

## Editing the Guided Tutorial visually (Godot 2D Inspector)

- Open `res://ui/tutorial/tutorial_home.tscn`. The three independent native
  buttons each own their own editable image child; the title, background, cat,
  decorative images and three onboarding cards are all separate 2D scene nodes.
  Reposition a node in Godot's **2D** editor; replace any image using the
  respective `TextureRect.texture` property in the Inspector. No screenshots
  have been flattened into a single hitbox.
- Open `res://ui/play/play_activity.tscn` to edit the **Choose Game** screen,
  its native activity buttons, captions and artwork. `ready.tscn` houses the
  pre-game ready UI separately.
- Open `res://ui/tutorial/spotlight_overlay.tscn` to change the overlay,
  five step arrows, caption panel, Next/Back/Replay Voice/Skip buttons, and
  each activity's named `FocusRegions`. The actual spotlight hole dynamically
  follows the currently relevant game element at runtime; the scene-authored
  regions are the fallback targets if an element is unavailable. Runtime
  movement of the highlight does **not** override your saved editor layout.
- The owner's arrow is copied unchanged to
  `res://Components/TutorialSpotlight/right-arrow.png`. Swap this Texture2D
  directly on an Arrow `TextureRect` in the scene; do not change it in Downloads.
- `res://ui/play/guided_countdown.tscn` is the editor-authored 3–2–1 overlay.
  The actual minigame remains frozen until after the countdown; camera
  processing continues in parallel during onboarding.
- For ElevenLabs, see `res://ui/tutorial/VOICEOVER_ELEVENLABS.md`. The
  Spotlight node exports `voice_clips` (AudioStreams) and `voice_clip_paths`
  (relative `res://` paths) dictionaries keyed by step ID. All captions remain
  readable and Next/Skip work even without recording assets.
- The guide explains **only the selected round rules**: Seconds means a
  60-second timer, while Lives teaches the available three lives. Do not
  assume these independent modes are simultaneously enabled.

## Credits and Settings visual system

- **Credits** uses a centered cream scroll panel and fixed dark-purple header.
  KERNEL lists the verified contributor names without role descriptions; the
  bottom of the scroll retains required Godot and Titan One license credits,
  plus attribution for Comic Lemon by Khurasan.
- **Settings** uses one centered dark-purple card with readable cream labels,
  amber slider knobs, and functional SETTINGS / CONTROLS / CAMERA tabs.
- The Settings tab row sits **outside and below** the card so it never covers
  the Fullscreen row, including at 1280×720.
- Both titles use Comic Lemon and an animated Godot RichTextLabel wave effect
  (`[wave amp=40.0 freq=4.0 connected=1]`). Titan One remains the clear,
  stationary font for controls and contributor names.
- Their palette is based on the user's local visual reference: cream `#FDE4B9`,
  deep slate-purple `#474660`, sage `#57826C`, mint `#74AB8E`. The procedural
  `ui/shared/lexi_reference_backdrop` recreates the look with original polygons,
  not copied background artwork.
- Master, Music and Effects sliders control actual Godot `AudioServer` buses:
  `Master`, `KilosMusic`, `KilosSFX`. `main_menu.gd` creates missing menu buses
  and routes music and one-shot menu sounds to them; Mute All and Fullscreen
  controls also work immediately.
- Audio/display changes are **session-only** for now; the informational
  Controls and Camera tabs do not pretend to access a live camera.

## Play selections

- Activities: Catch the Word, Human Plane, Balloon Popping.
- MVP grammar styles: Noun, Verb, Adjective, Adverb, Pronoun.
- Mode choices: **Seconds** (60-second round) and **Lives** (three chances in
  the guided instructions; Human Plane honors 3 lives across difficulties).
- Difficulties: Easy, Normal, Hard.
- Direct Play starts with **all student/configuration fields empty**, never
  silently defaults to a student or difficulty.

## Playable 2D minigames (keyboard prototype)

The `gameplay` route now delegates to one of three actual scenes in
`ui/minigames/`. All have collision-based game rules, score, mistakes/lives,
timer and Pause/Game Over handoffs. Catch the Word and Balloon Popping now
use the project owner's image assets in editable Godot `.tscn` scenes; Human
Plane still uses original programmatically drawn 2D visuals.

- **Catch the Word:** A/D or Left/Right to glide the catching basket into the
  path of correct falling grammar word tiles; incorrect catches and missed
  matching words cost lives. A randomized Boy/Girl/Grandma/Grandpa sprite and
  randomized City/Forest/Mountain background appear per fresh run. The basket
  shows no more than three labeled caught apples; further catches still
  score without expanding the visible inventory.
- **Balloon Popping:** A/D or Left/Right to aim the launcher; SPACE/ENTER to
  fire a visible projectile that pops the correct grammar balloon on impact.
  Easy starts with matching prompts; Normal introduces occasional "NOT NOUNS"
  or "NOT VERBS" rounds, and Hard uses exclusion prompts. One or two
  balloons can be correct, so pupils practice identifying non-members too.
  Three editable balloon sprites rise from behind the rear wooden counter,
  hold their grammar labels, and descend out of view when a question ends.
  A swept-collision fallback prevents fast projectiles from skipping a balloon
  between physics samples at very low frame rates.
- **Human Plane:** Camera-only movement maps actual measured CENTER/RIGHT/LEFT
  torso positions across the entire scene-authored path. Spreading BOTH arms
  wide enables smooth left/right flight; lowering either arm freezes the plane
  until both arms open again. No gyro tilt, keyboard movement or forced
  auto-centering. Choose a correct gate when it crosses the airplane's
  collision line; crossing lateral lanes early does not score.

**Pause/Resume** keeps the actual gameplay scene suspended behind the Pause
panel. RESUME reactivates that exact scene, retaining the current falling
tiles, balloon question/projectiles, or airplane gates; ESC and the on-screen
Pause button use the same freeze logic. Restart, View Results and Main Menu
discard the suspended scene instead of letting it run in the background.

### Editing the game art manually in Godot

Open `res://ui/minigames/catch_word.tscn` in the Godot 2D editor:

- `Background` is the editable full-screen map TextureRect. The active map
  texture is randomized on a new run from `res://WordCatcherMaps/`.
- `CharacterRig/Body` and `CharacterRig/Basket` are independent Sprite2D
  layers driven by the matching images under `res://WordCatcherCharacters/`.
- `CharacterRig/CollectedWords` sits behind Basket and displays up to three
  collected word cards; `FallingWordLayer` holds active falling words.
- `HUDLayer/HUD` contains editor-adjustable labels and Pause/Finish buttons.

Open `res://ui/minigames/balloon_popping.tscn`:

- `BoothBackdrop` is the booth background; `ForegroundCounter` is the rear
  table/ledge mask that hides descending balloons, not a set of table holes.
- `BalloonLayer/LeftTarget`, `CenterTarget`, `RightTarget` are editable child
  scenes under `res://ui/minigames/balloon_art/`; their position/collision
  logic is controlled by the game script, while sprite/labels can be edited.
- `LauncherLayer/Launcher` and `ProjectileLayer` separate the projectile
  controls from scenery; independent stone and launcher child scenes can be
  opened in the editor. Separate user-supplied slingshot/stone PNGs are not
  currently present, so these remain editable simple artwork placeholders.

Avoid changing the root scripts or renaming required nodes without updating
their GDScript references. The existing scene router continues to load the
same `.tscn` paths, so the Play flow is unchanged.

Each activity exposes `set_body_x(normalized_x)` (-1.0 left through +1.0
right) for keyboard and the **existing** `PoseService` calibrated-body adapter.
The activity itself does not open a webcam: the camera starts through the
calibration service, then its tracking values reach the game wrapper. Camera
sensor/inference FPS depends on hardware; rendering at 60 FPS does not mean
60 pose-inference updates per second. The five active grammar topics
use the shared `ui/minigames/grammar_bank.gd`, tested separately for valid,
unambiguous one- and two-answer sets.

**Quick manual test:** Press F5 → Play → complete the teacher setup form →
choose a game → **Play Keyboard Now** → Start Countdown. To test the full
proposed route instead, select **Next: Camera Check**. All played scores are
currently local to the session and appear on Game Over as NOT SAVED.

The three physical lanes (LEFT, CENTER, RIGHT) are logical states shared by all
players. The vision integration must calibrate real-world boundaries separately
for every new player and verify saved calibration for a continuing player.

## Screen interface

Each screen has a `Control` scene root and emits:

```gdscript
signal requested(target: String, payload: Dictionary)
```

The host merges `payload` into its session context and opens the named route.
Screens may implement `set_context(context: Dictionary)` to display active
activity, topic, difficulty, and any session-specific results.

## Feature status and honesty

The three minigames are playable and their scores reflect actual collision/
answer handling, but remain **UNSAVED**. `PoseService` already contains camera,
YOLO pose processing and a guided calibration path, with a keyboard fallback
when tracking is unavailable. Crowded-classroom identity-lock robustness,
integrated-GPU acceleration, production curriculum/adaptive content and
**local PostgreSQL** score persistence remain separate development milestones.
There is no cloud score sync planned. Headless test passes do not substitute
for testing with the intended classroom camera and real pupils.

The future PostgreSQL score identity will be `(student_id, game_style,
game_mode, difficulty)`, with the **latest completed score replacing** the
previous score for that exact combination. Aborted or interrupted attempts
must not overwrite a completed score. Do not place database passwords in
GDScript or Git-tracked settings.

Render target: Godot 60 FPS, with asynchronous pose inference (initial target
20–30+ updates/second) once computer vision is implemented.

## Validate screens

Open the existing `project.godot` in Godot 4.7.2, then press Play. The Main Panel
opens the new screens without changing the main scene in project settings.

There is also a checked-in smoke test that loads every UI scene and walks
through the main Play/Tutorial routes:

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\Yue\Documents\GODOT\kilos-grammar' --script 'res://tools/test_ui_screens.gd'
```

For layout-boundary checks across 1280×720, 1600×900 and 1920×1080, run
`--script res://tools/test_ui_layout.gd` with the same Godot executable.

Grammar correctness checks: `--script res://tools/test_grammar_bank.gd`.
Standalone minigame integration checks: `--script res://tools/test_minigames.gd`.
Gameplay regression checks: `--script res://tools/test_gameplay_edge_cases.gd`
(paused balloon projectiles, late collisions, low-FPS swept needle impact,
delayed balloon questions after Resume, Human Plane hitbox alignment,
correct gate scoring, last-life basket behavior and all five exclusion topics).
Live Pause/Resume routing and transient-state preservation checks:
`--script res://tools/test_pause_resume.gd` (same instances, no timer or
projectile drift while paused, correct teardown on Results/Main Menu).
