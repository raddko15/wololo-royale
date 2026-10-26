#!/usr/bin/env python3
"""Generates the building SVGs in assets/art from a few shared shapes, so every
building follows the same rules: light from the top left, a lit front face, a
shaded side face going back to the right, a ground shadow and dark outlines.
Civ-colored parts (flags, banners, shield faces) go in matching *_tint.svg
files drawn in white. Run from the repo root: python3 tools/make_building_art.py
"""
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "art")
INK = "#2b1d10"
C = {  # light, base, shade
    "wood": ("#c08a50", "#a0703f", "#6e4a28"),
    "dark_wood": ("#8a5f36", "#6e4a28", "#4a2f1a"),
    "straw": ("#f0d68a", "#e2c36b", "#b8984a"),
    "plaster": ("#f7f1e3", "#e9dfc9", "#c9bda3"),
    "marble": ("#ffffff", "#ecebe4", "#c9c4b8"),
    "terracotta": ("#df7254", "#c8553d", "#9c3d2a"),
    "slate": ("#6a5a52", "#4a3b35", "#33282a"),
    "stone": ("#d6d2c6", "#b9b4a8", "#8c877c"),
    "mud": ("#c9a27a", "#a8835c", "#7c5d3e"),
}


def svg(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w*2}" height="{h*2}" viewBox="0 0 {w} {h}">\n'
            f'<g stroke="{INK}" stroke-width="1.3" stroke-linejoin="round" stroke-linecap="round">\n{body}\n</g>\n</svg>\n')


def P(*pts):
    return " ".join(f"{x:g},{y:g}" for x, y in pts)


def shadow(cx, cy, rx, ry):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="#000" fill-opacity="0.25" stroke="none"/>'


def box(x, y, w, h, d, mat):
    """A block: front face (x, y)-(x+w, y+h), side face going back-right by d."""
    light, base, shade = C[mat]
    side = P((x + w, y), (x + w + d, y - d / 2), (x + w + d, y + h - d / 2), (x + w, y + h))
    return (f'<polygon points="{side}" fill="{shade}"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{base}"/>'
            f'<rect x="{x}" y="{y}" width="{w/2}" height="{h}" fill="{light}" stroke="none"/>'
            f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="none"/>')


def gable(x, y, w, d, rh, mat, o=2):
    """Gable roof over a box front: front triangle plus the slope running back."""
    light, base, shade = C[mat]
    tri = P((x - o, y), (x + w / 2, y - rh), (x + w + o, y))
    slope = P((x + w / 2, y - rh), (x + w / 2 + d, y - rh - d / 2), (x + w + o + d, y - d / 2), (x + w + o, y))
    return (f'<polygon points="{slope}" fill="{shade}"/>'
            f'<polygon points="{tri}" fill="{base}"/>'
            f'<polygon points="{P((x - o, y), (x + w / 2, y - rh), (x + w / 2, y))}" fill="{light}" stroke="none"/>'
            f'<polygon points="{tri}" fill="none"/>')


def shed_roof(x, y, w, d, mat, o=2, rise=6):
    """Single slope roof seen from the front: a band over the box."""
    light, base, shade = C[mat]
    top = P((x - o, y), (x - o + 4, y - rise), (x + w + o + d - 4, y - rise - d / 2), (x + w + o + d, y - d / 2), (x + w + o, y))
    return (f'<polygon points="{top}" fill="{base}"/>'
            f'<polygon points="{P((x - o, y), (x - o + 4, y - rise), (x + w / 2, y - rise), (x + w / 2, y))}" fill="{light}" stroke="none"/>'
            f'<polygon points="{top}" fill="none"/>')


def door(x, y, w, h, arch=True):
    if arch:
        return f'<path d="M{x} {y+h} L{x} {y+w/2} Q{x+w/2} {y-w/4} {x+w} {y+w/2} L{x+w} {y+h} Z" fill="{INK}"/>'
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{INK}"/>'


def window(x, y, w=4, h=5):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{INK}" stroke="none"/>'


def timber_frame(x, y, w, h):
    """Dark beams on a plaster front (medieval)."""
    beams = [f'<line x1="{x}" y1="{y+h/2}" x2="{x+w}" y2="{y+h/2}" stroke="{C["dark_wood"][2]}" stroke-width="1.6"/>']
    for k in range(1, 4):
        bx = x + w * k / 4
        beams.append(f'<line x1="{bx}" y1="{y}" x2="{bx}" y2="{y+h}" stroke="{C["dark_wood"][2]}" stroke-width="1.6"/>')
    beams.append(f'<line x1="{x}" y1="{y}" x2="{x+w/4}" y2="{y+h/2}" stroke="{C["dark_wood"][2]}" stroke-width="1.2"/>')
    return "".join(beams)


def columns(x, y, w, h, n, mat="marble"):
    light, base, shade = C[mat]
    out = []
    for k in range(n):
        cx = x + 2 + (w - 4) * k / max(n - 1, 1)
        out.append(f'<rect x="{cx-1.6}" y="{y}" width="3.2" height="{h}" fill="{light}" stroke-width="0.9"/>')
        out.append(f'<rect x="{cx-2.4}" y="{y}" width="4.8" height="1.6" fill="{base}" stroke-width="0.8"/>')
    return "".join(out)


def planks(x, y, w, h, mat="wood"):
    light, base, shade = C[mat]
    return "".join(f'<line x1="{x+w*k/5}" y1="{y}" x2="{x+w*k/5}" y2="{y+h}" stroke="{shade}" stroke-width="0.8" stroke-opacity="0.8"/>' for k in range(1, 5))


def logs(x, y, n=3):
    out = []
    for k in range(n):
        cx, cy = x + (k % 2) * 6 + (k // 2) * 3, y - (k // 2) * 5
        out.append(f'<circle cx="{cx}" cy="{cy}" r="3" fill="{C["wood"][1]}" stroke-width="1"/><circle cx="{cx}" cy="{cy}" r="1.3" fill="{C["straw"][0]}" stroke="none"/>')
    return "".join(out)


def flag(x, y):  # pole in the art, cloth in the tint file
    return f'<line x1="{x}" y1="{y}" x2="{x}" y2="{y-14}" stroke-width="1.3"/>'


def flag_tint(x, y):
    return f'<polygon points="{P((x, y-14), (x+10, y-11), (x, y-8))}" fill="#ffffff" stroke-width="1"/>'


ART = {}

# --- Military buildings: 64 x 52, ground line at y=46 -----------------------
def military(kind, look):
    walls = {"era0": "wood", "medieval": "plaster", "classical": "plaster"}[look]
    roof = {"era0": "straw", "medieval": "slate", "classical": "terracotta"}[look]
    b = [shadow(33, 47, 30, 5)]
    t = []
    if kind == "barracks":
        x, y, w, h, d = 10, 26, 34, 20, 12
        b += [box(x, y, w, h, d, walls)]
        if look == "medieval": b.append(timber_frame(x, y, w, h))
        if look == "classical": b.append(columns(x, y, w, h, 4))
        if look == "era0": b.append(planks(x, y, w, h))
        b += [gable(x, y, w, d, 13, roof), door(x + 13, y + 7, 8, 13)]
        b += [f'<line x1="{52+k*3}" y1="46" x2="{50+k*3}" y2="24" stroke-width="1.6" stroke="{C["dark_wood"][1]}"/>' for k in range(3)]
        b += [f'<polygon points="{P((49.5+k*3,24),(51.5+k*3,24),(50.5+k*3,20))}" fill="{C["stone"][0]}" stroke-width="0.8"/>' for k in range(3)]
        b.append(f'<line x1="48" y1="40" x2="60" y2="40" stroke-width="1.6" stroke="{C["dark_wood"][1]}"/>')
        b.append(flag(27, 13)); t.append(flag_tint(27, 13))
    elif kind == "archery_range":
        x, y, w, h, d = 6, 28, 24, 18, 10
        b += [box(x, y, w, h, d, walls)]
        if look == "medieval": b.append(timber_frame(x, y, w, h))
        if look == "classical": b.append(columns(x, y, w, h, 3))
        if look == "era0": b.append(planks(x, y, w, h))
        b += [gable(x, y, w, d, 11, roof), door(x + 8, y + 6, 7, 12)]
        # straw target on legs, rings in the civ color (tint)
        b += [f'<line x1="47" y1="46" x2="49" y2="34" stroke-width="1.8" stroke="{C["dark_wood"][1]}"/>',
              f'<line x1="57" y1="46" x2="55" y2="34" stroke-width="1.8" stroke="{C["dark_wood"][1]}"/>',
              f'<ellipse cx="52" cy="30" rx="9" ry="10" fill="{C["straw"][1]}"/>',
              f'<ellipse cx="52" cy="30" rx="5.6" ry="6.4" fill="#ffffff"/>']
        t.append('<ellipse cx="52" cy="30" rx="2.6" ry="3" fill="#ffffff" stroke-width="1"/>')
        b += [f'<line x1="{x}" y1="{y}" x2="{x}" y2="{y}" />', '<line x1="50" y1="27" x2="58" y2="22" stroke-width="1.1"/>']
    else:  # stables: a long low barn with two stalls and hay
        x, y, w, h, d = 6, 28, 42, 18, 10
        b += [box(x, y, w, h, d, walls)]
        if look == "medieval": b.append(timber_frame(x, y, w, h))
        if look == "classical": b.append(columns(x, y, w, h, 5))
        if look == "era0": b.append(planks(x, y, w, h))
        b.append(shed_roof(x, y, w, d, roof, rise=9))
        for sx in (x + 7, x + 24):
            b.append(door(sx, y + 6, 10, 12, arch=(look == "classical")))
            if look != "classical":
                b.append(f'<line x1="{sx}" y1="{y+6}" x2="{sx+10}" y2="{y+18}" stroke="{C["wood"][1]}" stroke-width="1.2"/>')
        b.append(f'<ellipse cx="58" cy="43" rx="5" ry="3.6" fill="{C["straw"][1]}"/><line x1="54" y1="43" x2="62" y2="43" stroke="{C["straw"][2]}" stroke-width="0.8"/>')
        b.append(flag(30, 18)); t.append(flag_tint(30, 18))
    ART[f"{kind}_{look}.svg"] = svg(64, 52, "".join(b))
    ART[f"{kind}_{look}_tint.svg"] = svg(64, 52, "".join(t))


for kind in ("barracks", "archery_range", "stables"):
    for look in ("era0", "medieval", "classical"):
        military(kind, look)

# Upgrade overlays on the same 64 x 52 frame: shields (level 2), stone base and
# pennants (level 3). Faces of shields and pennants are tinted.
ART["mil_tier1.svg"] = svg(64, 52, "".join(
    f'<circle cx="{x}" cy="38" r="3.6" fill="{C["wood"][1]}" stroke-width="1"/><circle cx="{x}" cy="38" r="1" fill="#d4dade" stroke="none"/>' for x in (8, 47)))
ART["mil_tier1_tint.svg"] = svg(64, 52, "".join(
    f'<path d="M{x} 35.4 A2.6 2.6 0 0 1 {x+2.6} 38 L{x} 38 Z M{x-2.6} 38 L{x} 38 L{x} 40.6 A2.6 2.6 0 0 1 {x-2.6} 38 Z" fill="#ffffff" stroke="none"/>' for x in (8, 47)))
ART["mil_tier2.svg"] = svg(64, 52, f'<rect x="3" y="45" width="56" height="4" fill="{C["stone"][1]}"/>' + "".join(
    f'<line x1="{x}" y1="46" x2="{x}" y2="18" stroke-width="1.4"/>' for x in (3, 61)))
ART["mil_tier2_tint.svg"] = svg(64, 52, "".join(
    f'<polygon points="{P((x, 18), (x + 9 * s, 21), (x, 24))}" fill="#ffffff" stroke-width="1"/>' for x, s in ((3, 1), (61, -1))))

# --- Huts: 24 x 22 ------------------------------------------------------------
def hut(look):
    walls = {"era0": "wood", "medieval": "plaster", "classical": "plaster"}[look]
    roof = {"era0": "straw", "medieval": "slate", "classical": "terracotta"}[look]
    b = [shadow(12, 20, 10, 2.5), box(4, 11, 12, 8, 5, walls)]
    if look == "medieval":
        b.append(f'<line x1="4" y1="15" x2="16" y2="15" stroke="{C["dark_wood"][2]}" stroke-width="1"/><line x1="10" y1="11" x2="10" y2="19" stroke="{C["dark_wood"][2]}" stroke-width="1"/>')
    b += [gable(4, 11, 12, 5, 6, roof, o=1.5), door(8, 14, 4, 5, arch=False)]
    ART[f"hut_{look}.svg"] = svg(24, 22, "".join(b))


for look in ("era0", "medieval", "classical"):
    hut(look)

# --- Wood buildings: 64 x 48, ground at y=42 ---------------------------------
def lean_to():
    b = [shadow(30, 43, 26, 4.5),
         f'<polygon points="{P((8, 42), (16, 12), (40, 42))}" fill="{C["dark_wood"][1]}"/>',
         f'<polygon points="{P((8, 42), (16, 12), (24, 42))}" fill="{C["dark_wood"][0]}" stroke="none"/>',
         f'<polygon points="{P((8, 42), (16, 12), (40, 42))}" fill="none"/>']
    b += [f'<line x1="{12+k*6}" y1="42" x2="{16+k*0.5}" y2="12" stroke="{C["dark_wood"][2]}" stroke-width="1.2"/>' for k in range(4)]
    b += [f'<rect x="44" y="34" width="10" height="8" fill="{C["dark_wood"][1]}"/><ellipse cx="49" cy="34" rx="5" ry="2" fill="{C["wood"][0]}"/>',
          f'<line x1="49" y1="33" x2="56" y2="22" stroke-width="1.6"/><polygon points="{P((53, 22), (58, 21), (57, 26))}" fill="{C["stone"][0]}" stroke-width="0.9"/>',
          logs(24, 40, 3)]
    return svg(64, 48, "".join(b))


def lumber_camp():
    b = [shadow(32, 43, 28, 4.5), box(8, 24, 26, 18, 10, "wood"), planks(8, 24, 26, 18),
         gable(8, 24, 26, 10, 11, "slate"), door(17, 30, 7, 12, arch=False), logs(46, 40, 5),
         f'<line x1="50" y1="27" x2="58" y2="19" stroke-width="1.6"/>']
    return svg(64, 48, "".join(b))


def timber_yard():
    b = [shadow(32, 43, 28, 4.5),
         columns(10, 22, 34, 20, 3, "plaster"), shed_roof(8, 22, 38, 8, "terracotta", rise=7), logs(20, 40, 5),
         f'<line x1="52" y1="42" x2="60" y2="32" stroke-width="1.6" stroke="{C["dark_wood"][1]}"/><line x1="60" y1="42" x2="52" y2="32" stroke-width="1.6" stroke="{C["dark_wood"][1]}"/>']
    return svg(64, 48, "".join(b))


def sawmill():
    b = [shadow(34, 43, 28, 4.5), box(18, 22, 28, 20, 10, "wood"), planks(18, 22, 28, 20),
         gable(18, 22, 28, 10, 11, "slate"), door(27, 30, 8, 12, arch=False),
         f'<rect x="2" y="36" width="16" height="6" fill="#3f6f8f" stroke-width="1"/>',
         ''.join(f'<rect x="{48+k*0}" y="{38-k*3}" width="14" height="2.6" fill="{C["wood"][0]}" stroke-width="0.9"/>' for k in range(3))]
    return svg(64, 48, "".join(b))


def carpentry():
    b = [shadow(32, 43, 28, 4.5), box(10, 24, 32, 18, 9, "plaster"), columns(10, 24, 32, 18, 4),
         gable(10, 24, 32, 9, 11, "terracotta"), door(22, 31, 8, 11),
         ''.join(f'<rect x="46" y="{39-k*3}" width="15" height="2.6" fill="{C["wood"][0]}" stroke-width="0.9"/>' for k in range(3))]
    return svg(64, 48, "".join(b))


ART["lean_to.svg"] = lean_to()
ART["lumber_camp.svg"] = lumber_camp()
ART["timber_yard.svg"] = timber_yard()
ART["sawmill.svg"] = sawmill()
ART["carpentry.svg"] = carpentry()

# --- Food buildings: 64 x 56, ground at y=50 (windmill blades turn in code) ---
def windmill_base(grand=False):
    if grand:
        b = [shadow(30, 51, 22, 4.5), box(20, 20, 18, 30, 7, "stone"), gable(20, 20, 18, 7, 13, "slate"),
             door(25, 38, 8, 12), window(27, 27),
             ''.join(f'<circle cx="{48+k*5}" cy="47" r="3.2" fill="#d9c49a" stroke-width="1"/>' for k in range(3))]
    else:
        b = [shadow(30, 51, 20, 4.5), box(20, 26, 18, 24, 7, "stone"), gable(20, 26, 18, 7, 10, "wood"),
             door(25, 38, 8, 12), ''.join(f'<circle cx="{48+k*5}" cy="47" r="3" fill="#d9c49a" stroke-width="1"/>' for k in range(2))]
    return svg(64, 56, "".join(b))


def olive_press(big=False):
    w = 30 if not big else 34
    b = [shadow(30, 51, 26, 4.5), box(8, 30, w, 20, 9, "plaster")]
    if big:
        b.append(columns(8, 30, w, 20, 4))
    b += [gable(8, 30, w, 9, 11, "terracotta"), door(8 + w / 2 - 4, 37, 8, 13)]
    b += [f'<ellipse cx="52" cy="46" rx="8" ry="4" fill="{C["stone"][1]}"/>', f'<circle cx="52" cy="42" r="4" fill="{C["stone"][0]}"/>',
          f'<line x1="52" y1="42" x2="60" y2="32" stroke-width="1.6" stroke="{C["dark_wood"][1]}"/>']
    n = 5 if big else 2
    for k in range(n):
        ax = 4 + k * 5 if not big else 46 + (k % 3) * 5
        ay = 48 if not big else 36 - (k // 3) * 0
        b.append(f'<ellipse cx="{ax}" cy="{ay}" rx="2.2" ry="3" fill="{C["terracotta"][1]}" stroke-width="0.9"/>')
    return svg(64, 56, "".join(b))


ART["windmill_base.svg"] = windmill_base()
ART["grand_mill_base.svg"] = windmill_base(grand=True)
ART["olive_press.svg"] = olive_press()
ART["oil_workshop.svg"] = olive_press(big=True)

# --- Town centers: 170 x 140, ground at y=122 (Era I and the wooden fort are
# hand-drawn files: longhouse.svg, fort_wood.svg) -----------------------------
def battlements(x, y, w, mat="stone", step=10):
    light, base, shade = C[mat]
    return "".join(f'<rect x="{x+k}" y="{y-5}" width="6" height="5" fill="{base}" stroke-width="1"/>' for k in range(0, int(w) - 4, step))


def castle_stone():
    b = [shadow(86, 126, 82, 11),
         box(28, 52, 116, 24, 10, "stone"), battlements(28, 52, 116),          # back curtain wall
         box(60, 30, 50, 60, 16, "stone"), battlements(60, 30, 50),              # keep
         window(70, 44), window(95, 44), window(70, 62), window(95, 62),
         box(16, 86, 140, 34, 10, "stone"), battlements(16, 86, 140),            # front wall
         ''.join(f'<line x1="16" y1="{86+r*11}" x2="156" y2="{86+r*11}" stroke="{C["stone"][2]}" stroke-width="0.8"/>' for r in (1, 2)),
         door(72, 94, 28, 26), ''.join(f'<line x1="{76+k*5}" y1="100" x2="{76+k*5}" y2="120" stroke="#6f6a60" stroke-width="1.2"/>' for k in range(5)),
         box(2, 70, 26, 52, 8, "stone"), box(144, 70, 26, 52, 8, "stone"),      # corner towers
         battlements(2, 70, 26, step=8), battlements(144, 70, 26, step=8),
         window(13, 88), window(155, 88), flag(85, 16)]
    t = [f'<polygon points="{P((56, 30), (85, 10), (114, 30))}" fill="#ffffff"/><polygon points="{P((85, 10), (114, 30), (126, 22), (101, 3))}" fill="#a8a8a8"/>',
         f'<polygon points="{P((0, 66), (15, 48), (30, 66))}" fill="#ffffff"/><polygon points="{P((15, 48), (30, 66), (36, 62))}" fill="#a8a8a8"/>',
         f'<polygon points="{P((142, 66), (157, 48), (172, 66))}" fill="#ffffff"/><polygon points="{P((157, 48), (172, 66), (176, 62))}" fill="#a8a8a8"/>',
         flag_tint(85, 16)]
    return svg(178, 140, "".join(b)), svg(178, 140, "".join(t))


def timber_hall():
    b = [shadow(86, 126, 80, 11),
         box(14, 112, 140, 10, 12, "dark_wood"),                                 # platform
         box(24, 66, 120, 46, 12, "wood"), planks(24, 66, 120, 46),
         door(72, 84, 24, 28),
         ''.join(f'<rect x="{x}" y="66" width="6" height="46" fill="{C["wood"][0]}" stroke-width="1"/><rect x="{x-1.5}" y="63" width="9" height="4" fill="{C["dark_wood"][1]}" stroke-width="1"/>' for x in (26, 46, 116, 136)),
         gable(18, 62, 132, 14, 34, "terracotta", o=6),
         ''.join(f'<line x1="{84-72*(1-k*7/34)+3}" y1="{62-k*7}" x2="{84+72*(1-k*7/34)-3}" y2="{62-k*7}" stroke="{C["terracotta"][2]}" stroke-width="1" stroke-opacity="0.7"/>' for k in range(1, 4)),
         flag(84, 28)]
    t = [flag_tint(84, 28), '<circle cx="84" cy="50" r="5" fill="#ffffff" stroke-width="1.2"/>']
    return svg(178, 140, "".join(b)), svg(178, 140, "".join(t))


def marble_palace():
    b = [shadow(86, 128, 84, 11)]
    for k in range(3):  # steps
        b.append(box(8 + k * 6, 112 - k * 6, 152 - k * 12, 6, 12, "marble"))
    b += [box(30, 58, 108, 42, 12, "marble"), door(74, 74, 20, 26),
          columns(26, 58, 116, 42, 7),
          box(22, 48, 124, 10, 12, "marble")]                                   # entablature
    tri = P((18, 48), (84, 14), (150, 48))
    b += [f'<polygon points="{P((84, 14), (96, 8), (162, 42), (150, 48))}" fill="{C["terracotta"][2]}"/>',
          f'<polygon points="{tri}" fill="{C["marble"][1]}"/>',
          f'<polygon points="{P((34, 44), (84, 20), (134, 44))}" fill="{C["marble"][2]}"/>',
          ''.join(f'<line x1="{x}" y1="112" x2="{x}" y2="56" stroke-width="1.4"/>' for x in (4, 164))]
    t = ['<rect x="22" y="51" width="124" height="3.5" fill="#ffffff" stroke-width="0.9"/>',
         '<circle cx="84" cy="34" r="6" fill="#ffffff" stroke-width="1.2"/>',
         ''.join(f'<rect x="{x - (8 if x > 84 else 0)}" y="56" width="8" height="22" fill="#ffffff" stroke-width="1"/>' for x in (4, 164))]
    return svg(178, 140, "".join(b)), svg(178, 140, "".join(t))


for name, fn in (("castle_stone", castle_stone), ("timber_hall", timber_hall), ("marble_palace", marble_palace)):
    ART[name + ".svg"], ART[name + "_tint.svg"] = fn()

for name, text in ART.items():
    with open(os.path.join(OUT, name), "w") as f:
        f.write(text)
print(f"wrote {len(ART)} files")
