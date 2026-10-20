"""
Generates docs/og-image.png at 1200x630 for OpenTime social previews.

Run from repo root:
    python3 scripts/make_og_image.py

The Apple "Download on the App Store" CTA is composited from the cached
PNG at scripts/assets/app-store-badge.png. To refresh that asset:

    curl -sSL \
      "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?releaseDate=1700000000" \
      -o scripts/assets/app-store-badge.svg
    rsvg-convert -h 240 scripts/assets/app-store-badge.svg \
      -o scripts/assets/app-store-badge.png
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ICON = REPO / "docs" / "icon.png"
BADGE = REPO / "scripts" / "assets" / "app-store-badge.png"
OUT = REPO / "docs" / "og-image.png"

BADGE_HEIGHT = 80  # CTA size that respects Apple's 40px minimum with headroom.

W, H = 1200, 630
BG = (10, 11, 13)
SURFACE = (17, 19, 23)
BORDER = (29, 32, 38)
TEXT = (232, 234, 236)
DIM = (138, 143, 150)
ACCENT = (74, 222, 128)

ICON_SIZE = 240
ICON_RADIUS = 52
LEFT_PAD = 80
TOP_PAD = 110


def rounded_mask(size: int, radius: int) -> Image.Image:
    """Single-channel mask with rounded square."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def load_font(candidates, size):
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    img = Image.new("RGB", (W, H), BG)

    # Subtle vignette in the corner so the card has depth.
    glow = Image.new("RGB", (W, H), BG)
    gd = ImageDraw.Draw(glow)
    gd.ellipse((-200, -200, 700, 700), fill=(22, 36, 28))
    glow = glow.filter(ImageFilter.GaussianBlur(200))
    img = Image.blend(img, glow, 0.55)

    # Icon: load, resize, paste with rounded mask.
    icon = Image.open(ICON).convert("RGB").resize(
        (ICON_SIZE, ICON_SIZE), Image.LANCZOS
    )
    mask = rounded_mask(ICON_SIZE, ICON_RADIUS)
    img.paste(icon, (LEFT_PAD, TOP_PAD), mask)

    draw = ImageDraw.Draw(img)

    sf_display = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    sf_text = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]

    title_font = load_font(sf_display, 112)
    tagline_font = load_font(sf_text, 38)
    eyebrow_font = load_font(sf_text, 22)
    footer_font = load_font(sf_text, 22)

    text_x = LEFT_PAD + ICON_SIZE + 56
    title_y = TOP_PAD + 8

    # Eyebrow above the title.
    eyebrow = "OPENTIME  ·  iOS APP"
    draw.text(
        (text_x, title_y - 4),
        eyebrow,
        font=eyebrow_font,
        fill=ACCENT,
    )

    draw.text(
        (text_x, title_y + 36),
        "OpenTime",
        font=title_font,
        fill=TEXT,
    )

    # Tagline: wrap manually to two lines if needed.
    tagline_lines = [
        "See your free time",
        "at a glance.",
    ]
    ty = title_y + 36 + 130
    for line in tagline_lines:
        draw.text((text_x, ty), line, font=tagline_font, fill=DIM)
        ty += 50

    # Apple App Store CTA badge, composited under the tagline.
    if BADGE.exists():
        badge = Image.open(BADGE).convert("RGBA")
        ratio = badge.width / badge.height
        badge_w = int(BADGE_HEIGHT * ratio)
        badge = badge.resize((badge_w, BADGE_HEIGHT), Image.LANCZOS)
        img.paste(badge, (text_x, ty + 18), badge)

    # Footer rule + meta.
    rule_y = H - 90
    draw.line((LEFT_PAD, rule_y, W - LEFT_PAD, rule_y), fill=BORDER, width=1)
    draw.text(
        (LEFT_PAD, rule_y + 22),
        "lulls.app",
        font=footer_font,
        fill=DIM,
    )
    right_meta = "iPhone  ·  iPad  ·  Apple Watch"
    rm_bbox = draw.textbbox((0, 0), right_meta, font=footer_font)
    rm_w = rm_bbox[2] - rm_bbox[0]
    draw.text(
        (W - LEFT_PAD - rm_w, rule_y + 22),
        right_meta,
        font=footer_font,
        fill=DIM,
    )

    img.save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT}  ({OUT.stat().st_size} bytes, {W}x{H})")


if __name__ == "__main__":
    main()
