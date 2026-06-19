"""
Curio app-icon preview generator.

Renders TWO candidate marks in the "X theme" (flat black + white, the look
that pairs perfectly with Material You themed icons):

    Option A  ->  bold geometric "C" monogram (for Curio)
    Option B  ->  bookmark + sparkle mark (knockout sparkle)

For each option it writes standalone PNGs (app icon, round, and a simulated
Material You tinted variant) plus a single side-by-side comparison sheet, so
the design can be eyeballed in a folder before being wired into the project.

Pure Pillow (no SVG / numpy needed). Geometry is authored in the Android
adaptive-icon 108x108 viewport so it maps 1:1 onto the vector drawables later.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = os.path.join("assets", "logo_preview")
os.makedirs(OUT_DIR, exist_ok=True)

# --------------------------------------------------------------------------
# Palettes
# --------------------------------------------------------------------------
# X theme: flat near-black background, flat white mark.
BG_TOP = (24, 24, 27)      # #18181B  (a whisper of sheen at the top)
BG_BOTTOM = (0, 0, 0)      # #000000
MARK = (255, 255, 255)     # pure white, like the X glyph

# Simulated Material You themed icon (launcher tints mono mark to wallpaper).
# Using a calm teal "wallpaper" to demonstrate how the silhouette re-colors.
THEMED_BG_TOP = (200, 226, 219)    # #C8E2DB
THEMED_BG_BOTTOM = (176, 212, 203) # #B0D4CB
THEMED_MARK = (20, 51, 43)         # #14332B

# --------------------------------------------------------------------------
# Geometry (authored in the 108x108 adaptive-icon viewport)
# --------------------------------------------------------------------------
CENTER = 54.0


def quad_bezier(p0, c, p1, n=26):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        x = mt * mt * p0[0] + 2 * mt * t * c[0] + t * t * p1[0]
        y = mt * mt * p0[1] + 2 * mt * t * c[1] + t * t * p1[1]
        pts.append((x, y))
    return pts


def arc_pts(cx, cy, r, a0_deg, a1_deg, n=96):
    """Sample a circular arc from a0 to a1 (degrees, screen space y-down)."""
    pts = []
    for i in range(n + 1):
        a = math.radians(a0_deg + (a1_deg - a0_deg) * i / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def c_monogram_points():
    """Bold 'C': ring band with an opening on the right. Returns one closed
    polygon tracing outer arc (the long way, through the left) then inner arc
    back. Ro=30, Ri=17 -> stroke 13. Opening half-angle 40deg."""
    cx = cy = CENTER
    Ro, Ri = 30.0, 17.0
    beta = 40.0
    # outer: top-right terminal (-beta) sweeping CCW through top/left/bottom to
    # bottom-right terminal (-(360-beta)); inner: back the other way.
    outer = arc_pts(cx, cy, Ro, -beta, -(360 - beta), n=120)
    inner = arc_pts(cx, cy, Ri, -(360 - beta), -beta, n=120)
    return outer + inner


def bookmark_points():
    """Rounded-top bookmark ribbon with a V-notch tail (clockwise)."""
    pts = [(46, 30), (62, 30)]
    pts += quad_bezier((62, 30), (71, 30), (71, 39))     # top-right corner
    pts += [(71, 80), (54, 66), (37, 80), (37, 39)]      # right, notch, left
    pts += quad_bezier((37, 39), (37, 30), (46, 30))     # top-left corner
    return pts


def sparkle_points():
    """Four-point AI sparkle (concave star) centered in the bookmark."""
    cx, cy = 54.0, 48.0
    # tips: top, right, bottom, left ; pinch controls near center
    pts = quad_bezier((54, 35), (56.40, 45.60), (67, 48))
    pts += quad_bezier((67, 48), (56.40, 50.40), (54, 61))
    pts += quad_bezier((54, 61), (51.60, 50.40), (41, 48))
    pts += quad_bezier((41, 48), (51.60, 45.60), (54, 35))
    return pts


def bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------
def _vgrad(size, top, bottom):
    """Vertical gradient RGB image."""
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        g.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((size, size))


def _fit_transform(pts, S, target_frac=0.62):
    """Scale+center a 108-space point list to an SxS canvas by its bbox."""
    x0, y0, x1, y1 = bbox(pts)
    bw, bh = x1 - x0, y1 - y0
    cx_src, cy_src = (x0 + x1) / 2, (y0 + y1) / 2
    scale = target_frac * S / max(bw, bh)
    return [((x - cx_src) * scale + S / 2, (y - cy_src) * scale + S / 2) for x, y in pts]


def render(mark, shape, S, themed=False):
    """mark: 'C' | 'bookmark'.  shape: 'square' | 'round'."""
    SS = max(1, min(4, 2048 // S))
    R = S * SS

    bg_top, bg_bot = (THEMED_BG_TOP, THEMED_BG_BOTTOM) if themed else (BG_TOP, BG_BOTTOM)
    mark_col = THEMED_MARK if themed else MARK

    grad = _vgrad(R, bg_top, bg_bot)
    shape_mask = Image.new("L", (R, R), 0)
    md = ImageDraw.Draw(shape_mask)
    if shape == "round":
        md.ellipse([0, 0, R - 1, R - 1], fill=255)
    else:
        md.rounded_rectangle([0, 0, R - 1, R - 1], radius=int(R * 0.235), fill=255)

    img = Image.new("RGBA", (R, R), (0, 0, 0, 0))
    img.paste(grad, (0, 0), shape_mask)

    draw = ImageDraw.Draw(img)
    if mark == "C":
        pts = _fit_transform(c_monogram_points(), R, target_frac=0.66)
        draw.polygon(pts, fill=mark_col)
    else:
        bm = bookmark_points()
        sp = sparkle_points()
        # fit both together using the bookmark bbox so the sparkle stays put
        x0, y0, x1, y1 = bbox(bm)
        cx_src, cy_src = (x0 + x1) / 2, (y0 + y1) / 2
        scale = 0.62 * R / max(x1 - x0, y1 - y0)
        tf = lambda P: [((x - cx_src) * scale + R / 2, (y - cy_src) * scale + R / 2) for x, y in P]
        draw.polygon(tf(bm), fill=mark_col)
        # knock the sparkle out -> reveal the background gradient through it
        sp_mask = Image.new("L", (R, R), 0)
        ImageDraw.Draw(sp_mask).polygon(tf(sp), fill=255)
        img.paste(grad, (0, 0), sp_mask)

    return img.resize((S, S), Image.LANCZOS)


# --------------------------------------------------------------------------
# Fonts + comparison sheet
# --------------------------------------------------------------------------
def _font(size, bold=False):
    candidates = (
        ["C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf"]
        if bold else
        ["C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"]
    )
    for c in candidates:
        try:
            return ImageFont.truetype(c, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _ctext(draw, cx, y, text, font, fill):
    l, t, r, b = draw.textbbox((0, 0), text, font=font)
    draw.text((cx - (r - l) / 2, y), text, font=font, fill=fill)


def comparison_sheet():
    W, H = 1280, 472
    sheet = Image.new("RGB", (W, H), (29, 29, 33))
    d = ImageDraw.Draw(sheet)

    f_title = _font(40, bold=True)
    f_opt = _font(30, bold=True)
    f_desc = _font(20)
    f_cap = _font(18)

    _ctext(d, W / 2, 32, "Curio  -  pick your app icon  (X theme)", f_title, (245, 245, 247))

    blocks = [
        ("Option A", "“C” monogram", "C"),
        ("Option B", "Bookmark + spark", "bookmark"),
    ]
    margin, gap = 40, 40
    block_w = (W - margin * 2 - gap) // 2
    T = 170
    tiles = [("square", "App icon", False), ("round", "Round", False), ("square", "Material You", True)]
    tile_total = len(tiles) * T + (len(tiles) - 1) * 24
    tx0_off = (block_w - tile_total) // 2

    for bi, (tag, name, mark) in enumerate(blocks):
        bx = margin + bi * (block_w + gap)
        d.rounded_rectangle([bx, 100, bx + block_w, H - 40], radius=24,
                            outline=(60, 60, 66), width=2)
        _ctext(d, bx + block_w / 2, 120, tag, f_opt, (255, 255, 255))
        _ctext(d, bx + block_w / 2, 162, name, f_desc, (170, 170, 178))

        ty = 210
        for ti, (shape, cap, themed) in enumerate(tiles):
            tx = bx + tx0_off + ti * (T + 24)
            icon = render(mark, shape, T, themed=themed)
            sheet.paste(icon, (int(tx), ty), icon)
            _ctext(d, tx + T / 2, ty + T + 12, cap, f_cap, (150, 150, 158))

    out = os.path.join(OUT_DIR, "comparison.png")
    sheet.save(out)
    return out


def main():
    written = []
    specs = [
        ("A_C_icon", "C", "square", False),
        ("A_C_round", "C", "round", False),
        ("A_C_materialyou", "C", "square", True),
        ("B_bookmark_icon", "bookmark", "square", False),
        ("B_bookmark_round", "bookmark", "round", False),
        ("B_bookmark_materialyou", "bookmark", "square", True),
    ]
    for name, mark, shape, themed in specs:
        img = render(mark, shape, 512, themed=themed)
        path = os.path.join(OUT_DIR, name + ".png")
        img.save(path)
        written.append(path)
    written.append(comparison_sheet())

    print("Wrote {} files to {}:".format(len(written), os.path.abspath(OUT_DIR)))
    for p in written:
        print("  " + p)


if __name__ == "__main__":
    main()
