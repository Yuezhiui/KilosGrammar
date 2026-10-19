# KilosGrammar

**Learn English grammar through play.**

KilosGrammar is an interactive **2D educational grammar game** made with
**Godot 4 and GDScript**. It turns identifying parts of speech into short,
arcade-style activities where players move, make choices, earn points, and
learn from immediate feedback.

> **Project status:** Playable keyboard-controlled prototype. The proposed
> camera-based body tracking and local student-score database are not yet
> connected.

## About the project

Instead of relying only on written grammar exercises, KilosGrammar lets
learners practice recognizing **nouns, pronouns, verbs, adjectives, and
adverbs** in three different games. A student/game setup flow allows players
to choose a grammar topic, an activity, and a difficulty level before
starting. The game includes tutorials, a grammar guide, visual feedback,
scores, and pause/resume controls.

The longer-term goal is to make grammar practice more physically interactive
using camera-based movement input, with local recordkeeping for classroom
use. Those integrations are still in development.

## Games

| Minigame | How it works |
| --- | --- |
| **Catch the Word** | Move a character's basket to catch falling words that match the selected part of speech. Avoid incorrect words and missed targets. |
| **Balloon Popping** | Aim a launcher and shoot the balloon with a valid grammar answer. Some difficulty levels include exclusion questions, such as finding words that are **not** nouns. |
| **Human Plane** | Steer an airplane between three lanes and fly through a correct word gate. |

## Features available in the prototype

- Three playable 2D minigames with keyboard controls, scoring, timers,
  mistakes/lives, and results screens.
- Grammar practice for **Noun, Pronoun, Verb, Adjective,** and **Adverb**.
- **Easy**, **Normal**, and **Hard** difficulty choices.
- Student and game setup screens, tutorials, and a grammar reference guide.
- Main menu, animated interface, pause/resume, results, settings, credits,
  and a leaderboard **interface**.
- Configurable audio and display settings; the current settings implementation
  stores preferences locally.
- Individual editable Godot scenes, scripts, and 2D art assets.

**Important limitations:** Scores from played rounds are currently
**not saved to a student database**, so the leaderboard is not yet a live
persistent ranking. Camera check and calibration screens are **previews**;
the games currently use keyboard input, not webcam or pose tracking.
Some curriculum and mode selections are still being developed.

## Keyboard controls

| Action | Controls |
| --- | --- |
| Move left/right | **A / D** or **Left / Right Arrow** |
| Shoot in Balloon Popping | **Space** or **Enter** |
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
5. Open **Play**, complete the student/game setup, select a minigame,
   and choose the **keyboard-playable** path. The camera setup path
   remains preview-only.

The project currently targets a **1280 × 720** viewport and uses the
Godot 4 Forward+ renderer. Windows-specific rendering settings may need
adjustment on another system.

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
│   ├── vision/               # Camera/calibration preview screens
│   └── secondary/            # Settings, leaderboard, results, credits
├── assets/                   # Fonts, audio, icons, and UI assets
├── Components/               # Shared visual assets
├── WordCatcherCharacters/    # Catch the Word character art
├── WordCatcherMaps/          # Catch the Word environments
├── BalloonPoppingBackground/ # Balloon Popping backgrounds
├── BalloonPoppingBalloons/   # Balloon sprite art
├── docs/                     # Development notes and planned integrations
└── tools/                    # Test, capture, and diagnostic scripts
```

For more information about existing screens and their routes, see
[`ui/README.md`](ui/README.md).

## Development roadmap

- [x] Menu, student/game setup, and tutorial UI
- [x] Three keyboard-playable grammar minigames
- [x] Scoring, results, and gameplay pause/resume
- [ ] Live webcam capture and pose-based player movement
- [ ] Per-player movement calibration
- [ ] Local PostgreSQL student profiles and completed-score persistence
- [ ] Persistent leaderboard data and broader grammar content

The database proposal is documented in
[`docs/NEXT_PHASE_LOCAL_POSTGRESQL.md`](docs/NEXT_PHASE_LOCAL_POSTGRESQL.md).

## Technology

**Engine:** Godot 4 · **Language:** GDScript · **Graphics:** 2D Godot scenes
and assets · **Planned integrations:** camera-based pose tracking and local
PostgreSQL storage.

---

**KilosGrammar — making grammar practice more engaging, one game at a time.**
