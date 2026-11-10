# -*- coding: utf-8 -*-
"""Launcher icons (legacy + adaptive) and a 512px store icon.
The mark: a gold single-elimination bracket feeding a champion dot.
Run from the project root:  python tool/make_icons.py
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

INK = (16, 32, 47)
INK2 = (27, 50, 72)
GOLD = (242, 193, 78)
BLUE = (76, 195, 232)
CORAL = (242, 124, 92)
SS = 4


def mark(n, scale):
    """Bracket drawn in an n×n RGBA image, occupying `scale` of the width."""
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = n * scale
    x0 = (n - w) / 2
    y0 = (n - w) / 2
    lw = max(2, int(w * 0.075))
    # four entrants on the left (y positions), two semis, one final
    ys = [y0 + w * f for f in (0.12, 0.38, 0.62, 0.88)]
    xa, xb, xc = x0 + w * 0.05, x0 + w * 0.36, x0 + w * 0.66
    cols = [BLUE, CORAL, BLUE, CORAL]
    for y, c in zip(ys, cols):
        r = lw * 0.95
        d.ellipse([xa - r, y - r, xa + r, y + r], fill=c)
        d.line([xa, y, xb, y], fill=GOLD, width=lw)
    s1, s2 = (ys[0] + ys[1]) / 2, (ys[2] + ys[3]) / 2
    for a, b, m in ((ys[0], ys[1], s1), (ys[2], ys[3], s2)):
        d.line([xb, a - lw / 2, xb, b + lw / 2], fill=GOLD, width=lw)
        d.line([xb, m, xc, m], fill=GOLD, width=lw)
    d.line([xc, s1 - lw / 2, xc, s2 + lw / 2], fill=GOLD, width=lw)
    fy = (s1 + s2) / 2
    xe = x0 + w * 0.86
    d.line([xc, fy, xe, fy], fill=GOLD, width=lw)
    r = w * 0.11
    d.ellipse([xe - r * 0.2, fy - r, xe + r * 1.8, fy + r], fill=GOLD)
    return img


def background(n, rounded):
    bg = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    grad = Image.new("RGBA", (1, n))
    gd = ImageDraw.Draw(grad)
    for y in range(n):
        t = y / max(1, n - 1)
        gd.point((0, y), fill=tuple(int(INK2[i] + (INK[i] - INK2[i]) * t) for i in range(3)) + (255,))
    grad = grad.resize((n, n))
    mask = Image.new("L", (n, n), 0)
    md = ImageDraw.Draw(mask)
    if rounded:
        md.rounded_rectangle([0, 0, n - 1, n - 1], radius=int(n * 0.22), fill=255)
    else:
        md.rectangle([0, 0, n, n], fill=255)
    bg.paste(grad, (0, 0), mask)
    return bg


def render(px, scale, rounded=True, with_bg=True):
    n = px * SS
    img = background(n, rounded) if with_bg else Image.new("RGBA", (n, n), (0, 0, 0, 0))
    m = mark(n, scale)
    img.alpha_composite(m)
    return img.resize((px, px), Image.LANCZOS)


DENS = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

for name, f in DENS.items():
    folder = os.path.join(RES, f"mipmap-{name}")
    os.makedirs(folder, exist_ok=True)
    render(int(48 * f), 0.62).save(os.path.join(folder, "ic_launcher.png"))
    # adaptive foreground: 108dp canvas, safe zone 66dp
    render(int(108 * f), 0.42, with_bg=False).save(os.path.join(folder, "ic_launcher_foreground.png"))

anydpi = os.path.join(RES, "mipmap-anydpi-v26")
os.makedirs(anydpi, exist_ok=True)
with open(os.path.join(anydpi, "ic_launcher.xml"), "w", encoding="utf-8") as fh:
    fh.write("""<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
""")
values = os.path.join(RES, "values")
os.makedirs(values, exist_ok=True)
with open(os.path.join(values, "ic_launcher_background.xml"), "w", encoding="utf-8") as fh:
    fh.write("""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#16293B</color>
</resources>
""")

store = os.path.join(ROOT, "store")
os.makedirs(store, exist_ok=True)
render(512, 0.62, rounded=False).save(os.path.join(store, "icon-512.png"))
# web favicon too
web = os.path.join(ROOT, "web", "icons")
if os.path.isdir(web):
    for sz in (192, 512):
        render(sz, 0.62, rounded=False).save(os.path.join(web, f"Icon-{sz}.png"))
        render(sz, 0.42, rounded=False).save(os.path.join(web, f"Icon-maskable-{sz}.png"))
print("icons written")
