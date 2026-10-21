"""Extract individual, draggable Godot assets from the supplied new leaderboard sheet.

The source is RGB with a baked grey checkerboard. Only the exterior
connected near-grey checkerboard is made transparent; non-neutral illustration
pixels are preserved. All source images and crop coordinates are retained.
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Components" / "Leaderboard"
INPUT = ASSETS / "new_user_reference.png"

# Source image is 1536 × 1024 pixels.
CROPS = {
    "new_title": (14, 407, 754, 551),
    "new_wood_board": (624, 129, 1359, 439),
    "new_back_button": (764, 443, 1007, 543),
    "new_filters_label": (27, 551, 159, 631),
    "new_table_header": (25, 633, 1116, 699),
    "new_table_body": (25, 698, 1117, 992),
    "new_download_green": (1140, 551, 1507, 644),
    "new_download_blue": (1331, 644, 1522, 714),
    "new_pot": (1356, 2, 1517, 218),
    "new_star": (1409, 211, 1494, 315),
    "new_books": (1356, 300, 1527, 431),
    "new_leaves_left": (1117, 452, 1238, 532),
    "new_leaves_right": (1228, 440, 1379, 539),
    "new_cap": (1374, 437, 1520, 544),
    "new_cat_paw": (1211, 902, 1292, 997),
    "new_open_book": (1280, 890, 1405, 995),
}


def remove_checker(image: Image.Image) -> Image.Image:
    """Remove only external checker pixels, retaining internal light art."""
    rgb = np.asarray(image.convert("RGB")).copy()
    # Neutral gray/white checker pattern has nearly equal color channels;
    # warm cream fills, dark outlines and saturated artwork are not neutral.
    maximum = rgb.max(axis=2).astype(np.int16)
    minimum = rgb.min(axis=2).astype(np.int16)
    near_gray = (maximum - minimum <= 13) & (minimum >= 177)
    near_gray_u8 = np.where(near_gray, 255, 0).astype(np.uint8)

    # Only those near-gray areas connected to the crop *outside* are removed.
    count, labels = cv2.connectedComponents(near_gray_u8, connectivity=8)
    perimeter = np.concatenate(
        (labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1])
    )
    touching = set(np.unique(perimeter).tolist()) - {0}
    outside = np.isin(labels, list(touching))
    # Checker antialiasing at foreground silhouettes may be colored, so
    # alpha feather of one pixel reduces seams without repainting source.
    foreground = (~outside).astype(np.uint8) * 255
    alpha = cv2.GaussianBlur(foreground, (3, 3), 0.55)
    rgba = np.dstack([rgb, alpha])
    return Image.fromarray(rgba, "RGBA")


def run() -> None:
    with Image.open(INPUT) as im:
        sheet = im.convert("RGB")
        if sheet.size != (1536, 1024):
            raise ValueError(f"Reference dimensions changed: {sheet.size}")
        background = sheet.crop((19, 9, 615, 408))
        background.save(ASSETS / "new_background.png", optimize=True)
        manifest = {}
        for name, box in CROPS.items():
            art = remove_checker(sheet.crop(box))
            # This sheet places the wood panel and duplicate title artwork
            # directly against (and partially over) one another. The small
            # cut-outs below remove ONLY pieces of the adjacent sprite that
            # otherwise leak into Godot when the art is moved independently.
            if name == "new_title":
                pixels = np.asarray(art).copy()
                pixels[:19, 630:, 3] = 0
                art = Image.fromarray(pixels, "RGBA")
            if name == "new_wood_board":
                pixels = np.asarray(art).copy()
                pixels[290:, :129, 3] = 0
                art = Image.fromarray(pixels, "RGBA")
            art.save(ASSETS / f"{name}.png", optimize=True)
            manifest[name] = {
                "source_bounds": box,
                "size": art.size,
                "file": f"{name}.png",
            }
    (ASSETS / "new_reference_manifest.json").write_text(
        json.dumps(
            {"original_source": INPUT.name, "original_size": (1536, 1024),
             "background": "new_background.png",
             "checker_removed_from_sprite_exteriors": True,
             "components": manifest},
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Created {len(CROPS)} independent assets, 1 changeable background")


if __name__ == "__main__":
    run()
