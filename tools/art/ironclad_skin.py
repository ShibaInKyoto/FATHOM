#!/usr/bin/env python3
"""The Ironclad's painted skin: x along its body from the tail shield (left)
to the head (right), and down the image the way round it from the back's
midline (top) to the belly's (bottom), the same on both flanks. RGB is the
colour, alpha the relief (0.5 flat).

Dark, hammered iron plates. Along every plate's trailing edge the metal is
rubbed bright, then heat-tinted as tempered steel is (straw, bronze,
purple, blue) by the molten flesh beneath its seams, fading back into iron
across the plate. Rust blooms on the flanks and runs down them in streaks
from the seams, the iron is pitted, sulphur and pale mineral crust heaps
round the chimneys on its back and in the seams towards the tail, and the
head and front plates are scraped and gouged by everything that has failed
to get through them. The belly is duller, its segments lined.

The plates come from src/creatures/boss/ironclad_model.gd, so the bands sit
on their edges:

    python3 tools/art/ironclad_skin.py   # writes assets/creatures/ironclad_skin.png
"""
import os
import re

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "src", "creatures", "boss", "ironclad_model.gd")
OUT = os.path.join(ROOT, "assets", "creatures", "ironclad_skin.png")
W, H = 2048, 1024
rng = np.random.default_rng(41)

with open(SRC) as f:
    SOURCE = f.read()


def const_floats(name):
    return [float(v) for v in re.search(r"const %s := \[([-\d., ]+)\]" % name, SOURCE).group(1).split(",")]


def const_rows(name):
    block = re.search(r"const %s := \[(.*?)\]\n" % name, SOURCE, re.S).group(1)
    return np.array([[float(v) for v in row.split(",")] for row in re.findall(r"\[([-\d., ]+)\]", block)])


def const_float(name):
    return float(re.search(r"const %s := ([-\d.]+)" % name, SOURCE).group(1))


def const_vec4(name):
    return [float(v) for v in re.search(r"const %s := Vector4\(([-\d., ]+)\)" % name, SOURCE).group(1).split(",")]


BODY = const_rows("BODY")
PLATES = const_floats("PLATES")
CHIMNEYS = const_rows("CHIMNEYS")
NOSE = const_float("NOSE")
FLANK_BACK = const_float("FLANK_BACK")
EPIMERA = const_vec4("EPIMERA")
BOX = const_vec4("PAINT_BOX")
X0, LENGTH = BOX[0], BOX[2]


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    return a + (np.asarray(b) - a) * t


def catmull(field, x):
    """A body station value (column [field]) at x, as the game interpolates it."""
    xs = BODY[:, 0]
    n = len(xs)
    k = np.clip(np.searchsorted(xs, x, side="left") - 1, 0, n - 2)
    p0, p1 = BODY[np.maximum(k - 1, 0), field], BODY[k, field]
    p2, p3 = BODY[k + 1, field], BODY[np.minimum(k + 2, n - 1), field]
    t = np.clip((x - xs[k]) / np.maximum(xs[k + 1] - xs[k], 1e-4), 0.0, 1.0)
    return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


# Where each texel lies: x along the body (columns), w radians round from
# the back's midline (rows), and about how many units of skin that is.
X = X0 + (np.arange(W)[None, :] + 0.5) / W * LENGTH + np.zeros((H, 1))
WA = (np.arange(H)[:, None] + 0.5) / H * np.pi + np.zeros((1, W))
_hw = np.maximum(catmull(1, X[0]), 0.05)
_tall = np.maximum(0.5 * (catmull(2, X[0]) + catmull(3, X[0])), 0.03)
_h = ((_hw - _tall) / (_hw + _tall)) ** 2
HALF_ROUND = (np.pi * (_hw + _tall) * (1 + 3 * _h / (10 + np.sqrt(4 - 3 * _h))) * 0.5)[None, :] + np.zeros((H, 1))
M = WA / np.pi * HALF_ROUND
PX = W / LENGTH


def noise(cell_x, cell_m):
    """Smooth value noise, its features about [cell_x] units along and
    [cell_m] round."""
    cw = max(cell_x * PX, 1.0)
    ch = max(cell_m * H / 2.3, 1.0)
    gw, gh = int(W / cw) + 4, int(H / ch) + 4
    grid = rng.random((gh, gw)).astype(np.float32)
    img = Image.fromarray(grid, mode="F").resize((int(gw * cw), int(gh * ch)), Image.BICUBIC)
    return np.clip(np.asarray(img)[:H, :W], 0.0, 1.0)


def fbm(cell_x, cell_m, octaves=4):
    total = np.zeros((H, W))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += amp * noise(cell_x / 2 ** o, cell_m / 2 ** o)
        norm += amp
        amp *= 0.5
    return total / norm


def flank(w):
    return smooth(EPIMERA[0], EPIMERA[1], w) * (1.0 - smooth(EPIMERA[2], EPIMERA[3], w))


def plates():
    """Which plate covers each texel, and how far ahead of its trailing
    edge (as the model draws the body plates' flanks back) it lies."""
    which = np.full((H, W), len(PLATES) - 1)
    ahead = np.zeros((H, W))
    rears = []
    for k, rear in enumerate(PLATES):
        back = FLANK_BACK * flank(WA) if 1 <= k <= 7 else 0.0
        rears.append(rear - back)
    for k in range(len(PLATES) - 1, -1, -1):
        hit = X >= rears[k]
        which[hit] = k
        ahead[hit] = (X - rears[k])[hit]
    return which, ahead


def blob(field, x, m, r, value=1.0, lobes=4, soft=0.3):
    """An irregular blob about r units across at x along and m round."""
    warp_x = fbm(0.06, 0.06, 2) - 0.5
    warp_m = fbm(0.06, 0.06, 2) - 0.5
    px = X + warp_x * r * 1.3
    pm = M + warp_m * r * 1.3
    out = np.zeros((H, W))
    for k in range(lobes):
        off = rng.normal(0.0, 0.45, 2) * r if k else np.zeros(2)
        rr = r * (rng.uniform(0.5, 0.9) if k else 1.0)
        d = np.sqrt((px - x - off[0]) ** 2 + (pm - m - off[1]) ** 2) / rr
        out = np.maximum(out, 1.0 - smooth(1.0 - soft, 1.0, d))
    np.maximum(field, out * value, out=field)


def scratch(field, x, m, length, angle, width, value=1.0):
    """A straight scratch, a little wavering, fading in and out at its ends."""
    dx, dm = X - x, M - m
    along = dx * np.cos(angle) + dm * np.sin(angle)
    across = -dx * np.sin(angle) + dm * np.cos(angle) + 0.006 * np.sin(along * 30.0)
    ends = smooth(-length * 0.5, -length * 0.35, along) * (1.0 - smooth(length * 0.2, length * 0.5, along))
    hit = (1.0 - smooth(width * 0.3, width, np.abs(across))) * ends
    np.maximum(field, hit * value, out=field)


def paint():
    which, ahead = plates()
    width = np.array([(NOSE if k == 0 else PLATES[k - 1]) - PLATES[k] for k in range(len(PLATES))])[which]
    body_plate = (which >= 1) & (which <= 7)
    belly = smooth(2.1, 2.45, WA)

    # Hammered iron, dark and blued, a little warmer here and there.
    col = np.ones((H, W, 3)) * np.array([0.26, 0.245, 0.24])
    col *= (0.8 + 0.4 * fbm(0.6, 0.6, 4))[..., None]
    col = mix(col, col * np.array([1.12, 1.0, 0.9]), smooth(0.45, 0.75, fbm(0.9, 0.9, 3)) * 0.6)
    dents = fbm(0.05, 0.05, 3) - 0.5
    col *= (1.0 + 0.12 * dents)[..., None]

    # Each plate's trailing edge rubbed bright, then the heat tints across
    # it as tempered steel takes them: straw, bronze, purple, blue.
    wobble = 0.03 * (fbm(0.08, 0.15, 3) - 0.5)
    t = np.clip((ahead + wobble) / np.minimum(0.12, width * 0.35), 0.0, 1.0)
    stops = np.array([0.0, 0.14, 0.32, 0.5, 0.72, 1.0])
    tints = np.array([[0.56, 0.45, 0.27], [0.5, 0.33, 0.2], [0.38, 0.24, 0.34], [0.24, 0.27, 0.44],
                      [0.25, 0.27, 0.33], [0.26, 0.245, 0.24]])
    tint = np.stack([np.interp(t, stops, tints[:, c]) for c in range(3)], -1)
    heat = (0.45 + 0.55 * fbm(0.3, 0.3, 3)) * (1.0 - 0.6 * smooth(1.3, 2.2, WA)) * (1.0 - belly)
    heat *= np.where(which == 0, 0.45, 0.7)
    col = mix(col, tint * (col / 0.26), heat * (1.0 - t))
    edge = (1.0 - smooth(0.006, 0.02, ahead)) * (1.0 - belly)
    col = mix(col, np.array([0.56, 0.53, 0.5]), edge * 0.65)

    # Rust: blooms on the flanks, and streaks run down them from the seams.
    bloom = smooth(0.58, 0.78, fbm(0.35, 0.35, 4)) * (0.35 + 0.65 * smooth(0.9, 1.9, WA))
    streak = smooth(0.58, 0.74, noise(0.022, 0.6)) * smooth(0.85, 1.35, WA) * (1.0 - smooth(1.95, 2.3, WA))
    streak *= smooth(0.3, 0.6, fbm(0.4, 1.0, 2)) * (1.0 - smooth(0.1, 0.3, ahead / np.maximum(width, 0.05)) * 0.5)
    rust = np.clip(bloom + streak * 0.8, 0.0, 1.0) * (1.0 - belly * 0.6)
    rust_col = mix(np.array([0.42, 0.2, 0.09]), np.array([0.56, 0.31, 0.13]), fbm(0.08, 0.08, 2))
    col = mix(col, rust_col, rust * 0.75)

    # Pitting.
    pits = smooth(0.8, 0.86, noise(0.011, 0.011)) * smooth(0.45, 0.75, fbm(0.4, 0.4, 2))
    col = mix(col, np.array([0.14, 0.11, 0.1]), pits * 0.5)

    # Mineral crust: heaped round the chimneys, in the seams towards the
    # tail, over the tail shield.
    crust = np.zeros((H, W))
    for c in CHIMNEYS:
        x, z, h = c
        hw = float(catmull(1, np.array([x]))[0])
        w = np.arcsin(min(abs(z) / hw, 1.0) ** (1.0 / 0.85))
        m = w / np.pi * float(np.interp(x, X[0], HALF_ROUND[0]))
        for _ in range(2):
            blob(crust, x + rng.normal(0.0, 0.04), m + rng.normal(0.0, 0.04), 0.06 + 0.2 * h, rng.uniform(0.7, 1.0))
    seam_crust = (1.0 - smooth(0.015, 0.05, ahead)) * smooth(-0.3, -1.2, X) * smooth(0.55, 0.75, fbm(0.15, 0.2, 3))
    tail_crust = smooth(-1.7, -1.95, X) * smooth(0.64, 0.76, fbm(0.1, 0.1, 3))
    crust = np.maximum(crust * smooth(0.25, 0.5, fbm(0.05, 0.05, 3) + 0.2), np.maximum(seam_crust, tail_crust))
    crust *= 1.0 - belly
    crust_col = mix(np.array([0.74, 0.67, 0.42]), np.array([0.7, 0.69, 0.64]), fbm(0.06, 0.06, 2))
    col = mix(col, crust_col, crust * 0.9)

    # Scrapes and gouges on the head and front plates; a few further back.
    scr = np.zeros((H, W))
    gouge = np.zeros((H, W))
    for _ in range(36):
        x = rng.uniform(0.3, 2.3) if rng.random() < 0.75 else rng.uniform(-1.6, 0.3)
        scratch(scr, x, rng.uniform(0.0, 1.8), rng.uniform(0.15, 0.7), rng.normal(0.4, 0.6),
                rng.uniform(0.004, 0.009), rng.uniform(0.35, 1.0))
    for _ in range(3):
        x = rng.uniform(0.6, 2.1)
        scratch(gouge, x, rng.uniform(0.1, 1.2), rng.uniform(0.3, 0.6), rng.normal(0.2, 0.3), 0.014)
    scr *= 1.0 - belly
    gouge *= 1.0 - belly
    col = mix(col, np.array([0.6, 0.58, 0.56]), scr * 0.7)
    gouge_rim = np.clip(gouge * 1.6, 0.0, 1.0) - np.clip(gouge * 3.0 - 1.6, 0.0, 1.0)
    col = mix(col, np.array([0.66, 0.63, 0.6]), gouge_rim * 0.8)
    col = mix(col, np.array([0.16, 0.14, 0.13]), np.clip(gouge * 3.0 - 1.6, 0.0, 1.0) * 0.8)

    # The belly: duller, browner, each segment lined.
    seg = np.zeros((H, W))
    for rear in PLATES:
        seg = np.maximum(seg, 1.0 - smooth(0.006, 0.02, np.abs(X - rear)))
    belly_col = np.array([0.36, 0.31, 0.27]) * (0.85 + 0.3 * fbm(0.3, 0.3, 3))[..., None]
    belly_col = mix(belly_col, np.array([0.16, 0.13, 0.12]), seg * 0.8)
    col = mix(col, belly_col, belly)

    # Relief: hammered dents, the crust heaped up, pits and scrapes sunk.
    height = 0.5 + 0.18 * dents + 0.35 * crust - 0.3 * pits - 0.15 * scr - 0.35 * np.clip(gouge * 3.0 - 1.6, 0, 1) \
        + 0.12 * gouge_rim + 0.06 * rust + 0.1 * edge
    return col, height


def main():
    col, height = paint()
    rgba = np.dstack([np.clip(col, 0.0, 1.0), np.clip(height, 0.0, 1.0)])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), mode="RGBA").save(OUT)


if __name__ == "__main__":
    main()
