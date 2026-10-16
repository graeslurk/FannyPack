#!/usr/bin/env python3
"""Generates Fanny Pack's button textures (white shapes, tinted in-game).

    mask-round.tga, mask-rounded.tga   64x64 masks that cut the icons, the
                                       cooldown sweep and the button's border
                                       to shape
    glow-square.tga, glow-rounded.tga,
    glow-round.tga                     128x128 soft glows around a button of
                                       each shape; the button covers the
                                       middle 64x64
    icon-look.tga, icon-clock.tga      32x32 sidebar icons for the Look and
                                       Reminders pages, in the style of
                                       Pocket Goblin's (icon-list, icon-sort
                                       and icon-profile come from there)

Shapes are drawn as signed distance fields with 1px anti-aliasing and saved
as 32-bit TGA, which WoW loads directly. The other textures in Media come
from Soul Warden and Pocket Goblin, and the logo from tools/make_emblem.js.
Run from anywhere:

    python3 tools/make_media.py
"""

import math
import os
import struct

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Media")

ROUNDED_RADIUS = 0.22  # corner radius of the rounded shape, as a fraction of its width
GLOW_SPREAD = 12  # how far the glow reaches, in pixels of the 64px button


def box(px, py, half, radius):
    """Distance to a centred rounded box (negative inside)."""
    qx = abs(px) - half + radius
    qy = abs(py) - half + radius
    outside = math.hypot(max(qx, 0), max(qy, 0))
    return outside + min(max(qx, qy), 0) - radius


SHAPES = {
    "square": lambda x, y, half: box(x, y, half, 0),
    "rounded": lambda x, y, half: box(x, y, half, half * 2 * ROUNDED_RADIUS),
    "round": lambda x, y, half: math.hypot(x, y) - half,
}


def save(name, size, alpha):
    """Writes a white texture whose alpha comes from alpha(x, y), with x and
    y measured from the centre in pixels."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 0x28)
    pixels = bytearray()
    for row in range(size):
        for column in range(size):
            x, y = column + 0.5 - size / 2, row + 0.5 - size / 2
            a = max(0.0, min(1.0, alpha(x, y)))
            pixels += bytes((255, 255, 255, round(a * 255)))
    with open(os.path.join(OUT, name + ".tga"), "wb") as f:
        f.write(header + pixels)


def ring(x, y, cx, cy, r, width):
    return abs(math.hypot(x - cx, y - cy) - r) - width / 2


def capsule(x, y, ax, ay, bx, by, r):
    pax, pay, bax, bay = x - ax, y - ay, bx - ax, by - ay
    h = max(0, min(1, (pax * bax + pay * bay) / (bax * bax + bay * bay)))
    return math.hypot(pax - bax * h, pay - bay * h) - r


def eye(x, y):
    """An eye: an almond outline (two overlapping circles) and a pupil."""
    almond = max(math.hypot(x, y - 9) - 14.5, math.hypot(x, y + 9) - 14.5)
    outline = abs(almond) - 1.25
    pupil = math.hypot(x, y) - 4
    return min(outline, pupil)


def clock(x, y):
    """A clock face with its hands at ten past twelve."""
    face = ring(x, y, 0, 0, 11, 2.5)
    hour = capsule(x, y, 0, 0, 0, -6.5, 1.25)
    minute = capsule(x, y, 0, 0, 5.5, 0, 1.25)
    return min(face, hour, minute)


def main():
    for shape in ("rounded", "round"):
        distance = SHAPES[shape]
        save("mask-" + shape, 64, lambda x, y, d=distance: 0.5 - d(x, y, 32))

    for shape, distance in SHAPES.items():
        def glow(x, y, d=distance):
            outside = max(0.0, d(x, y, 32))
            return math.exp(-((outside / GLOW_SPREAD) ** 2))
        save("glow-" + shape, 128, glow)

    for name, shape in (("icon-look", eye), ("icon-clock", clock)):
        save(name, 32, lambda x, y, d=shape: 0.5 - d(x, y))


if __name__ == "__main__":
    main()
