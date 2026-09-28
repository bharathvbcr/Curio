"""
Generate macOS AppIcon assets and AppIcon.icns for Curio macOS.

Renders Curio's Option B brand mark (bookmark ribbon + knocked-out spark in the
monochrome X aesthetic) inside Apple's macOS squircle container with proper
proportions, subtle drop shadow, and edge bevel.

Produces:
1. Full iconset directory with all required Apple resolutions:
   icon_16x16.png, icon_16x16@2x.png, icon_32x32.png, icon_32x32@2x.png,
   icon_128x128.png, icon_128x128@2x.png, icon_256x256.png, icon_256x256@2x.png,
   icon_512x512.png, icon_512x512@2x.png
2. AppIcon.icns via /usr/bin/iconutil
3. macOS Assets.xcassets/AppIcon.appiconset with Contents.json
"""

import math
import os
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_logo_previews import (
    BG_TOP,
    BG_BOTTOM,
    MARK,
    bookmark_points,
    sparkle_points,
    bbox,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAC_DIR = os.path.join(ROOT, "macos", "CurioMac")
XCSETS_DIR = os.path.join(MAC_DIR, "Assets.xcassets")
APPICON_SET_DIR = os.path.join(XCSETS_DIR, "AppIcon.appiconset")
ICONSET_TMP = os.path.join(ROOT, "build", "AppIcon.iconset")


def render_macos_icon_1024():
    """
    Renders a 1024x1024 macOS app icon according to Apple HIG.
    Canvas: 1024x1024 RGBA.
    Body: 824x824 squircle centered at (512, 512) -> [100, 100, 924, 924].
    Corner radius: 185px.
    Shadow: Soft Gaussian shadow underneath.
    """
    # Supersampling factor for crystal-clear antialiasing
    SS = 2
    CANVAS_SZ = 1024 * SS
    SQUIRCLE_SZ = 824 * SS
    RADIUS = int(185 * SS)
    PAD = (CANVAS_SZ - SQUIRCLE_SZ) // 2

    # 1. Create drop shadow
    shadow_mask = Image.new("L", (CANVAS_SZ, CANVAS_SZ), 0)
    sdraw = ImageDraw.Draw(shadow_mask)
    # Offset shadow slightly downwards (+16px * SS)
    shadow_offset_y = int(16 * SS)
    sdraw.rounded_rectangle(
        [PAD, PAD + shadow_offset_y, PAD + SQUIRCLE_SZ, PAD + SQUIRCLE_SZ + shadow_offset_y],
        radius=RADIUS,
        fill=140, # ~55% alpha before blur
    )
    # Blur the shadow
    shadow_blur = shadow_mask.filter(ImageFilter.GaussianBlur(radius=20 * SS))
    shadow_img = Image.new("RGBA", (CANVAS_SZ, CANVAS_SZ), (0, 0, 0, 0))
    shadow_black = Image.new("RGBA", (CANVAS_SZ, CANVAS_SZ), (0, 0, 0, 255))
    shadow_img.paste(shadow_black, (0, 0), shadow_blur)

    # 2. Render squircle base
    # Vertical gradient for background
    grad_1d = Image.new("RGB", (1, SQUIRCLE_SZ))
    for y in range(SQUIRCLE_SZ):
        t = y / max(1, SQUIRCLE_SZ - 1)
        r = round(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t)
        g = round(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t)
        b = round(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t)
        grad_1d.putpixel((0, y), (r, g, b))
    grad = grad_1d.resize((SQUIRCLE_SZ, SQUIRCLE_SZ))

    squircle_mask = Image.new("L", (SQUIRCLE_SZ, SQUIRCLE_SZ), 0)
    ImageDraw.Draw(squircle_mask).rounded_rectangle(
        [0, 0, SQUIRCLE_SZ - 1, SQUIRCLE_SZ - 1],
        radius=RADIUS,
        fill=255,
    )

    squircle_body = Image.new("RGBA", (SQUIRCLE_SZ, SQUIRCLE_SZ), (0, 0, 0, 0))
    squircle_body.paste(grad, (0, 0), squircle_mask)

    # 3. Draw Curio mark (Bookmark ribbon + spark knockout)
    bm = bookmark_points()
    sp = sparkle_points()
    x0, y0, x1, y1 = bbox(bm)
    cx_src, cy_src = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    # Scale bookmark to 58% of squircle height
    scale = (0.58 * SQUIRCLE_SZ) / max(x1 - x0, y1 - y0)
    cx_dst, cy_dst = SQUIRCLE_SZ / 2.0, SQUIRCLE_SZ / 2.0

    def transform(pts):
        return [
            ((x - cx_src) * scale + cx_dst, (y - cy_src) * scale + cy_dst)
            for x, y in pts
        ]

    # Draw white bookmark ribbon
    bmdraw = ImageDraw.Draw(squircle_body)
    bmdraw.polygon(transform(bm), fill=MARK)

    # Knock out the AI spark
    sp_mask = Image.new("L", (SQUIRCLE_SZ, SQUIRCLE_SZ), 0)
    ImageDraw.Draw(sp_mask).polygon(transform(sp), fill=255)
    squircle_body.paste(grad, (0, 0), sp_mask)

    # 4. Subtle inner border/highlight around squircle edge
    border_img = Image.new("RGBA", (SQUIRCLE_SZ, SQUIRCLE_SZ), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(border_img)
    bdraw.rounded_rectangle(
        [0, 0, SQUIRCLE_SZ - 1, SQUIRCLE_SZ - 1],
        radius=RADIUS,
        outline=(255, 255, 255, 38), # ~15% white top sheen
        width=int(1.5 * SS),
    )
    # Mask border to squircle
    squircle_body.paste(border_img, (0, 0), border_img)

    # 5. Composite squircle on top of drop shadow
    final_canvas = Image.new("RGBA", (CANVAS_SZ, CANVAS_SZ), (0, 0, 0, 0))
    final_canvas.alpha_composite(shadow_img)
    final_canvas.paste(squircle_body, (PAD, PAD), squircle_mask)

    # Downsample to 1024x1024 with high-quality Lanczos resampling
    return final_canvas.resize((1024, 1024), Image.LANCZOS)


def main():
    os.makedirs(APPICON_SET_DIR, exist_ok=True)
    os.makedirs(ICONSET_TMP, exist_ok=True)

    print("--> Rendering master 1024x1024 macOS app icon...")
    master = render_macos_icon_1024()

    # Required icon dimensions for macOS iconset
    resolutions = [
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

    print("--> Generating multi-resolution PNGs...")
    for filename, size in resolutions:
        resized = master if size == 1024 else master.resize((size, size), Image.LANCZOS)
        # Save to temporary iconset for iconutil
        p_iconset = os.path.join(ICONSET_TMP, filename)
        resized.save(p_iconset, "PNG")
        # Save to Asset Catalog appiconset
        p_xcassets = os.path.join(APPICON_SET_DIR, filename)
        resized.save(p_xcassets, "PNG")

    # Write Contents.json for Assets.xcassets/AppIcon.appiconset
    contents_json_path = os.path.join(APPICON_SET_DIR, "Contents.json")
    import json
    contents_data = {
        "images": [
            {
                "size": "16x16",
                "idiom": "mac",
                "filename": "icon_16x16.png",
                "scale": "1x"
            },
            {
                "size": "16x16",
                "idiom": "mac",
                "filename": "icon_16x16@2x.png",
                "scale": "2x"
            },
            {
                "size": "32x32",
                "idiom": "mac",
                "filename": "icon_32x32.png",
                "scale": "1x"
            },
            {
                "size": "32x32",
                "idiom": "mac",
                "filename": "icon_32x32@2x.png",
                "scale": "2x"
            },
            {
                "size": "128x128",
                "idiom": "mac",
                "filename": "icon_128x128.png",
                "scale": "1x"
            },
            {
                "size": "128x128",
                "idiom": "mac",
                "filename": "icon_128x128@2x.png",
                "scale": "2x"
            },
            {
                "size": "256x256",
                "idiom": "mac",
                "filename": "icon_256x256.png",
                "scale": "1x"
            },
            {
                "size": "256x256",
                "idiom": "mac",
                "filename": "icon_256x256@2x.png",
                "scale": "2x"
            },
            {
                "size": "512x512",
                "idiom": "mac",
                "filename": "icon_512x512.png",
                "scale": "1x"
            },
            {
                "size": "512x512",
                "idiom": "mac",
                "filename": "icon_512x512@2x.png",
                "scale": "2x"
            }
        ],
        "info": {
            "version": 1,
            "author": "xcode"
        }
    }
    with open(contents_json_path, "w", encoding="utf-8") as f:
        json.dump(contents_data, f, indent=2)

    # Root Contents.json for Assets.xcassets
    root_contents_path = os.path.join(XCSETS_DIR, "Contents.json")
    with open(root_contents_path, "w", encoding="utf-8") as f:
        json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)

    # 3. Compile AppIcon.icns with iconutil
    icns_dest = os.path.join(MAC_DIR, "AppIcon.icns")
    print(f"--> Compiling {icns_dest} using iconutil...")
    subprocess.check_call([
        "/usr/bin/iconutil",
        "-c", "icns",
        ICONSET_TMP,
        "-o", icns_dest
    ])

    print("Successfully generated:")
    print(f"  {icns_dest} ({os.path.getsize(icns_dest)} bytes)")
    print(f"  {APPICON_SET_DIR}")


if __name__ == "__main__":
    main()
