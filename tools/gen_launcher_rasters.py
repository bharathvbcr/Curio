"""
Generate the legacy raster launcher icons for Curio's chosen mark (Option B:
bookmark + spark, X theme).

minSdk = 24, so API 24-25 devices cannot use the adaptive-icon vectors and fall
back to these PNG/WebP bitmaps. Also emits a 512px Play Store icon.

Reuses the exact geometry/rendering from gen_logo_previews.render() so the
bitmaps match the vector drawables 1:1.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_logo_previews import render  # noqa: E402

RES = os.path.join("app", "src", "main", "res")
MARK = "bookmark"

# Launcher-icon edge length in px per density bucket.
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def save_webp(img, path):
    img.save(path, "WEBP", lossless=True, quality=100, method=6)


def main():
    written = []
    for bucket, size in DENSITIES.items():
        out_dir = os.path.join(RES, "mipmap-" + bucket)
        os.makedirs(out_dir, exist_ok=True)

        sq = render(MARK, "square", size)
        rd = render(MARK, "round", size)

        p1 = os.path.join(out_dir, "ic_launcher.webp")
        p2 = os.path.join(out_dir, "ic_launcher_round.webp")
        save_webp(sq, p1)
        save_webp(rd, p2)
        written += [p1, p2]

    # Play Store listing icon: 512x512 32-bit PNG.
    playstore = render(MARK, "square", 512)
    ppath = os.path.join(RES, "..", "ic_launcher-playstore.png")
    ppath = os.path.normpath(ppath)
    playstore.save(ppath, "PNG")
    written.append(ppath)

    print("Wrote {} launcher bitmaps:".format(len(written)))
    for p in written:
        print("  {}  ({} bytes)".format(p, os.path.getsize(p)))


if __name__ == "__main__":
    main()
