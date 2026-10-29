# KILOS GRAMMAR adversarial gameplay QA — October 28, 2026

Read-only findings plus two new runnable QA tools. No production files, existing
tests, webcam/YOLO process, live database, assets, commits, or Git history were
modified by this worker. Workspace contains many legitimate concurrent edits.

## Reproduction

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_kilos_gameplay_bruteforce_20261028.gd
python tools/test_kilos_asset_refs_20261028.py --hash
```

The GDScript suite uses **seed 20261028**, checks all **29 PackedScenes**, and
constructs **290 scene instances** across 1280×720, 1600×900, and 1920×1080.
It live-mounts **27** subtrees, including **9 calibration intro reentries** and
**18 minigame rounds** across all three activities, two modes, and three
difficulties. Gameplay uses the actual scene `_process()` and available
`_physics_process()` with synthetic delta increments through up to 65 seconds
of game logic. Checks include score ≥0, three-heart maximum, one Results event,
pause freeze, immediate restart/unmount, geometry, 3-second intro time,
repeated mount/free, and absence of test-owned orphan nodes.

Pose packet checks call the actual PoseService validators with raw person counts
0, 1, 2, 4, invalid/nonintegral/unknown people, and capture ages around the
650 ms source freshness limit. Zero and multiple person observations cannot
become a valid pose. The suite never starts a camera, opens UDP sockets,
launches YOLO, or claims it has tested authenticated UDP over the wire.

The audio section runs **12 repeated** GO, duck-on-voice, Pause, Resume, Results
and cleanup sequences with `KilosGameAudio`; it verifies exactly one manager
and one playback node survive rapid navigation. In headless Godot the native
`AudioStreamPlayer.stream_paused` playback property is not observable reliably
with no audio device, so these assertions cover the music manager state and
bus/stream configuration. They do **not** verify acoustic playback, actual
speaker output, clipping, or real-time mixing on a classroom PC.

### Results: original run and October 28 follow-up

| Suite | Outcome |
| --- | --- |
| `test_kilos_gameplay_bruteforce_20261028.gd` | **PASS 1050/1050**; 29 scenes, 290 instances, 27 live mounts, 18 accelerated rounds |
| `test_kilos_asset_refs_20261028.py --hash` | **PASS**; zero broken serialized scene `ext_resource` paths |
| Existing `test_calibration_five_pose_png_sequences.gd` (unchanged) | **PASS 193/193** |
| Existing `test_pose_raw_solo_occupancy_gate.gd` (unchanged) | **PASS 102/102** |
| Existing `test_calibration_three_second_sequence.gd` (rerun after worker16 fixes) | **PASS 647/647** |
| Existing `test_calibration_minimal_ui.gd` (rerun after worker16 fixes) | **PASS 132/132** |
| Existing `test_calibration_human_plane_center_only.gd` (rerun after worker16 fixes) | **PASS 78/78** |
| Existing `test_retry_cached_skeleton_intro_qa.gd` (rerun after worker16 fixes) | **PASS 122/122** |
| Existing `test_catch_alpha_framing.gd` (rerun after worker14 correction) | **PASS 955/955**, 45 animal/map/resolution combinations |
| Existing `test_catch_png_assets.gd` (animal migration run) | **PASS 1271/1271** |
| Existing `test_catch_character_editor_rig.gd` (animal migration run) | **PASS 1786/1786** |

Early RED test runs also caught transient compile errors during the concurrent
audio/calibration migration: `main_menu.gd` undeclared `characters`, calibration
indentation at line 552, unresolved `KilosGameAudio` in
`kids_voice_feedback.gd` and later `gameplay.gd`. These errors were reported to
the prime agent. The last full new-harness run had **no Godot parse/runtime
errors**. The test explicitly checks that any `.tscn` with a sibling root `.gd`
retains a compilable root script, so silently instantiated bare Controls are
now a failure.

**Historical RED, resolved:** Before worker16 updated the calibration tests,
`test_calibration_three_second_sequence.gd` had **25/547 failures**. Of these,
23 expected the removed `IntroOverlay/IntroBackButton` and two expected an
immediate `requested("gameplay")` without the new success-overlay phase. On
October 28 this worker independently reran the repaired suite: **PASS 647/647**,
alongside minimal UI **132/132**, Human Plane calibration **78/78**, and cached
skeleton Retry **122/122**. The historical failures are no longer current.

### Catch five-animal regression triage (October 28, headless)

**Prime's final follow-up after this worker's historical triage:** All **27/27**
`tools/test_catch_*.gd` suites now have successful independent headless runs,
with **zero remaining known assertions or parse/runtime errors**. In the final
whole-suite sweep, **26/27** passed; the one failure was the newly authored
animal-migration check detecting a real **one-pixel Dog Basket Inspector
adjustment**. The authored Sprite2D offset was preserved, while the alignment
check was refined to allow a 1.5-pixel source-canvas tolerance; its focused
rerun passed **526/526**, completing the 27-suite matrix. Before that final
sweep, the open graphical Godot editor rewrote five character roots to `Y=820`
and briefly reintroduced verified clipping. Prime reapplied editor-authored
`Y=620` (Bear/Cat/Dog/Panda) and `Y=621` (Lion), preserving the latest
individual Body/Basket adjustments. All seven formerly clipping-dependent
test suites then passed after the correction, and the scene file's modification
time remained stable during rerun. **Reload the scene in the open Godot editor
before saving an older in-memory version.**

`test_catch_audio_feedback.gd` was also migrated: it no longer mounts
MainMenu or starts the real DB client, but still tests the imported menu music
resource and the 39 user-supplied voice recordings through Catch instances.
It passes **236/236** without camera or database access. The seven historical
red fixtures below have since been fixed and are **not current blockers**;
their archived failures explain why the adversarial suite was valuable.

The prime migrated quoted Catch selections in 31 test/capture scripts to the
five live animal rigs: **Bear, Cat, Dog, Lion, Panda**. Of the 27 files matching
`tools/test_catch_*.gd`, **26 were executed**: initially **17 exit 0, 9 exit 1**.
Because the Catch workspace was being fixed concurrently, a targeted second
pass of seven previously failing suites subsequently moved two of them to
PASS. The **latest individually observed results are 19 passing and 7 failing**
among the 26 executed suites; the two long-count suites were not rerun after
that second pass, but their stale count conditions are directly verified in
source. The remaining `test_catch_audio_feedback.gd` was intentionally excluded because it
mounts the real `main_menu.tscn` and triggers `_start_database_client()` in
`main_menu.gd:206`; this QA pass must not touch a live database. The seven
remaining nonzero exits reflect test expectations inconsistent with recent migrations,
and do not individually demonstrate a current gameplay defect:

| Nonzero suite | Observed outcome and specific obsolete assumption |
| --- | --- |
| `test_catch_duplicate_labels.gd` | **1 failure / 1233 checks, 20 scenarios**: `(1280, 720): scene teardown has no remaining root children` (test line 161). A shared `KilosGameAudio` node is now owned by the SceneTree root. |
| `test_catch_hud_ui.gd` | **1 failure / 3309 checks**: `(1280, 720): disposing Catch scene removes its HUD, hearts and score nodes` (line 241); same absolute root-child-count assumption. |
| `test_catch_objective_fit.gd` | **1 asserted failure / 1140 checks, 60 scenarios** in latest rerun, plus repeated test-script type errors at **line 187**: `var streams: Dictionary = game.get("catch_voice_streams")` receives Nil because shared KidsVoice replaced the nine per-Catch MP3s. Its source-text assertion (line 204–208) demands obsolete `CATCH_VOICE_DIR`. The first run also had a root teardown assertion, which passed on the subsequent rerun. |
| `test_catch_revert_hud.gd` | **2 failures / 10 checks, 0 scenarios**: `required HUD/character nodes missing` at both `(1280, 720)` and `(875, 500)`; lines 98–99 demand deleted `Boy/Body` and `Boy/Basket`. |
| `test_catch_restored_positions.gd` | **3 failures**: old `Boy` body offset `(0.136,-209.87)`, old basket `(0.136,-149.89)`, and a fixed 60-pixel Lion body/basket Y gap. This suite now selects `Bear` but still checks old Boy offsets even though the authentic animal PNG crop and bottom boundary were corrected. |
| `test_catch_spawn_hud_safety.gd` | **1 failure**: `Only 30 of 24 gameplay configurations executed` from line 23. Its loops now intentionally cover 5 animals × 2 modes × 3 difficulties = **30**, so the count constant and success text remain stale. |
| `test_catch_three_apple_waves.gd` | **0 assertion failures / 12750 checks, 150 cases**, but exits 1 solely because line 47 requires `cases == 120`. With 5 animals × 5 topics × 2 modes × 3 difficulties, 150 is the correct case count. |

Two additional suites failed only in the first run and then passed after
concurrent updates: `test_catch_objective_editor_static.gd` initially had
**1/212** teardown failure and subsequently **PASS 214/214**; and
`test_catch_visual_layout.gd` initially had **1/2096** teardown failure and
subsequently **PASS 2097/2097**. Both initial failures were exact root-child
count comparisons after Catch destruction while a shared `KilosGameAudio` node
had been mounted. The remaining `duplicate_labels` and `hud_ui` root-count
assertions still fail on their latest individual runs. A root-count mismatch
alone cannot distinguish a persistent application-level music manager from a
leaked game-owned node; the test needs to inspect node identity/lifetime.

The affirmative checks strengthen the classification: animal migration
**PASS 526 assertions**, real PNG alpha/framing **PASS 955**, character editor
rig **PASS 1786**, apple foreground/collision **PASS 601**, original PNG assets
**PASS 1271**, unique session words **PASS 3539**, and wave spawn alignment
**PASS 7650**. The framing audit evaluates the actual nontransparent pixels and
the left/right steering extremes. After worker14's editor-art correction the
1280×720 Bear body bottom is **y=620.00**, basket bottom **y=525.05**; at
1920×1080, Lion body bottom is **y=931.48** and Panda is **y=930.00**.
All are inside their tested frames, replacing the earlier ~820 px overflow.
These are synthetic/render-geometry assertions, not a physical-camera claim.

No production or existing tests were modified during this Catch follow-up.
The prime subsequently updated the older suites' character names, expected
case counts, KidsVoice API, and root-manager lifetime expectations. Their
final targeted reruns passed, so the table above remains historical evidence
rather than unresolved QA failures.

## Static asset/reference audit

The Python tool scans source `.tscn`, `.tres`, and `.gd` files for quoted
literal `res://` references and verifies serialized scene `ext_resource`
paths separately. Its latest in-session scan inventories **1,933** project files excluding
`.git`, `.godot`, virtual environments, and generated cache directories;
**621** considered artwork/audio/font/data assets, including 552 PNG, 44 WAV
and 10 MP3 files. It finds **0 broken scene external-resource links**, **84
groups sharing basenames**, and **27 pairs of byte-identical assets** using
SHA-256. There are **23 advisory missing quoted literals**, mainly old test
fixtures, deleted 3D paths intentionally asserted absent, generated outputs,
and dynamic path prefixes; none is a broken serialized scene external link.

One concrete identical cross-folder pair:

```
SHA256 prefix: 242d920db42fb6
Components/Gameplay/Calibration/BACKGROUND.png
Components/Leaderboard/2026-10-24/BACKGROUND.png
```

The calibration copy has a direct static scene reference in
`ui/vision/calibration.tscn`; the leaderboard copy has no *quoted static* direct
reference in the scanned source. That is **not** proof the second copy is safe
to remove: resources may be loaded by computed paths, selected in the Godot
Inspector, preserved for custom theme overrides, or referenced outside scanned
source. Many other identical pairs are historical `showcase/` test screenshots
used for visual regression and defense presentation, despite having no
`res://` reference in runtime scenes. Preserve both copies until owners finish
their dynamic-path, UID, human-review and import metadata audit. Basename
matches alone never imply byte equality.

## Coverage boundaries

Headless synthetic time exercises **real game scripts** but does not measure
60 seconds of physical wall time, YOLO FPS, GPU/CPU latency, audio speakers,
collision accuracy under a real viewport/sensor, actual webcam recovery,
PostgreSQL persistence, or Windows installer behavior. The 3-second
calibration hold state machines were separately checked by the existing
five-pose regression suite, without a human standing in front of the camera.
Resource existence in a source checkout does not guarantee exported PCK
availability or that a teacher's local image overrides remain valid.
