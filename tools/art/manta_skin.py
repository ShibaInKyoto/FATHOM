#!/usr/bin/env python3
"""The Shelf Manta's skin: its back and its belly, painted over the disc as
seen from above and from below, across the whole span so that no two wings
are alike. RGB is the colour, alpha the relief (0.5 flat).

The back: near-black, darker down the spine and greying out towards the
wingtips; a white chevron over each shoulder, its inner edge crisp beside
the dark stem down the back, breaking into streaks out along the wing, with
dark freckles in it; old bite scars, nicks and fine speckling; the skin's
grain and the faint ridges of the fin rays in its relief.

The belly: white, a dark band across the mouth, five gill slits either
side, a scatter of dark spots (each manta's own), the wings edged in grey
and their tips dark.

The disc's outline and the box the paint covers come from
src/creatures/manta.gd, so the paint always fits it:

    python3 tools/art/manta_skin.py   # writes assets/creatures/manta_back.png and manta_belly.png
"""
import os
import re

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "src", "creatures", "manta.gd")
OUT = os.path.join(ROOT, "assets", "creatures")
W, H = 2048, 656
rng = np.random.default_rng(11)


def read_source():
    with open(SRC) as f:
        return f.read()


SOURCE = read_source()


def table(name):
    """A const array of Vector2 (z, value) points from manta.gd."""
    m = re.search(r"const %s := \[(.*?)\]\n" % name, SOURCE, re.S)
    pts = re.findall(r"Vector2\(([-\d.]+), ([-\d.]+)\)", m.group(1))
    return np.array([[float(a), float(b)] for a, b in pts])


def paint_box():
    m = re.search(r"const PAINT_BOX := Vector4\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\)", SOURCE)
    return [float(v) for v in m.groups()]


X_FRONT, Z_SIDE, LENGTH, SPAN = paint_box()
LEAD = table("LEAD")
TRAIL = table("TRAIL")
HALF = LEAD[-1, 0]


def curve(pts, z):
    """The smooth curve through pts at z, as Manta._edge draws it."""
    n = len(pts)
    i = np.clip(np.searchsorted(pts[:, 0], z, side="left"), 1, n - 1)
    a, b = pts[i - 1], pts[i]
    before, after = pts[np.maximum(i - 2, 0)], pts[np.minimum(i + 1, n - 1)]
    f = np.clip((z - a[..., 0]) / np.maximum(b[..., 0] - a[..., 0], 1e-4), 0.0, 1.0)
    p0, p1, p2, p3 = before[..., 1], a[..., 1], b[..., 1], after[..., 1]
    return 0.5 * (2 * p1 + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * f ** 3)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    return a + (np.asarray(b) - a) * t


# Where each texel lies: z across the span (columns), x from the head back
# (rows); and how far back across its wing's chord it is (0 at the leading
# edge, 1 at the trailing edge).
Z = Z_SIDE + (np.arange(W)[None, :] + 0.5) / W * SPAN + np.zeros((H, 1))
X = X_FRONT - (np.arange(H)[:, None] + 0.5) / H * LENGTH + np.zeros((1, W))
AZ = np.abs(Z)
_az = np.minimum(AZ, HALF)
LEAD_X = curve(LEAD, _az)
TRAIL_X = curve(TRAIL, _az)
C = np.clip((LEAD_X - X) / np.maximum(LEAD_X - TRAIL_X, 0.02), -0.5, 1.5)
PX = W / SPAN


def noise(cell, aspect=1.0):
    """Smooth value noise with features about [cell] metres across (and
    [aspect] times that along the span)."""
    cw = max(cell * aspect * PX, 1.0)
    ch = max(cell * PX, 1.0)
    gw, gh = int(W / cw) + 4, int(H / ch) + 4
    grid = rng.random((gh, gw)).astype(np.float32)
    img = Image.fromarray(grid, mode="F").resize((int(gw * cw), int(gh * ch)), Image.BICUBIC)
    return np.clip(np.asarray(img)[:H, :W], 0.0, 1.0)


def fbm(cell, octaves=4, aspect=1.0):
    total = np.zeros((H, W))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += amp * noise(cell / 2 ** o, aspect)
        norm += amp
        amp *= 0.5
    return total / norm


# Fine warps every spot's outline is pushed about by, so none is round.
WARP_X = None
WARP_Z = None


def warps():
    global WARP_X, WARP_Z
    if WARP_X is None:
        WARP_X = fbm(0.025, 3) - 0.5
        WARP_Z = fbm(0.025, 3) - 0.5


def stamp(field, x, z, r, value=1.0, lobes=3, soft=0.25):
    """An irregular spot about r across at (x, z): a few overlapping lobes,
    its outline pushed about by fine noise."""
    warps()
    c = int((z - Z_SIDE) / SPAN * W)
    row = int((X_FRONT - x) / LENGTH * H)
    reach = int(r * PX * 2.2 + 4)
    r0, r1 = max(row - reach, 0), min(row + reach + 1, H)
    c0, c1 = max(c - reach, 0), min(c + reach + 1, W)
    if r0 >= r1 or c0 >= c1:
        return
    px = X[r0:r1, c0:c1] + WARP_X[r0:r1, c0:c1] * r * 1.4
    pz = Z[r0:r1, c0:c1] + WARP_Z[r0:r1, c0:c1] * r * 1.4
    m = np.zeros(px.shape)
    for k in range(lobes):
        off = rng.normal(0.0, 0.45, 2) * r if k else np.zeros(2)
        rr = r * (rng.uniform(0.55, 0.9) if k else 1.0)
        squash = rng.uniform(0.7, 1.3)
        d = np.sqrt(((px - x - off[0]) * squash) ** 2 + ((pz - z - off[1]) / squash) ** 2) / rr
        m = np.maximum(m, 1.0 - smooth(1.0 - soft, 1.0, d))
    field[r0:r1, c0:c1] = np.maximum(field[r0:r1, c0:c1], m * value)


def arc(field, cx, cz, radius, a0, a1, width, value=1.0):
    """A thin arc (a scar) round (cx, cz) from angle a0 to a1."""
    dx, dz = X - cx, Z - cz
    d = np.abs(np.sqrt(dx * dx + dz * dz) - radius)
    ang = np.arctan2(dx, dz)
    span = smooth(a0, a0 + 0.15, ang) * (1.0 - smooth(a1 - 0.15, a1, ang))
    m = (1.0 - smooth(width * 0.4, width, d)) * span
    np.maximum(field, m * value, out=field)


def back():
    col = np.ones((H, W, 3)) * np.array([0.035, 0.04, 0.05])
    col *= (0.72 + 0.56 * fbm(0.5, 4))[..., None]
    col *= (1.0 - 0.32 * np.exp(-(AZ / 0.35) ** 2))[..., None]
    # Greying out towards the wingtips and along the trailing edges.
    sheen = 0.55 * smooth(1.5, 3.4, AZ) * (0.55 + 0.45 * fbm(0.25, 3, aspect=3.0))
    sheen = np.maximum(sheen, 0.32 * smooth(0.82, 1.0, C) * smooth(0.6, 1.6, AZ))
    col = mix(col, np.array([0.16, 0.18, 0.2]), sheen)

    # The chevrons: a white field over each shoulder, its outline pushed
    # about at every scale; crisp where it borders the dark stem down the
    # back and behind the head, breaking up behind and out along the wing
    # into cloudy grey and streaks.
    big = fbm(0.35, 3) - 0.5
    mid = fbm(0.1, 3) - 0.5
    wx = X + 0.1 * big + 0.03 * mid
    wz = AZ + 0.12 * (fbm(0.35, 3) - 0.5) + 0.03 * (fbm(0.1, 3) - 0.5)
    wc = np.clip(C + 0.06 * big, 0.0, 1.2)
    front = smooth(-0.02, 0.03, (0.58 - 0.3 * (wz - 0.42) - 0.12 * (wz - 0.42) ** 2) - wx)
    inner = smooth(-0.015, 0.02, wz - (0.42 - 0.06 * wx + 0.03 * np.sin(wx * 9.0)))
    rear = smooth(-0.15, 0.3, wx - (-0.3 - 0.45 * (wz - 0.45)))
    outer = 1.0 - smooth(-0.3, 0.45, wz - (1.95 - 1.3 * wc))
    field = front * inner * rear * outer
    streaks = fbm(0.04, 3, aspect=6.0)
    clouds = fbm(0.06, 3)
    edge = 4.0 * field * (1.0 - field)
    white_part = smooth(0.42, 0.58, field + 0.5 * (streaks - 0.5) * edge + 0.15 * (clouds - 0.5) * edge)
    grey_part = smooth(0.08, 0.45, field) * (0.45 + 0.55 * clouds)
    col = mix(col, np.array([0.2, 0.22, 0.24]), grey_part * 0.7)
    # Dark freckles and smudges in the white, some merging.
    freckles = np.zeros((H, W))
    for cluster in range(9):
        side = rng.choice([-1.0, 1.0])
        caz = rng.uniform(0.55, 1.5)
        cx = rng.uniform(-0.3, 0.45) - 0.25 * (caz - 0.45)
        for _ in range(rng.integers(1, 6)):
            stamp(freckles, cx + rng.normal(0, 0.05), side * (caz + rng.normal(0, 0.06)),
                  float(np.exp(rng.uniform(np.log(0.008), np.log(0.035)))), rng.uniform(0.5, 0.95))
    white_part *= 1.0 - freckles
    # The white itself clouded with grey, more so towards its ragged back.
    cloud = fbm(0.1, 4)
    white = np.array([0.82, 0.85, 0.86]) * (0.8 + 0.22 * cloud)[..., None]
    white = mix(white, np.array([0.45, 0.48, 0.5]), smooth(0.55, 0.85, cloud) * smooth(0.9, 0.35, field) * 0.6)
    col = mix(col, white, white_part)

    # A grey streak along each wing's leading edge, out from the chevron.
    leading = (1.0 - smooth(0.0, 0.09, C + 0.03 * mid)) * smooth(0.9, 1.5, AZ) * (1.0 - smooth(2.2, 3.0, AZ))
    col = mix(col, np.array([0.24, 0.26, 0.28]), leading * 0.5 * (0.5 + 0.5 * fbm(0.05, 2, aspect=5.0)))

    # A paler smudge at the root of the tail.
    blaze = 0.45 * np.exp(-((X + 0.9) / 0.12) ** 2 - (AZ / 0.14) ** 2) * (0.7 + 0.3 * fbm(0.05, 2))
    col = mix(col, np.array([0.3, 0.33, 0.35]), blaze)

    # Old wounds: a healed bite across one wing, a scrape on the other, and
    # small pale nicks here and there.
    scars = np.zeros((H, W))
    for k in range(4):
        arc(scars, -0.55 - 0.03 * k, -1.75, 0.42 + 0.07 * k, 0.9, 2.2, 0.012, 0.85 - 0.12 * k)
    for k in range(3):
        arc(scars, 0.9, 1.4 + 0.05 * k, 1.05, -1.75, -1.2, 0.008, 0.6)
    for _ in range(40):
        side = rng.choice([-1.0, 1.0])
        az = rng.uniform(0.2, 3.0)
        lead = curve(LEAD, np.array([az]))[0]
        trail = curve(TRAIL, np.array([az]))[0]
        stamp(scars, rng.uniform(trail, lead), side * az, rng.uniform(0.005, 0.012), rng.uniform(0.3, 0.7), lobes=2)
    col = mix(col, np.array([0.42, 0.45, 0.47]), scars * 0.8)

    # A faint, clumpy dusting of paler grey over the dark.
    dust = smooth(0.62, 0.8, fbm(0.03, 2)) * smooth(0.4, 0.7, fbm(0.2, 2)) * 0.18
    col = mix(col, np.array([0.22, 0.24, 0.26]), dust)

    # Relief: the skin's grain, the fin rays fanning out along the wings,
    # and the scars a little raised.
    grain = 0.7 * (fbm(0.02, 2) - 0.5) + 0.3 * (fbm(0.008, 1) - 0.5)
    # (The rays wander and fade in and out, so they never line up into
    # stripes.)
    ray_phase = np.clip(C, 0.0, 1.0) * np.pi * 2 * 13 + 2.5 * (fbm(0.4, 2) - 0.5)
    rays = np.sin(ray_phase) * smooth(0.6, 1.2, AZ) * (1.0 - smooth(2.6, 3.4, AZ)) * smooth(0.35, 0.75, fbm(0.3, 2))
    height = 0.5 + 0.18 * grain + 0.06 * rays + 0.25 * scars
    return col, height


def belly():
    col = np.ones((H, W, 3)) * np.array([0.88, 0.89, 0.9])
    col *= (0.93 + 0.1 * fbm(0.35, 3))[..., None]
    warp = fbm(0.2, 3) - 0.5
    fine = fbm(0.04, 2) - 0.5
    # Grey edging along the trailing edges, darkening to the tips, and a
    # shadow along the outer leading edges.
    dapple = fbm(0.05, 3)
    trailing = smooth(0.86, 0.98, C + 0.06 * warp + 0.05 * (dapple - 0.5)) * smooth(0.7, 1.7, AZ)
    tips = smooth(2.7, 3.4, AZ + 0.25 * warp + 0.08 * (dapple - 0.5))
    leading = (1.0 - smooth(0.0, 0.07, C + 0.04 * fine)) * smooth(1.6, 3.0, AZ) * 0.6
    margin = np.clip(np.maximum(np.maximum(trailing, tips), leading), 0.0, 1.0)
    # A grey wash feathering in from the edges before the dark rim.
    wash = smooth(0.62, 0.95, C + 0.1 * warp) * smooth(0.9, 2.2, AZ) * (0.4 + 0.6 * dapple)
    col = mix(col, np.array([0.55, 0.57, 0.6]), wash * 0.45)
    col = mix(col, np.array([0.12, 0.13, 0.15]), margin * 0.88)

    # The mouth: a dark band across the front of the head.
    mouth_d = np.sqrt(((LEAD_X - X) / 0.1) ** 2 + (np.maximum(AZ - 0.2, 0.0) / 0.2) ** 2)
    mouth = 1.0 - smooth(0.85, 1.05, mouth_d + 0.05 * fine)
    col = mix(col, np.array([0.07, 0.07, 0.08]), mouth * 0.92)

    # Five gill slits either side, curved, each with a pale lip and a
    # groove in the relief.
    slits = np.zeros((H, W))
    lips = np.zeros((H, W))
    for k in range(5):
        x0 = 0.6 - 0.085 * k
        length = 0.23 - 0.02 * k
        t = np.clip((AZ - 0.19) / length, -0.2, 1.2)
        curve_x = x0 - 0.05 * t * t
        d = np.abs(X - curve_x)
        along = smooth(-0.05, 0.05, t) * (1.0 - smooth(0.95, 1.05, t))
        slits = np.maximum(slits, (1.0 - smooth(0.003, 0.008, d)) * along)
        lips = np.maximum(lips, (1.0 - smooth(0.008, 0.02, d)) * along)
    col = mix(col, np.array([0.95, 0.95, 0.95]), (lips - slits) * 0.5)
    col = mix(col, np.array([0.2, 0.2, 0.22]), slits * 0.9)

    # The spots: each manta's own, mostly in loose clusters between and
    # behind the gills, a few strays out on the wings.
    spots = np.zeros((H, W))
    for cluster in range(7):
        side = rng.choice([-1.0, 1.0])
        caz = abs(rng.normal(0.0, 0.22))
        cx = rng.uniform(-0.55, 0.45)
        for _ in range(rng.integers(1, 6)):
            r = float(np.exp(rng.uniform(np.log(0.012), np.log(0.055))))
            stamp(spots, cx + rng.normal(0, 0.07), side * (caz + abs(rng.normal(0, 0.06))), r,
                  rng.uniform(0.8, 1.0), lobes=int(rng.integers(2, 5)))
    for _ in range(9):
        side = rng.choice([-1.0, 1.0])
        stamp(spots, rng.uniform(-0.5, 0.35), side * rng.uniform(0.5, 1.5), rng.uniform(0.008, 0.02),
              rng.uniform(0.6, 0.9), lobes=2)
    col = mix(col, np.array([0.07, 0.07, 0.08]), spots * 0.92)

    # A grey smudge over the vent, at the root of the tail.
    vent = 0.5 * np.exp(-((X + 0.9) / 0.1) ** 2 - (AZ / 0.1) ** 2)
    col = mix(col, np.array([0.45, 0.45, 0.47]), vent)

    height = 0.5 + 0.12 * (fbm(0.014, 2) - 0.5) + 0.2 * lips - 0.45 * slits
    return col, height


def save(name, col, height):
    rgba = np.dstack([np.clip(col, 0.0, 1.0), np.clip(height, 0.0, 1.0)])
    Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), mode="RGBA").save(os.path.join(OUT, name))


def main():
    os.makedirs(OUT, exist_ok=True)
    save("manta_back.png", *back())
    save("manta_belly.png", *belly())


if __name__ == "__main__":
    main()
