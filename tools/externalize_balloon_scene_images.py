#!/usr/bin/env python3
"""Safely replace redundant 45MB Godot scene-embedded pixels with source PNG refs.

The original PNGs already live in Components/Gameplay/Balloon Popping/Background/ and are separately
loaded by balloon_popping.gd at runtime/editor preview. This changes *only*
the resource serialization; no scene nodes, collision or artwork bytes.

Usage:
    py -3 tools/externalize_balloon_scene_images.py --check
    py -3 tools/externalize_balloon_scene_images.py --apply

--apply leaves an adjacent .inline-original.bak backup to allow rollback until
Godot regression tests complete. Once validated, that backup can be deleted.
"""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import struct


ROOT = Path(__file__).resolve().parents[1]
SCENE = ROOT / "ui" / "minigames" / "balloon_popping.tscn"
BACKUP = SCENE.with_suffix(".tscn.inline-original.bak")
TEMP = SCENE.with_suffix(".tscn.tmp")
IMAGES = (
    ("8_booth", ROOT / "BalloonPoppingBackground" /
     "0826b13c-250f-42e1-9398-a83d2922a1d8.png",
     "res://Components/Gameplay/Balloon Popping/Background/0826b13c-250f-42e1-9398-a83d2922a1d8.png"),
    ("9_counter", ROOT / "BalloonPoppingBackground" /
     "95ae2a22-302d-48f7-9b5f-e12b0104c822.png",
     "res://Components/Gameplay/Balloon Popping/Background/95ae2a22-302d-48f7-9b5f-e12b0104c822.png"),
)
RESOURCE_IDS = {
    'Image_wvuog', 'ImageTexture_8sdty',
    'Image_1ocwm', 'ImageTexture_sbjbv',
}
OLD_TEXTURES = {
    'texture = SubResource("ImageTexture_8sdty")':
        'texture = ExtResource("8_booth")',
    'texture = SubResource("ImageTexture_sbjbv")':
        'texture = ExtResource("9_counter")',
}


def validate_pngs():
    for _, path, _ in IMAGES:
        with path.open("rb") as source:
            header = source.read(24)
            if header[:8] != b"\x89PNG\r\n\x1a\n":
                raise ValueError(f"Expected an original PNG at {path}")
            width, height = struct.unpack(">II", header[16:24])
            if (width, height) != (1672, 941):
                raise ValueError(f"{path}: expected art size 1672x941, got {width}x{height}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
        print(f"ART UNCHANGED {path.relative_to(ROOT)} {width}x{height} SHA256={digest}…")


def convert_to_stage() -> dict:
    """Stream the scene, filtering only the four known redundant subresources."""
    seen_subresources = set()
    replacements = {key: 0 for key in OLD_TEXTURES}
    inserted = False
    suppress_resource = False
    node_count = 0
    try:
        with SCENE.open("r", encoding="utf-8", newline="") as old, TEMP.open(
            "w", encoding="utf-8", newline=""
        ) as new:
            for line in old:
                if line.startswith("[sub_resource "):
                    if line.count('id="') != 1:
                        raise ValueError("Unexpected subresource declaration")
                    resource_id = line.split('id="', 1)[1].split('"', 1)[0]
                    if resource_id not in RESOURCE_IDS:
                        raise ValueError(f"Unrecognized subresource: {resource_id}")
                    seen_subresources.add(resource_id)
                    suppress_resource = True
                if line.startswith("[node "):
                    suppress_resource = False
                    node_count += 1
                if suppress_resource:
                    continue
                # Inject the two existing source-PNG references after the
                # last authored external resource declaration.
                if line.startswith('[ext_resource ') and 'id="7_launcher"' in line:
                    new.write(line)
                    nl = "\r\n" if line.endswith("\r\n") else "\n"
                    for resource_id, _, resource_path in IMAGES:
                        new.write(
                            f'[ext_resource type="Texture2D" path="{resource_path}" '
                            f'id="{resource_id}"]{nl}'
                        )
                    inserted = True
                    continue
                for old_ref, new_ref in OLD_TEXTURES.items():
                    if old_ref in line:
                        if replacements[old_ref]:
                            raise ValueError(f"Duplicate source image reference: {old_ref}")
                        line = line.replace(old_ref, new_ref)
                        replacements[old_ref] += 1
                new.write(line)
        if (seen_subresources != RESOURCE_IDS or not inserted or node_count != 11
                or any(count != 1 for count in replacements.values())):
            raise ValueError(
                f"Unexpected scene structure: embedded={seen_subresources}, "
                f"node_count={node_count}, ext_inserted={inserted}, "
                f"refs={replacements}")
        if TEMP.stat().st_size >= 128_000:
            raise ValueError("Replacement unexpectedly retained giant embedded data")
        return {"nodes": node_count, "subresources": len(seen_subresources)}
    except BaseException:
        TEMP.unlink(missing_ok=True)
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Inspect without editing")
    parser.add_argument("--apply", action="store_true", help="Externalize safely")
    args = parser.parse_args()
    if args.check == args.apply:
        parser.error("Choose exactly one of --check or --apply")
    validate_pngs()
    size_before = SCENE.stat().st_size
    print(f"SCENE before={size_before:,} bytes")
    with SCENE.open("r", encoding="utf-8") as source:
        header = source.read(4096)
    if '[ext_resource type="Texture2D"' in header:
        print("Already externalized, nothing to change")
        return
    if size_before < 40_000_000:
        raise ValueError("Not the expected original large scene; refusing modification")
    if args.check:
        print("CHECK PASS: original inline Image data still present; conversion is safe")
        return
    if BACKUP.exists():
        raise ValueError(f"Refusing to overwrite backup {BACKUP}")
    try:
        stats = convert_to_stage()
        # Protect the untracked original until runtime QA verifies the output.
        shutil.copy2(SCENE, BACKUP)
        os.replace(TEMP, SCENE)
        print(
            f"CONVERTED scene={SCENE.relative_to(ROOT)} "
            f"bytes={SCENE.stat().st_size:,} (was {size_before:,}); "
            f"nodes={stats['nodes']} externalized_images=2")
        print(f"Rollback backup={BACKUP.relative_to(ROOT)}")
    except BaseException:
        TEMP.unlink(missing_ok=True)
        raise


if __name__ == "__main__":
    main()
