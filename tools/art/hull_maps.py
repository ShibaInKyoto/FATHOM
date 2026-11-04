#!/usr/bin/env python3
"""Paint-shop maps for a submarine's fairing: an RGB multiply (panel seams,
rivets, grime, rust streaks, hatches, the name, hull designation and depth
rating) and the matching normal
map. They wrap the fairing's UVs: u runs stern to bow, v round each section
from the keel (0), up the near side (0.25), over the deck (0.5) and down the
far side (0.75), spaced evenly by distance.

The fairing's shape comes from the game (tools/art/dump_hull.gd), so the
maps always fit it:

    python3 tools/art/hull_maps.py [frame...]   # writes assets/subs/<frame>_*.png
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "subs")
FONT = os.path.join(ROOT, "assets", "fonts", "ChakraPetch-SemiBold.ttf")
W, H = 2048, 1024
rng = np.random.default_rng(7)


def load_hull(frame):
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "hull.json")
        subprocess.run([os.environ.get("GODOT", "godot"), "--headless", "--path", ROOT, "-s",
                        "res://tools/art/dump_hull.gd", "--", path, frame], check=True, stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(path) as f:
            data = json.load(f)
    pts = np.array(data["points"], dtype=np.float64).reshape(data["nu"] + 1, data["nv"] + 1, 3)
    return data["x0"], data["x1"], pts


class Hull:
    """Where each texel lands on the fairing."""

    def __init__(self, x0, x1, pts):
        self.x0, self.x1 = x0, x1
        self.length = x1 - x0
        nu = pts.shape[0] - 1
        nv = pts.shape[1] - 1
        seg = np.linalg.norm(np.diff(pts, axis=1), axis=2)
        per_row = seg.sum(axis=1)
        self.u = (np.arange(W) + 0.5) / W
        self.v = (np.arange(H) + 0.5) / H
        # Section circumference under each column, and each texel's height.
        self.perimeter = np.interp(self.u, np.linspace(0, 1, nu + 1), per_row)
        ui = np.clip(self.u * nu, 0, nu - 1e-6)
        vi = np.clip(self.v * nv, 0, nv - 1e-6)
        i0 = ui.astype(int)
        j0 = vi.astype(int)
        fu = (ui - i0)[None, :]
        fv = (vi - j0)[:, None]
        y = pts[:, :, 1]
        z = pts[:, :, 2]

        def bilerp(a):
            a00 = a[i0][:, j0].T
            a10 = a[i0 + 1][:, j0].T
            a01 = a[i0][:, j0 + 1].T
            a11 = a[i0 + 1][:, j0 + 1].T
            return (a00 * (1 - fu) + a10 * fu) * (1 - fv) + (a01 * (1 - fu) + a11 * fu) * fv

        self.y = bilerp(y)
        self.z = bilerp(z)
        self.px_x = W / self.length
        self.X = x0 + self.u[None, :] * self.length + 0 * self.y
        self.V = self.v[:, None] + 0 * self.y

    def col(self, x):
        return (x - self.x0) / self.length * W

    def row(self, v):
        return v * H

    def px_v(self, x):
        """Texels per world unit round the hull at x."""
        return H / np.interp((x - self.x0) / self.length, self.u, self.perimeter)


def stamp(img, mask, c, r, value, mode="mul"):
    """Blends mask (2D, 0..1) into img centred on column c, row r."""
    h, w = mask.shape
    c0 = int(round(c - w / 2))
    r0 = int(round(r - h / 2))
    cs0, rs0 = max(c0, 0), max(r0, 0)
    cs1, rs1 = min(c0 + w, W), min(r0 + h, H)
    if cs0 >= cs1 or rs0 >= rs1:
        return
    m = mask[rs0 - r0:rs1 - r0, cs0 - c0:cs1 - c0]
    region = img[rs0:rs1, cs0:cs1]
    if mode == "mul":
        region *= 1 - m[..., None] * (1 - np.asarray(value)) if region.ndim == 3 else 1 - m * (1 - value)
    elif mode == "add":
        region += m * value if region.ndim == 2 else m[..., None] * value
    elif mode == "min":
        np.minimum(region, value + (1 - m) * 10, out=region)


def text_mask(text, width_px, height_px, size=220):
    font = ImageFont.truetype(FONT, size)
    l, t, r, b = font.getbbox(text)
    im = Image.new("L", (r - l + 8, b - t + 8), 0)
    ImageDraw.Draw(im).text((4 - l, 4 - t), text, font=font, fill=255)
    if width_px is None:
        width_px = height_px * im.width / im.height
    im = im.resize((max(int(width_px), 1), max(int(height_px), 1)), Image.LANCZOS)
    return np.asarray(im, dtype=np.float32) / 255.0


def smooth_noise(shape, cells, seed):
    g = np.random.default_rng(seed).random((cells[0] + 3, cells[1] + 3))
    im = Image.fromarray((g * 255).astype(np.uint8)).resize((shape[1], shape[0]), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32) / 255.0


def paint_lantern(hull):
    paint = np.ones((H, W, 3), dtype=np.float32) * 0.95
    height = np.zeros((H, W), dtype=np.float32)
    X, V = hull.X, hull.V
    pv = hull.px_v(X)  # texels per unit round the hull, per texel
    up = hull.y

    # Panel seams round the hull (constant v) and across it (constant x).
    long_seams = [0.0, 0.065, 0.155, 0.345, 0.435]
    long_seams += [1.0 - s for s in long_seams[1:]] + [1.0]
    width = 0.005
    seam = np.zeros((H, W), dtype=np.float32)
    rivets = []
    for s in long_seams:
        d = np.abs(V - s) * hull.perimeter[None, :]
        seam = np.maximum(seam, np.exp(-(d / width) ** 2))
        for side in (-1, 1):
            for x in np.arange(hull.x0 + 0.06, hull.x1 - 0.05, 0.05):
                rivets.append((x, s + side * 0.02 / np.interp((x - hull.x0) / hull.length, hull.u, hull.perimeter)))
    bands = sorted(set(long_seams))
    stations = [-1.62, -1.06, -0.5, 0.06, 0.62]
    for b in range(len(bands) - 1):
        lo, hi = bands[b], bands[b + 1]
        mid = (lo + hi) / 2
        if 0.155 <= mid <= 0.345 or 0.655 <= mid <= 0.845:
            xs = [-1.45, -0.72, 0.62]  # the lettered band: no seams through the name
        elif 0.435 <= mid <= 0.565:
            xs = [-1.62, -0.62, 0.3]
        else:
            xs = [x + (0.28 if b % 2 else 0.0) for x in stations]
        for x in xs:
            inside = (V >= lo) & (V <= hi)
            d = np.abs(X - x)
            seam = np.maximum(seam, np.exp(-(d / width) ** 2) * inside)
            per = np.interp((x - hull.x0) / hull.length, hull.u, hull.perimeter)
            for side in (-1, 1):
                for v in np.arange(lo + 0.03 / per, hi - 0.02 / per, 0.05 / per):
                    rivets.append((x + side * 0.02, v))
    height -= seam * 0.0035
    paint *= (1 - 0.42 * seam)[..., None]

    # Rivets: little domes with a dark ring where paint has pooled.
    r_world = 0.0085
    for x, v in rivets:
        c = hull.col(x)
        r = hull.row(v)
        rx = r_world * hull.px_x
        ry = r_world * hull.px_v(x)
        ys, xs = np.mgrid[-int(ry * 2) - 1:int(ry * 2) + 2, -int(rx * 2) - 1:int(rx * 2) + 2]
        dist = np.sqrt((xs / rx) ** 2 + (ys / ry) ** 2)
        dome = np.sqrt(np.clip(1 - dist ** 2, 0, 1))
        ring = np.exp(-((dist - 1.1) / 0.35) ** 2)
        stamp(height, dome * 0.0028, c, r, 1.0, "add")
        stamp(paint, ring * 0.28, c, r, 0.0)
        # A rust streak running down from some of them.
        if rng.random() < 0.18:
            streak_len = rng.uniform(0.03, 0.12)
            sl = int(streak_len * hull.px_v(x))
            sw = max(int(rx * 0.9), 1)
            near = v < 0.5
            ys2, xs2 = np.mgrid[0:sl, -sw:sw + 1]
            fade = (1 - ys2 / max(sl, 1)) * np.exp(-(xs2 / max(sw * 0.6, 0.5)) ** 2)
            mask = np.zeros((2 * sl + 1, 2 * sw + 1), dtype=np.float32)
            # Down the hull is falling v on the near side and rising v on the far side.
            if near:
                mask[:sl] = fade[::-1]
            else:
                mask[sl + 1:] = fade
            stamp(paint, mask * rng.uniform(0.15, 0.35), c, r, np.array([0.55, 0.38, 0.25]))

    # The name, the hull designation and the depth rating on both sides.
    def letter(mask, x, v, far):
        m = mask[:, ::-1] if far else mask[::-1, :]
        stamp(paint, m * 0.9, hull.col(x), hull.row(v), np.array([0.07, 0.07, 0.08]))
        stamp(height, m * 0.0004, hull.col(x), hull.row(v), 1.0, "add")

    def text(words, height_world, x, width_world=None):
        mask = text_mask(words, None, height_world * hull.px_v(x))
        width = width_world * hull.px_x if width_world else mask.shape[1] * hull.px_x / hull.px_v(x)
        return np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).resize(
            (int(width), mask.shape[0]), Image.LANCZOS), dtype=np.float32) / 255

    # Below the name is falling v on the near side and rising v on the far side.
    for far in (False, True):
        side = 1 if far else -1
        v_mid = 0.75 - side * 0.012 if far else 0.25 + side * 0.012
        letter(text("LANTERN", 0.17, -0.12), -0.12, v_mid, far)
        letter(text("TEST DEPTH 11 000 M", 0.032, -0.12), -0.12, v_mid + side * 0.042, far)
        letter(text("DSV-7", 0.07, 0.76, 0.24), 0.76, (0.75 + 0.04) if far else (0.25 - 0.04), far)
        letter(text("NO STEP", 0.035, -1.72, 0.16), -1.72, 0.5 + (0.035 if far else -0.035), far)

    # A bolted access hatch low on each side, aft of the name.
    for far in (False, True):
        x0, x1 = -1.02, -0.74
        vc = 0.75 + 0.01 if far else 0.25 - 0.01
        per = np.interp((x0 + x1) / 2 - hull.x0, [0, hull.length], [hull.perimeter[0], hull.perimeter[-1]])
        per = np.interp(((x0 + x1) / 2 - hull.x0) / hull.length, hull.u, hull.perimeter)
        hv = 0.13 / per
        inside_x = np.clip(np.minimum(X - x0, x1 - X), -1, 1)
        inside_v = np.clip(np.minimum(V - (vc - hv), (vc + hv) - V) * hull.perimeter[None, :], -1, 1)
        edge = np.minimum(inside_x, inside_v)
        groove = np.exp(-((edge - 0.0) / 0.004) ** 2) * (np.abs(X - (x0 + x1) / 2) < 0.2)
        height -= groove * 0.003
        paint *= (1 - 0.45 * groove)[..., None]
        for cx in (x0 + 0.025, x1 - 0.025):
            for cv in (vc - hv + 0.025 / per, vc + hv - 0.025 / per):
                rivets_r = 0.012
                rx = rivets_r * hull.px_x
                ry = rivets_r * hull.px_v(cx)
                ys, xs = np.mgrid[-int(ry * 2) - 1:int(ry * 2) + 2, -int(rx * 2) - 1:int(rx * 2) + 2]
                dist = np.sqrt((xs / rx) ** 2 + (ys / ry) ** 2)
                stamp(height, np.sqrt(np.clip(1 - dist ** 2, 0, 1)) * 0.002, hull.col(cx), hull.row(cv), 1, "add")
                slot = (np.abs(xs / rx) < 0.9) & (np.abs(ys / ry) < 0.18)
                stamp(paint, (dist < 1).astype(np.float32) * 0.25 + slot * 0.5, hull.col(cx), hull.row(cv), 0.0)

    # A vent grille high on each side near the bow: a row of recessed slots.
    for far in (False, True):
        vc = 0.75 - 0.1 if far else 0.25 + 0.1
        for k in range(7):
            x = 0.6 + k * 0.045
            per = np.interp((x - hull.x0) / hull.length, hull.u, hull.perimeter)
            slot = (np.abs(X - x) < 0.012) & (np.abs(V - vc) * hull.perimeter[None, :] < 0.06)
            soft = slot.astype(np.float32)
            height -= soft * 0.004
            paint *= (1 - 0.75 * soft)[..., None]

    # Hazard stripes round the deck thruster.
    tx, tv = -1.08, 0.5
    dx = X - tx
    dv = (V - tv) * hull.perimeter[None, :]
    rad = np.sqrt(dx ** 2 + dv ** 2)
    ring = (rad > 0.205) & (rad < 0.25)
    stripes = (np.floor((np.arctan2(dv, dx) / (2 * np.pi)) * 24) % 2 == 0)
    paint *= (1 - 0.85 * (ring & stripes))[..., None]
    paint *= (1 - 0.35 * (np.abs(rad - 0.25) < 0.004))[..., None]

    # Grime: darker low down and under the stern, streaked, with soft blotches.
    low = np.clip((0.1 - up) / 0.5, 0, 1)
    streak = smooth_noise((1, W), (1, 180), 3)[0]
    blotch = smooth_noise((H, W), (10, 24), 4)
    fine = smooth_noise((H, W), (60, 160), 5)
    grime = 0.28 * low * (0.6 + 0.4 * streak[None, :]) + 0.07 * blotch + 0.04 * fine
    ends = np.exp(-((X - hull.x0) / 0.18) ** 2) + np.exp(-((hull.x1 - X) / 0.1) ** 2)
    grime += 0.25 * ends
    paint *= (1 - np.clip(grime, 0, 0.6))[..., None]
    paint *= np.array([1.0, 0.985, 0.96])  # a little warmth in the dirt
    height += (fine - 0.5) * 0.0004
    return np.clip(paint, 0, 1), height, pv


def normal_map(hull, height, pv):
    du = hull.length / W
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) / (2 * du)
    dv_world = 1.0 / pv
    gy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / (2 * dv_world)
    n = np.stack([-gx, gy, np.ones_like(gx)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def text_on(hull, paint, height, words, height_world, x, v, far, width_world=None, shear=0.0,
            ink=(0.07, 0.07, 0.08), depth=0.0004):
    """Paints words centred at x, v, upright from whichever side they're seen."""
    mask = text_mask(words, None, height_world * hull.px_v(x))
    if shear:
        im = Image.fromarray((mask * 255).astype(np.uint8))
        extra = int(abs(shear) * im.height)
        im = im.transform((im.width + extra, im.height), Image.AFFINE, (1, shear, -extra if shear > 0 else 0, 0, 1, 0),
                          resample=Image.BICUBIC)
        mask = np.asarray(im, dtype=np.float32) / 255
    width = width_world * hull.px_x if width_world else mask.shape[1] * hull.px_x / hull.px_v(x)
    mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).resize(
        (max(int(width), 1), mask.shape[0]), Image.LANCZOS), dtype=np.float32) / 255
    m = mask[:, ::-1] if far else mask[::-1, :]
    stamp(paint, m * 0.92, hull.col(x), hull.row(v), np.array(ink))
    stamp(height, m * depth, hull.col(x), hull.row(v), 1.0, "add")


def side_v(hull, x, far, offset=0.0):
    """The v of the widest point of the section at x on one side, moved
    offset towards the deck (negative: towards the keel)."""
    col = int(np.clip(hull.col(x), 0, W - 1))
    half = hull.z[: H // 2, col] if not far else -hull.z[H // 2:, col]
    j = int(np.argmax(half))
    v = (j + 0.5) / H + (0.0 if not far else 0.5)
    return v - offset if far else v + offset


def paint_mako(hull):
    paint = np.ones((H, W, 3), dtype=np.float32) * 0.96
    height = np.zeros((H, W), dtype=np.float32)
    X, V = hull.X, hull.V
    per = hull.perimeter[None, :]

    # Flush composite panels: fine seams and countersunk screws, no rivets.
    seam = np.zeros((H, W), dtype=np.float32)
    width = 0.0035
    long_seams = [0.0, 0.085, 0.4, 0.46]
    long_seams += [1.0 - s for s in long_seams[1:]] + [1.0]
    for s in long_seams:
        seam = np.maximum(seam, np.exp(-((np.abs(V - s) * per) / width) ** 2))
    gills = (-0.42, 0.12)
    for x in [-1.62, -1.05, -0.5, 0.3, 0.98, 1.62]:
        d = np.abs(X - x)
        keep = np.ones_like(V, dtype=bool)
        if gills[0] - 0.05 < x < gills[1] + 0.05:
            keep = (np.abs(V - 0.25) > 0.09) & (np.abs(V - 0.75) > 0.09)
        seam = np.maximum(seam, np.exp(-(d / width) ** 2) * keep)
    height -= seam * 0.0025
    paint *= (1 - 0.38 * seam)[..., None]
    screws = []
    for s in long_seams[1:-1]:
        for x in np.arange(hull.x0 + 0.12, hull.x1 - 0.1, 0.075):
            p_here = np.interp((x - hull.x0) / hull.length, hull.u, hull.perimeter)
            screws.append((x, s + 0.016 / p_here))
    for x in [-1.62, -1.05, -0.5, 0.3, 0.98, 1.62]:
        p_here = np.interp((x - hull.x0) / hull.length, hull.u, hull.perimeter)
        for v in np.arange(0.02, 0.98, 0.06 / p_here):
            if gills[0] - 0.05 < x < gills[1] + 0.05 and (abs(v - 0.25) < 0.09 or abs(v - 0.75) < 0.09):
                continue
            screws.append((x + 0.016, v))
    for x, v in screws:
        rx = 0.0055 * hull.px_x
        ry = 0.0055 * hull.px_v(x)
        ys, xs = np.mgrid[-int(ry * 2) - 1:int(ry * 2) + 2, -int(rx * 2) - 1:int(rx * 2) + 2]
        dist = np.sqrt((xs / rx) ** 2 + (ys / ry) ** 2)
        dish = np.clip(1 - dist ** 2, 0, 1)
        stamp(height, -dish * 0.0012, hull.col(x), hull.row(v), 1.0, "add")
        stamp(paint, np.exp(-((dist - 0.85) / 0.3) ** 2) * 0.35, hull.col(x), hull.row(v), 0.0)

    # Gills: five slanted intakes on each flank, dark inside, their lips raised.
    for far in (False, True):
        vc = side_v(hull, -0.15, far)
        for k in range(5):
            xc = gills[1] - k * 0.11
            lean = 0.07  # the top of each slot sits further aft
            t = (V - vc) * per * (1 if not far else -1)  # height up the side from the slot's middle
            along = X - (xc - lean * t / 0.13)
            inside = (np.abs(along) < 0.018) & (np.abs(t) < 0.13 - k * 0.012)
            soft = np.exp(-(np.maximum(np.abs(along) - 0.018, 0) / 0.004) ** 2) * (np.abs(t) < 0.135 - k * 0.012)
            height -= inside * 0.006
            height += (soft - inside) * 0.0015
            paint *= (1 - 0.85 * inside)[..., None]

    # A dark belly below twin pinstripes along the lower flank, nose to tail.
    for far in (False, True):
        vs = np.array([side_v(hull, x, far, -0.06) for x in hull.X[0]])
        kernel = np.ones(151) / 151
        vs = np.convolve(np.pad(vs, 75, mode="edge"), kernel, mode="valid")
        below = (V - vs[None, :]) * per * (1 if not far else -1)
        side = (V < 0.5) if not far else (V >= 0.5)
        belly = np.clip(-below / 0.01, 0, 1) * side
        paint *= (1 - 0.62 * belly)[..., None]
        for off, w in ((-0.105, 0.006), (-0.125, 0.003)):
            vs = np.array([side_v(hull, x, far, off * 0.5) for x in hull.X[0]])
            kernel = np.ones(151) / 151
            vs = np.convolve(np.pad(vs, 75, mode="edge"), kernel, mode="valid")
            d = np.abs(V - vs[None, :]) * per
            band = np.exp(-(d / w) ** 4) * ((X > -1.75) & (X < 1.9))
            paint *= (1 - 0.6 * band)[..., None]

    # Access panels: outlined hatches with a screw at each corner.
    for far in (False, True):
        for (xa, xb, off, half) in ((-1.55, -1.3, 0.03, 0.07), (1.15, 1.42, 0.06, 0.05), (0.42, 0.62, -0.02, 0.06)):
            vc = side_v(hull, (xa + xb) / 2, far, off)
            t = (V - vc) * per
            inside_x = np.minimum(X - xa, xb - X)
            inside_t = half - np.abs(t)
            edge = np.minimum(inside_x, inside_t)
            groove = np.exp(-(edge / 0.003) ** 2) * (np.abs(t) < half + 0.01) * (X > xa - 0.01) * (X < xb + 0.01)
            height -= groove * 0.002
            paint *= (1 - 0.5 * groove)[..., None]
            for cx in (xa + 0.018, xb - 0.018):
                for ct in (-half + 0.018, half - 0.018):
                    cv = vc + ct / np.interp((cx - hull.x0) / hull.length, hull.u, hull.perimeter)
                    rx = 0.007 * hull.px_x
                    ry = 0.007 * hull.px_v(cx)
                    ys, xs = np.mgrid[-int(ry * 2) - 1:int(ry * 2) + 2, -int(rx * 2) - 1:int(rx * 2) + 2]
                    dist = np.sqrt((xs / rx) ** 2 + (ys / ry) ** 2)
                    stamp(paint, (dist < 1).astype(np.float32) * 0.45, hull.col(cx), hull.row(cv), 0.0)

    # Name, prototype designation and a canopy rescue marking.
    for far in (False, True):
        up = 1
        text_on(hull, paint, height, "MAKO", 0.22, -0.98, side_v(hull, -0.98, far, 0.012), far, shear=0.28)
        text_on(hull, paint, height, "PROTOTYPE", 0.034, -0.98, side_v(hull, -0.98, far, -0.04), far)
        text_on(hull, paint, height, "XP-2", 0.08, 0.68, side_v(hull, 0.68, far, 0.035 * up), far, shear=0.2)
        text_on(hull, paint, height, "RESCUE", 0.026, 0.9, side_v(hull, 0.9, far, 0.105), far)
        # An arrow under RESCUE pointing up at the canopy.
        v_arrow = side_v(hull, 0.9, far, 0.085)
        tip = np.abs(X - 0.9) * 1.0
        rise = (V - v_arrow) * per * (1 if not far else -1)
        arrow = ((rise > -0.015) & (rise < 0.012) & (tip < 0.006)) | ((rise >= 0.004) & (rise < 0.022) &
                                                                    (tip < (0.022 - rise) * 0.9))
        paint *= (1 - 0.8 * arrow)[..., None]

    # Hazard chevrons round the pump-jet's intake.
    band = (X > -1.97) & (X < -1.86)
    chevron = np.floor(((X + 1.97) * 18 + np.abs(V - 0.5) * 22) ) % 2 == 0
    paint *= (1 - 0.8 * (band & chevron))[..., None]

    # Light grime: a prototype kept clean, dulled underneath and at the tail.
    low = np.clip((-0.05 - hull.y) / 0.35, 0, 1)
    fine = smooth_noise((H, W), (60, 160), 11)
    blotch = smooth_noise((H, W), (10, 24), 12)
    grime = 0.12 * low + 0.04 * blotch + 0.025 * fine + 0.2 * np.exp(-((X - hull.x0) / 0.15) ** 2)
    paint *= (1 - np.clip(grime, 0, 0.5))[..., None]
    height += (fine - 0.5) * 0.0002
    pv = hull.px_v(X)
    return np.clip(paint, 0, 1), height, pv


def paint_bathysphere(hull):
    """Old cast steel under worn paint: pitting, chips down to rust, rust
    running from the flange, the hatch and the ports, and stencilled
    markings."""
    paint = np.ones((H, W, 3), dtype=np.float32) * 0.94
    height = np.zeros((H, W), dtype=np.float32)
    X, V = hull.X, hull.V
    per = hull.perimeter[None, :]
    rust = np.array([0.5, 0.29, 0.16])

    # Cast texture: soft mottling and fine pits.
    # Noise cells sized to the sphere: three times as far round as along.
    mottle = smooth_noise((H, W), (21, 7), 21)
    fine = smooth_noise((H, W), (240, 80), 22)
    pits = smooth_noise((H, W), (520, 180), 23)
    paint *= (0.94 + 0.08 * mottle)[..., None]
    pit = np.clip((pits - 0.78) / 0.1, 0, 1)
    height -= pit * 0.0008
    paint *= (1 - 0.3 * pit)[..., None]
    height += (fine - 0.5) * 0.0006

    # Chips: patches of paint gone to rust, most of them low down.
    low = np.clip((0.2 - hull.y) / 1.0, 0, 1)
    chips_n = smooth_noise((H, W), (90, 30), 24) * 0.7 + smooth_noise((H, W), (270, 90), 25) * 0.3
    damage = smooth_noise((H, W), (9, 3), 27)
    chip = np.clip((chips_n - (0.86 - 0.12 * low - 0.12 * damage)) / 0.03, 0, 1)
    # Bare metal shows through in the alpha; the paint's edge around a chip is darker.
    rim = np.clip((chips_n - (0.83 - 0.12 * low - 0.12 * damage)) / 0.03, 0, 1) - chip
    paint *= (1 - 0.3 * rim)[..., None]
    height -= chip * 0.0004
    bare = chip.copy()

    # Rust running down from the flange (x = 0), round the ports and from scattered spots.
    streak = smooth_noise((1, W), (1, 120), 26)[0]
    near_flange = np.exp(-(X / 0.12) ** 2)
    sources = [(0.0, 0.32), (0.0, 0.22), (0.62, 0.34), (-0.5, 0.36), (0.3, 0.4), (-0.75, 0.3), (0.75, 0.26)]
    run = np.zeros((H, W), dtype=np.float32)
    for x, v in sources:
        for far in (False, True):
            vs = 1 - v if far else v
            below = (vs - V) * per if not far else (V - vs) * per
            width = 0.035 + 0.03 * streak[None, :]
            col = np.exp(-((X - x) / width) ** 2)
            run = np.maximum(run, col * np.clip(below / 0.05, 0, 1) * np.exp(-np.clip(below, 0, None) / 0.45))
    run += 0.5 * near_flange * low
    run *= (0.6 + 0.4 * streak[None, :])
    bare = np.maximum(bare, 0.8 * np.clip(run * 1.3, 0, 1))

    # Stencils: hull number, test pressure and a warning by the hatch.
    for far in (False, True):
        text_on(hull, paint, height, "B-3", 0.3, -0.42, side_v(hull, -0.42, far, 0.02), far,
                ink=(0.1, 0.09, 0.08), depth=0.0002)
        text_on(hull, paint, height, "TESTED 1 100 ATM", 0.045, -0.42, side_v(hull, -0.42, far, -0.075), far,
                ink=(0.1, 0.09, 0.08), depth=0.0001)
        text_on(hull, paint, height, "DO NOT OPEN UNDER PRESSURE", 0.035, -0.46, 0.44 if not far else 0.56, far,
                ink=(0.1, 0.09, 0.08), depth=0.0001)

    # Heavy grime underneath.
    grime = 0.3 * np.clip((-0.1 - hull.y) / 0.8, 0, 1) + 0.05 * mottle
    paint *= (1 - np.clip(grime, 0, 0.6))[..., None]
    # Decades in the water: the paint dulled and yellowed all over.
    paint *= np.array([0.9, 0.86, 0.78])
    pv = hull.px_v(X)
    alpha = 1 - np.clip(bare, 0, 1)
    return np.concatenate([np.clip(paint, 0, 1), alpha[..., None]], axis=-1), height, pv


def coating(shape, seed):
    """The Whisper's anechoic coating: a dark, patchy shade and a fine rubbery
    grain (its height)."""
    blotch = smooth_noise(shape, (8, 20), seed)
    mid = smooth_noise(shape, (30, 80), seed + 1)
    fine = smooth_noise(shape, (120, 320), seed + 2)
    shade = 0.49 * (1 + 0.08 * (blotch - 0.5) + 0.05 * (mid - 0.5) + 0.04 * (fine - 0.5))
    return shade, (fine - 0.5) * 0.0003 + (mid - 0.5) * 0.0002


def groove_of(mask, px=2):
    """The rim of a mask, px texels wide: where a panel's edge is cut."""
    inner = mask.copy()
    for dy in (-px, 0, px):
        for dx in (-px, 0, px):
            inner &= np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
    return mask & ~inner


def tri(t):
    """A triangle wave, 0..1, period 1: the teeth of a sawtooth edge."""
    return 1 - np.abs((t % 1.0) * 2 - 1)


def fastener_rows(d, along, offset, spacing, r=0.0032):
    """Flush fasteners in a row either side of a seam: d is the distance across
    it, along the distance along it (both in world units)."""
    across = np.minimum(np.abs(d - offset), np.abs(d + offset))
    step = (along / spacing) % 1.0 - 0.5
    return (across ** 2 + (step * spacing) ** 2) < r * r


def stealth_panels(paint, height, X, T, x_lines, t_lines, seed, tape=()):
    """Panels between seams across x and round the hull (t, distance round in
    world units), each its own shade, the seams grooved and lined with flush
    fasteners; tape strips laid over some seams."""
    w = 0.0024
    seam = np.zeros(X.shape, dtype=np.float32)
    dots = np.zeros(X.shape, dtype=bool)
    xi = np.zeros(X.shape, dtype=np.int32)
    for x in x_lines:
        seam = np.maximum(seam, np.exp(-((X - x) / w) ** 2))
        dots |= fastener_rows(X - x, T, 0.013, 0.045)
        xi += (X > x)
    ti = np.zeros(X.shape, dtype=np.int32)
    for t in t_lines:
        seam = np.maximum(seam, np.exp(-((T - t) / w) ** 2))
        dots |= fastener_rows(T - t, X, 0.013, 0.045)
        ti += (T > t)
    rnd = ((np.sin(xi * 12.9898 + ti * 78.233 + seed) * 43758.5453) % 1.0 + 1.0) % 1.0
    paint *= (0.95 + 0.1 * rnd)[..., None]
    for kind, at, width in tape:
        d = (X - at) if kind == "x" else (T - at)
        strip = np.clip((width / 2 - np.abs(d)) / 0.004, 0, 1)
        paint *= (1 + 0.07 * strip)[..., None]
        height += strip * 0.0004
        dots &= strip < 0.5
    paint *= (1 - 0.32 * seam)[..., None]
    height -= seam * 0.0016
    paint *= np.where(dots[..., None], 0.84, 1.0)
    height += dots * 0.0003


def sawtooth_hatch(paint, height, X, T, xa, xb, ta, tb, tooth=0.022):
    """An access hatch whose edges are cut into a sawtooth, as on stealth
    craft: grooved round, a shade apart, a fastener in each corner."""
    amp = tooth * 0.5
    inside = ((X > xa + amp * tri((T - ta) / tooth)) & (X < xb - amp * tri((T - ta) / tooth)) &
              (T > ta + amp * tri((X - xa) / tooth)) & (T < tb - amp * tri((X - xa) / tooth)))
    groove = groove_of(inside)
    paint *= np.where(inside[..., None], 0.93, 1.0)
    paint *= np.where(groove[..., None], 0.6, 1.0)
    height -= groove * 0.002
    for cx in (xa + 0.02, xb - 0.02):
        for ct in (ta + 0.02, tb - 0.02):
            dot = (X - cx) ** 2 + (T - ct) ** 2 < 0.0045 ** 2
            paint *= np.where(dot[..., None], 0.7, 1.0)
            height += dot * 0.0004


def flakes(hull_shape, X, T, spots, seed):
    """Where the coating has flaked off: returns (bare 0..1, rim 0..1)."""
    noise = smooth_noise(hull_shape, (40, 100), seed)
    bare = np.zeros(hull_shape, dtype=np.float32)
    for (x, t, r) in spots:
        d = np.sqrt((X - x) ** 2 + ((T - t) * 1.3) ** 2) / r
        bare = np.maximum(bare, (d < 0.55 + 0.6 * noise).astype(np.float32))
    rim = groove_of(bare > 0.5, 2).astype(np.float32)
    return bare, rim


def paint_whisper(hull):
    paint = np.ones((H, W, 3), dtype=np.float32)
    height = np.zeros((H, W), dtype=np.float32)
    X, V = hull.X, hull.V
    per = hull.perimeter[None, :]
    shade, grain = coating((H, W), 31)
    paint *= shade[..., None]
    height += grain

    # Distance round the hull from the near chine (positive towards the deck),
    # and from the far chine the same way, so panels sit square to the facets.
    vc = np.array([side_v(hull, x, False) for x in hull.X[0]])
    vcf = np.array([side_v(hull, x, True) for x in hull.X[0]])
    k = np.ones(61) / 61
    vc = np.convolve(np.pad(vc, 30, mode="edge"), k, mode="valid")[None, :]
    vcf = np.convolve(np.pad(vcf, 30, mode="edge"), k, mode="valid")[None, :]
    near = V < 0.5
    T = np.where(near, (V - vc) * per, (vcf - V) * per)

    # Panels square to the facets: seams at the chines, along the sides, at
    # the ridge and keel, and across at the facets' joints.
    x_lines = [-1.45, -1.12, -0.55, -0.1, 0.3, 0.68, 1.05, 1.4]
    t_lines = [-0.12, 0.0, 0.24, 0.4]
    stealth_panels(paint, height, X, T, x_lines, t_lines, 3,
                   tape=(("x", 0.3, 0.035), ("t", 0.4, 0.03)))
    ridge = np.exp(-((np.abs(V - 0.5) * per) / 0.0024) ** 2) + np.exp(-((np.minimum(V, 1 - V) * per) / 0.0024) ** 2)
    paint *= (1 - 0.3 * np.clip(ridge, 0, 1))[..., None]
    height -= np.clip(ridge, 0, 1) * 0.0015

    # Sawtooth access hatches: on each roof facet aft and forward, and low on
    # each side amidships.
    for (xa, xb, ta, tb) in ((-1.4, -1.18, 0.27, 0.37), (0.74, 0.98, 0.07, 0.15), (-0.45, -0.18, -0.1, -0.03)):
        sawtooth_hatch(paint, height, X, T, xa, xb, ta, tb)

    # The conformal hydrophone arrays: a darker panel set with a grid of elements.
    inside = (X > -0.05) & (X < 0.27) & (T > 0.03) & (T < 0.12)
    paint *= np.where(inside[..., None], 0.8, 1.0)
    height -= groove_of(inside) * 0.0015
    gx = ((X + 0.05) / 0.026) % 1.0
    gy = ((T - 0.03) / 0.0225) % 1.0
    dot = inside & (np.hypot(gx - 0.5, gy - 0.5) < 0.26)
    paint *= np.where(dot[..., None], 0.72, 1.0)
    height -= dot * 0.0006

    # Flush intakes aft: a slot each side, dark in its throat, a streak of grime behind.
    d = X + 1.3
    slot = (np.abs(d) < 0.1) & (np.abs(T - 0.1) < 0.008 + 0.016 * np.clip((d + 0.1) / 0.2, 0, 1))
    paint *= np.where(slot[..., None], 0.3, 1.0)
    height -= slot * 0.004
    streak = np.exp(-((T - 0.1) / 0.012) ** 2) * (X < -1.38) * np.exp((X + 1.38) / 0.25)
    paint *= (1 - 0.18 * streak)[..., None]

    # Low-visibility lettering: the name and designation in a darker grey,
    # and the coating's placard.
    ink = (0.62, 0.62, 0.68)
    for far in (False, True):
        text_on(hull, paint, height, "WHISPER", 0.085, -0.82, side_v(hull, -0.82, far, 0.06), far, ink=ink,
                depth=0.0002)
        text_on(hull, paint, height, "ANECHOIC COATING - DO NOT PAINT", 0.02, -0.82, side_v(hull, -0.82, far, 0.025),
                far, ink=ink, depth=0.0001)
        text_on(hull, paint, height, "SD-4", 0.07, 1.22, side_v(hull, 1.22, far, 0.045), far, ink=ink, depth=0.0002)

    # Flaked patches down to the primer, mostly at the bow and along the chines.
    spots = [(1.6, 0.02, 0.03), (1.75, -0.02, 0.022), (0.9, -0.01, 0.025), (-0.3, 0.015, 0.02), (-1.0, -0.02, 0.028),
             (-1.55, 0.03, 0.022), (0.45, 0.25, 0.018), (1.3, 0.12, 0.02)]
    bare, rim = flakes((H, W), X, T, spots, 41)
    height -= bare * 0.0025
    paint *= (1 + 0.25 * rim)[..., None]

    # Scuffs: short pale scrapes along the chines and the bow.
    rng_s = np.random.default_rng(5)
    scuff = np.zeros((H, W), dtype=np.float32)
    for _ in range(46):
        x = rng_s.uniform(-1.6, 1.8)
        t = rng_s.normal(0.0, 0.05)
        length = rng_s.uniform(0.03, 0.12)
        ang = rng_s.normal(0.0, 0.25)
        dx, dt = np.cos(ang), np.sin(ang)
        rx, rt = X - x, T - t
        along = rx * dx + rt * dt
        across = -rx * dt + rt * dx
        scuff = np.maximum(scuff, (np.abs(across) < 0.0012) * (np.abs(along) < length / 2) * 0.8)
    paint *= (1 + 0.3 * scuff)[..., None]

    # Dulled underneath and towards the jet.
    low = np.clip((-0.08 - hull.y) / 0.2, 0, 1)
    blotch = smooth_noise((H, W), (10, 24), 21)
    grime = 0.1 * low + 0.04 * blotch + 0.16 * np.exp(-((X - hull.x0) / 0.12) ** 2)
    paint *= (1 - np.clip(grime, 0, 0.5))[..., None]
    pv = hull.px_v(X)
    alpha = 1 - bare
    return np.concatenate([np.clip(paint, 0, 1), alpha[..., None]], axis=-1), height, pv


def paint_whisper_house(hull):
    paint = np.ones((H, W, 3), dtype=np.float32)
    height = np.zeros((H, W), dtype=np.float32)
    X, V = hull.X, hull.V
    per = hull.perimeter[None, :]
    shade, grain = coating((H, W), 51)
    paint *= shade[..., None]
    height += grain
    vc = np.array([side_v(hull, x, False) for x in hull.X[0]])[None, :]
    vcf = np.array([side_v(hull, x, True) for x in hull.X[0]])[None, :]
    near = V < 0.5
    T = np.where(near, (V - vc) * per, (vcf - V) * per)
    stealth_panels(paint, height, X, T, [0.14, 0.36, 0.55], [0.07], 7, tape=(("x", 0.55, 0.026),))
    ridge = np.exp(-((np.abs(V - 0.5) * per) / 0.0022) ** 2)
    paint *= (1 - 0.3 * ridge)[..., None]
    height -= ridge * 0.0015
    for (xa, xb, ta, tb) in ((0.17, 0.33, 0.015, 0.06), (0.6, 0.76, 0.1, 0.16)):
        sawtooth_hatch(paint, height, X, T, xa, xb, ta, tb, tooth=0.018)
    bare, rim = flakes((H, W), X, T, [(0.06, 0.05, 0.016), (0.78, 0.02, 0.014)], 52)
    height -= bare * 0.0025
    paint *= (1 + 0.25 * rim)[..., None]
    low = np.clip((0.22 - hull.y) / 0.08, 0, 1)
    paint *= (1 - 0.12 * low)[..., None]
    pv = hull.px_v(X)
    return np.concatenate([np.clip(paint, 0, 1), (1 - bare)[..., None]], axis=-1), height, pv


def paint_whisper_fin(shape):
    """A fin's map, on its own surface: u (across) runs root to tip, v (down)
    round the section from the leading edge (0), over one face to the
    trailing edge (0.5) and back over the other."""
    h, w = shape
    U = np.broadcast_to(((np.arange(w) + 0.5) / w)[None, :], shape)
    V = np.broadcast_to(((np.arange(h) + 0.5) / h)[:, None], shape)
    paint = np.ones((h, w, 3), dtype=np.float32)
    height = np.zeros(shape, dtype=np.float32)
    shade, grain = coating(shape, 61)
    paint *= shade[..., None]
    height += grain
    # Edge strips round the leading and trailing edges, their inner sides cut in a sawtooth.
    edge = np.minimum(np.minimum(V, 1 - V), np.abs(V - 0.5))
    bound = 0.07 + 0.018 * tri(U * 9)
    strip = edge < bound
    paint *= np.where(strip[..., None], 1.07, 1.0)
    groove = groove_of(strip, 1)
    paint *= np.where(groove[..., None], 0.62, 1.0)
    height -= groove * 0.002
    # A seam across each face, and fasteners along the root.
    seam = np.exp(-((U - 0.52) / 0.004) ** 2) * ~strip
    paint *= (1 - 0.3 * seam)[..., None]
    height -= seam * 0.0015
    dots = (np.abs(U - 0.06) < 0.012) & (np.abs(((V / 0.035) % 1.0) - 0.5) < 0.18) & ~strip
    paint *= np.where(dots[..., None], 0.8, 1.0)
    height += dots * 0.0004
    # Wear at the tip and along the leading edge.
    tip = np.clip((U - 0.88) / 0.1, 0, 1) * smooth_noise(shape, (12, 12), 62)
    paint *= (1 + 0.3 * tip)[..., None]
    le = np.clip(1 - np.minimum(V, 1 - V) / 0.025, 0, 1) * smooth_noise(shape, (16, 16), 63)
    paint *= (1 + 0.25 * le)[..., None]
    return np.clip(paint, 0, 1), height, (0.3 / w, 0.4 / h)


def paint_whisper_duct(shape):
    """The jet duct's map, on its own surface: u (across) runs from the
    sawtooth lip (0) forward to the intake (1), v (down) round the duct."""
    h, w = shape
    U = np.broadcast_to(((np.arange(w) + 0.5) / w)[None, :], shape)
    V = np.broadcast_to(((np.arange(h) + 0.5) / h)[:, None], shape)
    paint = np.ones((h, w, 3), dtype=np.float32)
    height = np.zeros(shape, dtype=np.float32)
    shade, grain = coating(shape, 71)
    paint *= shade[..., None]
    height += grain
    seam = np.zeros(shape, dtype=np.float32)
    for v in (0.125, 0.375, 0.625, 0.875):
        seam = np.maximum(seam, np.exp(-((V - v) / 0.003) ** 2) * (U > 0.12) * (U < 0.9))
    for u in (0.12, 0.9):
        seam = np.maximum(seam, np.exp(-((U - u) / 0.004) ** 2))
    paint *= (1 - 0.32 * seam)[..., None]
    height -= seam * 0.0016
    dots = np.zeros(shape, dtype=bool)
    for u in (0.17, 0.85):
        dots |= (np.abs(U - u) < 0.012) & (np.abs(((V / 0.02) % 1.0) - 0.5) < 0.2)
    paint *= np.where(dots[..., None], 0.8, 1.0)
    height += dots * 0.0004
    # Heat and wear at the lip, scrapes at the intake.
    lip = np.clip(1 - U / 0.12, 0, 1)
    paint *= (1 - 0.25 * lip)[..., None] * np.array([1.0, 0.97, 1.06])
    front = np.clip((U - 0.94) / 0.06, 0, 1) * smooth_noise(shape, (20, 6), 72)
    paint *= (1 + 0.3 * front)[..., None]
    return np.clip(paint, 0, 1), height, (0.45 / w, 1.1 / h)


def normal_map_flat(height, scale):
    """A normal map from a height field on a surface's own coordinates, scale
    being the world size of a texel (across, down)."""
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) / (2 * scale[0])
    gy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / (2 * scale[1])
    n = np.stack([-gx, gy, np.ones_like(gx)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


PAINTERS = {"lantern": paint_lantern, "mako": paint_mako, "bathysphere": paint_bathysphere,
            "whisper": paint_whisper, "whisper_house": paint_whisper_house}
## Maps for parts painted on their own surface's coordinates, with no hull to dump.
PART_PAINTERS = {"whisper_fin": (paint_whisper_fin, (512, 512)), "whisper_duct": (paint_whisper_duct, (512, 512))}
## Texture size (along, round) for hulls far from twice as long as they are round.
SIZES = {"bathysphere": (1024, 2048), "whisper_house": (1024, 1024)}


def main():
    os.makedirs(OUT, exist_ok=True)
    for frame in sys.argv[1:] or list(PAINTERS) + list(PART_PAINTERS):
        global W, H
        if frame in PART_PAINTERS:
            fn, (w, h) = PART_PAINTERS[frame]
            paint, height, scale = fn((h, w))
            Image.fromarray((paint * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "%s_paint.png" % frame))
            nm = normal_map_flat(height, scale)
            Image.fromarray((nm * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "%s_normal.png" % frame))
            print("painted", frame)
            continue
        W, H = SIZES.get(frame, (2048, 1024))
        hull = Hull(*load_hull(frame))
        paint, height, pv = PAINTERS[frame](hull)
        Image.fromarray((paint * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "%s_paint.png" % frame))
        nm = normal_map(hull, height, pv)
        Image.fromarray((nm * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "%s_normal.png" % frame))
        print("painted", frame)


if __name__ == "__main__":
    sys.exit(main())
