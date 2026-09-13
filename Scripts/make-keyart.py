#!/usr/bin/env python3
"""Draw the splash key art: a contact sheet, which is what this app makes.

640 x 250 at 1x, 2x and 3x. The lockup sits bottom-left over a scrim applied in
SwiftUI, so the art is drawn without one and simply keeps that corner quiet.
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 640, 250
GROUND = (18, 20, 24)

# Muted photographic hues — dusk, tungsten, foliage, harbour. Nothing saturated
# enough to fight the white type that sits over the bottom-left corner.
PALETTE = [
    ((44, 78, 130), (128, 176, 220)),   # blue hour
    ((150, 88, 40), (238, 176, 96)),    # tungsten
    ((36, 84, 70), (112, 170, 136)),    # foliage
    ((118, 52, 74), (206, 128, 138)),   # rose
    ((56, 64, 82), (148, 158, 180)),    # overcast
    ((128, 110, 58), (232, 208, 136)),  # sand
    ((30, 58, 84), (98, 140, 178)),     # harbour
    ((88, 54, 108), (170, 132, 196)),   # dusk
    ((162, 74, 52), (244, 158, 112)),   # terracotta
]


def gradient(size: tuple[int, int], top: tuple, bottom: tuple, angle: float) -> Image.Image:
    """A soft two-stop gradient, drawn large and rotated so it is never flat."""
    width, height = size
    span = int(math.hypot(width, height)) + 4
    strip = Image.new("RGB", (1, span))
    pixels = strip.load()
    for y in range(span):
        t = y / max(span - 1, 1)
        pixels[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return (strip.resize((span, span), Image.BILINEAR)
            .rotate(angle, resample=Image.BILINEAR)
            .crop(((span - width) // 2, (span - height) // 2,
                   (span - width) // 2 + width, (span - height) // 2 + height)))


def cell(draw_on: Image.Image, box: tuple[int, int, int, int],
         scale: int, rng: random.Random, filled: bool) -> None:
    x0, y0, x1, y1 = box
    radius = 3 * scale

    if filled:
        top, bottom = rng.choice(PALETTE)
        tile = gradient((x1 - x0, y1 - y0), top, bottom, rng.uniform(-40, 40))
        mask = Image.new("L", (x1 - x0, y1 - y0), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, x1 - x0 - 1, y1 - y0 - 1), radius=radius, fill=255)
        draw_on.paste(tile, (x0, y0), mask)
    else:
        # A frame still waiting for its bytes — the state the app spends most
        # of its time in.
        ImageDraw.Draw(draw_on, "RGBA").rounded_rectangle(
            (x0, y0, x1 - 1, y1 - 1), radius=radius, fill=(255, 255, 255, 10))

    ImageDraw.Draw(draw_on, "RGBA").rounded_rectangle(
        (x0, y0, x1 - 1, y1 - 1), radius=radius,
        outline=(255, 255, 255, 40 if filled else 26), width=max(1, scale // 2))


def draw(scale: int) -> Image.Image:
    rng = random.Random(20260912)
    width, height = WIDTH * scale, HEIGHT * scale
    art = Image.new("RGB", (width, height), GROUND)

    columns, rows = 9, 4
    gap = 7 * scale
    margin = 10 * scale
    cell_w = (width - margin * 2 - gap * (columns - 1)) / columns
    cell_h = (height - margin * 2 - gap * (rows - 1)) / rows

    for row in range(rows):
        for column in range(columns):
            x0 = int(margin + column * (cell_w + gap))
            y0 = int(margin + row * (cell_h + gap))
            box = (x0, y0, int(x0 + cell_w), int(y0 + cell_h))
            # The lockup sits over the bottom-left, so that corner is held
            # back rather than emptied: a void reads as a broken layout, a
            # dimmed frame reads as a contact sheet.
            cell(art, box, scale, rng, filled=rng.random() > 0.14)

    # The type sits bottom-left over a scrim, so the art is graded down towards
    # that corner — a diagonal falloff rather than a blanket vignette, which
    # crushed the top corners and made the plate look underexposed.
    shade = Image.new("L", (width, height), 255)
    pixels = shade.load()
    for y in range(height):
        vertical = y / max(height - 1, 1)
        for x in range(0, width, 4):
            horizontal = 1 - x / max(width - 1, 1)
            weight = (vertical * 0.55 + horizontal * 0.45) ** 1.3
            value = int(255 * (1 - 0.72 * weight))
            for step in range(4):
                if x + step < width:
                    pixels[x + step, y] = value
    shade = shade.filter(ImageFilter.GaussianBlur(radius=6 * scale))
    art = Image.composite(art, Image.new("RGB", (width, height), (9, 10, 13)), shade)

    return art


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "Sources/CaterinaUI/Resources"
    out.mkdir(parents=True, exist_ok=True)
    for scale in (1, 2, 3):
        name = "ContactSheetAbout.png" if scale == 1 else f"ContactSheetAbout@{scale}x.png"
        draw(scale).save(out / name)
        print(f"wrote {name}")


if __name__ == "__main__":
    main()
