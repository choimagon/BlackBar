#!/usr/bin/env python3

from pathlib import Path
from PIL import Image
import shutil
import subprocess
import sys


ICON_SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    source = root / "image.png"
    iconset = root / "AppBundle" / "AppIcon.iconset"
    output = root / "AppBundle" / "AppIcon.icns"

    if not source.exists():
        print(f"Missing source image: {source}", file=sys.stderr)
        return 1

    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir(parents=True)

    with Image.open(source) as image:
        image = image.convert("RGBA")
        square = render_square(image)
        for filename, size in ICON_SIZES:
            resized = square.resize((size, size), Image.Resampling.LANCZOS)
            resized.save(iconset / filename)

    subprocess.run(
        ["iconutil", "--convert", "icns", "--output", str(output), str(iconset)],
        check=True,
    )
    shutil.rmtree(iconset)
    print(f"Generated {output}")
    return 0


def render_square(image: Image.Image) -> Image.Image:
    side = max(image.width, image.height)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    x = (side - image.width) // 2
    y = (side - image.height) // 2
    canvas.alpha_composite(image, (x, y))
    return canvas


if __name__ == "__main__":
    raise SystemExit(main())
