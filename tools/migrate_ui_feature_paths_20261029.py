"""One-time audited, non-destructive KILOS GRAMMAR UI feature-folder migration.

Run at the repository root: python tools/migrate_ui_feature_paths_20261029.py

Refuses overwrites, preserves bytes of every .uid file, and updates only
exact res:// paths, not unrelated text. The main menu, minigame scripts,
project.godot, and Tutorial Home remain outside this worker's write scope;
their owning agents must apply the reported path-only references separately.
"""

from pathlib import Path
import os
import sys

ROOT = Path(__file__).resolve().parents[1]

FEATURES: dict[str, list[str]] = {
    "ui/play/activity": ["play_activity.gd", "play_activity.tscn"],
    "ui/play/topic": ["play_topic.gd", "play_topic.tscn"],
    "ui/play/difficulty": ["play_difficulty.gd", "play_difficulty.tscn"],
    "ui/play/ready": ["ready.gd", "ready.tscn"],
    "ui/play/gameplay": [
        "gameplay.gd", "gameplay.tscn", "guided_countdown.tscn",
        "catch_asset_preloader.gd",
    ],
    "ui/play/pause": ["pause.gd", "pause.tscn"],
    "ui/play/shared": ["play_ui.gd"],
    "ui/student/setup": ["student_setup.gd", "student_setup.tscn"],
    "ui/student/existing_score": ["existing_score_dialog.gd", "existing_score_dialog.tscn"],
    "ui/secondary/leaderboard": [
        "leaderboard.gd", "leaderboard.tscn", "leaderboard_row.tscn",
    ],
    "ui/secondary/settings": ["settings.gd", "settings.tscn"],
    "ui/secondary/results": ["results.gd", "results.tscn"],
    "ui/secondary/credits": ["credits.gd", "credits.tscn"],
    "ui/vision/calibration": [
        "calibration.gd", "calibration.tscn", "calibration_voice.gd",
    ],
    "ui/vision/camera_check": ["camera_check.gd", "camera_check.tscn"],
    "ui/tutorial/grammar_guide": ["grammar_guide.gd", "grammar_guide.tscn"],
}

REWRITABLE = {".gd", ".tscn", ".tres", ".gdshader", ".py", ".md"}
SKIP = {
    "main_menu.gd", "project.godot", "ui/tutorial/tutorial_home.gd",
    "ui/tutorial/tutorial_home.tscn",
}


def main() -> int:
    old_new: dict[str, str] = {}
    old_files: list[tuple[Path, Path]] = []
    for destination_dir, names in FEATURES.items():
        category_dir = str(Path(destination_dir).parent).replace("\\", "/")
        for name in names:
            src = ROOT / category_dir / name
            dst = ROOT / destination_dir / name
            if not src.is_file() or dst.exists():
                raise RuntimeError(f"Missing original or colliding destination: {src} -> {dst}")
            old_files.append((src, dst))
            old_new[f"res://{src.relative_to(ROOT).as_posix()}"] = (
                f"res://{dst.relative_to(ROOT).as_posix()}"
            )
            # Preserve the Godot script identity sidecar byte-for-byte.
            uid = src.with_name(src.name + ".uid")
            if uid.is_file():
                new_uid = dst.with_name(dst.name + ".uid")
                if new_uid.exists():
                    raise RuntimeError(f"Godot UID collision: {new_uid}")
                old_files.append((uid, new_uid))

    rewrite_candidates: list[tuple[Path, bytes, bytes]] = []
    owner_references: dict[str, list[str]] = {}
    # Locate references BEFORE moving, so this is one atomic-scoped batch.
    for base in (ROOT / "ui", ROOT / "tools", ROOT / "showcase", ROOT / "docs", ROOT / "release"):
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix not in REWRITABLE:
                continue
            rel = path.relative_to(ROOT).as_posix()
            if rel.startswith("ui/minigames/") or rel in SKIP:
                continue
            before = path.read_bytes()
            after = before
            # Longest names first avoids prefix shadowing.
            for old, new in sorted(old_new.items(), key=lambda x: -len(x[0])):
                after = after.replace(old.encode("utf-8"), new.encode("utf-8"))
            if after != before:
                rewrite_candidates.append((path, before, after))

    # Surface owner-required replacements without editing their files.
    for rel in ("main_menu.gd", "ui/minigames/balloon_popping.gd", "project.godot"):
        path = ROOT / rel
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        owner_references[rel] = [
            f"{old} -> {new}" for old, new in old_new.items() if old in text
        ]

    # Any absent .uid is a real scene file (script UIDs are expected); do not
    # create regenerated IDs or alter serialized resource UIDs in .tscn.
    for source, target in old_files:
        target.parent.mkdir(parents=True, exist_ok=True)
        os.rename(source, target)

    for original, _before, updated in rewrite_candidates:
        # Content is now under the new path if it was one of the moved scripts.
        key = next((target for source, target in old_files if source == original), original)
        key.write_bytes(updated)

    print(f"Moved {len(old_files)} files ({len(old_new)} feature resources).")
    for source, target in old_files:
        print(f"MOVE {source.relative_to(ROOT).as_posix()} -> {target.relative_to(ROOT).as_posix()}")
    print(f"Updated literal references inside {len(rewrite_candidates)} permitted text files.")
    for source, _, _ in rewrite_candidates:
        print(f"REFS {source.relative_to(ROOT).as_posix()}")
    for owner, refs in owner_references.items():
        if refs:
            print(f"OWNER {owner}:")
            for path_change in refs:
                print(f"  {path_change}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
