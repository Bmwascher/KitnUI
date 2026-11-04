"""Build the Forever marks: transparent images the size of each background, drawn
over the retail art on the Forever client only, so the retail files never change.

Each mark is an infinity with a theme-colored ring, a cool comet tapering onto the
right lobe, and three stars in the constellation's white-core style, in the header
arch; a simplified copy left of the title; and the word FOREVER below the title.

Coordinates are canvas pixels of the background each image overlays:
  installer 1024 x 808, drawn with Wizard.lua's ART_CROP
  options   1500 x 1154, stretched over EllesmereUI's main frame by Theme.lua

Language, in canvas pixels:
  curve       x = cos t (1 + Q sin^2 t), y = sin 2t (1 + K cos 2t), width 2, aspect 2.4833
  comet       starts at width 0 at 78 percent of the arc length, head at 5 percent
  small mark  ring, comet and head star only; no crossing star, no dust
  detail floor  a stroke under 1.5 px or a dust point under radius 1.1 is dropped
  clearance   anything at alpha 40 or more stays 4 px from title, Skip, slider, thanks and rails

Run: python -I dev/art/build_forever_art.py   (needs NumPy, Pillow, Edge, Segoe UI Black)
"""
import math, os, subprocess, time
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

ASPECT, K, Q = 2.4833, -0.25, -0.1
THEMES = {
    "kitn": dict(line="#ff4fb3", star="#ffd1ea", cool="#8fd8ff"),
    "rasta": dict(line="#f2c24d", star="#fff0c8", cool="#5fe6d2"),
}
# (file stem, theme) per folder. The stem is the retail background's plus -Forever.
OUTPUTS = {
    "installer": (os.path.join("Media", "Background"), {"kitn": "KitnUI-EUI-Background-Forever", "rasta": "KitnUI-EUI-Background-Rasta-Forever"}),
    "options": (os.path.join("KitnUI_EUI", "Media", "Backgrounds"), {"kitn": "KitnUI-EUI-Options-Forever", "rasta": "KitnUI-EUI-Options-Rasta-Forever"}),
}
SURFACES = {
    "installer": dict(
        size=(1024, 808), arch_clip=(772, 62, 174, 75), title_clip=(44, 60, 58, 44),
        cx=840, cy=100, half=60, ring=2.1, blur=1.5, glow=7, body=3.4, core=1.5,
        head=(8.6, 2.6), cross=(6.2, 2.1), left=(4.8, 1.5),
        dust=[(864, 68.5, 1.25, "star", 0.68), (879, 71.5, 1.45, "cool", 0.75), (905, 102, 1.3, "cool", 0.70), (892, 133, 1.3, "star", 0.64)],
        tx=76, ty=82, thalf=23, word=(110.5, 104.5, 13, 1.5)),
    "options": dict(
        size=(1500, 1154), arch_clip=(974, 150, 171, 77), title_clip=(104, 120, 45, 56),
        cx=1060, cy=187, half=80, ring=2.3, blur=1.6, glow=8, body=4, core=1.8,
        head=(9.2, 2.9), cross=(7, 2.4), left=(4.8, 1.7),
        dust=[(1095, 151.8, 1.3, "star", 0.68), (1108, 153.3, 1.1, "cool", 0.75), (1143, 190, 1.2, "cool", 0.70), (1137, 223, 1.35, "star", 0.64)],
        tx=126, ty=148, thalf=20, word=(154, 176, 16, 2)),
}

_t = np.linspace(0, 2 * math.pi, 12000, endpoint=False)
_x = np.cos(_t) * (1 + Q * np.sin(_t) ** 2)
_y = np.sin(2 * _t) * (1 + K * np.cos(2 * _t))
_x, _y = np.r_[_x, _x[0]] / np.abs(_x).max(), np.r_[_y, _y[0]] / np.abs(_y).max() / ASPECT
_s = np.r_[0, np.cumsum(np.hypot(np.diff(_x), np.diff(_y)))]


def at(p):
    """The unit curve at p percent of its arc length, clockwise from the right extreme."""
    d = (np.asarray(p, float) % 100) / 100 * _s[-1]
    return np.interp(d, _s, _x), np.interp(d, _s, _y)


def ring_path(cx, cy, half):
    x, y = at(np.linspace(0, 100, 360, endpoint=False))
    return "M" + " L".join(f"{cx + half * a:.3f} {cy + half * b:.3f}" for a, b in zip(x, y)) + " Z"


def taper(cx, cy, half, p0, p1, w0, w1):
    """A filled outline along the curve whose width runs from w0 to w1, with a round end at p1."""
    n = max(24, int(abs(p1 - p0) * 3))
    ps = np.linspace(p0, p1, n)
    x, y = at(ps)
    x, y = cx + half * x, cy + half * y
    dx, dy = np.gradient(x), np.gradient(y)
    ln = np.hypot(dx, dy) + 1e-9
    nx, ny = -dy / ln, dx / ln
    w = np.linspace(w0, w1, n) / 2
    left = [(a + u * r, b + v * r) for a, b, u, v, r in zip(x, y, nx, ny, w)]
    right = [(a - u * r, b - v * r) for a, b, u, v, r in zip(x, y, nx, ny, w)]
    ang = math.atan2(dy[-1], dx[-1])
    cap = [(x[-1] + w[-1] * math.cos(ang + a), y[-1] + w[-1] * math.sin(ang + a)) for a in np.linspace(math.pi / 2, -math.pi / 2, 9)]
    return "M" + " L".join(f"{a:.2f} {b:.2f}" for a, b in left + cap + right[::-1]) + " Z"


def star(x, y, halo, core, gradient):
    return (f'<circle cx="{x:.3f}" cy="{y:.3f}" r="{halo}" fill="url(#{gradient})"/>'
            f'<circle cx="{x:.3f}" cy="{y:.3f}" r="{core}" fill="#fff"/>')


def svg(s, t):
    cx, cy, half = s["cx"], s["cy"], s["half"]
    tx, ty, thalf = s["tx"], s["ty"], s["thalf"]
    hx, hy = (float(v) for v in at(5))
    ax, ay, aw, ah = s["arch_clip"]
    bx, by, bw, bh = s["title_clip"]
    wx, wy, wsize, wtrack = s["word"]
    dust = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{t[c]}" fill-opacity="{o}"/>' for x, y, r, c, o in s["dust"])
    w, h = s["size"]
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" style="position:fixed;left:0;top:0">
<defs>
  <clipPath id="arch"><rect x="{ax}" y="{ay}" width="{aw}" height="{ah}"/></clipPath>
  <clipPath id="title"><rect x="{bx}" y="{by}" width="{bw}" height="{bh}"/></clipPath>
  <filter id="soft" x="-25%" y="-40%" width="150%" height="180%" color-interpolation-filters="sRGB"><feGaussianBlur stdDeviation="{s['blur']}"/></filter>
  <radialGradient id="cool"><stop offset="0" stop-color="{t['cool']}" stop-opacity="0.90"/><stop offset="0.45" stop-color="{t['cool']}" stop-opacity="0.32"/><stop offset="1" stop-color="{t['cool']}" stop-opacity="0"/></radialGradient>
  <radialGradient id="star"><stop offset="0" stop-color="{t['star']}" stop-opacity="0.80"/><stop offset="0.5" stop-color="{t['star']}" stop-opacity="0.25"/><stop offset="1" stop-color="{t['star']}" stop-opacity="0"/></radialGradient>
</defs>
<g clip-path="url(#arch)">
  <path d="{ring_path(cx, cy, half)}" fill="none" stroke="{t['line']}" stroke-width="{s['ring']}" stroke-opacity="0.78"/>
  <g filter="url(#soft)"><path d="{taper(cx, cy, half, 78, 105, 0, s['glow'])}" fill="{t['cool']}" fill-opacity="0.36"/></g>
  <path d="{taper(cx, cy, half, 78, 105, 0, s['body'])}" fill="{t['cool']}" fill-opacity="0.96"/>
  <path d="{taper(cx, cy, half, 89, 105, 0, s['core'])}" fill="#fff" fill-opacity="0.94"/>
  {star(cx + half * hx, cy + half * hy, *s['head'], 'cool')}
  {star(cx, cy, *s['cross'], 'star')}
  {star(cx - half, cy, *s['left'], 'star')}
  {dust}
</g>
<g clip-path="url(#title)">
  <path d="{ring_path(tx, ty, thalf)}" fill="none" stroke="{t['star']}" stroke-width="2.1" stroke-opacity="0.96"/>
  <path d="{taper(tx, ty, thalf, 82, 105, 0, 2.5)}" fill="{t['cool']}" fill-opacity="0.96"/>
  <path d="{taper(tx, ty, thalf, 94, 105, 0, 1.1)}" fill="#fff"/>
  {star(tx + thalf * hx, ty + thalf * hy, 4.4, 1.9, 'cool')}
</g>
<text x="{wx}" y="{wy}" font-family="Segoe UI Black" font-weight="900" font-size="{wsize}" letter-spacing="{wtrack}" fill="{t['star']}">FOREVER</text>
</svg>"""


def render(markup, size, html_path, png_path):
    with open(html_path, "w", encoding="utf-8") as fh:
        fh.write(f'<!doctype html><html><body style="margin:0;background:transparent">{markup}</body></html>')
    tmp = png_path + ".tmp.png"
    if os.path.exists(tmp):
        os.remove(tmp)
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--default-background-color=00000000",
                    "--force-device-scale-factor=1", f"--window-size={size[0]},{size[1]}", f"--screenshot={tmp}",
                    "file:///" + html_path.replace("\\", "/")], capture_output=True, timeout=90)
    for _ in range(60):
        if os.path.exists(tmp) and os.path.getsize(tmp) > 0:
            break
        time.sleep(0.5)
    time.sleep(0.5)
    rgba = np.array(Image.open(tmp).convert("RGBA"))
    os.remove(tmp)
    os.remove(html_path)
    return rgba


def bleed(rgba, passes=8):
    """Spread color into fully transparent pixels next to the mark, so the game's filter never fringes it dark."""
    out = rgba.astype(np.float64)
    known = out[..., 3] > 0
    for _ in range(passes):
        total, count = np.zeros_like(out[..., :3]), np.zeros(known.shape)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            mask = np.roll(known, (dy, dx), (0, 1))
            total += np.roll(out[..., :3], (dy, dx), (0, 1)) * mask[..., None]
            count += mask
        fill = ~known & (count > 0)
        out[..., :3][fill] = total[fill] / count[fill][..., None]
        known = known | fill
    return np.uint8(np.rint(out))


if __name__ == "__main__":
    for kind, (folder, stems) in OUTPUTS.items():
        s = SURFACES[kind]
        for theme, stem in stems.items():
            png = os.path.join(REPO, folder, stem + ".png")
            rgba = render(svg(s, THEMES[theme]), s["size"], png + ".html", png)
            Image.fromarray(bleed(rgba), "RGBA").save(png, optimize=True)
            ys, xs = np.where(rgba[..., 3] > 0)
            print(stem, os.path.getsize(png), "bytes, drawn box", xs.min(), ys.min(), xs.max(), ys.max())
