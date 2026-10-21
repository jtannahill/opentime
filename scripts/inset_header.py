"""Shrink an App Store header into the area an iPhone actually shows.

The product page on iPhone crops about 8% off each side of the 3840x1646
header, so artwork that runs close to the edges loses its first letters.
This scales the artwork to 89% and centres it on the same background,
leaving about 11% clear on each side.

    uv run --with pillow python scripts/inset_header.py in.png out.png [preview.png]

The optional preview stacks the before and after as an iPhone crops them.
"""
import sys

from PIL import Image

SCALE = 0.89
IPHONE_CROP = 0.082  # share of the width hidden on each side, measured on device

src, out = sys.argv[1:3]
im = Image.open(src).convert("RGB")
W, H = im.size
small = im.resize((round(W * SCALE), round(H * SCALE)), Image.LANCZOS)
canvas = Image.new("RGB", (W, H), im.getpixel((5, 5)))
canvas.paste(small, ((W - small.width) // 2, (H - small.height) // 2))
canvas.save(out, optimize=True)

if len(sys.argv) > 3:
    m = round(W * IPHONE_CROP)
    before, after = im.crop((m, 0, W - m, H)), canvas.crop((m, 0, W - m, H))
    pad = 60
    sheet = Image.new("RGB", (before.width + 2 * pad, before.height * 2 + 3 * pad), (40, 40, 44))
    sheet.paste(before, (pad, pad))
    sheet.paste(after, (pad, before.height + 2 * pad))
    sheet.save(sys.argv[3])
