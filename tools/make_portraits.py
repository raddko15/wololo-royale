#!/usr/bin/env python3
"""Writes the troop card portraits: assets/art/portrait2/<unit>_<tier>_<k>.svg.

Each portrait is a stack of layers drawn in order k = 0, 1, ...; a layer
named ..._tint.svg is drawn in the civ's color (it is white and grey, so its
shading survives the tint). Run: python3 tools/make_portraits.py
"""
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "art", "portrait2")
INK = "#2b160a"
W = 'stroke="%s" stroke-width="2" stroke-linejoin="round"' % INK

DEFS = """<defs>
<radialGradient id="skin" cx="0.4" cy="0.35" r="0.75"><stop offset="0" stop-color="#f8d7b4"/><stop offset="1" stop-color="#d49a6c"/></radialGradient>
<linearGradient id="cloth" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#a9a9a9"/></linearGradient>
<linearGradient id="steel" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#e9edf1"/><stop offset="0.45" stop-color="#a7afb8"/><stop offset="1" stop-color="#5d646d"/></linearGradient>
<linearGradient id="bronze" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#ffe29a"/><stop offset="0.5" stop-color="#c98f2e"/><stop offset="1" stop-color="#7a4f14"/></linearGradient>
<linearGradient id="wood" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#b07a45"/><stop offset="1" stop-color="#6b4022"/></linearGradient>
<linearGradient id="hairb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7a4a22"/><stop offset="1" stop-color="#4a2a12"/></linearGradient>
<linearGradient id="horse" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#b8743c"/><stop offset="1" stop-color="#6e3e1a"/></linearGradient>
<linearGradient id="hood" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5f9a4a"/><stop offset="1" stop-color="#2f5a28"/></linearGradient>
<linearGradient id="straw" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f3d77c"/><stop offset="1" stop-color="#c9a23e"/></linearGradient>
</defs>"""


class P:
    def __init__(self):
        self.parts = []  # (tinted, svg)

    def add(self, svg, tint=False):
        self.parts.append((tint, svg))

    def layers(self):
        out = []
        for tint, svg in self.parts:
            if out and out[-1][0] == tint:
                out[-1][1].append(svg)
            else:
                out.append((tint, [svg]))
        return out


# --- People ----------------------------------------------------------------

def body(p):
    p.add('<path d="M12 100 C13 83 22 72 37 68 L63 68 C78 72 87 83 88 100 Z" fill="url(#cloth)" %s/>'
          '<path d="M30 80 C32 88 31 95 30 100 M70 80 C68 88 69 95 70 100" stroke="#8c8c8c" stroke-width="1.5" fill="none"/>' % W, True)


def neck(p):
    p.add('<path d="M42 56 L42 70 C46 74 54 74 58 70 L58 56 Z" fill="#d49a6c" %s/>' % W)
    p.add('<path d="M37 68 C42 76 58 76 63 68" fill="none" stroke="%s" stroke-width="2.5"/>'
          '<path d="M38 69.5 C43 77 57 77 62 69.5" fill="none" stroke="#c9a23e" stroke-width="1.6"/>' % INK)


def head(p, beard=False, face=True):
    p.add('<ellipse cx="35" cy="41" rx="3.6" ry="5.5" fill="#e0aa7e" %s/>'
          '<ellipse cx="65" cy="41" rx="3.6" ry="5.5" fill="#e0aa7e" %s/>' % (W, W))
    p.add('<path d="M35 37 C35 23 42 18 50 18 C58 18 65 23 65 37 C65 50 59 59 50 59 C41 59 35 50 35 37 Z" fill="url(#skin)" %s/>' % W)
    if beard:
        p.add('<path d="M35.5 41 C36 54 43 62 50 62 C57 62 64 54 64.5 41 C62 47 58 49 55 48.5 L45 48.5 C42 49 38 47 35.5 41 Z" fill="url(#hairb)" %s/>'
              '<path d="M42 50 C46 47 54 47 58 50 C55 51 52 50.5 50 49.5 C48 50.5 45 51 42 50 Z" fill="#4a2a12"/>' % W)
    if face:
        eyes = ''
        for x in (44, 56):
            eyes += '<ellipse cx="%d" cy="39.5" rx="2.8" ry="2" fill="#fff"/><circle cx="%.1f" cy="39.7" r="1.45" fill="#3a2410"/>' % (x, x + 0.3)
        p.add(eyes +
              '<path d="M40 35.5 L47.5 34.5 M52.5 34.5 L60 35.5" stroke="#4a2a12" stroke-width="2.2" stroke-linecap="round"/>'
              '<path d="M50 40 L48 47 L51.5 47.5" fill="none" stroke="#b07850" stroke-width="1.5" stroke-linejoin="round"/>'
              '<ellipse cx="41" cy="46" rx="3" ry="1.8" fill="#e8907a" opacity="0.45"/><ellipse cx="59" cy="46" rx="3" ry="1.8" fill="#e8907a" opacity="0.45"/>')
        p.add('<path d="M45.5 52 Q50 54.5 54.5 52" fill="none" stroke="%s" stroke-width="1.6" stroke-linecap="round"/>'
              % ("#e9c9a8" if beard else "#7a3a22"))


def hair(p):
    p.add('<path d="M34 38 C32 20 41 14 50 14 C59 14 68 20 66 38 C64 31 61 27 57 26 C52 29 45 28 41 25 C38 28 35 32 34 38 Z" fill="url(#hairb)" %s/>' % W)


def straw_hat(p):
    p.add('<ellipse cx="50" cy="28" rx="27" ry="6.5" fill="url(#straw)" %s/>'
          '<path d="M37 27 C37 15 43 10 50 10 C57 10 63 15 63 27 Z" fill="url(#straw)" %s/>'
          '<path d="M37.5 23 L62.5 23" stroke="#8b5a2b" stroke-width="3"/>' % (W, W))


def nasal_helm(p):
    p.add('<path d="M33 35 C33 19 41 13 50 13 C59 13 67 19 67 35 Z" fill="url(#steel)" %s/>'
          '<path d="M33 33 L67 33 L67 37 L33 37 Z" fill="#7d858e" %s/>'
          '<path d="M48 35 L52 35 L51.5 47 L48.5 47 Z" fill="url(#steel)" %s/>'
          '<path d="M41 18 C44 16 47 15.5 50 15.5" stroke="#fff" stroke-width="2" fill="none" stroke-linecap="round" opacity="0.8"/>' % (W, W, W))


def great_helm(p):
    p.add('<path d="M32 24 C32 15 40 12 50 12 C60 12 68 15 68 24 L68 56 C62 60 38 60 32 56 Z" fill="url(#steel)" %s/>'
          '<path d="M34 37 L66 37 L66 41 L34 41 Z" fill="#1d1d22"/>'
          '<path d="M50 41 L50 58" stroke="#5d646d" stroke-width="2.5"/>'
          '<path d="M48 12 L52 12 L52 37 L48 37 Z" fill="#c9a23e" stroke="#2b160a" stroke-width="1.2"/>'
          '<circle cx="42" cy="48" r="1"  fill="#1d1d22"/><circle cx="42" cy="52" r="1" fill="#1d1d22"/><circle cx="58" cy="48" r="1" fill="#1d1d22"/><circle cx="58" cy="52" r="1" fill="#1d1d22"/>'
          '<path d="M36 20 C38 16 42 15 45 15" stroke="#fff" stroke-width="2" fill="none" stroke-linecap="round" opacity="0.8"/>' % W)


def kettle_hat(p):
    p.add('<path d="M22 32 C30 28 70 28 78 32 C74 36 26 36 22 32 Z" fill="url(#steel)" %s/>'
          '<path d="M35 31 C35 18 42 13 50 13 C58 13 65 18 65 31 Z" fill="url(#steel)" %s/>'
          '<path d="M50 13 L50 31" stroke="#5d646d" stroke-width="1.6"/>' % (W, W))


def hood(p):
    p.add('<path d="M30 50 C27 24 38 12 50 12 C62 12 73 24 70 50 C72 62 80 68 84 76 L16 76 C20 68 28 62 30 50 Z" fill="url(#hood)" %s/>' % W)


def hood_front(p):
    p.add('<path d="M37 36 C37 26 43 21 50 21 C57 21 63 26 63 36 C60 30 55 27 50 27 C45 27 40 30 37 36 Z" fill="#2f5a28" opacity="0.6"/>')


def corinthian(p):
    p.add('<path d="M32 40 C30 18 40 12 50 12 C60 12 70 18 68 40 L66 58 L57 60 L56 46 L44 46 L43 60 L34 58 Z" fill="url(#bronze)" %s/>'
          '<path d="M38 37 L46 36 L48 46 L44 46 Z M62 37 L54 36 L52 46 L56 46 Z" fill="#2a1a08"/>'
          '<path d="M48.5 36 L51.5 36 L51 48 L49 48 Z" fill="url(#bronze)" %s/>'
          '<path d="M38 18 C41 15 45 14 48 14" stroke="#fff4c8" stroke-width="2" fill="none" stroke-linecap="round"/>' % (W, W))


def crest(p):
    p.add('<path d="M28 20 C30 4 70 4 72 20 C66 12 34 12 28 20 Z" fill="url(#cloth)" %s/>'
          '<path d="M34 14 L36 9 M42 11 L43 6 M50 10 L50 5 M58 11 L57 6 M66 14 L64 9" stroke="#8c8c8c" stroke-width="1.4"/>' % W, True)


def plume(p):
    p.add('<path d="M58 14 C62 0 78 -2 86 4 C78 6 72 10 68 18 Z" fill="url(#cloth)" %s/>' % W, True)


# --- Gear ------------------------------------------------------------------

def club(p):
    p.add('<path d="M70 100 L76 46 L74 30 C75 22 85 22 86 30 L84 46 L78 100 Z" fill="url(#wood)" %s/>'
          '<circle cx="77" cy="34" r="1.6" fill="#4a2a12"/><circle cx="82" cy="40" r="1.6" fill="#4a2a12"/>' % W)


def sword(p):
    p.add('<path d="M77 64 L79 10 L82 4 L85 10 L83 64 Z" fill="url(#steel)" %s/>'
          '<path d="M70 64 L92 64 L92 69 L70 69 Z" fill="#c9a23e" %s/>'
          '<path d="M78 69 L84 69 L84 84 L78 84 Z" fill="#5b3a1e" %s/>' % (W, W, W))


def spear(p, x=80):
    p.add('<path d="M%d 100 L%d 22" stroke="%s" stroke-width="5" stroke-linecap="round"/>'
          '<path d="M%d 100 L%d 22" stroke="#8b5a2b" stroke-width="2.6" stroke-linecap="round"/>'
          '<path d="M%d 24 L%d 6 L%d 24 L%d 28 Z" fill="url(#steel)" %s/>'
          % (x, x + 4, INK, x, x + 4, x + 1, x + 4, x + 7, x + 4, W))


def round_shield(p):
    p.add('<circle cx="26" cy="84" r="20" fill="url(#cloth)" %s/>'
          '<path d="M26 64 L26 104 M6 84 L46 84" stroke="#9a9a9a" stroke-width="3"/>' % W, True)
    p.add('<circle cx="26" cy="84" r="20" fill="none" stroke="#7d858e" stroke-width="3"/>'
          '<circle cx="26" cy="84" r="20" fill="none" stroke="%s" stroke-width="1.2"/>'
          '<circle cx="26" cy="84" r="5.5" fill="url(#steel)" %s/>' % (INK, W))


def aspis(p):
    p.add('<circle cx="28" cy="82" r="23" fill="url(#cloth)" %s/>' % W, True)
    p.add('<circle cx="28" cy="82" r="23" fill="none" stroke="url(#bronze)" stroke-width="4"/>'
          '<circle cx="28" cy="82" r="25" fill="none" stroke="%s" stroke-width="1.2"/>'
          '<path d="M19 92 L28 72 L37 92" fill="none" stroke="#c98f2e" stroke-width="4" stroke-linejoin="round"/>' % INK)


def mail(p):
    rings = ''
    for row in range(4):
        y = 72 + row * 5
        for i in range(-6, 7):
            x = 50 + i * 5 + (2.5 if row % 2 else 0)
            if abs(x - 50) < 13 + row * 6:
                rings += '<path d="M%.1f %.1f q2.5 3 5 0" fill="none" stroke="#5d646d" stroke-width="1"/>' % (x - 2.5, y)
    p.add('<path d="M22 84 C26 75 32 71 38 69 L62 69 C68 71 74 75 78 84 C70 88 30 88 22 84 Z" fill="url(#steel)" %s/>' % W + rings)


def bow(p):
    p.add('<path d="M74 18 C92 36 92 72 74 98" fill="none" stroke="%s" stroke-width="6" stroke-linecap="round"/>'
          '<path d="M74 18 C92 36 92 72 74 98" fill="none" stroke="#9a6a35" stroke-width="3.4" stroke-linecap="round"/>'
          '<path d="M74 18 L74 98" stroke="#efe6cf" stroke-width="1"/>' % INK)


def quiver(p):
    p.add('<path d="M18 22 L26 18 L40 64 L32 68 Z" fill="#7a4a22" %s/>'
          '<path d="M19 21 L14 10 M22 19 L19 8 M25 18 L24 7" stroke="#3a2410" stroke-width="1.4"/>'
          '<path d="M12 8 L16 4 L18 11 Z M17 6 L21 3 L22 10 Z M22 5 L26 2 L27 9 Z" fill="#e8e1cf" stroke="#2b160a" stroke-width="1"/>' % W)


def crossbow(p):
    p.add('<path d="M30 92 L76 60 L80 66 L34 98 Z" fill="url(#wood)" %s/>'
          '<path d="M56 56 C64 60 74 72 76 82" fill="none" stroke="%s" stroke-width="5" stroke-linecap="round"/>'
          '<path d="M56 56 C64 60 74 72 76 82" fill="none" stroke="#a7afb8" stroke-width="2.6" stroke-linecap="round"/>'
          '<path d="M56 56 L76 82" stroke="#efe6cf" stroke-width="1"/>' % (W, INK))


def hoe(p):
    p.add('<path d="M74 100 L80 18" stroke="%s" stroke-width="5" stroke-linecap="round"/>'
          '<path d="M74 100 L80 18" stroke="#9a6a35" stroke-width="2.6" stroke-linecap="round"/>'
          '<path d="M78 16 L92 22 L90 27 L79 23 Z" fill="url(#steel)" %s/>' % (INK, W))


def lance(p):
    p.add('<path d="M66 100 L90 2" stroke="%s" stroke-width="5" stroke-linecap="round"/>'
          '<path d="M66 100 L90 2" stroke="#9a6a35" stroke-width="2.6" stroke-linecap="round"/>' % INK)


def pennant(p):
    p.add('<path d="M88 10 L64 14 L72 18 L64 22 L86 20 Z" fill="url(#cloth)" %s/>' % W, True)


# --- Horses and wheels -----------------------------------------------------

def horse(p):
    """A horse's head and neck in profile, facing left, at the lower left."""
    p.add('<path d="M22 52 L21 42 L27 49 Z" fill="#8a5428" %s/>'
          '<path d="M27 50 C22 54 14 64 6 75 C3 80 4 86 9 87.5 C13 88.5 17 86 20 83 C23 81 26 81 28 83 '
          'C30 88 30 94 30 100 L48 100 C46 86 42 72 36 60 C34 55 31 51 27 50 Z" fill="url(#horse)" %s/>'
          '<path d="M27 49 C33 51 41 59 45 71 C47 81 49 91 50 100 L45 100 C43 88 41 76 37 66 C34 60 31 55 27 49 Z" fill="#3a2410" %s/>'
          '<ellipse cx="20" cy="61" rx="2" ry="1.6" fill="#1a0f05"/><circle cx="19.4" cy="60.5" r="0.6" fill="#fff"/>'
          '<ellipse cx="8" cy="80" rx="1.4" ry="1" fill="#1a0f05"/>'
          '<path d="M6 83 C9 85 12 85 14 84" fill="none" stroke="#4a2a12" stroke-width="1.2"/>'
          '<path d="M11 73 L18 79 M24 57 L13 81 M18 79 L28 83" fill="none" stroke="#4a2a12" stroke-width="1.8"/>' % (W, W, W))


def barding(p):
    p.add('<path d="M27 86 C32 82 41 82 46 85 L49 100 L29 100 C30 95 29 90 27 86 Z" fill="url(#cloth)" %s/>'
          '<path d="M30 92 L47 92" stroke="#9a9a9a" stroke-width="2"/>' % W, True)


def chamfron(p):
    p.add('<path d="M24 54 L28 58 L15 78 L10 76 Z" fill="url(#steel)" %s/>'
          '<circle cx="22" cy="60" r="1.2" fill="#c9a23e"/>' % W)


def wheel(p):
    spokes = ''.join('<path d="M80 84 L%.1f %.1f" stroke="#6b4022" stroke-width="2"/>' % (80 + 15 * c, 84 + 15 * s)
                     for c, s in ((1, 0), (0.5, 0.87), (-0.5, 0.87), (-1, 0), (-0.5, -0.87), (0.5, -0.87)))
    p.add('<circle cx="80" cy="84" r="16" fill="none" stroke="%s" stroke-width="6"/><circle cx="80" cy="84" r="16" fill="none" stroke="#9a6a35" stroke-width="3.5"/>' % INK
          + spokes + '<circle cx="80" cy="84" r="3.5" fill="#c9a23e" %s/>' % W)


# --- Troops ----------------------------------------------------------------

def person(p, top=None, beard=False, front=None, face=True, behind_head=None):
    body(p)
    if behind_head:
        behind_head(p)
    neck(p)
    head(p, beard, face)
    for t in (top or []):
        t(p)
    for f in (front or []):
        f(p)


def rider(p, **kw):
    """The rider a little smaller and to the right; then the horse."""
    sub = P()
    person(sub, **kw)
    for tint, svg in sub.parts:
        p.add('<g transform="translate(12 6) scale(0.9)">%s</g>' % svg, tint)


def mounted(p, gear_back, rider_kw, horse_gear):
    for g in gear_back:
        g(p)
    rider(p, **rider_kw)
    horse(p)
    for g in horse_gear:
        g(p)


PORTRAITS = {
    "villager": [lambda p: (hoe(p), person(p, top=[hair, straw_hat]))],
    "fighter": [
        lambda p: (club(p), person(p, top=[hair], beard=True)),
        lambda p: (club(p), person(p, top=[nasal_helm], beard=True, front=[round_shield])),
        lambda p: (sword(p), person(p, top=[great_helm], face=False, front=[mail, round_shield])),
    ],
    "archer": [
        lambda p: (person(p, top=[hair], front=[bow])),
        lambda p: (quiver(p), person(p, top=[hood_front], behind_head=hood, front=[bow])),
        lambda p: (quiver(p), person(p, top=[kettle_hat], beard=True, front=[crossbow])),
    ],
    "phalanx": [lambda p: (spear(p), person(p, top=[crest, corinthian], face=False, front=[aspis]))],
    "cavalry": [
        lambda p: mounted(p, [lance], {"top": [hair]}, []),
        lambda p: mounted(p, [lance], {"top": [hair], "beard": True}, [barding]),
        lambda p: mounted(p, [lance], {"top": [nasal_helm], "beard": True}, [barding, chamfron]),
    ],
    "knight": [lambda p: mounted(p, [lance, pennant], {"top": [plume, great_helm], "face": False}, [barding, chamfron])],
    "chariot": [
        lambda p: mounted(p, [], {"top": [hair], "front": [bow]}, [wheel]),
        lambda p: mounted(p, [], {"top": [nasal_helm], "front": [bow]}, [barding, wheel]),
    ],
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".svg"):
            os.remove(os.path.join(OUT, f))
    for unit, tiers in PORTRAITS.items():
        for tier, make in enumerate(tiers):
            p = P()
            make(p)
            for k, (tint, svgs) in enumerate(p.layers()):
                name = "%s_%d_%d%s.svg" % (unit, tier, k, "_tint" if tint else "")
                with open(os.path.join(OUT, name), "w") as f:
                    f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="128" height="128">%s%s</svg>\n'
                            % (DEFS, "".join(svgs)))


main()
