# KilosGrammar build and version

**Source version:** `v0.2.0-beta.1`

**Revision date:** 2026-10-26 (Asia/Manila)

**Engine:** Godot 4.7.2.stable

**Target export platform:** Windows Desktop x86-64 (not yet released)

## Highlights of this source beta

- New editable Main Menu, Settings (Audio & Display only), Credits, Leaderboard home artwork and Game Chooser screens, with hover/press feedback preserved.
- Tutorial-only practice does not register students or save scores; only completed normal Play rounds can save results through the local API.
- Catch the Word and Balloon Popping retain CENTER -> RIGHT -> LEFT body-position calibration, effects, and existing game rules.
- Human Plane is now a cloud-based 3D flight game with editable portrait answer portals instead of torus rings. Neutral, stationary center calibration uses multiple fresh locked-student observations; steering then follows left/center/right torso position, with one wrist temporarily occluded if the same student remains reliably tracked.
- Human Plane score is +100 for an unambiguously correct answer, no deduction for incorrect/missed/ambiguous overlaps; correct gates permanently increase speed by 14% cumulatively.

## Source asset redistribution

The public repository contains the CC BY 4.0 'stylize clouds' by ragad.sallabi and a CC BY 4.0 Toy Plane by l3clarke with their original licenses and credits. A locally supplied 3D red aircraft from 3DPolyForge/Sketchfab and legacy mountain/terrain model packs have unclear or restricted republication rights. **They are not included in the public Git source beta.** The public 3D scene therefore uses a separate Toy Plane fallback while the original supplied art remains untouched in the developer's local Godot workspace. Public users can replace the flight model with their own properly licensed 3D asset using the editor. This is not a claim of rights to redistribute the local model.

## Build and acceptance limitations

This version is **source-code beta**, not a completed Windows installer, executable, or stable 1.0 release. Windows offline export still requires verified Godot templates and an approved bundled/local Python/YOLO/PostgreSQL deployment process. The game does not include credentials, local student records, private media or a classroom database.

Automated tests use synthetic pose/camera observations without launching a physical webcam or writing to a live student database. Real classroom one-student lock behavior, performance and a second offline Windows PC remain to be acceptance-tested. For a future release follow `release/windows/README.md`, run `release/windows/Build-WindowsRelease.ps1 -PreflightOnly` only after staging approved dependencies and templates, and do not ship incomplete builds.