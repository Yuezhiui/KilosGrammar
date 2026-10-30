# KilosGrammar

**Move. Think. Learn English grammar.**

KilosGrammar is a **movement-based, 2D English grammar learning game** developed in **Godot 4.7.2** for elementary learners (Grades 1–6). Three arcade-style activities combine word recognition, immediate game feedback, and optional webcam-based body movement. The project is a capstone-stage application, not a published study of learning outcomes.

> **Status — source beta `v0.3.0-beta.2` (in preparation).** The repository contains playable game scenes, a local Python/YOLO pose bridge, and a PostgreSQL-backed student/score workflow. A locally integrity-verified offline Windows ZIP and installer candidate exist, but **they are not yet approved as school-ready or uploaded to GitHub Releases**. Export integrity and physical classroom acceptance are separate release gates. See [Deployment and release acceptance](docs/DEPLOYMENT.md).

## Play the three grammar games

| Game | Grammar challenge | Movement-based interaction |
| --- | --- | --- |
| **Catch the Word** | Catch words matching the selected grammar category. | Move your body **left / center / right** to guide the character and its basket. |
| **Balloon Popping** | Identify matching or excluded words, depending on difficulty. | Aim by calibrated body position; raise a hand to launch a projectile at the correct balloon. |
| **Human Plane** | Guide an airplane through the appropriate grammar-answer gates. | Spread **both arms** to enable left / center / right torso steering; lower an arm to pause steering. |

Practice topics: **nouns, pronouns, verbs, adjectives, and adverbs**. Each game offers **Easy, Normal, Hard**, **Seconds** (a 60-second session), and **Lives** (three hearts), plus tutorials, pause/resume, scores, and results. Scores are based on the game's actual answer and collision rules, not on visual-only demonstrations.

## How the system works

**Student & game setup → camera calibration → 3–2–1 countdown → active game → results → local leaderboard**

- **Single-student pose control.** A locally run **Python/YOLO pose worker** and student-lock logic are designed to select one learner rather than treat every person in view as the player. Camera play requires a working webcam, model file, local Python dependencies, and fresh **measured calibration**. Catch the Word and Balloon Popping guide **CENTER → RIGHT → LEFT**; Human Plane uses a neutral center calibration and verifies arm posture during steering. Live webcam reliability and crowd behavior still require validation on actual target hardware.
- **Verified local student identity.** A student ID is checked against the locally registered **name and grade/section** when the database is connected. A reused ID with conflicting details must be resolved rather than silently attributed to a different learner. This is **record-consistency validation**, not biometric identification or formal proof of identity.
- **Completed-score leaderboard.** Normal **completed Play rounds** are eligible to update a PostgreSQL-backed leaderboard, organized by student, minigame, grammar topic, mode, and difficulty. Tutorials and incomplete/aborted rounds must not be reported as completed. Actual persistence depends on a healthy local database/API; successful synthetic tests do not prove a particular school's database is configured.
- **CSV tools.** The leaderboard supports CSV import/export (including activity-aware data) and a teacher-controlled delete action with confirmation. Import compatibility includes an older seven-column format; exports and imports should be treated as student records and handled privately.
- **Designed for local operation.** The game, camera worker, and database API are intended to run on the same computer. The API listens on `127.0.0.1:18765`; PostgreSQL normally listens locally on port `5432`. No online student account or cloud synchronization is required for the documented local workflow.

### Student data and privacy

Student IDs, names, grade/sections, and completed scores belong in the **school-controlled local PostgreSQL database**, not in the public repository. The local setup stores the **application database credential** in the current Windows user's DPAPI-protected profile, outside the project. Camera inference is designed to be processed locally, but **loopback binding is not authentication against other software on the same computer**. Teachers should obtain appropriate consent, restrict account/device access, protect backups and CSV files, and follow their school’s student-data handling policy. Do not commit student records, screenshots of children, credentials, models with unclear redistribution rights, or private backups.

## Run the project from source

**Requirements:** Godot **4.7.2 stable**; Windows is the main deployment target. The editor can open the game scenes without a finished installer. **Live camera play and persistent records require additional local setup.**

1. Clone [this repository](https://github.com/Yuezhiui/KilosGrammar), or obtain an approved source archive.
2. Open **Godot 4.7.2** → **Import** → select `project.godot` → allow resources to import → **F5**.
3. Use **Play** to complete the student and game selections. For live movement controls, configure the local webcam/YOLO runtime and complete the on-screen calibration before starting.
4. To enable student lookup and completed-score persistence, install and configure **local PostgreSQL** and the Python HTTP service using [database/README.md](database/README.md). The game can invoke the one-time local setup wizard; an unconfigured database is **not** silently initialized.

The UI is authored against a **1280 × 720** base with responsive 16:9 layouts. Camera frame rate, model-inference rate, and compatibility vary by PC and are **not** guaranteed by editor or headless test results.

### Database setup, migration, and local checks

From a **Windows PowerShell** terminal in the repository root, the supported setup entrypoints include:

    .\database\setup_local.ps1
    .\database\configure_local.ps1
    .\database\start_auto.ps1
    Invoke-RestMethod http://127.0.0.1:18765/health

These commands require a suitable local Python installation, a running PostgreSQL instance, and school-approved credentials. **Do not run database initialization against an existing school database without reviewing backups and the current schema.** The wizard offers explicit `CREATE`/`MIGRATE` confirmations as appropriate; `start_auto.ps1` is intended for a database **already configured** on that Windows account.

If existing scores use the older schema, inspect first without changing data:

    .\tools\diagnose_database_readonly.ps1
    .\database\upgrade_existing_scores.ps1 -CheckOnly

Follow the documented backup-and-confirm migration procedure for `database/migrations/002_add_minigame.sql` only if preflight identifies the legacy schema. Full instructions, API contracts, and troubleshooting: **[database/README.md](database/README.md)**.

## Offline Windows deployment: preparation, not a released installer

The repository includes **release-building and school-PC setup scripts**, but those scripts alone are **not** an installable distribution. A reproducible package still needs the **matching Godot 4.7.2 Windows x64 export templates**, legally redistributable YOLO checkpoint, **CPython 3.11 x64**, **PostgreSQL 18 x64**, a complete compatible offline wheelhouse, and reviewed third-party licenses. A successful export must include the actual EXE/PCK and verified SHA-256 manifests; a manifest is not proof of digital signing.

Start with **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** and the full **[release/windows/README.md](release/windows/README.md)**. Only after the package passes preflight, integrity validation, and offline target-PC acceptance should its **`Setup Offline.cmd`** and **`Play KilosGrammar.cmd`** be offered to a teacher. Do not present a source checkout or partial build folder as a finished installer.

## Capstone defense / release acceptance

The release candidate must demonstrate the **same functional flow** on a real target PC, not just passing automated fixtures:

- [ ] Version, source revision, Windows export metadata, authorship/asset licenses, and redistribution permissions are reviewed.
- [ ] A real EXE/PCK, complete offline prerequisites, and both verified release manifests exist and pass package integrity tests.
- [ ] Offline setup and launch succeed on a **second Windows x64 school PC with the Internet disconnected**, including after reboot.
- [ ] Webcam permission, local YOLO model loading, **single-student selection**, calibration, and all three movement games are verified with a person on that PC.
- [ ] Student-ID conflicts are handled safely; **only completed Play scores** persist in the correct minigame/topic/mode/difficulty leaderboard after restart.
- [ ] CSV import/export and guarded deletion work with authorized, disposable test data; real student data is never used for destructive tests.
- [ ] Performance, readability, accessibility, privacy safeguards, backups, and error recovery are reviewed with the intended school users.

**Unverified claims:** An offline installer is **not yet verified/published**; there is no universal Windows compatibility guarantee, certified real-world accuracy/FPS figure, second-PC acceptance signoff, or validated educational impact claim.

## Repository guide

| Path | Purpose |
| --- | --- |
| [`project.godot`](project.godot) · [`ui/main_menu/main_menu.tscn`](ui/main_menu/main_menu.tscn) | Godot project and entry scene |
| [`ui/minigames/`](ui/minigames/) | Three playable activities and shared grammar logic |
| [`ui/vision/`](ui/vision/) | Local pose worker, student lock, and calibration integration |
| [`ui/student/`](ui/student/) · [`ui/secondary/`](ui/secondary/) | Student setup, leaderboard, and results screens |
| [`database/`](database/) · [`database/README.md`](database/README.md) | PostgreSQL schema, loopback API, registration and migrations |
| [`release/windows/`](release/windows/) · [deployment guide](docs/DEPLOYMENT.md) | Staging, preflight, offline build, verification, school-PC acceptance |
| [`tools/`](tools/) · [`ui/README.md`](ui/README.md) | QA scripts and additional development/scene notes |
| [`docs/human-plane-2d/`](docs/human-plane-2d/) · [build notes](docs/BUILD_VERSION.md) | Design details and historical local build notes |

A local user-provided menu music file is intentionally excluded from version control; the game is designed to handle its absence.

**Suggested GitHub About description:** `Movement-based English grammar exergame for Grades 1–6 | Godot, YOLO pose controls, and local score tracking.`

**KilosGrammar — learn grammar through movement, practice, and play.**
