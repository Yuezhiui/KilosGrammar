# KilosGrammar v0.3.0-beta.4

**Move. Think. Learn English grammar.**

KilosGrammar is an interactive, movement-based English grammar learning
application for Grades 1–6. It uses local webcam pose tracking and guided
activity tutorials to help students practice nouns, pronouns, verbs,
adjectives, and adverbs through three colorful games.

## Games

- **Catch the Word:** Move left, center, or right to collect matching words.
- **Balloon Popping:** Raise your hand to launch at correct grammar balloons.
- **Human Plane:** Spread both arms, steer an airplane, and fly through
  the correct grammar-answer ring.

Each game offers Easy, Normal, and Hard difficulty, a 60-second timed mode
and a three-heart Lives mode. Correct answers earn on-screen score feedback.

## What's new

- Restored step-by-step guided explanations inside each game, with spoken
  instructions, focused highlights, and a dimmed background. Arrows remain
  hidden in this update.
- Corrected Catch the Word's tutorial overlay visibility before the
  gameplay countdown.
- Improved Human Plane physical ring-and-airplane collision detection and
  correct +100 / +0 score feedback across repeated gates.
- Rebalanced the leaderboard columns so student names, grade/section,
  game modes, and scores are easier to read.
- Improved repeat Play navigation and tutorial transitions.
- Improved foreground camera tracking so a student can play while distant,
  smaller classmates remain seated behind them. Nearby or overlapping
  players safely pause activity until tracking is clear.

## Local student progress

Completed Play scores can be saved in a local PostgreSQL database and shown
on the leaderboard. CSV import and export tools are available to teachers.
The app uses a local Python/YOLO webcam worker rather than requiring a
cloud account.

## Windows installation

Use the **complete offline ZIP** or **Setup.exe** for Windows x64. The
standalone EXE requires its matching PCK and supporting files from the same
version. Complete the bundled local Python/PostgreSQL setup before using
the full webcam-and-leaderboard workflow. Windows may warn that the
installer is from an unidentified publisher because it is not code-signed.

Source: https://github.com/Yuezhiui/KilosGrammar
