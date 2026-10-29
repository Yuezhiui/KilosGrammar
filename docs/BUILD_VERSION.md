# KilosGrammar build and version

**Source version:** `v0.2.0-beta.1`

**Local working-tree revision date:** 2026-10-28 (Asia/Manila). Changes since the tagged beta are not yet committed or published.

**Engine:** Godot 4.7.2.stable

**Target export platform:** Windows Desktop x86-64 (not yet released)

## Highlights of this source beta

- New editable Main Menu, Settings (Audio & Display only), Credits, Leaderboard home artwork and Game Chooser screens, with hover/press feedback preserved.
- Tutorial-only practice does not register students or save scores; only completed normal Play rounds can save results through the local API.
- Catch the Word and Balloon Popping retain CENTER -> RIGHT -> LEFT body-position calibration, effects, and existing game rules.
- Human Plane now uses a single editable **pure 2D pseudo-3D** scene with the original painted background, 2D airplane and curved answer arcs. Neutral, stationary center calibration uses at least eight distinct locked-student pose packets during a 2.5-second hold; steering then follows left/center/right torso position, with safe short occlusion recovery.
- Human Plane score is +100 for an unambiguously correct answer, no deduction for incorrect/missed/ambiguous overlaps; correct gates permanently increase speed by 14% cumulatively.

## Source asset redistribution

The current local working tree removes the retired Human Plane 3D models, scene, materials and scripts. The active game uses its own original 2D PNG artwork. This does **not** change the already published `v0.2.0-beta.1` tag on GitHub, which still reflects the earlier version; a future source publication should follow a fresh rights and packaging audit.

## Build and acceptance limitations

This version is **source-code beta**, not a completed Windows installer, executable, or stable 1.0 release. Windows offline export still requires verified Godot templates and an approved bundled/local Python/YOLO/PostgreSQL deployment process. The game does not include credentials, local student records, private media or a classroom database.

Automated tests use synthetic pose/camera observations without launching a physical webcam or writing to a live student database. Real classroom one-student lock behavior, performance and a second offline Windows PC remain to be acceptance-tested. For a future release follow `release/windows/README.md`, run `release/windows/Build-WindowsRelease.ps1 -PreflightOnly` only after staging approved dependencies and templates, and do not ship incomplete builds.
