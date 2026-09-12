#!/usr/bin/env python3
"""Draws the application icon and writes the .appiconset.

The mark is the contact sheet the splash shows and the app makes: other
people's frames, some of them still waiting for their bytes. Two of the tiles
are drawn as empty outlines for exactly that reason — a downloader is a thing
that is partway through.

The structure changes with the drawn size rather than being scaled down: nine
tiles at 16 points is mush, so the small sizes carry four. That is a different
drawing, not a blurrier one.

Writes App/FlickrDownloader/Assets.xcassets/AppIcon.appiconset and
documents/icon.png.
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# The plate: near-black, so the tiles are the only colour in the mark.
GROUND_TOP = (34, 37, 44)
GROUND_BOTTOM = (18, 20, 24)

# The key art's four signature hues, in the order they read best clockwise.
TUNGSTEN = ((150, 88, 40), (238, 176, 96))
BLUE_HOUR = ((44, 78, 130), (128, 176, 220))
FOLIAGE = ((36, 84, 70), (112, 170, 136))
ROSE = ((118, 52, 74), (206, 128, 138))

# Nine cells, row by row. `None` is a frame with nothing in it yet.
FULL = [BLUE_HOUR, TUNGSTEN, None,
        FOLIAGE, ROSE, BLUE_HOUR,
        None, TUNGSTEN, FOLIAGE]
SMALL = [BLUE_HOUR, TUNGSTEN,
         ROSE, None]


def vertical(size: tuple[int, int], top, bottom) -> Image.Image:
    width, height = size
    strip = Image.new("RGB", (1, max(height, 1)))
    pixels = strip.load()
    for y in range(height):
        t = y / max(height - 1, 1)
        pixels[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return strip.resize((width, height), Image.BILINEAR)


def tile(draw: ImageDraw.ImageDraw, plate: Image.Image,
         box: tuple[float, float, float, float], colours, radius: float,
         line: float) -> None:
    x0, y0, x1, y1 = (int(round(v)) for v in box)
    if colours is not None:
        fill = vertical((x1 - x0, y1 - y0), colours[1], colours[0])
        mask = Image.new("L", (x1 - x0, y1 - y0), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, x1 - x0 - 1, y1 - y0 - 1), radius=radius, fill=255)
        plate.paste(fill, (x0, y0), mask)
    else:
        # A frame still waiting: the state the app spends its time in.
        draw.rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=radius,
                               outline=(255, 255, 255, 78), width=max(1, int(line * 0.85)))


def design(size: int, detail: str) -> Image.Image:
    plate = vertical((size, size), GROUND_TOP, GROUND_BOTTOM).convert("RGBA")
    draw = ImageDraw.Draw(plate, "RGBA")

    cells = SMALL if detail == "small" else FULL
    columns = 2 if detail == "small" else 3
    margin = size * (0.150 if detail == "small" else 0.135)
    gap = size * (0.062 if detail == "small" else 0.045)
    span = (size - margin * 2 - gap * (columns - 1)) / columns
    radius = span * (0.20 if detail == "small" else 0.17)
    line = max(1, size * 0.018)

    for index, colours in enumerate(cells):
        row, column = divmod(index, columns)
        x0 = margin + column * (span + gap)
        y0 = margin + row * (span + gap)
        tile(draw, plate, (x0, y0, x0 + span, y0 + span), colours, radius, line)

    return plate


def draw_icon(size: int, detail: str = "full") -> Image.Image:
    """The mark on the macOS plate: inset from the canvas, corners rounded."""
    art = design(size, detail)

    # The house proportions, shared with Nino: the plate does not fill the
    # canvas, and the corner radius is a fixed fraction of it.
    inset, radius = 0.055 * size, 0.196 * size
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, size - inset - 1, size - inset - 1], radius=radius, fill=255)

    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(art, (0, 0), mask)
    return icon


def rendered(pixels: int, detail: str) -> Image.Image:
    """Drawn at 4x and resampled, so the rounded corners are not stair-stepped."""
    scale = 4 if pixels <= 256 else 2
    large = draw_icon(pixels * scale, detail)
    return large.resize((pixels, pixels), Image.LANCZOS)


SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
         (256, 1), (256, 2), (512, 1), (512, 2)]


def main() -> None:
    here = Path(__file__).resolve().parent.parent
    out = here / "App/FlickrDownloader/Assets.xcassets/AppIcon.appiconset"
    out.mkdir(parents=True, exist_ok=True)

    images = []
    for points, scale in SIZES:
        pixels = points * scale
        # By *drawn* size, not by size in points: 16 points at 2x is 32 pixels
        # and can carry what 32 points at 1x carries.
        detail = "small" if pixels <= 32 else "full"
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        rendered(pixels, detail).save(out / name)
        images.append({"idiom": "mac", "size": f"{points}x{points}",
                       "scale": f"{scale}x", "filename": name})

    (out / "Contents.json").write_text(json.dumps(
        {"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2) + "\n")

    rendered(1024, "full").save(here / "documents/icon.png")

    print(f"icon set: {len(images)} sizes")


if __name__ == "__main__":
    main()
