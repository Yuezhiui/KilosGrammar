"""Reproducible Phase-2 sprite extraction, run manually (never by Godot).

Source sheets remain untouched. Each entry is a source pixel rectangle (left,
top, right, bottom), cropped without painting new art. Transparent pixels are
preserved. Visual precision caveats live in inventory.

Example (PowerShell):
    python ui/redesign/assets/extract_phase2.py --source-dir "$HOME/Downloads" main student shared

The --source-dir directory contains MAIN/, STUDENT GAME SETUP/, and SETTINGS/.
Alternatively set KILOS_GRAMMAR_SOURCE_DIR; otherwise use Path.home()/Downloads.
Pillow/OpenCV are needed only when explicitly running this extraction script,
not when starting the Godot game. No packages are installed automatically.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

ASSET_ROOT = Path(__file__).resolve().parent

SOURCES = {
    "main_decor": ("MAIN", "16e2cc3e-574f-409e-a3bb-f7bc4cb27b58.png"),
    "main_stickers": ("MAIN", "4ba88951-a495-430f-9a34-d580aea1b89f.png"),
    "main_clouds": ("MAIN", "5e404e45-74fb-4f27-b5e9-eaf8aadb98e3.png"),
    "main_logo_parts": ("MAIN", "7ef65dc8-d1df-4b70-8c12-e3538ca236fd.png"),
    "main_buttons": ("MAIN", "81a7d8bd-eb2b-413e-9b74-dd305844bd9b.png"),
    "main_flat_reference": ("MAIN", "91190188-c67a-449d-a03f-a52542d668a5.png"),
    "main_logo": ("MAIN", "f2abe4b3-a62f-4761-b7b2-8246da404a16.png"),
    "student_controls": ("STUDENT GAME SETUP", "42268c5f-bd9f-469a-8085-9b203f2cb030.png"),
    "student_topics": ("STUDENT GAME SETUP", "435d767e-07ae-4ea7-b06b-c9f44b08977a.png"),
    "student_modes": ("STUDENT GAME SETUP", "7ee2f611-a9c4-4eb5-8260-07c47b031bd6.png"),
    "student_panel": ("STUDENT GAME SETUP", "ce1ac866-46f2-43e1-9469-9adc131fd868.png"),
    "shared_classroom": ("SETTINGS", "52c44321-00e4-4f07-92ce-012696fa4ce6.png"),
}

# The 1672x941 originals are ALREADY transparent sprite sheets except the
# main_flat_reference mockup. Box coordinates intentionally leave a few pixels
# of anti-aliased shadows and decorative rays around actual printed elements.
SPECS: dict[str, list[tuple[str, str, tuple[int, int, int, int], str]]] = {
    "main": [
        ("bg_clouds", "main_clouds", (843, 20, 1654, 485), "Clean teal/cloud background; rounded source corners."),
        ("bg_clouds_starry", "main_clouds", (19, 20, 831, 485), "Teal/cloud background with baked star motifs."),
        ("logo_full", "main_logo", (243, 17, 1440, 524), "Full KILOS GRAMMAR combined title with decorative stars."),
        ("logo_compact", "main_logo", (47, 523, 737, 762), "KILOS-only alternate wordmark; NOT a complete combined logo."),
        ("btn_tutorial", "main_buttons", (43, 86, 576, 284), "Purple TUTORIAL including book icon."),
        ("btn_play", "main_buttons", (574, 86, 1100, 284), "Green PLAY including triangle icon."),
        ("btn_quit", "main_buttons", (1095, 86, 1629, 284), "Red QUIT including door icon."),
        ("btn_leaderboard", "main_buttons", (164, 287, 617, 434), "Small purple LEADERBOARD with trophy icon."),
        ("btn_settings", "main_buttons", (624, 287, 1057, 434), "Small purple SETTINGS with gear icon."),
        ("btn_credits", "main_buttons", (1061, 287, 1504, 434), "Small purple CREDITS with star icon."),
        ("btn_blank_purple", "main_buttons", (42, 438, 576, 624), "Purple unlabeled 3D button background; tint-safe variant not guaranteed."),
        ("btn_blank_green", "main_buttons", (569, 438, 1103, 624), "Green unlabeled 3D button background."),
        ("btn_blank_red", "main_buttons", (1094, 438, 1630, 624), "Red unlabeled 3D button background."),
        ("btn_blank_nav", "main_buttons", (70, 627, 483, 763), "Short dark-purple unlabeled navigation button."),
        ("cloud_edge_left", "main_clouds", (27, 494, 232, 638), "Short standalone bottom cloud cluster."),
        ("cloud_edge_center", "main_clouds", (450, 525, 819, 646), "Wide standalone bottom cloud strip."),
        ("cloud_edge_right", "main_clouds", (846, 528, 1225, 643), "Second wide bottom cloud strip."),
        ("sparkle_gold", "main_decor", (474, 481, 635, 638), "Gold four-point star decoration (source artwork)."),
        ("sparkle_white", "main_decor", (463, 285, 642, 471), "White/cyan star decoration."),
        ("sticker_today", "main_stickers", (29, 134, 636, 488), "Isolated blue TODAY sticker and its 4 ornamental rays."),
        ("sticker_soft", "main_stickers", (603, 140, 1173, 488), "Isolated orange SOFT sticker and its 4 ornamental rays."),
        ("sticker_book", "main_logo_parts", (1481, 380, 1620, 482), "Single white/teal book symbol; left edge and bottom clipped to exclude adjacent yellow accent and dark-green book."),
        ("sticker_book_green", "main_logo_parts", (1486, 482, 1628, 598), "Single dark green open-book symbol; separated from white variant.")
    ],
    "student": [
        ("btn_back", "student_controls", (101, 64, 790, 300), "Large BACK with left arrow; full padding around corner highlights."),
        ("btn_continue", "student_controls", (821, 26, 1651, 311), "Large CONTINUE with right arrow and all yellow rays."),
        ("topic_noun", "student_topics", (35, 150, 564, 385), "Green NOUN option with book icon."),
        ("topic_pronoun", "student_topics", (570, 151, 1107, 384), "Purple PRONOUN option with people icon."),
        ("topic_verb", "student_topics", (1111, 151, 1643, 384), "Red VERB option with running figure icon."),
        ("topic_adjective", "student_topics", (228, 388, 831, 639), "Orange ADJECTIVE with stars."),
        ("topic_adverb", "student_topics", (841, 389, 1448, 639), "Blue ADVERB with lightning bolt."),
        ("topic_preposition_locked", "student_topics", (36, 635, 562, 869), "Gray PREPOSITION SOON locked option, deliberately not playable."),
        ("topic_conjunction_locked", "student_topics", (569, 635, 1107, 866), "Gray CONJUNCTION SOON locked option, deliberately not playable."),
        ("topic_interjection_locked", "student_topics", (1112, 635, 1643, 868), "Gray INTERJECTION SOON locked option, deliberately not playable."),
        ("mode_seconds", "student_modes", (163, 51, 827, 399), "Blue clock badge 60s; literal 60s baked text, not a dynamic countdown."),
        ("mode_lives", "student_modes", (837, 52, 1510, 400), "Green 3 LIVES badge with white heart; static selector not lives HUD."),
        ("difficulty_easy", "student_modes", (69, 421, 571, 743), "Green EASY with star."),
        ("difficulty_normal", "student_modes", (586, 421, 1088, 744), "Orange NORMAL with two stars."),
        ("difficulty_hard", "student_modes", (1102, 421, 1607, 744), "Red HARD with three stars."),
        ("setup_main_panel", "student_panel", (120, 17, 1554, 524), "Large blue framed empty cream panel, background only."),
        ("setup_heading", "student_panel", (118, 519, 915, 650), "Blue GAME SETUP title board with controller icon."),
        ("setup_topic_caption", "student_panel", (120, 650, 905, 748), "Cream GAME STYLE/GRAMMAR TOPIC caption; baked text."),
        ("setup_mode_caption", "student_panel", (901, 650, 1552, 748), "Cream GAME MODE/UI PREVIEW caption; UI PREVIEW baked."),
        ("setup_difficulty_caption", "student_panel", (119, 747, 1550, 839), "Cream DIFFICULTY caption; baked text."),
        ("setup_required_caption", "student_panel", (119, 839, 1552, 938), "Blue REQUIRED Student ID/Name/Grade&Section... caption; baked text."),
        ("icon_player", "student_controls", (34, 627, 180, 779), "Standalone orange student/person square icon."),
        ("icon_clipboard", "student_controls", (193, 624, 333, 773), "Standalone blue clipboard icon."),
        ("icon_graduation", "student_controls", (347, 623, 514, 772), "Standalone graduation cap icon."),
        ("icon_gamepad", "student_controls", (513, 624, 694, 781), "Standalone controller icon; check nearby rays."),
        ("icon_book", "student_controls", (699, 626, 866, 783), "Standalone open-book icon.")
    ],
    "shared": [
        ("classroom_bg", "shared_classroom", (0, 0, 1672, 941),
         "Standalone clean classroom illustration from SETTINGS source, not a flattened UI screenshot; board space for two columns.")
    ],
}

# Source-sheet neighboring accents sometimes overlap the desired rectangle.
# Select ORIGINAL ALPHA connected components by their precise source bounding
# boxes instead of painting away approximated shapes, preserving anti-aliasing.
# Bounding boxes here use source xywh from a thresholded-alpha analysis.
ISOLATE_COMPONENTS: dict[str, list[tuple[int, int, int, int]]] = {
    "sticker_today": [(111, 144, 451, 327), (63, 189, 58, 56), (39, 262, 66, 40),
                      (553, 339, 71, 44), (540, 393, 60, 62)],
    "sticker_soft": [(669, 151, 426, 323), (632, 158, 60, 57), (611, 225, 66, 39),
                     (1092, 339, 72, 41), (1079, 389, 61, 62)],
    "sticker_book": [(1483, 389, 127, 101)],
    "sticker_book_green": [(1495, 489, 122, 97)],
}


def isolate_source_components(img: Image.Image, bboxes: list[tuple[int, int, int, int]]) -> Image.Image:
    import cv2
    import numpy as np
    from PIL import Image

    pixels = np.asarray(img).copy()
    mask = (pixels[:, :, 3] > 24).astype(np.uint8)
    total, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    selection = np.zeros(mask.shape, dtype=np.uint8)
    for bbox in bboxes:
        matches = [
            i for i in range(1, total)
            if all(abs(int(stats[i, j]) - bbox[j]) <= 3 for j in range(4))
        ]
        if len(matches) != 1:
            raise ValueError(f"Cannot uniquely find exact alpha island {bbox}, found {matches}")
        selection[labels == matches[0]] = 1
    # Restore the original low-alpha antialiasing around each island.
    selection = cv2.dilate(selection, np.ones((3, 3), dtype=np.uint8), iterations=1)
    pixels[:, :, 3] = pixels[:, :, 3] * selection
    return Image.fromarray(pixels, "RGBA")


def extract(folder: str, source_root: Path) -> list[dict]:
    from PIL import Image

    dest = ASSET_ROOT / folder
    dest.mkdir(parents=True, exist_ok=True)
    cache: dict[str, Image.Image] = {}
    report: list[dict] = []
    for name, source_key, box, comment in SPECS[folder]:
        source_dir, source_file = SOURCES[source_key]
        source = source_root / source_dir / source_file
        if not source.is_file():
            raise FileNotFoundError(str(source))
        if source_key not in cache:
            cache[source_key] = Image.open(source).convert("RGBA")
        img = cache[source_key]
        if not (0 <= box[0] < box[2] <= img.width and 0 <= box[1] < box[3] <= img.height):
            raise ValueError(f"Invalid crop for {folder}/{name}: {box}")
        isolation = ISOLATE_COMPONENTS.get(name) if folder == "main" else None
        cropped = (isolate_source_components(img, isolation) if isolation else img).crop(box)
        alpha = cropped.getchannel("A")
        if alpha.getextrema()[0] == 255 and folder != "shared":
            raise ValueError(f"Cannot export opaque atlas crop as standalone: {folder}/{name}")
        dst = dest / f"{name}.png"
        cropped.save(dst, optimize=True)
        report.append({
            "target": f"res://ui/redesign/assets/{folder}/{name}.png",
            "source": source.relative_to(source_root).as_posix(),
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "crop_xyxy": list(box), "size": [cropped.width, cropped.height],
            "bytes": dst.stat().st_size, "alpha_extrema": list(alpha.getextrema()),
            "nontransparent_bbox_local": list(alpha.getbbox()) if alpha.getbbox() else None,
            "notes": comment, "review": "visual acceptance needed",
            "isolated_source_alpha_bboxes_xywh": [list(v) for v in isolation] if isolation else None,
        })
        print(f"CREATED {folder}/{dst.name} {cropped.width}x{cropped.height} {dst.stat().st_size}B alpha={alpha.getextrema()}")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-dir", type=Path, metavar="DIRECTORY",
        help="Parent directory containing MAIN/, STUDENT GAME SETUP/, SETTINGS/. "
             "Overrides KILOS_GRAMMAR_SOURCE_DIR and ~/Downloads.",
    )
    parser.add_argument(
        "folders", nargs="*", choices=tuple(SPECS),
        help="Asset sets to extract (default: main student).",
    )
    args = parser.parse_args()
    source_root = Path(
        args.source_dir or os.environ.get("KILOS_GRAMMAR_SOURCE_DIR") or Path.home() / "Downloads"
    ).expanduser().resolve()
    if not source_root.is_dir():
        parser.error(f"Source directory not found: {source_root}. Supply --source-dir.")
    which = args.folders or ["main", "student"]
    manifest_file = ASSET_ROOT / "asset_manifest.json"
    old = json.loads(manifest_file.read_text(encoding="utf-8")) if manifest_file.exists() else {}
    for folder in which:
        old[folder] = extract(folder, source_root)
    manifest_file.write_text(json.dumps(old, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("MANIFEST", manifest_file)
