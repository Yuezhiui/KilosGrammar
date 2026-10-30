# KilosGrammar v0.3.0-beta.5

**Move. Think. Learn English grammar.**

KilosGrammar is a movement-based English grammar learning game for Grades 1–6. Children use webcam body tracking to play Catch the Word, Balloon Popping, and Human Plane while practicing nouns, pronouns, verbs, adjectives, and adverbs. Each game has guided voice tutorials, difficulty settings, timed or three-heart Lives play, and score feedback.

## What's new in beta.5

- **New students can play without importing a CSV file first.** Enter a new Student ID, name, and grade/section, then Continue to the game. Single-word names are supported, including the test case `123` / `qqqq` / `qq`.
- Returning students retain their existing identity and score history. An existing ID associated with a different name is not silently reused.
- Corrected the registration-check error that blocked some manually entered new students.
- Retains the integrated narrated tutorials, improved foreground webcam tracking, gameplay refinements, and redesigned leaderboard from beta.4.

## Windows setup

The standalone `KilosGrammar.exe` must stay beside its matching `KilosGrammar.pck` and the rest of the provided offline package. The `Setup.exe` installs the game files; follow `RELEASE-INSTRUCTIONS.md` and complete the bundled local Python/PostgreSQL setup to enable webcam tracking and persistent leaderboard results. The beta installer is not code-signed, and Windows may display a publisher warning.

This is an offline **test candidate**; complete independent clean-PC installation and redistribution-rights checks before distributing it publicly.

Source: https://github.com/Yuezhiui/KilosGrammar
