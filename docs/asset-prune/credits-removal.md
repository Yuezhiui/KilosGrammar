# Credits screen removal — 26 October 2026

The user requested removal of the Credits entry from the game. `res://main_menu.tscn` now contains five native, editor-editable menu buttons (Leaderboard, Settings, Tutorial, Play, Quit). `res://main_menu.gd` has no `credits` navigation route or animation reference. The obsolete standalone `res://ui/secondary/credits/credits.tscn` and its script/UID were removed along with the four Credits-only PNGs, matching `.png.import` sidecars and `Components/Credits/README.md`. The main menu's former `Components/Main Panel/Original/credits.png` button artwork also has no runtime consumer, but is outside this worker's designated asset ownership; it can be safely handled during the separate Main Panel asset-prune review.

The former screen's project contributors (recorded here to preserve the non-UI attribution record) were: Teoxon John William Ruiz; Arabi Harwyn Lance Quinto; Cawicaan James Francis Alfaro; Estaris Kristina Yvonne Frial; Daantos Johncarlos Opo; Matienzo Ron Jaypee V; Blase John Barry Villanueva; Manangan Andrew Garcia; Calleja Rodrigo Jhon Lagarto; Bobis Lordjethro Bequilla; Burgos Riviera Irish Amor.

The former **Special Acknowledgments** text is preserved verbatim below because removing a menu screen must not erase software/font/model attribution:

> Godot Engine — MIT License
> Titan One — SIL Open Font License 1.1
> Comic Lemon — Khurasan (free personal/commercial)
> Toy Plane by l3clarke (Sketchfab) — CC BY 4.0
> 3D model scaled/rotated for Human Plane; sketchfab.com/3d-models/toy-plane-804d6814818247978f28d12efcc38cce

Keep the original third-party files, including `Components/Gameplay/Human Plane/3D/toy_plane/license.txt` and `Components/Gameplay/Human Plane/3D/mountain/license.txt`, together with source assets and applicable license notices. The former screen's short text is a record, not a substitute for those complete terms. The separate NATURE mountain asset has restrictions noted in `Components/README_ASSETS.md` and requires its own licensing review.

Routes, scene inventory expectations, hover/animation fixtures and button-sound fixtures were updated to represent the remaining screens. The existing Main Panel geometry is unchanged except for the deleted Credits button; the left menu still has editable Leaderboard and Settings buttons.
