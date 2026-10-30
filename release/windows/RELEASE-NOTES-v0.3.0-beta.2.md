# KilosGrammar v0.3.0-beta.2 — Windows offline deployment candidate

**Pre-release / testing build. Not yet independently validated on a clean
classroom laptop.**

## Updates

- Play now explains student-ID verification instead of appearing to do
  nothing when Continue becomes gray. Legitimate ID/name conflicts remain
  blocked to protect existing student records. Changing student details
  safely permits retry, and stale delayed lookups do not start a different
  game configuration.
- Play and Tutorial use the same guided camera calibration scene. Normal
  completed Play rounds retain database score persistence; Tutorial and
  unfinished rounds cannot create completed-score records.
- Human Plane has a uniform circular 3D torus, looping forward-flight
  presentation and Catch-the-Word-aligned score plaque and direct ScoreNumber
  (no retired ScoreBottomContainer). Floating +100 / +0 scoring feedback
  accompanies correct, wrong and missed gates.
- Balloon Popping shows Catch-style floating +100 / +0 feedback for correct
  hits, wrong hits, missed stones and missed questions, while preserving
  its established speed, hand shooting and hearts/timer rules.

## Installation

Windows x64. Use the complete ZIP or Setup.exe distribution for the same
version. The EXE requires its matching PCK and additional offline support
files; the EXE alone is **not** a complete school installation.

The installer copies the entire verified package to a writable user folder,
not Program Files. A teacher/administrator must review and run the included
signed offline Python 3.11 and PostgreSQL 18 installers if those products
are not already installed, and configure a dedicated local database safely.
Then run **Setup Offline.cmd**, followed by **Play KilosGrammar.cmd**.

See RELEASE-INSTRUCTIONS.md inside the ZIP or installation folder. Do not
transfer student score databases or DPAPI credential files between computers.

## Remaining release acceptance

- Complete redistribution-rights review for Ultralytics/code/model,
  fonts, game artwork, narration, audio and all third-party notices.
- Confirm all game modes, single-student YOLO webcam calibration, persistent
  profiles/scores, and full CSV export/re-import on a **second clean Windows
  laptop with Internet disconnected**, including restart/reboot.
- The installer is unsigned and may show a Windows unidentified-publisher
  warning. No code-signing certificate is implied.

The tagged source, ZIP, Windows installer, EXE, PCK and SHA-256 sidecars
must all come from the exact same verified v0.3.0-beta.2 commit. Never
rename an older beta.1 binary to beta.2.
