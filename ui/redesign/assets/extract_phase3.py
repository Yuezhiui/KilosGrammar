"""Extract original, separate Godot PNG components for Game Over/Tutorial/Settings.

Run manually (never from game runtime):
    python ui/redesign/assets/extract_phase3.py
    python ui/redesign/assets/extract_phase3.py --source-dir "C:/path/to/Downloads"

Requires Python, Pillow, numpy and OpenCV only at extraction time. Original art
is read-only. Existing MAIN/STUDENT Phase 2 outputs are never touched. Each
output is a real source crop, with the original alpha and colors retained.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


HERE = Path(__file__).resolve().parent
ART_ROOT = HERE.parents[2] / "Components"
ART_FOLDERS = {
    "game_over": "Results/Redesign",
    "tutorial": "Tutorial/Redesign",
    "settings": "Settings/Redesign",
}

# Component rank is the descending alpha-connected area (threshold 45/255).
# This is more robust than clipping rectangles from a flattened screen design:
# overlapping decorations in neighboring atlas cells remain independent.
SOURCES = {
    "go_decors": ("GAME OVER", "21c38a89-e765-4a40-9347-c0e9d8bdf7f1.png"),
    "go_icons": ("GAME OVER", "58bfaf29-c8d1-4dea-9702-1948b7f2d381.png"),
    "go_panels": ("GAME OVER", "bd415751-73f7-4488-a851-e7da2d71950d.png"),
    "go_buttons": ("GAME OVER", "de37ba98-8e4b-4239-9114-64ce39b11daa.png"),
    "tutorial_steps": ("TUTORIAL", "0e1ae538-e3f3-4baa-afb2-21aa6e8d2e5a.png"),
    "tutorial_bg": ("TUTORIAL", "4080601d-0d7a-47b0-b108-a1e534f44f56.png"),
    "tutorial_buttons": ("TUTORIAL", "7e4b73c1-10d5-4fe1-8f50-8da3ae32cc21.png"),
    "tutorial_panel": ("TUTORIAL", "a8056136-4d23-4878-8457-13f003c21a43.png"),
    "tutorial_icons": ("TUTORIAL", "c9345c38-0591-44dd-b67c-63f0b8eed9ae.png"),
    "settings_title": ("SETTINGS", "0e12567d-88f7-49e6-9bce-06cc27a6d16b.png"),
    "settings_sliders": ("SETTINGS", "1d297c55-4e6b-4caf-b705-5228ef4e32df.png"),
    "settings_frames": ("SETTINGS", "66f6d386-a694-4ac8-9813-525cf4ed144c.png"),
    "settings_decor": ("SETTINGS", "79097ef5-f37d-4e23-9c4d-ecef0ee3a164.png"),
    "settings_buttons": ("SETTINGS", "c6745883-d3fb-4d7f-8d95-d977f1f6d2f3.png"),
}

# (name, source key, connected-component rank, role, baked text?, extraction mode)
# "component" selects only the original pixel island, retaining its soft edge.
# "box" retains everything originally inside that one large framed source area.
# Static sample strips explicitly marked below are not live sliders or controls.
SPECS = {
    "game_over": [
        ("bg_teal_clean", "go_decors", 2, "Teal cloud/star backdrop", False, "box"),
        ("bg_teal_decorated", "go_decors", 1, "Decorated teal results backdrop", False, "box"),
        ("panel_results_header", "go_panels", 1, "Blank cream results header", False, "component"),
        ("panel_results_side", "go_panels", 6, "Blank cream side information panel", False, "component"),
        ("panel_student", "go_panels", 2, "Student summary card with baked sample labels", True, "component"),
        ("panel_round", "go_panels", 3, "Round summary card with baked sample labels", True, "component"),
        ("panel_student_blank", "go_panels", 4, "Editable student information card", False, "component"),
        ("panel_round_blank", "go_panels", 5, "Editable round information card", False, "component"),
        ("panel_student_rows", "go_panels", 9, "Separate Student ID/Name/Grade rows", True, "component"),
        ("panel_round_rows", "go_panels", 8, "Separate topic/mode/difficulty rows", True, "component"),
        ("score_footer", "go_panels", 7, "FINAL SCORE bar with balloons", True, "component"),
        ("button_retry", "go_buttons", 5, "Purple RETRY button", True, "component"),
        ("button_retry_hover", "go_buttons", 2, "Purple RETRY hover glow", True, "component"),
        ("button_retry_disabled", "go_buttons", 7, "Purple RETRY dimmed", True, "component"),
        ("button_main_menu", "go_buttons", 3, "Blue MAIN MENU button", True, "component"),
        ("button_main_menu_hover", "go_buttons", 1, "Blue MAIN MENU hover glow", True, "component"),
        ("button_main_menu_disabled", "go_buttons", 6, "Blue MAIN MENU dimmed", True, "component"),
        ("button_blank_purple", "go_buttons", 11, "Blank purple rounded button", False, "component"),
        ("button_blank_blue", "go_buttons", 8, "Blank blue rounded button", False, "component"),
        ("icon_star_large", "go_panels", 11, "Golden star", False, "component"),
        ("icon_star_small", "go_panels", 13, "Small golden star", False, "component"),
        ("icon_star_green", "go_panels", 12, "Green-backed star", False, "component"),
        ("decor_books_red", "go_decors", 3, "Red open-book illustration", False, "component"),
        ("decor_books_blue", "go_decors", 5, "Blue open-book illustration", False, "component"),
        ("decor_books_stack", "go_decors", 6, "Stack of books", False, "component"),
        ("decor_clouds", "go_decors", 7, "Blue and white cloud cluster", False, "component"),
        ("decor_balloons", "go_decors", 20, "Red and blue balloons", False, "component"),
        ("decor_word_today", "go_decors", 14, "TODAY word tile", True, "component"),
        ("decor_word_him", "go_decors", 19, "HIM word tile", True, "component"),
        ("decor_word_often", "go_decors", 12, "OFTEN word tile", True, "component"),
        ("decor_word_learn", "go_decors", 11, "LEARN word tile", True, "component"),
        ("decor_word_play", "go_decors", 13, "PLAY word tile", True, "component"),
        ("icon_grad_cap", "go_icons", 4, "Graduation cap", False, "component"),
        ("icon_target", "go_icons", 7, "Target and arrow", False, "component"),
        ("icon_student_id", "go_icons", 9, "Student ID card", False, "component"),
        ("icon_avatar", "go_icons", 11, "Purple student avatar", False, "component"),
        ("icon_controller", "go_icons", 8, "Game controller", False, "component"),
        ("icon_gear", "go_icons", 13, "Gear", False, "component"),
        ("icon_chart", "go_icons", 15, "Bar chart", False, "component"),
    ],
    "tutorial": [
        ("bg_classroom", "tutorial_bg", 0, "Standalone illustrated classroom backdrop", False, "full"),
        ("path_title", "tutorial_panel", 3, "TUTORIAL PATH banner", True, "component"),
        ("title_whole_body", "tutorial_panel", 2, "LEARN WITH YOUR WHOLE BODY! title", True, "component"),
        ("panel_blank", "tutorial_panel", 1, "Empty cream-bordered information card", False, "component"),
        ("steps_three", "tutorial_steps", 1, "Three camera/calibrate/practice cards connected by arrows", True, "component"),
        ("camera_advisory", "tutorial_steps", 2, "Camera/body tracking UI preview disclaimer", True, "component"),
        ("button_guided", "tutorial_buttons", 2, "START GUIDED TUTORIAL", True, "component"),
        ("button_movement", "tutorial_buttons", 1, "MOVEMENT PRACTICE", True, "component"),
        ("button_grammar", "tutorial_buttons", 3, "GRAMMAR GUIDE", True, "component"),
        ("button_back", "tutorial_buttons", 4, "BACK TO MAIN", True, "component"),
        ("icon_cat", "tutorial_panel", 4, "Black cat mascot", False, "component"),
        ("icon_cap", "tutorial_icons", 3, "Graduation cap", False, "component"),
        ("icon_books", "tutorial_icons", 2, "Stack of books", False, "component"),
        ("icon_camera", "tutorial_icons", 6, "Webcam eye", False, "component"),
        ("icon_calibration", "tutorial_icons", 4, "Body calibration", False, "component"),
        ("icon_controller", "tutorial_icons", 5, "Game controller", False, "component"),
        ("icon_play", "tutorial_icons", 11, "Play icon", False, "component"),
        ("icon_movement", "tutorial_icons", 10, "Movement icon", False, "component"),
        ("icon_guide", "tutorial_icons", 9, "Book guide", False, "component"),
        ("icon_home", "tutorial_icons", 8, "Home icon", False, "component"),
        ("icon_star", "tutorial_icons", 13, "Large gold star", False, "component"),
        ("decor_leaf", "tutorial_icons", 18, "Glossy green leaf", False, "component"),
        ("decor_leaves", "tutorial_icons", 14, "Paired green leaves", False, "component"),
        ("decor_pencil", "tutorial_icons", 7, "Blue and yellow pencil", False, "component"),
    ],
    "settings": [
        ("title_settings", "settings_title", 1, "SETTINGS wooden title with cat and leaves", True, "component"),
        ("panel_main", "settings_frames", 1, "Large blank cream settings panel", False, "component"),
        ("panel_sidebar", "settings_frames", 2, "Tall narrow cream sidebar frame", False, "component"),
        ("field_row_cream", "settings_frames", 3, "Wide empty white/cream field", False, "component"),
        ("field_row_blue", "settings_frames", 4, "Wide empty pale-blue field", False, "component"),
        ("field_row_white", "settings_frames", 5, "Wide empty white field", False, "component"),
        ("field_row_header", "settings_frames", 6, "Wide blue rounded header strip", False, "component"),
        ("field_card_blue", "settings_frames", 7, "Blue empty settings card", False, "component"),
        ("field_card_cream", "settings_frames", 8, "Cream empty settings card", False, "component"),
        ("button_home", "settings_buttons", 2, "Purple HOME button", True, "component"),
        ("tab_settings_green", "settings_buttons", 10, "Green SETTINGS tab", True, "component"),
        ("tab_controls_green", "settings_buttons", 11, "Green CONTROLS tab", True, "component"),
        ("tab_camera_green", "settings_buttons", 9, "Green CAMERA tab", True, "component"),
        ("tab_settings_cream", "settings_buttons", 8, "Cream SETTINGS tab", True, "component"),
        ("tab_controls_cream", "settings_buttons", 7, "Cream CONTROLS tab", True, "component"),
        ("tab_camera_cream", "settings_buttons", 6, "Cream CAMERA tab", True, "component"),
        ("button_blank_green", "settings_buttons", 5, "Unlabeled green rounded button", False, "component"),
        ("button_blank_purple", "settings_buttons", 4, "Unlabeled purple rounded button", False, "component"),
        ("button_blank_cream", "settings_buttons", 3, "Unlabeled cream rounded button", False, "component"),
        ("volume_preview_empty", "settings_sliders", 3, "Volume track sample empty (100% text baked)", True, "component"),
        ("volume_preview_mid", "settings_sliders", 1, "Volume track sample partial (100% text baked)", True, "component"),
        ("volume_preview_full", "settings_sliders", 2, "Volume track sample full (100% text baked)", True, "component"),
        ("toggle_on_sample", "settings_sliders", 10, "ON toggle sample; use native CheckButton to interact", True, "component"),
        ("toggle_off_sample", "settings_sliders", 9, "OFF toggle sample; use native CheckButton to interact", True, "component"),
        ("icon_settings", "settings_sliders", 17, "Settings gear icon", False, "component"),
        ("icon_controls", "settings_sliders", 18, "Controller icon", False, "component"),
        ("icon_camera", "settings_sliders", 13, "Camera icon", False, "component"),
        ("icon_sound", "settings_sliders", 15, "Speaker icon", False, "component"),
        ("icon_music", "settings_sliders", 16, "Music note icon", False, "component"),
        ("icon_star", "settings_sliders", 12, "Star icon", False, "component"),
        ("icon_muted", "settings_sliders", 19, "Muted speaker icon", False, "component"),
        ("icon_screen", "settings_sliders", 11, "Screen icon", False, "component"),
        ("icon_fullscreen", "settings_sliders", 14, "Fullscreen arrows icon", False, "component"),
        ("icon_cat", "settings_title", 2, "Black cat mascot", False, "component"),
        ("icon_cap", "settings_title", 3, "Graduation cap", False, "component"),
        ("decor_leaf_cluster", "settings_title", 4, "Green leaves cluster", False, "component"),
        ("decor_books_purple", "settings_decor", 1, "Purple book stack", False, "component"),
        ("decor_books_blue", "settings_decor", 2, "Blue book stack", False, "component"),
        ("decor_books_red", "settings_decor", 3, "Red book stack", False, "component"),
        ("decor_books_standing", "settings_decor", 5, "Standing books", False, "component"),
        ("decor_plant", "settings_decor", 6, "Potted plant", False, "component"),
        ("decor_green_leaves", "settings_decor", 15, "Leaf decoration", False, "component"),
    ],
}


def component_rank_masks(source: Image.Image) -> list[tuple[int, tuple[int, int, int, int], np.ndarray]]:
    rgba = np.asarray(source.convert("RGBA"))
    _, labels, stats, _ = cv2.connectedComponentsWithStats(
        (rgba[:, :, 3] > 45).astype("uint8"), 8
    )
    ranked = sorted(
        [(int(s[4]), tuple(map(int, s[:4])), i) for i, s in enumerate(stats) if i and s[4] > 100],
        key=lambda item: item[0], reverse=True
    )
    return [(area, bbox, labels == label_index) for area, bbox, label_index in ranked]


def extract(source_dir: Path, overwrite: bool = False) -> dict[str, list[dict]]:
    source_cache: dict[str, Image.Image] = {}
    regions: dict[str, list] = {}
    hashed: dict[str, str] = {}
    manifest: dict[str, list[dict]] = {}
    for category, specifications in SPECS.items():
        output_folder = ART_ROOT / ART_FOLDERS[category]
        output_folder.mkdir(parents=True, exist_ok=True)
        records: list[dict] = []
        for name, key, rank, meaning, baked, mode in specifications:
            if mode == "skip":
                continue
            folder, file_name = SOURCES[key]
            input_path = source_dir / folder / file_name
            if not input_path.is_file():
                raise FileNotFoundError(input_path)
            if key not in source_cache:
                with Image.open(input_path) as loaded:
                    loaded.load()
                    source_cache[key] = loaded.convert("RGBA")
                regions[key] = component_rank_masks(source_cache[key])
                hashed[key] = hashlib.sha256(input_path.read_bytes()).hexdigest()
            src = source_cache[key]
            if mode == "full":
                bbox = (0, 0, src.width, src.height)
                cut = src.copy()
                selected_area = src.width * src.height
            else:
                if rank <= 0 or rank > len(regions[key]):
                    raise ValueError(f"{key} component rank {rank} not available")
                selected_area, (x, y, w, h), component = regions[key][rank - 1]
                pad = 6
                bbox = (max(0, x - pad), max(0, y - pad),
                        min(src.width, x + w + pad), min(src.height, y + h + pad))
                cut = src.crop(bbox)
                if mode == "component":
                    # Restore 1px of low-alpha antialiasing at edge.
                    retained = cv2.dilate(component.astype("uint8"), np.ones((3, 3), np.uint8))
                    selected = retained[bbox[1]:bbox[3], bbox[0]:bbox[2]]
                    pixels = np.array(cut)
                    pixels[:, :, 3] *= selected
                    cut = Image.fromarray(pixels, "RGBA")
            alpha = cut.getchannel("A")
            if mode != "full" and not alpha.getbbox():
                raise ValueError(f"Output {category}/{name} was empty")
            output = output_folder / f"{name}.png"
            raw = io.BytesIO()
            cut.save(raw, format="PNG", optimize=True)
            if output.exists() and output.read_bytes() != raw.getvalue() and not overwrite:
                raise FileExistsError(
                    f"{output} already exists with edits. Use --overwrite only after reviewing them."
                )
            if not output.exists() or output.read_bytes() != raw.getvalue():
                output.write_bytes(raw.getvalue())
            record = {
                "name": name,
                "path": f"res://Components/{ART_FOLDERS[category]}/{name}.png",
                "source": (Path(folder) / file_name).as_posix(),
                "source_sha256": hashed[key],
                "source_component_rank": rank if mode != "full" else None,
                "source_crop_xyxy": list(bbox),
                "extraction": mode,
                "meaning": meaning,
                "baked_text": baked,
                "size": [cut.width, cut.height],
                "alpha_extrema": list(alpha.getextrema()),
                "alpha_bbox": list(alpha.getbbox()) if alpha.getbbox() else None,
                "bytes": output.stat().st_size,
            }
            records.append(record)
            print(f"READY {category}/{name}.png {cut.width}x{cut.height}")
        manifest[category] = records
    out = HERE / "phase3_manifest.json"
    out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("MANIFEST", out)
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path,
                        help="Parent containing GAME OVER, TUTORIAL, SETTINGS")
    parser.add_argument("--overwrite", action="store_true",
                        help="Explicitly refresh existing source sprites after reviewing current work")
    args = parser.parse_args()
    root = Path(args.source_dir or os.environ.get("KILOS_GRAMMAR_SOURCE_DIR")
                or Path.home() / "Downloads").expanduser().resolve()
    if not root.is_dir():
        parser.error(f"Missing source directory {root}")
    extract(root, overwrite=args.overwrite)
