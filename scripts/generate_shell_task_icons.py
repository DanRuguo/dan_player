"""Generate original 24-grid, rounded Material-style Windows task icons.

Requires Pillow. These geometric assets use no downloaded artwork or font data.
The ICOs are committed so ordinary Windows builds need no Python dependency.
"""
from pathlib import Path
from PIL import Image, ImageDraw

DESTINATION = Path(__file__).resolve().parents[1] / "windows/runner/resources"
COLOR = (89, 120, 123, 255)
SCALE = 8


def icon(name):
    image = Image.new("RGBA", (24 * SCALE, 24 * SCALE))
    draw = ImageDraw.Draw(image)

    def box(bounds, filled=False):
        draw.rounded_rectangle(tuple(round(v * SCALE) for v in bounds),
                               radius=SCALE, fill=COLOR if filled else None,
                               outline=COLOR, width=2 * SCALE)

    def triangle(points):
        draw.polygon([(round(x * SCALE), round(y * SCALE)) for x, y in points], fill=COLOR)

    if name == "window":
        box((3, 4, 21, 20))
        draw.line((4 * SCALE, 9 * SCALE, 20 * SCALE, 9 * SCALE), fill=COLOR, width=2 * SCALE)
    elif name == "mini":
        box((3, 4, 21, 20))
        box((12, 12, 18, 17), True)
    elif name == "play":
        triangle(((4, 5), (13, 12), (4, 19)))
        box((15, 5, 17, 19), True)
        box((20, 5, 22, 19), True)
    elif name == "previous":
        box((4, 5, 6, 19), True)
        triangle(((18, 5), (8, 12), (18, 19)))
    elif name == "next":
        triangle(((6, 5), (16, 12), (6, 19)))
        box((18, 5, 20, 19), True)

    image.save(DESTINATION / f"task_{name}.ico", sizes=[(n, n) for n in (16, 24, 32, 48, 64)])


if __name__ == "__main__":
    for task in ("window", "play", "previous", "next", "mini"):
        icon(task)
