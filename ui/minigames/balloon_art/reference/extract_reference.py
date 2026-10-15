"""Extract alpha-ready Balloon Popping artwork from the user's six RGB sheets.

Run from project root:
    py ui/minigames/balloon_art/reference/extract_reference.py
    py ui/minigames/balloon_art/reference/extract_reference.py "D:/art/my_sheets"

This script reads the user's original images. It writes ONLY to this folder.
It deliberately preserves baked static 'BALLOON POPPING' and 'SCORE' lettering;
all changing scores, timer numbers, grammar prompts, and balloon words stay blank.
"""

from pathlib import Path
from collections import deque
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

DEST = Path(__file__).resolve().parent
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / "Downloads" / "New folder (2)"
FILES = {
    "hud": "775303c9-5f98-418b-9807-915a2cc2b3a6.png",
    "objective": "e8de9655-618a-4fa5-b7a4-9a9bf2dfbfb8.png",
    "cannon": "885144b6-bce2-47a3-9440-81bd2fe5f681.png",
    "balloons": "a5f50af6-6dce-4087-8542-dc2271e7aec6.png",
}


def crop(group, bounds):
    with Image.open(SOURCE / FILES[group]) as source:
        return source.convert("RGB").crop(bounds)


def flood_component(mask: Image.Image, target):
    # Recolor only the chosen connected foreground cluster.
    probe = mask.copy()
    ImageDraw.floodfill(probe, target, 128, thresh=0)
    return Image.fromarray((np.asarray(probe) == 128).astype("uint8") * 255, "L")


def fill_internal_holes(mask: Image.Image):
    # Fills the cream prompt center and white marquee letters without losing
    # the detailed outer silhouette or the glossy highlights.
    work = Image.fromarray(255 - np.asarray(mask, dtype=np.uint8), "L").copy()
    ImageDraw.floodfill(work, (5, 5), 128, thresh=0)
    inside = np.asarray(work) != 128
    return Image.fromarray(inside.astype("uint8") * 255, "L")


def crop_alpha(rgb, alpha, padding=3):
    region = alpha.getbbox()
    if region is None:
        raise ValueError("Empty mask")
    x0, y0, x1, y1 = region
    region = (max(0, x0-padding), max(0, y0-padding),
              min(rgb.width, x1+padding), min(rgb.height, y1+padding))
    out = rgb.crop(region).convert("RGBA")
    out.putalpha(alpha.crop(region))
    return out


def chroma_sprite(group, bounds, seed, kind, name, rgb_override=None):
    rgb = rgb_override if rgb_override is not None else crop(group, bounds)
    a = np.asarray(rgb).astype(np.int16)
    bright = a.max(axis=2)
    dark = a.min(axis=2)
    saturation = bright - dark
    if kind == "cream":
        foreground = ((saturation > 43) & (dark < 229)) | (dark < 115)
    elif kind == "dark":
        foreground = (bright > 91) | ((saturation > 47) & (bright > 67))
    else:
        raise ValueError(kind)

    base = Image.fromarray(foreground.astype("uint8") * 255, "L")
    # Unite small anti-aliased gaps in bulb strings and gold line-work.
    clustered = base.filter(ImageFilter.MaxFilter(5))
    component = flood_component(clustered, seed)
    component = fill_internal_holes(component)
    component = component.filter(ImageFilter.MinFilter(5))
    # Restores a natural 1-pixel edge from the unaltered RGB art.
    alpha = component.filter(ImageFilter.GaussianBlur(0.85))
    result = crop_alpha(rgb, alpha)
    result.save(DEST / name)
    print(name, result.size, "alpha", result.getchannel("A").getextrema())
    return result


def score_remove_number(rgb):
    # Keep the baked 'SCORE' heading and all bulbs; erase only dynamic 0.
    # The inner off-white textbox is smooth; sample unaffected pixels beside
    # the digit, interpolate a subtle horizontal cream gradient, and feather.
    canvas = rgb.convert("RGB")
    array = np.array(canvas).astype(np.float32)
    h, w = array.shape[:2]
    cx0, cx1, cy0, cy1 = 139, 257, 122, 211
    # sample 12 pixels to either side, horizontally interpolate across digit
    left = array[cy0:cy1, 120:134].mean(axis=1)
    right = array[cy0:cy1, 266:280].mean(axis=1)
    overlay = np.array(rgb).astype(np.float32)
    for x in range(cx0, cx1):
        t = (x - cx0) / max(cx1 - cx0 - 1, 1)
        overlay[cy0:cy1, x] = left * (1-t) + right * t
    fill = Image.fromarray(np.clip(overlay, 0, 255).astype("uint8"), "RGB")
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rectangle((cx0 + 2, cy0, cx1 - 2, cy1 - 2), fill=255)
    # All dark 0 pixels are 10+ pixels inside the fully covered region.
    mask = mask.filter(ImageFilter.GaussianBlur(2.5))
    return Image.composite(fill, canvas, mask)


def clean_baked_question(rgb):
    # This is the composite one-line BALLOON POPPING banner seen in reference
    # Image 2. The 2-line example question must remain user-editable in Godot.
    # Paint a soft cream gradient using untouched margins on both sides.
    original = np.asarray(rgb).astype(np.float32)
    patched = original.copy()
    x0, x1, y0, y1 = 102, 582, 162, 250
    left = original[y0:y1, 87:99].mean(axis=1)
    right = original[y0:y1, 586:602].mean(axis=1)
    for x in range(x0, x1):
        t = (x - x0) / (x1 - x0)
        patched[y0:y1, x] = left * (1-t) + right * t
    paint = Image.fromarray(np.clip(patched, 0, 255).astype("uint8"), "RGB")
    mask = Image.new("L", rgb.size)
    ImageDraw.Draw(mask).rectangle((x0+2, y0+1, x1-3, y1-2), fill=255)
    # The old example glyphs span x~126..562/y~174..239; the entire region
    # receives 100% new cream color, with feathering only at its distant edge.
    return Image.composite(paint, rgb, mask.filter(ImageFilter.GaussianBlur(2.2)))


def extract_objective():
    bounds = (995, 625, 1665, 930)
    cleaned = clean_baked_question(crop("objective", bounds))
    return chroma_sprite("objective", bounds, (183, 115), "cream",
                         "objective_panel.png", rgb_override=cleaned)


def extract_score():
    rgb = score_remove_number(crop("hud", (1090, 190, 1490, 490)))
    a = np.asarray(rgb).astype(np.int16)
    maxc, minc = a.max(axis=2), a.min(axis=2)
    fg = ((maxc - minc > 45) & (minc < 230)) | (minc < 100)
    base = Image.fromarray((fg.astype("uint8") * 255), "L")
    joined = base.filter(ImageFilter.MaxFilter(5))
    selected = flood_component(joined, (60, 100))
    filled = fill_internal_holes(selected).filter(ImageFilter.MinFilter(5))
    alpha = filled.filter(ImageFilter.GaussianBlur(0.9))
    result = crop_alpha(rgb, alpha)
    result.save(DEST / "score_plaque_blank.png")
    print("score_plaque_blank.png", result.size, "alpha", result.getchannel("A").getextrema())
    return result


def contact_sheet(assets):
    names = list(assets)
    columns = 2
    cellw, cellh = 760, 420
    board = Image.new("RGB", (columns * cellw, ((len(names)+1)//2)*cellh), (39, 45, 61))
    draw = ImageDraw.Draw(board)
    for i, key in enumerate(names):
        asset = assets[key]
        x0, y0 = (i % columns)*cellw, (i//columns)*cellh
        draw.rectangle((x0+8, y0+8, x0+cellw-8, y0+cellh-8), fill=(233, 234, 239))
        # Show true transparency against checkerboard squares.
        for yy in range(y0+36, y0+cellh-30, 24):
            for xx in range(x0+20, x0+cellw-20, 24):
                if ((xx-x0)//24 + (yy-y0)//24)%2 == 0:
                    draw.rectangle((xx, yy, xx+23, yy+23), fill=(193, 197, 203))
        scaled = asset.copy()
        scaled.thumbnail((cellw-40, cellh-94), Image.Resampling.LANCZOS)
        board.paste(scaled, (x0+(cellw-scaled.width)//2,
                             y0+48+(cellh-94-scaled.height)//2), scaled)
        draw.text((x0+20, y0+13), f"{key}   {asset.width} x {asset.height}", fill=(18, 26, 38))
    board.save(DEST / "contact_sheet.png")
    print("contact_sheet.png", board.size)


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    assets = {}
    assets["title_marquee"] = chroma_sprite(
        "hud", (10, 140, 685, 505), (84, 200),
        "cream", "title_marquee.png")
    assets["objective_panel"] = extract_objective()
    assets["prompt_blank"] = chroma_sprite(
        "hud", (575, 600, 1100, 875), (58, 115),
        "cream", "prompt_blank.png")
    assets["score_plaque_blank"] = extract_score()
    assets["cannon_front"] = chroma_sprite(
        "cannon", (15, 110, 405, 570), (180, 230),
        "cream", "cannon_front.png")
    for color, bounds, seed in [
        ("purple", (75, 106, 424, 596), (160, 150)),
        ("green", (477, 106, 815, 596), (160, 150)),
        ("blue", (857, 106, 1204, 596), (160, 150)),
    ]:
        assets[f"balloon_{color}"] = chroma_sprite(
            "balloons", bounds, seed, "dark", f"balloon_{color}.png")
    contact_sheet(assets)


if __name__ == "__main__":
    main()
