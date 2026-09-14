#!/usr/bin/env python3
"""Regenerates every file in assets/icon/export/ from the published mark.

R-32-410 in docs/32-design-language.md requires assets/icon/src/ to be the
single source for every icon the product ships, and R-32-422 requires a
change to the art to regenerate every export file, never a subset. This
script is that generator: it reads the two source rasters below and writes
every file in assets/icon/export/, with the composition named at each call
site so a reader can audit a pixel without re-deriving the formula.

Sources:
  - remote.svg: the untouched published path. remote.png is its raster
    companion at 1254 x 1254 and is already the brand's own tile
    composition (https://herdr.dev/assets/logo.png): the bust starts at
    20.3% from the left and 27.1% from the top and bleeds off the right and
    bottom edges. Every launcher, store and iOS export is this tile, scaled
    to its canvas, recoloured to MARK_HEX and composited on BG_HEX. Nothing
    is centred, shrunk or clipped; a platform mask crops the body.
  - android_notification.png: the near-white original silhouette for the
    unmasked Android status-bar glyph, R-32-420.
  - The background: the Ink ground BG_HEX with the ground grid of R-32-332
    drawn in GRID_HEX at GRID_CELLS per side, R-32-411. android_background.png
    is that ground rendered as a full-bleed raster; this script regenerates it.

Also written: export/brand/ram.png, the mark's true bounding box as a white
silhouette with alpha, 1024 px wide, for the app's in-chrome brand mark.

Run: python assets/icon/generate.py
Needs: Pillow (`pip install pillow`). No other dependency.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"
EXPORT = ROOT / "export"

BG_HEX = "#17171a"  # R-32-411: the Ink ground, `color.bg.base`.
GRID_HEX = "#202024"  # R-32-411: the Ink theme's `color.bg.grid`, painted as 1 px lines.
MARK_HEX = "#cba6f7"  # R-32-411: the Ink theme's spot colour; 8.8:1 against BG_HEX.
BG_RGB = tuple(int(BG_HEX[i : i + 2], 16) for i in (1, 3, 5))
GRID_RGB = tuple(int(GRID_HEX[i : i + 2], 16) for i in (1, 3, 5))
MARK_RGB = tuple(int(MARK_HEX[i : i + 2], 16) for i in (1, 3, 5))
TILE_MASTER = SRC / "remote.png"  # the published tile raster; alpha carries the shape.
STATUS_MASTER = SRC / "android_notification.png"  # original silhouette for status-bar use only.

# The published tile's geometry, R-32-413: bbox at alpha > 10 on the 1254 canvas, and the
# count of opaque pixels along its right and bottom edges (the bleed).
TILE_CANVAS = 1254
TILE_BBOX = (255, 340, 1253, 1253)
TILE_MIN_RIGHT_RUN = 700
TILE_MIN_BOTTOM_RUN = 450

# Android adaptive-icon densities: name -> px-per-dp scale. R-32-418.
ANDROID_DENSITIES = {
    "mdpi": 1.0,
    "hdpi": 1.5,
    "xhdpi": 2.0,
    "xxhdpi": 3.0,
    "xxxhdpi": 4.0,
}
ADAPTIVE_CANVAS_DP = 108
MASK_RADIUS_DP = 36  # the 72 dp circle every launcher mask at least shows.
STATUS_BAR_CANVAS_DP = 24
STATUS_GLYPH_HEIGHT_FRACTION = 0.85
BRAND_MARK_WIDTH = 1024


def _alpha_floor_bbox(img: Image.Image, floor: int = 10) -> tuple[int, int, int, int]:
    """The true bounding box per R-32-413: alpha > floor, not alpha > 0. Inclusive."""
    alpha = img.convert("RGBA").getchannel("A")
    bbox = alpha.point(lambda a: 255 if a > floor else 0).getbbox()
    if bbox is None:
        raise ValueError("master has no opaque pixel")
    x0, y0, x1, y1 = bbox
    return x0, y0, x1 - 1, y1 - 1


def _verify_tile_geometry(tile: Image.Image) -> None:
    """R-32-413's acceptance proof: the raster is the published tile, unchanged."""
    if tile.size != (TILE_CANVAS, TILE_CANVAS):
        raise ValueError(f"remote.png must be {TILE_CANVAS} square, got {tile.size}")
    bbox_zero = _alpha_floor_bbox(tile, floor=0)
    bbox_ten = _alpha_floor_bbox(tile, floor=10)
    if bbox_zero != bbox_ten or bbox_ten != TILE_BBOX:
        raise ValueError(f"remote.png bbox drift: floor0={bbox_zero}, floor10={bbox_ten}")
    pixels = tile.getchannel("A").load()
    x1, y1 = TILE_BBOX[2], TILE_BBOX[3]
    right_run = sum(pixels[x1, y] > 10 for y in range(tile.height))
    bottom_run = sum(pixels[x, y1] > 10 for x in range(tile.width))
    if right_run < TILE_MIN_RIGHT_RUN or bottom_run < TILE_MIN_BOTTOM_RUN:
        raise ValueError(
            f"remote.png no longer bleeds: right={right_run}, bottom={bottom_run}"
        )


def _recolour(tile: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
    """A flat colour with the tile's alpha: the shape, in one ink."""
    out = Image.new("RGBA", tile.size, rgb + (0,))
    out.putalpha(tile.getchannel("A"))
    return out


def _fit_tile(tile: Image.Image, canvas_px: int) -> Image.Image:
    """R-32-415: the whole tile scaled to the whole canvas. No centring, no margin."""
    return tile.resize((canvas_px, canvas_px), Image.LANCZOS)


def _verify_head_inside_mask(fg: Image.Image, mask_radius_px: float) -> None:
    """R-32-416: the muzzle, the mark's leftmost point, MUST sit inside the 72 dp mask circle,
    so no launcher shape ever cuts the head. The body bleeding past the circle is the design."""
    alpha = fg.getchannel("A")
    x0, y0, _, _ = _alpha_floor_bbox(fg)
    px = alpha.load()
    ys = [y for y in range(fg.height) if px[x0, y] > 10]
    muzzle_y = (min(ys) + max(ys)) / 2.0
    cx = cy = fg.width / 2.0
    d = math.hypot(x0 - cx + 0.5, muzzle_y - cy + 0.5)
    if d >= mask_radius_px:
        raise ValueError(f"muzzle at distance {d:.2f} px is outside the mask radius {mask_radius_px:.2f}")
    horn_xs = [x for x in range(fg.width) if px[x, y0] > 10]
    horn_x = (min(horn_xs) + max(horn_xs)) / 2.0
    d = math.hypot(horn_x - cx + 0.5, y0 - cy + 0.5)
    if d >= mask_radius_px:
        raise ValueError(f"horn at distance {d:.2f} px is outside the mask radius {mask_radius_px:.2f}")


def _height_fraction_fit(master: Image.Image, canvas_px: int, height_fraction: float) -> Image.Image:
    """Centres master's bbox on canvas_px, scaled so its bbox height reaches
    height_fraction * canvas_px. R-32-420's method for the unmasked status-bar glyph."""
    x0, y0, x1, y1 = _alpha_floor_bbox(master)
    bh = y1 - y0 + 1
    bcx, bcy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    scale = (height_fraction * canvas_px) / bh
    new_w = max(1, round(master.width * scale))
    new_h = max(1, round(master.height * scale))
    resized = master.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
    off_x = round(canvas_px / 2 - bcx * scale)
    off_y = round(canvas_px / 2 - bcy * scale)
    canvas.paste(resized, (off_x, off_y), resized)
    return canvas


def _flat_fill(canvas_px: int, rgb: tuple[int, int, int], alpha: bool) -> Image.Image:
    mode = "RGBA" if alpha else "RGB"
    fill = rgb + (255,) if alpha else rgb
    return Image.new(mode, (canvas_px, canvas_px), fill)


# R-32-411: the ground grid of `docs/32-design-language.md` R-32-332, 40 logical px on a 1080 px
# phone, becomes this many cells across the icon tile, so a launcher tile and the welcome hero
# read as one surface.
GRID_CELLS = 8


def _ground(canvas_px: int, alpha: bool) -> Image.Image:
    """The Ink ground with `color.bg.grid` lines at GRID_CELLS per side, one device pixel wide at
    every density (R-32-411). Lines sit on cell boundaries, never on the canvas edge."""
    img = _flat_fill(canvas_px, BG_RGB, alpha)
    px = img.load()
    line = GRID_RGB + (255,) if alpha else GRID_RGB
    width = max(1, round(canvas_px / 432))  # 1 px at mdpi, up to 3 px on the 1024 export.
    for cell in range(1, GRID_CELLS):
        pos = round(canvas_px * cell / GRID_CELLS)
        for offset in range(width):
            p = pos + offset
            if p >= canvas_px:
                continue
            for q in range(canvas_px):
                px[p, q] = line
                px[q, p] = line
    return img


def _composite_on_bg(fg: Image.Image, canvas_px: int) -> Image.Image:
    return Image.alpha_composite(_ground(canvas_px, alpha=True), fg)


def _brand_mark(tile: Image.Image) -> Image.Image:
    """The mark's true bounding box, white with alpha, BRAND_MARK_WIDTH wide. Its right and
    bottom edges are the published crop, so a layout can sit them on a real edge."""
    x0, y0, x1, y1 = _alpha_floor_bbox(tile)
    crop = _recolour(tile, (255, 255, 255)).crop((x0, y0, x1 + 1, y1 + 1))
    height = round(crop.height * BRAND_MARK_WIDTH / crop.width)
    return crop.resize((BRAND_MARK_WIDTH, height), Image.LANCZOS)


def generate() -> None:
    tile = Image.open(TILE_MASTER).convert("RGBA")
    _verify_tile_geometry(tile)
    mark = _recolour(tile, MARK_RGB)
    mono = _recolour(tile, (255, 255, 255))
    status_master = Image.open(STATUS_MASTER).convert("RGBA")

    # --- src/android_background.png: the ground raster, regenerated from BG_HEX and GRID_HEX. ---
    _ground(TILE_CANVAS, alpha=False).save(SRC / "android_background.png")

    # --- Android adaptive icon, five densities. Foreground and monochrome are the whole tile on
    # the whole 108 dp canvas; the launcher's mask crops the body, R-32-415. ---
    for density, scale in ANDROID_DENSITIES.items():
        canvas_px = round(ADAPTIVE_CANVAS_DP * scale)
        out_dir = EXPORT / "android" / f"mipmap-{density}"
        out_dir.mkdir(parents=True, exist_ok=True)

        _ground(canvas_px, alpha=False).save(out_dir / "ic_launcher_background.png")

        fg = _fit_tile(mark, canvas_px)
        _verify_head_inside_mask(fg, MASK_RADIUS_DP * scale)
        fg.save(out_dir / "ic_launcher_foreground.png")
        _fit_tile(mono, canvas_px).save(out_dir / "ic_launcher_monochrome.png")

        # Status-bar glyph, R-32-420: pure white, shape in alpha only, unmasked, height-fit.
        stat_canvas_px = round(STATUS_BAR_CANVAS_DP * scale)
        stat_out_dir = EXPORT / "android" / f"drawable-{density}"
        stat_out_dir.mkdir(parents=True, exist_ok=True)
        stat = _height_fraction_fit(status_master, stat_canvas_px, STATUS_GLYPH_HEIGHT_FRACTION)
        stat.save(stat_out_dir / "ic_stat_agent.png")

    # --- iOS: one flattened opaque 1024 x 1024 tile, R-32-417. ---
    ios_dir = EXPORT / "ios" / "AppIcon.appiconset"
    ios_dir.mkdir(parents=True, exist_ok=True)
    _composite_on_bg(_fit_tile(mark, 1024), 1024).convert("RGB").save(ios_dir / "Icon-1024.png")

    # --- Google Play store icon: 512 x 512 tile, alpha channel present and fully opaque,
    # R-32-419. ---
    store_dir = EXPORT / "store"
    store_dir.mkdir(parents=True, exist_ok=True)
    _composite_on_bg(_fit_tile(mark, 512), 512).save(store_dir / "play-store-512.png")

    # --- The in-app brand mark, R-32-424. ---
    brand_dir = EXPORT / "brand"
    brand_dir.mkdir(parents=True, exist_ok=True)
    _brand_mark(tile).save(brand_dir / "ram.png")

    print("Regenerated assets/icon/export/ and assets/icon/src/android_background.png.")


if __name__ == "__main__":
    generate()
