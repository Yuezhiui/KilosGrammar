# KilosGrammar

**Learn English grammar through movement, play, and instant feedback.**

KilosGrammar is a classroom-focused **2D English grammar learning game** built
with **Godot 4.7.2 and GDScript**. It combines three arcade-style minigames,
optional webcam/pose-controlled movement, guided body-position calibration,
and **local PostgreSQL student records and completed-score leaderboards**.

> **Project status:** Active beta source development (`0.1.0-beta.1`). Godot
> gameplay, local PostgreSQL persistence, and a camera/YOLO pose bridge are
> implemented. Camera play requires a separately installed local Python/pose
> model runtime and a compatible webcam; automated tests do not replace
> physical classroom validation. A packaged Windows installer is not yet
> provided by this repository.

## About the project

Students practice **Noun, Pronoun, Verb, Adjective,** and **Adverb** through
guided activities. They choose a minigame, **Easy / Normal / Hard** difficulty,
and **Seconds / Lives** play. Teachers can use the local student-ID workflow,
review scores, and manage CSV exports/imports with confirmation and
authorization safeguards.

## Games

| Minigame | How it works |
| --- | --- |
| **Catch the Word** | Move the selected character's basket to collect matching words; four independent, editor-adjustable character rigs and collected-word layers. |
| **Balloon Popping** | Identify and pop the correct grammar answers with the game's interactive launcher and voice feedback. |
| **Human Plane** | Fly through the correct word gate by shifting calibrated body position, with **both arms wide** required to steer; lowered arms or lost tracking freeze movement. |

## Features

- Three 2D minigames with difficulty settings, scores, **60-second Seconds
  rounds**, Lives mode, pause/resume, results, and tutorials.
- Grammar practice for **Noun, Pronoun, Verb, Adjective,** and **Adverb**.
- Optional local webcam/YOLO pose worker with student lock, camera preview,
  and **CENTER -> RIGHT -> LEFT** calibration guidance.
- Native Godot, scene-editable UI artwork, responsive leaderboard controls,
  shared button hover/press feedback, and Main Menu/Settings sound effects.
- Local PostgreSQL-backed student lookup, registration, completed-round scores,
  activity-aware leaderboard, and **CSV import/export/delete** with teacher
  authorization and safeguards for destructive actions.
- Automatic **localhost API launch/reconnect** when an existing Windows
  PostgreSQL installation, saved credentials, and the correct database schema
  are available.
- Automated Godot scene, pose/calibration, database security, and UI tests.

**Important limitations:** This is **source code, not an offline Windows EXE
installer**. The database and camera worker require their own locally
installed dependencies. Local student records are not included in the repo.
Camera FPS, pose tracking quality, and Windows distribution should be tested
on the target classroom machine; no live webcam/second-PC acceptance claim is
made here.

## Interaction

| Action | Controls |
| --- | --- |
| Classroom camera movement | Calibrated body position and game-specific pose/gesture |
| Keyboard in supported test/alternate modes | **A / D**, arrow keys, or other on-screen guidance depending on minigame |
| Balloon Popping | Launcher gesture/interaction according to selected mode |
| Pause / resume navigation | **Esc** or the on-screen pause control |
| Navigate menus | Mouse and on-screen buttons |

Controls and behavior can vary slightly across screens.

## Getting started

1. Install a compatible **Godot 4** editor (this project is currently
   configured for **Godot 4.7** and has been developed with **4.7.2**).
2. Clone the repository:

   ```bash
   git clone https://github.com/Yuezhiui/KilosGrammar.git
   ```

3. Open Godot and select **Import**, then choose the cloned
   `project.godot` file.
4. Let Godot import the project assets, then press **F5** to run it.
5. Open **Play**, complete student/game setup, choose an activity, and follow
   the on-screen instructions. Camera play requires a working local pose
   runtime and completing calibration.

The game authors its UI against a **1280 x 720** base viewport and supports
responsive 16:9 layouts. Windows rendering and pose dependencies may need
adjustment on another system.

### Local PostgreSQL setup (Windows)

PostgreSQL is a separate Windows service; an `.exe` export is **not** required
to use it while running inside the Godot editor. Configure credentials through
the game's **SET UP LOCAL DATABASE** window and follow
[`database/README.md`](database/README.md). Once configured, the game can start
and reconnect its **127.0.0.1-only HTTP API** automatically on launch.

**Existing databases:** An older `001_initial.sql` score schema cannot be used
until the optional `002_add_minigame.sql` migration has been applied. The
teacher-controlled upgrade script **backs up and verifies the existing
database before asking for explicit migration confirmation**, preserving all
existing student/score rows and labeling unidentified older minigame scores
as `Legacy`. Backups and database credentials are stored privately on the
local Windows account and **must never be uploaded to GitHub**.

Use `database/upgrade_existing_scores.ps1 -CheckOnly` to inspect first. See
[`database/README.md`](database/README.md) for the complete safe workflow.

An optional user-provided menu soundtrack is deliberately excluded
from version control. The app is designed to handle that file being
absent.

## Project layout

```text
kilos-grammar/
├── project.godot              # Godot project settings
├── main_menu.tscn             # Main entry scene
├── main_menu.gd               # Menu, effects, and UI routing
├── ui/
│   ├── minigames/            # Catch the Word, Balloon Popping, Human Plane
│   ├── play/                 # Activity selection, ready, pause, gameplay
│   ├── student/              # Student and game setup
│   ├── tutorial/             # Tutorials and grammar guide
│   ├── vision/               # Camera/YOLO pose bridge and calibration
│   ├── shared/               # Global button hover effects and audio wiring
│   └── secondary/            # Settings, leaderboard, results, credits
├── assets/                   # Fonts, audio, icons, and UI assets
├── database/                 # Local HTTP API, PostgreSQL schema and QA tests
├── Components/               # Shared visual assets
├── Components/Gameplay/Catch the Word/Characters/    # Catch the Word character art
├── Components/Gameplay/Catch the Word/Maps/          # Catch the Word environments
├── Components/Gameplay/Balloon Popping/Background/ # Balloon Popping backgrounds
├── Components/Gameplay/Balloon Popping/Balloons/   # Balloon sprite art
├── docs/                     # Development notes and planned integrations
└── tools/                    # Test, capture, and diagnostic scripts
```

For more information about existing screens and their routes, see
[`ui/README.md`](ui/README.md).

## Development roadmap

- [x] Menu, student/game setup, and tutorial UI
- [x] Three grammar minigames with Seconds/Lives scoring
- [x] Scoring, results, and gameplay pause/resume
- [x] Local webcam/YOLO pose bridge and body-position steering integration
- [x] Center/Right/Left calibrated player guidance
- [x] Local PostgreSQL profiles, completed-score schema and API reconnect
- [x] Editable leaderboard with activity-aware records and CSV actions
- [ ] On-site webcam performance and school/classroom acceptance testing
- [ ] Reproducible offline Windows installer with bundled pose/runtime tools

The current database setup is documented in
[`database/README.md`](database/README.md).

## Technology

**Engine:** Godot 4.7.2 · **Game:** GDScript / 2D editable scenes · **Pose
worker:** local Python + YOLO · **Database:** PostgreSQL, Python HTTP bridge,
localhost-only API · **Target:** classroom use with Windows local setup.

---

**KilosGrammar — making grammar practice more engaging, one game at a time.**
