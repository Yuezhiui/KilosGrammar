# All Godot scenes: editor cleanup and obsolete-node audit (2026-10-28)

## Scope and safeguards

Audited **all 29 project `.tscn` files**. An invisible Control, a scene-only
resource, a direct-root child, or a group with no graphic children is **not**
by itself proof of obsolescence. Before removing/reparenting anything, checked
runtime GDScript NodePaths, unique-name references (`%Node`), conditionally
shown UI, animations, internal child transforms and Godot resource links.

No existing user-authored positions, styles, camera alignment, button actions,
game modes, player rigs, gates, scoring, database/CSV confirmation controls,
or source images were deliberately changed. Project already had extensive
uncommitted changes, left intact. No Git publication, webcam, live database,
or installer work was performed.

## Safe structural improvements

| Scene | Editor-oriented changes |
| --- | --- |
| `ui/vision/calibration.tscn` | Previously completed: removed 16 explicitly retired badges/labels, six functionally grouped Controls (`CameraArea`, `PoseGuides`, `Directions`, `CountdownArtwork`, `CameraFeedback`, `Navigation`); active source pose PNGs and intro preserved |
| `ui/vision/camera_check.tscn` | Added zero-offset `HeaderArtwork`, `CameraPreview`, `TrackingStatus`, and `FooterControls`. Camera display is an **editor-authored** `CameraPreview/LiveCameraImage` TextureRect, not recreated with hardcoded runtime geometry. `camera_check.gd` now binds child paths and preserves all buttons/status displays. Legacy runtime-only drawing fallback retained only for a missing `.tscn` |
| `ui/play/pause.tscn` | Added mouse-ignore `BackdropLayer` for `ColorRect`, `SetupArtworkBackground` and `Dimmer`; interactive `PauseCard`/buttons remain at their prior paths |
| `ui/play/ready.tscn` | Added mouse-ignore `BackdropLayer` for `CleanBackdrop` and `SetupArtworkBackground`; `LayoutMargins` and controls stay at their prior paths |
| `ui/secondary/results.tscn` | Added zero-offset full-rect `HeaderArtwork` and `InformationCards`; preserved `%` unique-name script bindings, values, Retry and Home paths |
| `ui/secondary/leaderboard.tscn`, `leaderboard_row.tscn`, `settings.tscn`, `ui/shared/lexi_reference_backdrop.tscn` | Editor descriptions added to document live conditional controls or scene structure; avoided breaking existing direct-script paths |

`main_menu.tscn` was **already** appropriately organized in LogoGroup,
LeftMenu, CenterMenu and FallingLayer. Its hidden `FallingTemplate` is used for
falling letter animations and was retained.

## Other inspected scenes preserved intentionally

| Group | Inspected `.tscn` files | Reason no destructive pruning |
| --- | --- | --- |
| Gameplay | `ui/minigames/catch_the_word/catch_word.tscn`, `balloon_popping.tscn`, `human_plane.tscn` | Catch Girl/Grandma/Grandpa rigs; Balloon lives plaque; Human Plane pure-2D gate bars, labels, `UpcomingGates`, hitbox and LivesPlaque all have conditional/runtime references. Removing hidden nodes would break modes or collision |
| Balloon art (five) | `ui/minigames/balloon_popping/balloon_art/balloon_blue.tscn`, `balloon_green.tscn`, `balloon_purple.tscn`, `launcher.tscn`, `stone.tscn` | Each visible or physics/collision node is used by its instantiated mini-scene |
| Play | `ui/play/gameplay.tscn`, `guided_countdown.tscn`, `play_activity.tscn`, `play_difficulty.tscn`, `play_topic.tscn` | Conditional tracking notice, timers, scene controller wrappers and editor-authored selection controls are live |
| Student | `ui/student/student_setup.tscn`, `existing_score_dialog.tscn` | Student registration/recovery, hidden scroll hint and existing-score actions are conditional/live; no unreferenced resource |
| Tutorial | `ui/tutorial/tutorial_home.tscn`, `grammar_guide.tscn`, `spotlight_overlay.tscn` | Guide grid is populated at runtime; spotlight arrows/feedback conditionally displayed; paths retain authoring geometry |
| Secondary | `ui/secondary/credits.tscn` | CreditsStage/scroll/Back already grouped; route remains active |

All resource declaration audits for these scene families found no safely
unreferenced ext/subresources that should be deleted merely to reduce the
node count. Native file dialogs and destructive Delete All Data confirmations
must remain in the scene even though they are usually invisible.

## Repeatable QA

Godot 4.7.2 Windows console from project root:

```powershell
$g = 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
& $g --headless --editor --path . --quit
& $g --headless --path . --script res://tools/test_all_scenes_bruteforce.gd
& $g --headless --path . --script res://tools/test_camera_check_grouped_editor_qa.gd
& $g --headless --path . --script res://tools/test_calibration_grouped_editor_qa.gd
& $g --headless --path . --script res://tools/test_ui_layout.gd
```

Known limitations in old **legacy** QA are kept separate from the cleanup
contract: older camera/intro fixtures may refer to the retired flat Calibration
node paths, old Back button artwork, or synthetic pose packets rejected by
current freshness policy; some Human Plane HUD pixel tests refer to earlier
Catch HUD geometry. Tests that fail those unrelated prior assumptions are not
grounds to revive obsolete art or weaken authentic YOLO safety.
