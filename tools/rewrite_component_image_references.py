"""One-time, auditable asset migration reference rewrite.

All old-to-new res:// source paths are recorded in docs/asset-migration/*.json.
The source images must already have been moved with their Godot .import files.
Run from anywhere: py -3 tools/rewrite_component_image_references.py

Updates text files byte-for-byte (aside from literal paths), preserving CRLF,
BOMs and unrelated dirty edits. Original input manifests are never rewritten.
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAPPINGS = ROOT / "docs" / "asset-migration"
MANIFESTS = ["worker2.json", "worker24.json", "prime.json"]
TEXT_EXTS = {
    ".gd", ".tscn", ".tres", ".py", ".md", ".json", ".cfg", ".godot",
    ".import", ".ps1", ".psm1", ".txt", ".gdshader", ".sh", ".bat",
    ".ini", ".yml", ".yaml", ".html", ".xml", ".toml",
}
IGNORED_DIRS = {
    ".git", ".godot", "showcase", ".venv", "node_modules", "__pycache__",
    ".next", "build", "dist", "out",
}


def load_mapping() -> dict[str, str]:
    mapping: dict[str, str] = {}
    for manifest in MANIFESTS:
        path = MAPPINGS / manifest
        pairs = json.loads(path.read_text(encoding="utf-8-sig"))
        if not isinstance(pairs, dict):
            raise ValueError(f"{manifest} is not a flat path mapping")
        for old, new in pairs.items():
            if not isinstance(old, str) or not isinstance(new, str):
                raise TypeError(f"Invalid item from {manifest}: {old!r} -> {new!r}")
            if not old.startswith("res://") or not new.startswith("res://"):
                raise ValueError(f"Not res:// paths: {old!r} -> {new!r}")
            if old in mapping and mapping[old] != new:
                raise ValueError(f"Contradictory mapping {old!r}")
            target = ROOT / new.removeprefix("res://")
            if not target.is_file():
                raise FileNotFoundError(f"Destination does not exist: {target}")
            mapping[old] = new
    return mapping


def main() -> None:
    mapping = load_mapping()
    # Also remap literal constructor directory paths, such as
    # `"res://WordCatcherMaps/%sMap.png" % map_name`. Most script paths use
    # full filenames covered by the explicit maps.
    directory_aliases = {
        "res://WordCatcherMaps/": "res://Components/Gameplay/Catch the Word/Maps/",
        "res://WordCatcherCharacters/": "res://Components/Gameplay/Catch the Word/Characters/",
        "res://BalloonPoppingBackground/": "res://Components/Gameplay/Balloon Popping/Background/",
        "res://BalloonPoppingBalloons/": "res://Components/Gameplay/Balloon Popping/Balloons/",
        "res://Components/MainMenu/": "res://Components/Main Panel/Original/",
        "res://Components/CalibrationV2/": "res://Components/Gameplay/Calibration/",
        "res://Components/HumanPlaneAssets/": "res://Components/Gameplay/Human Plane/",
        "res://Components/TutorialSpotlight/": "res://Components/Tutorial/Spotlight/",
    }
    # The dynamically authored seven-category redesign extractor must be
    # updated separately; its output folder is *not* a single destination.
    operations: dict[bytes, bytes] = {}
    for old, new in mapping.items():
        operations[old.encode("utf-8")] = new.encode("utf-8")
        # Also rewrite plain project-relative paths in manifests/generators.
        operations[old.removeprefix("res://").encode("utf-8")] = new.removeprefix("res://").encode("utf-8")
    for old, new in directory_aliases.items():
        operations[old.encode()] = new.encode()
        operations[old.removeprefix("res://").encode()] = new.removeprefix("res://").encode()

    # Longest paths first, so a directory-alias cannot preempt a specific
    # image-file mapping. This also avoids replacing a path twice.
    ordered = sorted(operations.items(), key=lambda pair: len(pair[0]), reverse=True)
    touched: list[tuple[str, int]] = []
    replacements = 0
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in TEXT_EXTS:
            continue
        relative = path.relative_to(ROOT)
        if any(part in IGNORED_DIRS for part in relative.parts):
            continue
        if relative.parts[:2] == ("docs", "asset-migration"):
            continue
        if path.resolve() == Path(__file__).resolve():
            continue
        source = path.read_bytes()
        if not (b"res://" in source or b"ui/redesign/assets/" in source or b"WordCatcher" in source or b"Components/" in source or b"BalloonPopping" in source):
            continue
        changed = source
        local_count = 0
        for old, new in ordered:
            if old in changed:
                local_count += changed.count(old)
                changed = changed.replace(old, new)
        if changed != source:
            path.write_bytes(changed)
            touched.append((relative.as_posix(), local_count))
            replacements += local_count

    report = {
        "mapped_resource_paths": len(mapping),
        "files_rewritten": len(touched),
        "literal_replacements": replacements,
        "modified_files": dict(sorted(touched)),
    }
    (MAPPINGS / "rewrite_report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(json.dumps({key: report[key] for key in ("mapped_resource_paths", "files_rewritten", "literal_replacements")}, indent=2))


if __name__ == "__main__":
    main()
