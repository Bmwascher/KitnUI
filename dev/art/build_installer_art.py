"""Build the installer wizard backgrounds (KitnUI and KitnUI Rasta) as SVG and
render them to the PNGs the wizard loads.

Geometry is in wizard frame units (760 x 560, Installer/Wizard.lua). The PNG is
1024 x 808 and the wizard crops it with ART_CROP {0.065, 0.940, 0.099, 0.916},
so the frame sits at image x 66.56..962.56, y 80..740.1: 1.1789 px per unit.
The SVG viewBox maps frame units straight onto that, so no code changes.

Features the wizard positions against (Wizard.lua):
  sidebar 0..178 (SIDEBAR_W 176, divider ~178), step rail y 76..393 (11 rows of 29)
  header band to y 103 (Desc1 at y 116 clears it), glow line at y 73
  footer rule y 520 (Back/Next below it, progress bar at y 504..510)
  close box centered at 746,14 (26 x 24 hit area)
  version text centered at x 88 near the bottom, divider at y 526

Run: python -I dev/art/build_installer_art.py   (needs Pillow, numpy, Edge)
"""
import base64, io, math, os, random, subprocess, time
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
IMG_W, IMG_H = 1024, 808
K = 896 / 760
VB = (-66.56 / K, -80 / K, IMG_W / K, IMG_H / K)
W, H = 760, 560
SIDE = 178
CX, CY, S = 468, 300, 0.85

THEMES = {
    "KitnUI": dict(
        file="KitnUI-EUI-Background", logo="pink",
        window=("#2a0f24", "#1e0a1a", "#170814"), sidebar=("#1a0916", "#220c1d"), header=("#2c1027", "#1f0b1b"),
        band="#1b0918", content="#3a1232", accent="#ff008c", line="#ff4fb3", rule="#a8357f", border="#c2408f",
        star="#ffd1ea", eye="#ffb3dc", title="#fff0f8", side_line="#ff4fb3",
        glow=(("#ff008c", 0.15), ("#ff4fb3", 0.9), ("#ff008c", 0.35)), wash=None, box="#c2408f", glyph="#ffd1ea",
        blunt=False),
    "Rasta": dict(
        file="KitnUI-EUI-Background-Rasta", logo="teal",
        window=("#13201d", "#0f1513", "#140c0b"), sidebar=("#0b1715", "#0e1c19"), header=("#141b17", "#0f1311"),
        band="#0d1110", content="#2a2212", accent="#f2a33a", line="#f2c24d", rule="#8c7a3c", border="url(#border)",
        star="#fff0c8", eye="#ffd27a", title="#c8fff4", side_line="#2fd6c0",
        glow=(("#2fd6c0", 0.35), ("#f2b33d", 0.9), ("#e0483c", 0.9)),
        wash=(("#2fd6c0", 0.13), ("#f2b33d", 0.07), ("#e0483c", 0.17)), box="#e0483c", glyph="#ffd9cf",
        blunt=True),
}


def cat_logo(kind):
    src = Image.open(os.path.join(HERE, "kitnui-cathead.png")).convert("RGBA").resize((96, 96), Image.LANCZOS)
    if kind == "teal":
        a = np.asarray(src).astype(np.float64) / 255.0
        lum = 0.3 * a[..., 0] + 0.59 * a[..., 1] + 0.11 * a[..., 2]
        lum = np.clip(lum / max(lum[a[..., 3] > 0.2].max(), 1e-6), 0, 1) ** 0.8
        dark, light = np.array([4, 34, 32]) / 255.0, np.array([150, 255, 236]) / 255.0
        rgb = dark + (light - dark) * lum[..., None]
        src = Image.fromarray((np.dstack([rgb, a[..., 3]]) * 255).round().astype(np.uint8), "RGBA")
    buf = io.BytesIO()
    src.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def star(x, y, r, color):
    return (f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{color}" filter="url(#soft)"/>'
            f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r * 0.55:.2f}" fill="#fff"/>')


def P(x, y):
    return CX + x * S, CY + y * S


def poly(points, closed=False):
    d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in (P(*p) for p in points))
    return d + (" Z" if closed else "")


def constellation(t):
    rnd = random.Random(7)
    field = []
    for _ in range(55):
        x, y = rnd.uniform(190, 750), rnd.uniform(112, 512)
        if abs(x - CX) < 130 and abs(y - CY) < 130:
            continue
        r = rnd.choice([0.6, 0.8, 0.8, 1.0, 1.3, 1.7])
        field.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{t["star"]}" opacity="{rnd.uniform(0.25, 0.8):.2f}"/>')
    outline = [(-92, -138), (-118, -52), (-128, 8), (-98, 62), (-50, 94), (0, 104), (50, 94), (98, 62), (128, 8),
               (118, -52), (92, -138), (40, -82), (0, -88), (-40, -82)]
    ear_l, ear_r = [(-92, -138), (-80, -82), (-56, -84)], [(92, -138), (80, -82), (56, -84)]
    nose, mouth, mark = (0, 38), [(-18, 58), (0, 50), (18, 58)], (0, -46)
    whiskers = [((-34, 46), (-178, 22)), ((-34, 52), (-184, 52)), ((-32, 58), (-172, 84)),
                ((34, 46), (178, 22)), ((34, 52), (184, 52)), ((32, 58), (172, 84))]
    lines = [(poly(outline, True), 0.5, 1.3), (poly(ear_l), 0.3, 1), (poly(ear_r), 0.3, 1),
             (poly([nose, (0, 50)]) + " " + poly(mouth), 0.4, 1)]
    lines += [(poly([a, b]), 0.18, 0.9) for a, b in whiskers]
    out = [f'<circle cx="{CX}" cy="{CY}" r="190" fill="url(#catGlow)" opacity="0.7"/>'] + field
    out += [f'<path d="{d}" fill="none" stroke="{t["line"]}" stroke-opacity="{o}" stroke-width="{w}" stroke-linejoin="round"/>'
            for d, o, w in lines]
    for ex in (-48, 48):
        (x0, y0), (x1, y1), (xc, yc) = P(ex - 22, -8), P(ex + 22, -8), P(ex, -24)
        out.append(f'<path d="M{x0:.1f} {y0:.1f} Q{xc:.1f} {yc:.1f} {x1:.1f} {y1:.1f}" fill="none" stroke="{t["eye"]}" '
                   f'stroke-opacity="0.7" stroke-width="1.7" stroke-linecap="round" filter="url(#glow)"/>')
    out += [star(*P(*p), 3.4, t["star"]) for p in outline]
    out += [star(*P(*p), 2.5, t["star"]) for p in (ear_l[1], ear_l[2], ear_r[1], ear_r[2])]
    out += [star(*P(*nose), 3.3, t["star"]), star(*P(*mark), 5.2, t["star"])]
    out += [star(*P(*b), 2, t["star"]) for _, b in whiskers]
    if t["blunt"]:
        out.append(blunt())
    return "\n    ".join(out)


def blunt():
    (x0, y0), (x1, y1) = P(20, 57), P(150, 100)
    ang = math.atan2(y1 - y0, x1 - x0)
    nx, ny = -math.sin(ang), math.cos(ang)
    off = lambda x, y, d: f"{x + nx * d:.1f} {y + ny * d:.1f}"
    bx, by = x1 - math.cos(ang) * 15, y1 - math.sin(ang) * 15
    ex, ey = x1 + math.cos(ang) * 4, y1 + math.sin(ang) * 4
    return f"""<g id="blunt">
      <path d="M{off(x0, y0, -3.4)} L{off(x1, y1, -5.5)} L{off(x1, y1, 5.5)} L{off(x0, y0, 3.4)} Z" fill="#f2c24d" fill-opacity="0.08" stroke="#f2c24d" stroke-opacity="0.55" stroke-width="1.1" stroke-linejoin="round"/>
      <path d="M{off(bx, by, -5.2)} L{off(bx, by, 5.2)}" stroke="#f2c24d" stroke-opacity="0.4" stroke-width="0.9"/>
      <circle cx="{ex:.1f}" cy="{ey:.1f}" r="17" fill="#e0483c" fill-opacity="0.4" filter="url(#emberHaze)"/>
      <circle cx="{ex:.1f}" cy="{ey:.1f}" r="6" fill="#ff7a3c" filter="url(#soft)"/>
      <circle cx="{ex:.1f}" cy="{ey:.1f}" r="3" fill="#ffe2b0"/>
      <path d="M{ex:.1f} {ey - 5:.1f} C {ex + 12:.1f} {ey - 26:.1f}, {ex - 14:.1f} {ey - 45:.1f}, {ex + 2:.1f} {ey - 68:.1f} S {ex + 19:.1f} {ey - 102:.1f}, {ex + 4:.1f} {ey - 128:.1f}" fill="none" stroke="#fff0c8" stroke-opacity="0.22" stroke-width="1.9" stroke-linecap="round" filter="url(#soft)"/>
      <path d="M{ex + 3:.1f} {ey - 17:.1f} C {ex + 17:.1f} {ey - 34:.1f}, {ex + 2:.1f} {ey - 53:.1f}, {ex + 14:.1f} {ey - 78:.1f}" fill="none" stroke="#fff0c8" stroke-opacity="0.14" stroke-width="1.4" stroke-linecap="round" filter="url(#soft)"/>
    </g>"""


def sidebar_flare(t):
    rnd = random.Random(23)
    dust = []
    for _ in range(24):
        x, y = rnd.uniform(6, 172), rnd.uniform(418, 518)
        if 58 <= x <= 118 and 430 <= y <= 500:
            continue
        dust.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{rnd.choice([0.6, 0.8, 1.0, 1.2])}" fill="{t["star"]}" opacity="{rnd.uniform(0.2, 0.6):.2f}"/>')
    px, py = 88, 468
    toes = [(px - 23, py - 14, -30), (px - 8, py - 25, -10), (px + 8, py - 25, 10), (px + 23, py - 14, 30)]
    pad = [(px, py - 10), (px - 15, py + 18), (px, py + 23), (px + 15, py + 18)]
    pad_d = (f"M{px-21} {py+10} C{px-21} {py-6} {px-10} {py-10} {px} {py-10} "
             f"C{px+10} {py-10} {px+21} {py-6} {px+21} {py+10} "
             f"C{px+21} {py+18} {px+15} {py+22} {px+10} {py+19} "
             f"C{px+6} {py+25} {px-6} {py+25} {px-10} {py+19} "
             f"C{px-15} {py+22} {px-21} {py+18} {px-21} {py+10} Z")
    c = t["side_line"]
    toe_rings = "".join(f'<ellipse cx="{x}" cy="{y}" rx="5.5" ry="7.5" transform="rotate({r} {x} {y})" fill="{c}" fill-opacity="0.08" stroke="{c}" stroke-opacity="0.45" stroke-width="1"/>'
                        for x, y, r in toes)
    return f"""<g id="sidebar-flare">
      <circle cx="0" cy="{H}" r="170" fill="url(#cornerGlow)"/>
      {"".join(dust)}
      <g transform="translate({px} {py}) scale(1.1) translate({-px} {-py})">
      <path d="{pad_d}" fill="{c}" fill-opacity="0.06" stroke="{c}" stroke-opacity="0.45" stroke-width="1.1" stroke-linejoin="round"/>
      {toe_rings}
      {"".join(star(x, y, 2.2, t["star"]) for x, y in pad)}
      {"".join(star(x, y, 2.6, t["star"]) for x, y, _ in toes)}
      </g>
    </g>"""


def build(name, t):
    g0, g1, g2 = t["glow"]
    wash_defs = wash_rects = ""
    if t["wash"]:
        w0, w1, w2 = t["wash"]
        wash_defs = f"""
    <linearGradient id="wash" x1="0" y1="0" x2="1" y2="0.35">
      <stop offset="0" stop-color="{w0[0]}" stop-opacity="{w0[1]}"/><stop offset="0.45" stop-color="{w1[0]}" stop-opacity="{w1[1]}"/><stop offset="1" stop-color="{w2[0]}" stop-opacity="{w2[1]}"/>
    </linearGradient>
    <linearGradient id="border" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="{g0[0]}" stop-opacity="0.8"/><stop offset="0.5" stop-color="{g1[0]}" stop-opacity="0.7"/><stop offset="1" stop-color="{g2[0]}" stop-opacity="0.85"/>
    </linearGradient>"""
        wash_rects = f'<rect x="0" y="0" width="{W}" height="{H}" fill="url(#wash)"/>'
    corner = t["side_line"] if t["blunt"] else t["accent"]
    vb = " ".join(f"{v:.3f}" for v in VB)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!-- KitnUI installer background ({name}). Generated by build_installer_art.py;
     edit the script, not this file. Frame units: the wizard is 760 x 560. -->
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"
     width="{IMG_W}" height="{IMG_H}" viewBox="{vb}">
  <defs>
    <linearGradient id="windowFill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{t['window'][0]}"/><stop offset="0.5" stop-color="{t['window'][1]}"/><stop offset="1" stop-color="{t['window'][2]}"/>
    </linearGradient>
    <linearGradient id="sidebarFill" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="{t['sidebar'][0]}"/><stop offset="1" stop-color="{t['sidebar'][1]}"/>
    </linearGradient>
    <linearGradient id="headerFill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{t['header'][0]}"/><stop offset="1" stop-color="{t['header'][1]}"/>
    </linearGradient>
    <linearGradient id="glowLine" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="{g0[0]}" stop-opacity="{g0[1]}"/><stop offset="0.75" stop-color="{g1[0]}" stop-opacity="{g1[1]}"/><stop offset="1" stop-color="{g2[0]}" stop-opacity="{g2[1]}"/>
    </linearGradient>
    <radialGradient id="contentGlow" cx="0.5" cy="0.45" r="0.6">
      <stop offset="0" stop-color="{t['content']}" stop-opacity="0.9"/><stop offset="1" stop-color="{t['content']}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="arcFill" cx="0.5" cy="1" r="0.75">
      <stop offset="0" stop-color="{t['accent']}" stop-opacity="0.18"/><stop offset="1" stop-color="{t['accent']}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="catGlow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="{t['accent']}" stop-opacity="0.22"/><stop offset="1" stop-color="{t['accent']}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="cornerGlow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="{corner}" stop-opacity="0.22"/><stop offset="1" stop-color="{corner}" stop-opacity="0"/>
    </radialGradient>{wash_defs}
    <filter id="glow" x="-5%" y="-200%" width="110%" height="500%">
      <feGaussianBlur stdDeviation="2.5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="1.9"/></filter>
    <filter id="emberHaze" x="-150%" y="-150%" width="400%" height="400%"><feGaussianBlur stdDeviation="6"/></filter>
    <clipPath id="headerClip"><rect x="{SIDE}" y="0" width="{W - SIDE}" height="73"/></clipPath>
    <clipPath id="frameClip"><rect x="0" y="0" width="{W}" height="{H}"/></clipPath>
  </defs>

  <rect x="{VB[0]:.2f}" y="{VB[1]:.2f}" width="{VB[2]:.2f}" height="{VB[3]:.2f}" fill="#000"/>

  <g id="window" clip-path="url(#frameClip)">
    <rect x="0" y="0" width="{W}" height="{H}" fill="url(#windowFill)"/>
    <rect x="0" y="0" width="{SIDE}" height="{H}" fill="url(#sidebarFill)"/>
    <rect x="{SIDE}" y="0" width="{W - SIDE}" height="73" fill="url(#headerFill)"/>
    <g clip-path="url(#headerClip)">
      <circle cx="590" cy="98" r="120" fill="url(#arcFill)"/>
      <circle cx="590" cy="98" r="120" fill="none" stroke="{t['line']}" stroke-opacity="0.14" stroke-width="1.2"/>
    </g>
    <rect x="{SIDE}" y="73" width="{W - SIDE}" height="30" fill="{t['band']}"/>
    <rect x="{SIDE}" y="103" width="{W - SIDE}" height="417" fill="url(#contentGlow)"/>
    <rect x="{SIDE}" y="520" width="{W - SIDE}" height="40" fill="{t['band']}"/>
    {wash_rects}
    {sidebar_flare(t)}
  </g>

  <g id="center">
    {constellation(t)}
  </g>

  <g id="lines" fill="none">
    <line x1="{SIDE - 0.5}" y1="0" x2="{SIDE - 0.5}" y2="{H}" stroke="{t['side_line']}" stroke-opacity="0.7" stroke-width="1.2"/>
    <path d="M0 45.5 H139 L145 40.5 H{SIDE - 1}" stroke="{t['side_line']}" stroke-opacity="0.8" stroke-width="1.2" filter="url(#glow)"/>
    <path d="M{SIDE} 73.5 H707 L715 66.5 H{W}" stroke="url(#glowLine)" stroke-width="1.6" filter="url(#glow)"/>
    <line x1="{SIDE}" y1="103.5" x2="{W}" y2="103.5" stroke="{t['rule']}" stroke-opacity="0.6" stroke-width="0.9"/>
    <line x1="{SIDE}" y1="520.5" x2="{W}" y2="520.5" stroke="{t['rule']}" stroke-opacity="0.7" stroke-width="0.9"/>
    <path d="M14 405.5 H90 L98 413.5 H{SIDE - 1}" stroke="{t['side_line']}" stroke-opacity="0.3" stroke-width="0.9"/>
    <rect x="0.6" y="0.6" width="{W - 1.2}" height="{H - 1.2}" stroke="{t['border']}" stroke-opacity="0.9" stroke-width="1.2"/>
  </g>

  <g id="logo">
    <circle cx="31" cy="22" r="22" fill="url(#catGlow)"/>
    <image x="12" y="3" width="38" height="38" xlink:href="{cat_logo(t['logo'])}"/>
    <text x="56" y="30" font-family="Segoe UI Black, Segoe UI, Arial, sans-serif" font-size="21" font-weight="900" letter-spacing="0.4" fill="{t['title']}" stroke="{t['accent'] if not t['blunt'] else t['side_line']}" stroke-opacity="0.35" stroke-width="0.8" filter="url(#glow)">KitnUI</text>
  </g>

  <g id="close-box">
    <rect x="734.5" y="3.5" width="23" height="21" rx="2.5" fill="{t['band']}" fill-opacity="0.85" stroke="{t['box']}" stroke-width="1.1"/>
    <path d="M741 9 L751 19 M751 9 L741 19" fill="none" stroke="{t['glyph']}" stroke-width="1.5" stroke-linecap="round"/>
  </g>
</svg>
"""


def render(svg_path, png_path):
    tmp = png_path + ".tmp.png"
    if os.path.exists(tmp):
        os.remove(tmp)
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--default-background-color=000000ff",
                    "--force-device-scale-factor=1", f"--window-size={IMG_W},{IMG_H}", f"--screenshot={tmp}",
                    "file:///" + svg_path.replace("\\", "/")], capture_output=True, timeout=90)
    for _ in range(60):
        if os.path.exists(tmp) and os.path.getsize(tmp) > 0:
            break
        time.sleep(0.5)
    time.sleep(0.5)
    Image.open(tmp).convert("RGB").save(png_path, optimize=True)
    os.remove(tmp)


if __name__ == "__main__":
    for name, t in THEMES.items():
        svg_path = os.path.join(HERE, f"{t['file']}.svg")
        with open(svg_path, "w", encoding="utf-8") as fh:
            fh.write(build(name, t))
        png = os.path.join(REPO, "Media", "Background", f"{t['file']}.png")
        render(svg_path, png)
        print(name, os.path.getsize(png))
