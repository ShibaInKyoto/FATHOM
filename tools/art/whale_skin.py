#!/usr/bin/env python3
"""The sperm whale's skin, painted all round its body: x along it from the
flukes (left) to the snout (right), and down the image the way round it from
the belly's midline (top), up one flank (its left), over the back (the
middle row) and down the other flank to the belly again (bottom), each row
a share of the way round rather than metres, so the paint wraps the body
however thick it is there. RGB is the colour, alpha the relief (0.5 flat).

Dark slate grey-brown, darkest along the back; behind the head the skin is
wrinkled like a prune in furrows running round the body. The head is
paler, smoother, and scarred: white rings left by the suckers of squid and
pale rakes of their beaks and of other whales' teeth. White lips along the
lower jaw, white at the corners of the mouth, a pale patch round the eye,
the blowhole an S at the front of the head on its left, a rough pale
callus on the hump, and white blotches on the belly.

The body's sections come from src/world/passing_whale.gd, so the features
keep their size on it:

    python3 tools/art/whale_skin.py   # writes assets/creatures/whale_skin.png
"""
import os
import re

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "src", "world", "passing_whale.gd")
OUT = os.path.join(ROOT, "assets", "creatures", "whale_skin.png")
W, H = 2048, 1024
rng = np.random.default_rng(23)

with open(SRC) as f:
    SOURCE = f.read()


def const_rows(name):
    block = re.search(r"const %s := \[(.*?)\]\n" % name, SOURCE, re.S).group(1)
    return np.array([[float(v) for v in row.split(",")] for row in re.findall(r"\[([-\d., ]+)\]", block)])


def const_float(name):
    return float(re.search(r"const %s := ([-\d.]+)" % name, SOURCE).group(1))


STATIONS = const_rows("STATIONS")
LENGTH = const_float("LENGTH")
EYE_X = const_float("EYE_X")
# The eye sits this far round from the back's midline (radians), as
# passing_whale.gd places it.
EYE_A = float(re.search(r"_surface\(EYE_X, PI \* ([\d.]+)", SOURCE).group(1)) * np.pi
X0 = -LENGTH * 0.5


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    return a + (np.asarray(b) - a) * t


def catmull(field, x):
    """A station value (column [field]) at x, as the game interpolates it."""
    xs = STATIONS[:, 0]
    n = len(xs)
    k = np.clip(np.searchsorted(xs, x, side="left") - 1, 0, n - 2)
    p0, p1 = STATIONS[np.maximum(k - 1, 0), field], STATIONS[k, field]
    p2, p3 = STATIONS[k + 1, field], STATIONS[np.minimum(k + 2, n - 1), field]
    t = np.clip((x - xs[k]) / np.maximum(xs[k + 1] - xs[k], 1e-4), 0.0, 1.0)
    return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def round_share(x, a):
    """How far round from the back's midline the point at x, a radians
    round (as passing_whale.gd lofts it), is, as a share of the way to the
    belly."""
    hw, top, bottom, square = (float(catmull(i, np.array([x]))[0]) for i in (1, 2, 3, 5))
    e = 2.0 / square

    def point(t):
        c, s_ = np.cos(t), np.sin(t)
        r = np.where(c >= 0.0, top, bottom)
        return np.stack([np.sign(c) * np.abs(c) ** e * r, np.sign(s_) * np.abs(s_) ** e * hw], -1)

    ts = np.linspace(0.0, np.pi, 400)
    pts = point(ts)
    arc = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
    return float(np.interp(a, ts, arc) / arc[-1])


# Where each texel lies: x along the body (columns), v round it (rows,
# -1 at the top of the image, 1 at the bottom, 0 the back's midline), and
# how many metres of skin one unit of v spans there.
X = X0 + (np.arange(W)[None, :] + 0.5) / W * LENGTH + np.zeros((H, 1))
V = -1.0 + (np.arange(H)[:, None] + 0.5) / H * 2.0 + np.zeros((1, W))
AV = np.abs(V)
_half_w = catmull(1, X[0])
_tall = 0.5 * (catmull(2, X[0]) + catmull(3, X[0]))
# Half the perimeter of the section (Ramanujan, for the ellipse it nearly is).
_a, _b = np.maximum(_half_w, 0.02), np.maximum(_tall, 0.02)
_h = ((_a - _b) / (_a + _b)) ** 2
HALF_ROUND = (np.pi * (_a + _b) * (1 + 3 * _h / (10 + np.sqrt(4 - 3 * _h))) * 0.5)[None, :] + np.zeros((H, 1))
# Metres round from the back's midline.
M = V * HALF_ROUND
PX_X = W / LENGTH


def noise(cell_x, cell_v):
    """Smooth value noise with features [cell_x] metres along and [cell_v]
    of the way round across."""
    cw = max(cell_x * PX_X, 1.0)
    ch = max(cell_v * H / 2.0, 1.0)
    gw, gh = int(W / cw) + 4, int(H / ch) + 4
    grid = rng.random((gh, gw)).astype(np.float32)
    img = Image.fromarray(grid, mode="F").resize((int(gw * cw), int(gh * ch)), Image.BICUBIC)
    return np.clip(np.asarray(img)[:H, :W], 0.0, 1.0)


def fbm(cell_x, cell_v, octaves=4):
    total = np.zeros((H, W))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += amp * noise(cell_x / 2 ** o, cell_v / 2 ** o)
        norm += amp
        amp *= 0.5
    return total / norm


def blob(field, x, m, r, value=1.0, lobes=3, soft=0.25):
    """An irregular blob about r metres across at x along and m metres round."""
    warp_x = fbm(0.05, 0.02, 2) - 0.5
    warp_m = fbm(0.05, 0.02, 2) - 0.5
    px = X + warp_x * r * 1.2
    pm = M + warp_m * r * 1.2
    out = np.zeros((H, W))
    for k in range(lobes):
        off = rng.normal(0.0, 0.4, 2) * r if k else np.zeros(2)
        rr = r * (rng.uniform(0.55, 0.9) if k else 1.0)
        d = np.sqrt((px - x - off[0]) ** 2 + (pm - m - off[1]) ** 2) / rr
        out = np.maximum(out, 1.0 - smooth(1.0 - soft, 1.0, d))
    np.maximum(field, out * value, out=field)


def local(x, m, r):
    """The rows and columns within r metres of (x, m), and those texels'
    offsets from it."""
    c0 = int(max((x - r - X0) / LENGTH * W, 0))
    c1 = int(min((x + r - X0) / LENGTH * W + 1, W))
    hr = float(np.interp(x, X[0], HALF_ROUND[0]))
    r0 = int(max(((m - r) / hr + 1.0) / 2.0 * H, 0))
    r1 = int(min(((m + r) / hr + 1.0) / 2.0 * H + 1, H))
    return slice(r0, r1), slice(c0, c1)


def ring(field, x, m, r, width, value=1.0):
    """A sucker's scar: a pale ring."""
    rows, cols = local(x, m, r + width * 2)
    d = np.sqrt((X[rows, cols] - x) ** 2 + (M[rows, cols] - m) ** 2)
    hit = 1.0 - smooth(width * 0.4, width, np.abs(d - r))
    field[rows, cols] = np.maximum(field[rows, cols], hit * value)


def rake(field, x, m, length, angle, lines, gap, width, value=1.0):
    """Parallel scratches: [lines] of them [gap] apart, [length] long."""
    rows, cols = local(x, m, length * 0.6 + gap * lines)
    dx, dm = X[rows, cols] - x, M[rows, cols] - m
    along = dx * np.cos(angle) + dm * np.sin(angle)
    across = -dx * np.sin(angle) + dm * np.cos(angle)
    ends = smooth(-length * 0.5, -length * 0.3, along) * (1.0 - smooth(length * 0.3, length * 0.5, along))
    for k in range(lines):
        off = (k - (lines - 1) * 0.5) * gap
        bend = 0.02 * np.sin(along * 4.0 + k)
        hit = (1.0 - smooth(width * 0.3, width, np.abs(across - off - bend))) * ends
        field[rows, cols] = np.maximum(field[rows, cols], hit * value * rng.uniform(0.6, 1.0))


def paint():
    head = smooth(2.2, 3.4, X)
    snout = smooth(7.2, 7.9, X)
    col = np.ones((H, W, 3)) * np.array([0.36, 0.35, 0.34])
    col *= (0.78 + 0.44 * fbm(0.8, 0.3, 4))[..., None]
    # Darkest along the back, a little lighter towards the belly.
    col *= (0.8 + 0.3 * smooth(0.0, 0.9, AV))[..., None]
    # The head paler and greyer.
    col = mix(col, np.array([0.48, 0.48, 0.47]) * (0.85 + 0.3 * fbm(0.5, 0.2, 3))[..., None], head * 0.7)

    # Prune-like wrinkles behind the head: furrows running round the body,
    # wavering, broken into patches; strongest on the flanks.
    # (The contours of a noise stretched round the body: short furrows that
    # meander, fork and close, as the skin of a prune does.)
    n = fbm(0.11, 0.06, 3) + 0.35 * (fbm(0.5, 0.2, 2) - 0.5)
    furrow = (1.0 - np.abs(np.sin(np.pi * n * 7.0))) ** 4
    patchy = 0.45 + 0.55 * smooth(0.3, 0.6, fbm(0.7, 0.3, 3))
    where = smooth(-7.0, -5.5, X) * (1.0 - smooth(1.8, 3.0, X)) * smooth(0.08, 0.3, AV) * (1.0 - smooth(0.8, 0.95, AV))
    wrinkles = furrow * patchy * where
    col *= (1.0 - 0.18 * wrinkles)[..., None]

    # The callus on the hump.
    callus = np.exp(-((X + 3.3) / 0.45) ** 2 - (M / 0.35) ** 2) * smooth(0.35, 0.65, fbm(0.08, 0.04, 2))
    col = mix(col, np.array([0.55, 0.53, 0.5]), callus * 0.7)

    # Scars on the head: rings left by squid suckers, in clusters, and the
    # rakes of beaks and teeth; a scatter of them back along the body.
    scars = np.zeros((H, W))
    for _ in range(12):
        cx = rng.uniform(3.4, 7.7)
        cm = rng.uniform(-3.6, 3.6)
        for _ in range(rng.integers(2, 8)):
            r = float(np.exp(rng.uniform(np.log(0.015), np.log(0.045))))
            ring(scars, cx + rng.normal(0, 0.2), cm + rng.normal(0, 0.2), r, r * 0.3, rng.uniform(0.25, 0.6))
    # Scratched all over the head, most of them faint and old, a few fresh.
    for _ in range(110):
        rake(scars, rng.uniform(3.0, 7.95), rng.uniform(-4.0, 4.0), rng.uniform(0.15, 1.2),
             rng.normal(0.0, 0.7), int(rng.integers(1, 4)), rng.uniform(0.015, 0.04), rng.uniform(0.005, 0.011),
             rng.uniform(0.15, 0.55) if rng.random() < 0.8 else rng.uniform(0.7, 1.0))
    for _ in range(30):
        rake(scars, rng.uniform(-6.5, 3.0), rng.uniform(-3.8, 3.8), rng.uniform(0.2, 0.9),
             rng.normal(0.0, 0.5), int(rng.integers(1, 3)), 0.03, 0.007, rng.uniform(0.15, 0.45))
    col = mix(col, np.array([0.72, 0.71, 0.68]), scars * 0.85)

    # White lips along the lower jaw, the corners of the mouth white, and a
    # pale patch round the eye.
    lips = smooth(0.89, 0.94, AV + 0.02 * (fbm(0.1, 0.02, 2) - 0.5)) \
        * smooth(2.4, 2.9, X) * (1.0 - smooth(7.4, 7.8, X))
    corner = np.exp(-((X - 2.6) / 0.2) ** 2 - ((AV - 0.9) / 0.04) ** 2)
    white = np.clip(np.maximum(lips, corner * 0.7), 0.0, 1.0) * smooth(0.3, 0.55, fbm(0.15, 0.04, 2) + 0.25)
    col = mix(col, np.array([0.7, 0.69, 0.66]), white)
    # A paler, wrinkled patch round the eye (the eye itself is modelled).
    eye_v = round_share(EYE_X, EYE_A)
    eye_ring = np.exp(-((X - EYE_X) / 0.2) ** 2 - ((AV - eye_v) / 0.045) ** 2)
    col = mix(col, np.array([0.42, 0.41, 0.4]), eye_ring * 0.5)

    # White blotches on the belly, between and behind the flippers.
    belly = np.zeros((H, W))
    for _ in range(7):
        side = rng.choice([-1.0, 1.0])
        x = rng.uniform(-3.0, 1.8)
        m = side * float(np.interp(x, X[0], HALF_ROUND[0])) * rng.uniform(0.93, 1.0)
        blob(belly, x, m, rng.uniform(0.12, 0.3), rng.uniform(0.5, 0.9))
    # Streaked a little along the body, and only on its underside.
    belly *= smooth(0.82, 0.95, AV) * smooth(0.3, 0.6, fbm(0.25, 0.015, 2) + 0.2)
    col = mix(col, np.array([0.55, 0.54, 0.52]), belly * 0.7)

    # The blowhole: an S-shaped slit at the front of the head, on its left
    # (the -Z flank, negative v), slanting.
    t = np.clip((X - 7.35) / 0.4, -0.3, 1.3)
    slit_m = -0.18 - 0.07 * np.sin(t * np.pi * 1.6)
    d = np.abs(M - slit_m)
    span = smooth(-0.05, 0.08, t) * (1.0 - smooth(0.92, 1.05, t))
    slit = (1.0 - smooth(0.012, 0.03, d)) * span
    lip = (1.0 - smooth(0.03, 0.07, d)) * span
    col = mix(col, np.array([0.12, 0.12, 0.12]), lip * 0.4)
    col = mix(col, np.array([0.02, 0.02, 0.02]), slit)

    # The snout's front a touch darker, the flukes' stock darkest.
    col *= (1.0 - 0.15 * snout)[..., None]
    col *= (1.0 - 0.2 * (1.0 - smooth(-7.8, -6.5, X)))[..., None]

    # Relief: the wrinkles' ridges, the scars raised a little, the slit sunk.
    grain = fbm(0.03, 0.01, 2) - 0.5
    height = 0.5 + 0.35 * (wrinkles - 0.5 * where * patchy) + 0.12 * grain + 0.15 * scars - 0.5 * slit + 0.2 * callus
    return col, height


def wrap(img):
    """Blends each row towards its mirror near the belly's midline, so the
    two edges of the paint meet there without a seam."""
    w = smooth(0.85, 1.0, AV)[..., None] if img.ndim == 3 else smooth(0.85, 1.0, AV)
    return img + (img[::-1] - img) * 0.5 * w


def main():
    col, height = paint()
    col, height = wrap(col), wrap(height)
    rgba = np.dstack([np.clip(col, 0.0, 1.0), np.clip(height, 0.0, 1.0)])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), mode="RGBA").save(OUT)


if __name__ == "__main__":
    main()
