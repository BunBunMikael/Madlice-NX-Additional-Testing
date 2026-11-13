#!/usr/bin/env python3
"""Draws the Switch build's fallback icon: app/switch/icon.jpg (256x256 JPEG, as elf2nro wants), used when the disc
has no dashboard art for tools/disc_icon.py.

    python3 tools/make_icon.py [out.jpg]

Original artwork, drawn here from plain shapes (a clock dial, a keyhole and the project's name): no logo, character or
official art of the game (those belong to their owners). The committed icon.jpg is what the build uses; this script
only remakes it (needs Pillow and the Noto fonts).
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'app', 'switch', 'icon.jpg')
S = 1024  # drawn at 4x, scaled down at the end
FONT_TITLE = '/usr/share/fonts/noto/NotoSerifDisplay-Black.ttf'
FONT_SMALL = '/usr/share/fonts/noto/NotoSans-Black.ttf'

INK = (10, 14, 16)
TEAL = (70, 150, 140)
BRASS = (196, 160, 92)
CREAM = (240, 230, 210)
RED = (170, 24, 32)

# Background: a dark teal vignette.
img = Image.new('RGB', (S, S), INK)
px = img.load()
cx, cy = S * 0.5, S * 0.40
for y in range(S):
    for x in range(S):
        d = min(1.0, math.hypot(x - cx, y - cy) / (S * 0.75))
        k = (1.0 - d) ** 1.6
        px[x, y] = tuple(int(INK[i] + (TEAL[i] * 0.45 - INK[i]) * k) for i in range(3))

draw = ImageDraw.Draw(img)

# The dial: a brass ring, a cream face, sixty ticks (every fifth longer) and two hands.
R = S * 0.30
draw.ellipse([cx - R - 26, cy - R - 26, cx + R + 26, cy + R + 26], fill=BRASS)
draw.ellipse([cx - R - 8, cy - R - 8, cx + R + 8, cy + R + 8], fill=(120, 92, 48))
draw.ellipse([cx - R, cy - R, cx + R, cy + R], fill=CREAM)
for i in range(60):
    a = i * math.tau / 60
    long_tick = i % 5 == 0
    r0 = R * (0.80 if long_tick else 0.88)
    w = 10 if long_tick else 4
    draw.line([cx + r0 * math.sin(a), cy - r0 * math.cos(a), cx + R * 0.95 * math.sin(a),
               cy - R * 0.95 * math.cos(a)], fill=INK, width=w)
for angle, length, width in ((-50, 0.50, 18), (100, 0.72, 10)):
    a = math.radians(angle)
    draw.line([cx, cy, cx + R * length * math.sin(a), cy - R * length * math.cos(a)], fill=INK, width=width)

# A keyhole at the centre, in red.
draw.ellipse([cx - 30, cy - 30, cx + 30, cy + 30], fill=RED)
draw.polygon([(cx - 18, cy + 10), (cx + 18, cy + 10), (cx + 30, cy + 92), (cx - 30, cy + 92)], fill=RED)

# The crown of the watch on top.
draw.rectangle([cx - 34, cy - R - 76, cx + 34, cy - R - 26], fill=BRASS)
draw.ellipse([cx - 22, cy - R - 120, cx + 22, cy - R - 76], outline=BRASS, width=12)

img = img.filter(ImageFilter.SMOOTH)
draw = ImageDraw.Draw(img)


def centered(text, font, y, color, stroke=0, stroke_color=None):
    w = draw.textlength(text, font=font)
    draw.text(((S - w) / 2, y), text, font=font, fill=color, stroke_width=stroke, stroke_fill=stroke_color)


centered('ALICE-NX', ImageFont.truetype(FONT_TITLE, 150), S * 0.74, CREAM, 6, INK)
centered('UNOFFICIAL PORT', ImageFont.truetype(FONT_SMALL, 56), S * 0.905, BRASS)

img.resize((256, 256), Image.LANCZOS).save(out, 'JPEG', quality=95)
print('wrote', out)
