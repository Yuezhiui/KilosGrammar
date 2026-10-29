"""Read-only scene/asset integrity audit after KILOS GRAMMAR UI migration.

Usage: python tools/test_kilos_asset_refs_20261028.py
Checks only explicit resource paths. Godot UID resolution, runtime directory
lookups, inspector overrides, scene inheritance and bundled exports require
separate editor/runtime checks. No file deletion or database/webcam activity.
"""

from __future__ import annotations

from collections import Counter, defaultdict
import hashlib
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE_EXTENSIONS = {".tscn", ".tres", ".gd"}
ASSET_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".webp", ".svg", ".bmp", ".gif",
    ".mp3", ".ogg", ".wav", ".flac", ".ttf", ".otf",
    ".glb", ".gltf", ".pt", ".pck", ".json", ".csv",
}
IGNORED = {".git", ".godot", "__pycache__", ".venv", "venv", "node_modules"}
RES_LITERAL = re.compile(r"[\"']res://(?P<path>[^\"'\r\n]*)[\"']")
EXT_RESOURCE = re.compile(r"\[ext_resource\s+[^\]]*?path=\"(?P<path>res://[^\"]+)\"", re.S)
DYNAMIC_PATH = re.compile(r"(?:load|preload|ResourceLoader\.load|FileAccess\.open|DirAccess\.open)\s*\(\s*(?:[a-zA-Z_][\w.]*|\S*\+)")


def project_files():
    for path in ROOT.rglob("*"):
        if path.is_file() and not any(part in IGNORED for part in path.relative_to(ROOT).parts):
            yield path


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            sha.update(chunk)
    return sha.hexdigest()


def main() -> int:
    files = list(project_files())
    scenes = sorted(x for x in files if x.suffix.lower() == ".tscn")
    assets = [x for x in files if x.suffix.lower() in ASSET_EXTENSIONS]
    extension_counts = Counter(x.suffix.lower() or "<none>" for x in assets)
    missing = []
    broken_external = []
    invalid_traversal = []
    dynamic_refs = []
    explicit_uses = defaultdict(set)
    names = defaultdict(list)
    for asset in assets:
        names[asset.name.casefold()].append(asset.relative_to(ROOT).as_posix())

    for src in files:
        if src.suffix.lower() not in SOURCE_EXTENSIONS:
            continue
        relative = src.relative_to(ROOT).as_posix()
        try:
            content = src.read_text(encoding="utf-8-sig")
        except UnicodeDecodeError:
            continue
        if DYNAMIC_PATH.search(content):
            dynamic_refs.append(relative)
        for match in RES_LITERAL.finditer(content):
            literal = match.group("path")
            if (not literal or literal.startswith("...") or literal.endswith("/") or
                    any(marker in literal for marker in ("%", "{", "}", "*"))):
                continue
            normalized = (ROOT / literal).resolve()
            if not normalized.is_relative_to(ROOT):
                invalid_traversal.append((relative, literal))
                continue
            explicit_uses[literal].add(relative)
            if not normalized.exists():
                missing.append((relative, literal))
        if src.suffix.lower() == ".tscn":
            for match in EXT_RESOURCE.finditer(content):
                literal = match.group("path")
                normalized = (ROOT / literal.removeprefix("res://")).resolve()
                if not normalized.is_file():
                    broken_external.append((relative, literal))

    # This is a static audit. Missing paths in quoted code may be optional
    # branches, whereas a missing scene ext_resource is a definite blocker.
    print("ASSET_AUDIT files={} scenes={} assets={} explicit_paths={} dynamic_source_files={}".format(
        len(files), len(scenes), len(assets), len(explicit_uses), len(dynamic_refs)
    ))
    print("ASSET_TYPES " + ", ".join(f"{k}:{v}" for k, v in extension_counts.most_common(12)))
    print("ASSET_MISSING_LITERAL_REFERENCES count={}".format(len(missing)))
    for source, resource in sorted(set(missing))[:30]:
        print(f"  POSSIBLY_MISSING {source} -> res://{resource}")
    print("ASSET_BROKEN_SCENE_EXT_RESOURCE count={}".format(len(broken_external)))
    for source, resource in sorted(set(broken_external))[:30]:
        print(f"  BROKEN_EXT {source} -> {resource}")
    print("ASSET_OUTSIDE_ROOT_REFERENCES count={}".format(len(invalid_traversal)))
    for source, resource in invalid_traversal[:10]:
        print(f"  OUTSIDE_ROOT {source} -> {resource}")
    duplicates = [(name, locations) for name, locations in names.items() if len(locations) > 1]
    print("ASSET_SHARED_BASENAMES count={}".format(len(duplicates)))
    for name, locations in sorted(duplicates, key=lambda v: (-len(v[1]), v[0]))[:15]:
        print(f"  SAME_NAME ({len(locations)}) {name}: {locations[:4]}")
    if "--hash" in sys.argv:
        by_digest = defaultdict(list)
        for asset in assets:
            by_digest[digest(asset)].append(asset.relative_to(ROOT).as_posix())
        groups = [(sha, locations) for sha, locations in by_digest.items() if len(locations) > 1]
        print(f"ASSET_BYTE_IDENTICAL_SHA256_GROUPS count={len(groups)}")
        for sha, locations in sorted(groups, key=lambda pair: (-len(pair[1]), pair[0]))[:25]:
            linked = [(p, sorted(explicit_uses.get(p, ()))[:3]) for p in locations]
            print(f"  DUPLICATE_SHA256 {sha[:16]} files={len(locations)} paths_and_static_callers={linked[:5]}")
    print("ASSET_DYNAMIC_PATH_CALLERS sample=" + repr(dynamic_refs[:25]))
    print("NOTE static path validation cannot prove unused/orphan safe deletion; hash/UID/runtime checks required")
    # Treat only definite broken .tscn ext_resource links and explicit path
    # traversal as a failing test; other missing literals are reports.
    return 1 if broken_external or invalid_traversal else 0


if __name__ == "__main__":
    sys.exit(main())
