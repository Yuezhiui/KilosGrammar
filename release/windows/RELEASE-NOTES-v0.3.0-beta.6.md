# KilosGrammar v0.3.0-beta.6 — Windows testing update

**Move. Think. Learn English grammar.**

KilosGrammar is an offline-capable English grammar movement game for Grades 1–6. Webcam poses control Catch the Word, Balloon Popping, and Human Plane. The games include narrated tutorials, English grammar topics, timed and Lives modes, difficulty choices, and a PostgreSQL-backed local leaderboard.

## Fixes and improvements

- Preserves beta.5's manual new-student Play fix: a child can enter a new ID, one-word name and grade/section without importing a CSV first.
- Fixed a Windows localhost API startup race which could launch duplicate backend listeners and invalidate the teacher's CSV authorization token. Only one API can bind the same port; the private same-user authorization token stays stable between startups.
- Improved leaderboard CSV/import/delete authorization notices with readable contrast and action-specific explanations. Teacher-protected operations remain protected; the update does not silently export, import or delete records.
- Improved the supported offline Windows launcher to prepare Python/YOLO from the verified bundled dependencies where possible, without downloading anything. An existing approved PostgreSQL service can be started without changing its database.
- The Windows installer now offers offline dependency setup after copying the game files. A school administrator must still approve first-time PostgreSQL installation and configuration, and the database wizard explicitly protects creation and migration.

## How to launch

Run the installer, accept its offered **offline setup**, and open **Play KilosGrammar** from the Start menu. The game EXE requires its matching PCK and installed offline Python environment. If PostgreSQL is absent, review the bundled offline installer with a school administrator and complete the one-time database configuration. See `RELEASE-INSTRUCTIONS.md` inside the installed folder.

The installer is unsigned and may display a Windows publisher warning. This is a local test candidate, not yet validated on a separate clean offline computer for public distribution.

Source: https://github.com/Yuezhiui/KilosGrammar
