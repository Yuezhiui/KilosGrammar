"""Cut the user's leaderboard components sheet into individually named PNGs.

Input artwork is a supplied RGBA atlas. This deliberately does *not*
regenerate or restyle any images; it preserves original pixels/alpha.
The files are stored alongside KilosGrammar's existing root Components.

Usage (project root, Windows):
  python tools/extract_leaderboard_components.py
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image


PROJECT = Path(__file__).resolve().parent.parent
SOURCES = Path.home() / "Downloads"
ATLAS = SOURCES / "components.png"
REFERENCE = SOURCES / "Leaderboard new.png"
DESTINATION = PROJECT / "Components" / "Leaderboard"

# Source sheet coordinates in its own native 1536 x 1024 pixel space.
# Several composite sprites intentionally include their original decorative
# leaves/soft shadows rather than cutting them into separate artwork.
CROPS: dict[str, tuple[int, int, int, int]] = {
    "title_cat_wood": (101, 4, 878, 192),
    "back_button": (34, 181, 251, 272),
    "filters_bar": (275, 209, 1301, 290),
    "table_header": (65, 292, 1292, 359),
    "table_wood_frame": (22, 357, 1325, 749),
    "csv_button_green": (560, 727, 975, 822),
    "dropdown_dark": (1322, 256, 1508, 314),
    "dropdown_cream": (1323, 317, 1509, 377),
    "dropdown_white": (1323, 375, 1509, 436),
    "button_green": (1324, 437, 1507, 497),
    "button_blue": (1324, 495, 1507, 557),
    "button_purple": (1324, 555, 1507, 616),
    "button_red": (1324, 614, 1507, 674),
    "cat_icon": (885, 65, 1091, 201),
    "grad_cap": (1081, 75, 1235, 195),
    "books_stack": (1231, 69, 1375, 192),
    "star_large": (1378, 89, 1465, 166),
    "star_small": (1462, 154, 1513, 212),
    "table_empty_panel": (729, 825, 1454, 1001),
    "classroom_background_crop": (35, 759, 563, 1019),
    "checkbox_states": (1329, 686, 1457, 745),
    "radio_states": (1329, 744, 1457, 811),
    "vertical_scrollbar": (1467, 690, 1506, 918),
}


def main() -> None:
    atlas_path = ATLAS if ATLAS.is_file() else DESTINATION / "source_components_sheet.png"
    reference_path = REFERENCE if REFERENCE.is_file() else DESTINATION / "leaderboard_reference_screen.png"
    if not atlas_path.is_file() or not reference_path.is_file():
        raise SystemExit(f"Missing input reference: {ATLAS} or {REFERENCE}")
    DESTINATION.mkdir(parents=True, exist_ok=True)
    with Image.open(atlas_path) as original:
        source = original.convert("RGBA")
        if source.size != (1536, 1024):
            raise SystemExit(f"Unexpected components source size: {source.size}")
        manifest = {}
        for name, bounds in CROPS.items():
            cropped = source.crop(bounds)
            filepath = DESTINATION / f"{name}.png"
            cropped.save(filepath, "PNG", optimize=True)
            manifest[name] = {"file": filepath.name, "bounds": list(bounds),
                              "size": list(cropped.size)}
    # Keep an original editable atlas and the user's exact screen reference.
    if atlas_path != DESTINATION / "source_components_sheet.png":
        shutil.copy2(atlas_path, DESTINATION / "source_components_sheet.png")
    if reference_path != DESTINATION / "leaderboard_reference_screen.png":
        shutil.copy2(reference_path, DESTINATION / "leaderboard_reference_screen.png")
    (DESTINATION / "source_manifest.json").write_text(
        json.dumps({"source": "components.png", "native_size": [1536, 1024],
                    "art_original": True, "components": manifest}, indent=2),
        encoding="utf-8"
    )
    print(f"Saved {len(CROPS)} original-art sprites in {DESTINATION}")


if __name__ == "__main__":
    main()
