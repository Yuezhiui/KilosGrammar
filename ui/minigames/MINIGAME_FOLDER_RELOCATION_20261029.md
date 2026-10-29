# Catch the Word and Balloon Popping folder migration

October 29, 2026. This manifest records the active resource paths after the
scene organization. Only Catch and Balloon files were relocated; `human_plane`
and the shared `grammar_bank.gd` remain in `ui/minigames/`.

## Scene and script paths

| Former project path | Current project path |
| --- | --- |
| `ui/minigames/catch_word.tscn` | `ui/minigames/catch_the_word/catch_word.tscn` |
| `ui/minigames/catch_word.gd` | `ui/minigames/catch_the_word/catch_word.gd` |
| `ui/minigames/catch_word.gd.uid` | `ui/minigames/catch_the_word/catch_word.gd.uid` |
| `ui/minigames/balloon_popping.tscn` | `ui/minigames/balloon_popping/balloon_popping.tscn` |
| `ui/minigames/balloon_popping.gd` | `ui/minigames/balloon_popping/balloon_popping.gd` |
| `ui/minigames/balloon_popping.gd.uid` | `ui/minigames/balloon_popping/balloon_popping.gd.uid` |

The Catch scene UID remains `uid://bcns0owcuap3q` and its script UID remains
`uid://bmhyrdbwye3jg`. The Balloon scene UID remains `uid://bigsef1pvcay2`
and its script UID remains `uid://cc5uy3fkd1nl2`. Node hierarchies, assets,
gameplay scripts, and editor-authored transforms are preserved.

## Supporting files

The five live Balloon PackedScenes were moved as a directory, preserving their
filenames and scene contents:

`ui/minigames/balloon_art/` →
`ui/minigames/balloon_popping/balloon_art/`

This includes `balloon_blue.tscn`, `balloon_green.tscn`,
`balloon_purple.tscn`, `launcher.tscn`, and `stone.tscn`. The source art
extractor is at
`ui/minigames/balloon_popping/balloon_art/reference/extract_reference.py`;
its `Path(__file__).resolve().parents[5]` lookup still reaches the project root.

Catch documentation moved from `ui/minigames/catch_hud/` and
`ui/minigames/characters/` into `ui/minigames/catch_the_word/catch_hud/`
and `ui/minigames/catch_the_word/characters/`, respectively. Gameplay art in
`Components/Gameplay/` stays at its existing resource paths.

## Reference migration

Exact path-only substitutions were applied to source, scenes, tests, previews,
profiling scripts, docs and historical manifests without reformatting their
other content. At the time of migration, 80 project text files were updated,
with these replacement totals:

| Old path fragment | New path fragment | Occurrences |
| --- | --- | ---: |
| `ui/minigames/catch_word.` | `ui/minigames/catch_the_word/catch_word.` | 66 |
| `ui/minigames/balloon_popping.` | `ui/minigames/balloon_popping/balloon_popping.` | 31 |
| `minigames/balloon_art` | `minigames/balloon_popping/balloon_art` | 36 |
| `minigames/catch_hud` | `minigames/catch_the_word/catch_hud` | 40 |

The main gameplay loader now targets the two new `.tscn` paths, and all
five Balloon art PackedScene references and its stone preload point inside
the Balloon directory. The two script sidecar UID files were **moved**, never
regenerated. No files were reset, deleted or committed as part of this task.

## Local verification

Run `Godot --headless --path . --editor --quit` to rescan imported resources,
then invoke focused SceneTree scripts from `tools/` with
`Godot --headless --path . --script res://tools/<test_name>.gd`.
Test source files and the gameplay route already use the new scene locations.

Verified after relocation with Godot 4.7.2 (`--headless --path .`):

- Editor import and script scan: exit 0, no reported resource or script errors.
- `test_catch_animal_migration_20261028.gd`: PASS 526 assertions.
- `test_catch_vocab_cycle_20261029.gd`: PASS 17,018 checks.
- `test_balloon_vocab_recycle_20261029.gd`: PASS 42,806 checks.
- `test_balloon_shared_hud.gd`: PASS 2,466 checks.
- `test_balloon_quick_hand_raise.gd`: PASS 150 checks.
- `test_catch_character_editor_rig.gd`: 60 failures from existing authored
  animal Y=810 placement in 720/1080 viewport tests; no scene positions were
  changed as part of folder organization.
- `test_art_scenes.gd`: active scene paths load, but Panda screen framing and
  Balloon projectile/collision assertions remain red.
- `test_minigames.gd`: Balloon completed-round result signal assertion remains
  red; other cross-game checks run.

Remaining gameplay/visual QA concerns above should be handled independently
of the path migration and without changing this resource mapping.
