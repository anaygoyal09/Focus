#!/usr/bin/env python3
"""Generate a purple/blue Focus app icon and the Focus.iconset directory.

Usage: ./create_icon.py
"""

from __future__ import annotations

import os
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError as e:
    raise SystemExit("This script needs Pillow. Run: python3 -m pip install --user Pillow") from e


HERE = Path(__file__).resolve().parent
ICONSET = HERE / "Focus.iconset"
ICONSET.mkdir(exist_ok=True)

BASE = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def make_master() -> Image.Image:
    img = Image.new("RGBA", (BASE, BASE), (0, 0, 0, 0))
    px = img.load()

    top    = (90, 70, 230)   # vibrant indigo
    bottom = (60, 130, 255)  # bright blue

    cx, cy = BASE / 2, BASE / 2
    r_outer = BASE / 2 - 16

    for y in range(BASE):
        for x in range(BASE):
            dx, dy = x - cx, y - cy
            d = (dx * dx + dy * dy) ** 0.5
            if d <= r_outer:
                t = y / BASE
                color = lerp(top, bottom, t)
                # subtle radial highlight near top-left
                hx, hy = cx - r_outer * 0.35, cy - r_outer * 0.45
                hd = ((x - hx) ** 2 + (y - hy) ** 2) ** 0.5
                hl = max(0.0, 1.0 - hd / (r_outer * 1.1))
                hl = hl ** 2 * 0.25
                color = tuple(min(255, int(c + hl * 255)) for c in color)
                px[x, y] = (color[0], color[1], color[2], 255)

    draw = ImageDraw.Draw(img)

    # Concentric focus rings
    ring_color = (255, 255, 255, 235)
    rings = [
        (0.78, 26),
        (0.56, 22),
        (0.34, 18),
    ]
    for frac, width in rings:
        r = r_outer * frac
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=ring_color, width=width)

    # Center dot
    dot_r = r_outer * 0.10
    draw.ellipse((cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r), fill=(255, 255, 255, 255))

    # Soft glow pass
    glow = img.filter(ImageFilter.GaussianBlur(radius=8))
    out = Image.alpha_composite(glow, img)
    return out


SIZES = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]


def main() -> None:
    master = make_master()
    for size, scale in SIZES:
        px = size * scale
        resized = master.resize((px, px), Image.LANCZOS)
        suffix = "" if scale == 1 else "@2x"
        out = ICONSET / f"icon_{size}x{size}{suffix}.png"
        resized.save(out, format="PNG")
        print(f"  wrote {out.relative_to(HERE)}")
    print(f"Iconset ready at {ICONSET}")


if __name__ == "__main__":
    main()
