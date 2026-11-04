#!/usr/bin/env python3
"""Paint-shop maps for a submarine's fairing: an RGB multiply (panel seams,
rivets, grime, rust streaks, hatches, the name, hull designation and depth
rating) and the matching normal
map. They wrap the fairing's UVs: u runs stern to bow, v round each section
from the keel (0), up the near side (0.25), over the deck (0.5) and down the
far side (0.75), spaced evenly by distance.

The fairing's shape comes from the game (tools/art/dump_hull.gd), so the
maps always fit it:

    python3 tools/art/hull_maps.py            # writes assets/subs/lantern_*.png
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


def load_hull():
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "hull.json")
        subprocess.run([os.environ.get("GODOT", "godot"), "--headless", "--path", ROOT, "-s",
                        "res://tools/art/dump_hull.gd", "--", path], check=True, stdin=subprocess.DEVNULL,
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


def main():
    os.makedirs(OUT, exist_ok=True)
    hull = Hull(*load_hull())
    paint, height, pv = paint_lantern(hull)
    Image.fromarray((paint * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "lantern_paint.png"))
    nm = normal_map(hull, height, pv)
    Image.fromarray((nm * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "lantern_normal.png"))
    print("wrote", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    sys.exit(main())
