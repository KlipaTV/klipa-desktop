# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow==12.0.0"]
# ///
"""Render the MSIX visual assets from the Klipa mark.

Run from the repository root with `uv run tool/generate_msix_assets.py`. It
rewrites packaging/windows/msix/Assets/ from the mark's vector geometry (the
same k and tally dot as assets/branding/logo_mark.png), so every scale and
target size is drawn at its own resolution instead of resampled from a PNG.
"""

from pathlib import Path

from PIL import Image, ImageDraw

INK = (8, 9, 11, 255)
FOREGROUND = (244, 241, 234, 255)
TALLY = (255, 91, 36, 255)

# The mark in a 512-unit square, as in klipa.tv's brand icon.
K_PATH = [
    (101.6, 410.9), (101.6, 103.7), (171.0, 103.7), (171.0, 277.3),
    (246.5, 187.4), (327.7, 187.4), (248.7, 276.0), (330.7, 410.9),
    (251.6, 410.9), (202.0, 324.1), (171.0, 354.0), (171.0, 410.9),
]
DOT_CENTER = (390.1, 138.4)
DOT_RADIUS = 37.3
# logo_mark.png draws the mark at this fraction of its square.
MARK_SCALE = 0.77
# Corner radius of the icon square, as a fraction of its side (klipa.tv: 112/512).
ICON_RADIUS = 112 / 512
SUPERSAMPLE = 8

SCALES = (100, 125, 150, 200, 400)
TARGET_SIZES = (16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 256)


def draw_mark(draw, box_size, offset_x, offset_y):
    unit = box_size * MARK_SCALE / 512
    shift = box_size * (1 - MARK_SCALE) / 2

    def point(x, y):
        return (offset_x + shift + x * unit, offset_y + shift + y * unit)

    draw.polygon([point(x, y) for x, y in K_PATH], fill=FOREGROUND)
    cx, cy = point(*DOT_CENTER)
    r = DOT_RADIUS * unit
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=TALLY)


def render(width, height, rounded):
    big_w, big_h = width * SUPERSAMPLE, height * SUPERSAMPLE
    image = Image.new("RGBA", (big_w, big_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    if rounded:
        draw.rounded_rectangle(
            (0, 0, big_w - 1, big_h - 1), radius=round(big_w * ICON_RADIUS), fill=INK
        )
    else:
        draw.rectangle((0, 0, big_w, big_h), fill=INK)
    # The mark sits in a centred square as tall as the asset.
    draw_mark(draw, big_h, (big_w - big_h) / 2, 0)
    return image.resize((width, height), Image.Resampling.LANCZOS)


def main():
    out = Path("packaging/windows/msix/Assets")
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()

    def save(image, name):
        image.save(out / name, optimize=True)

    # Name, base width, base height, rounded icon square (else a full-bleed tile).
    scaled = [
        ("Square44x44Logo", 44, 44, True),
        ("StoreLogo", 50, 50, True),
        ("SmallTile", 71, 71, False),
        ("Square150x150Logo", 150, 150, False),
        ("Wide310x150Logo", 310, 150, False),
        ("LargeTile", 310, 310, False),
    ]
    for name, width, height, rounded in scaled:
        for scale in SCALES:
            w = round(width * scale / 100)
            h = round(height * scale / 100)
            save(render(w, h, rounded), f"{name}.scale-{scale}.png")

    # Taskbar, Start and Explorer sizes, drawn unplated for both themes.
    for size in TARGET_SIZES:
        icon = render(size, size, True)
        save(icon, f"Square44x44Logo.targetsize-{size}.png")
        save(icon, f"Square44x44Logo.targetsize-{size}_altform-unplated.png")
        save(icon, f"Square44x44Logo.targetsize-{size}_altform-lightunplated.png")


if __name__ == "__main__":
    main()
