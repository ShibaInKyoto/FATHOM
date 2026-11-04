"""Sound effect recipes. Each function returns a mono or stereo numpy array."""
from __future__ import annotations

import numpy as np

from synth import (SR, RNG, additive, bandpass, env_exp, env_adsr, fade, fm, highpass, lerp_env,
                   lowpass, mix, noise, normalize, phase_from_freq, reverb_ir, saw, seconds, sine,
                   soft_clip, square, t_axis, to_stereo, trim_silence, wet_dry, VOWELS, formant_amps)

SMALL_ROOM = reverb_ir(1.2, 0.35, 2500, seed=1)
BIG_WATER = reverb_ir(3.5, 1.1, 1800, seed=2)
HUGE_WATER = reverb_ir(6.0, 2.2, 1200, seed=3)


def _sweep(f0: float, f1: float, duration: float, curve: float = 1.0) -> np.ndarray:
    t = np.linspace(0, 1, seconds(duration)) ** curve
    return f0 * (f1 / f0) ** t


def _thud(freq0: float = 90, freq1: float = 40, duration: float = 0.4, decay: float = 0.12) -> np.ndarray:
    return sine(_sweep(freq0, freq1, duration, 0.5)) * env_exp(duration, decay, 0.001)


def _clang(base: float, duration: float = 1.2, decay: float = 0.35) -> np.ndarray:
    ratios = [1.0, 2.76, 5.4, 8.93, 13.3]
    out = np.zeros(seconds(duration))
    for i, r in enumerate(ratios):
        out += sine(base * r, duration) * env_exp(duration, decay / (1 + i * 0.6)) / (1 + i)
    return out


def _bubbles(duration: float, count: int, low: float = 300, high: float = 1400) -> np.ndarray:
    out = np.zeros(seconds(duration))
    for _ in range(count):
        start = RNG.uniform(0, duration * 0.85)
        f = RNG.uniform(low, high)
        d = RNG.uniform(0.03, 0.09)
        blip = sine(_sweep(f, f * 1.8, d, 0.5)) * env_exp(d, d * 0.4, 0.002) * RNG.uniform(0.3, 1.0)
        i = seconds(start)
        out[i:i + len(blip)] += blip[: max(0, len(out) - i)]
    return out


# --- Sonar ------------------------------------------------------------------------------

def sonar_ping():
    d = 2.2
    tone = sine(_sweep(1250, 1180, d)) * env_exp(d, 0.45, 0.004)
    tone += sine(_sweep(2500, 2360, d)) * env_exp(d, 0.2, 0.004) * 0.15
    return normalize(trim_silence(wet_dry(tone * 0.8, BIG_WATER, 0.55)), 0.8)


def sonar_contact():
    out = np.zeros(seconds(0.9))
    for i, f in enumerate([1580, 1880]):
        blip = sine(f, 0.35) * env_exp(0.35, 0.08, 0.003)
        s = seconds(0.14 * i)
        out[s:s + len(blip)] += blip
    return normalize(trim_silence(wet_dry(out, SMALL_ROOM, 0.4)), 0.6)


def beacon_ping():
    tone = sine(2100, 0.8) * env_exp(0.8, 0.1, 0.002) + sine(4200, 0.8) * env_exp(0.8, 0.05) * 0.2
    return normalize(trim_silence(wet_dry(tone, BIG_WATER, 0.5)), 0.5)


def decoy_ping():
    # A hard mechanical double chirp: easy to tell from the sub's own sonar.
    out = np.zeros(seconds(1.4))
    for i, (f0, f1) in enumerate([(820, 760), (1240, 1150)]):
        d = 0.22
        chirp = square(_sweep(f0, f1, d), n_harm=5) * env_exp(d, 0.05, 0.002)
        s = seconds(0.11 * i)
        out[s:s + len(chirp)] += lowpass(chirp, 3200) * (0.8 if i == 0 else 0.6)
    return normalize(trim_silence(wet_dry(out, BIG_WATER, 0.5)), 0.65)


# --- Submarine ---------------------------------------------------------------------------

def lamp_toggle():
    click = highpass(noise(0.03), 2000) * env_exp(0.03, 0.006)
    thunk = sine(220, 0.08) * env_exp(0.08, 0.02)
    return normalize(mix(click, thunk * 0.6), 0.6)


def lantern_flame():
    # A small flame breathing in still air: soft, fluttering, a tick or two.
    d = 2.6
    breath = lowpass(noise(d, "pink"), 900) * (0.55 + 0.45 * np.abs(np.sin(t_axis(d) * 7.3) * np.sin(t_axis(d) * 2.1)))
    flutter = bandpass(noise(d), 380, 1.5) * 0.25
    ticks = np.zeros(seconds(d))
    for at in (0.7, 1.55, 2.2):
        tick = highpass(noise(0.02), 3000) * env_exp(0.02, 0.004)
        i = seconds(at)
        ticks[i:i + len(tick)] += tick * 0.35
    return normalize(fade(mix(breath, flutter, ticks), 0.6, 0.4), 0.32)


def lantern_douse():
    # Water closes over the flame: a sharp hiss of steam, a sizzle, a burst of bubbles.
    d = 1.8
    hiss = highpass(noise(d), 3000) * lerp_env([(0, 0), (0.02, 1), (0.3, 0.45), (1.4, 0)], d)
    sizzle = bandpass(noise(d), 5500, 3.0) * lerp_env([(0, 0), (0.02, 0.6), (0.5, 0.1), (1.0, 0)], d)
    bubbles = _bubbles(d, 26, 250, 900) * lerp_env([(0, 0.2), (0.1, 1), (1.6, 0)], d)
    thump = _thud(70, 40, 0.5, 0.15)
    return normalize(wet_dry(mix(hiss * 0.6, sizzle * 0.4, bubbles * 0.7, thump * 0.5), SMALL_ROOM, 0.25), 0.6)


def water_rise():
    # Dark water welling up: a low swell, a slow slosh, bubbles breaking loose.
    d = 3.6
    swell = lowpass(noise(d, "brown"), 400) * lerp_env([(0, 0), (1.5, 0.8), (3.0, 1.0), (3.6, 0)], d)
    slosh = bandpass(noise(d, "pink"), 700, 1.2) * (0.5 + 0.5 * np.sin(t_axis(d) * 2.6)) * \
        lerp_env([(0, 0), (1.0, 0.6), (3.6, 0)], d)
    bubbles = _bubbles(d, 18, 200, 700) * 0.5
    return normalize(mix(swell, slosh * 0.5, bubbles), 0.45)


def denied():
    d = 0.32
    out = np.zeros(seconds(d))
    for i in range(2):
        b = square(196, 0.11) * env_adsr(0.11, 0.005, 0.02, 0.7, 0.03)
        s = seconds(i * 0.14)
        out[s:s + len(b)] += b
    return normalize(lowpass(out, 1800), 0.5)


def power_down():
    d = 1.4
    tone = saw(_sweep(700, 60, d, 0.6), n_harm=10) * env_exp(d, 0.6, 0.01)
    return normalize(lowpass(tone, 1500) + lowpass(noise(d), 400) * env_exp(d, 0.3) * 0.3, 0.7)


def warning():
    d = 0.7
    out = np.zeros(seconds(d))
    for i, f in enumerate([880, 660]):
        b = sine(f, 0.22) * env_adsr(0.22, 0.01, 0.05, 0.6, 0.06) + sine(f * 2, 0.22) * 0.2 * env_exp(0.22, 0.05)
        s = seconds(i * 0.25)
        out[s:s + len(b)] += b
    return normalize(wet_dry(out, SMALL_ROOM, 0.3), 0.55)


def impact_rock():
    d = 0.9
    body = _thud(110, 35, d, 0.18)
    crunch = lowpass(noise(d, "pink"), 1400) * env_exp(d, 0.09)
    grit = bandpass(noise(d), 2500, 1.5) * env_exp(d, 0.03) * 0.5
    return normalize(trim_silence(wet_dry(mix(body, crunch, grit), SMALL_ROOM, 0.35)), 0.9)


def rock_loose():
    # Gravel trickling out of a ceiling under a low groan of stone.
    d = 1.1
    groan = sine(_sweep(70, 52, d)) * env_adsr(d, 0.15, 0.3, 0.7, 0.5) * 0.7
    out = np.zeros(seconds(d))
    for _ in range(34):
        s = seconds(RNG.uniform(0.0, d * 0.9))
        c = bandpass(noise(0.02), RNG.uniform(1800, 4200), 2.0) * env_exp(0.02, 0.004) * RNG.uniform(0.2, 0.9)
        out[s:s + len(c)] += c[: max(0, len(out) - s)]
    return normalize(trim_silence(wet_dry(mix(groan, out * 0.6), BIG_WATER, 0.45)), 0.65)


def rock_shatter():
    d = 1.6
    crack = highpass(noise(0.05), 1500) * env_exp(0.05, 0.01)
    body = _thud(120, 32, d, 0.25)
    crumble = np.zeros(seconds(d))
    for _ in range(40):
        s = seconds(RNG.uniform(0.02, d * 0.7))
        c = lowpass(noise(0.05, "pink"), RNG.uniform(600, 2200)) * env_exp(0.05, 0.015) * RNG.uniform(0.2, 0.8)
        crumble[s:s + len(c)] += c[: max(0, len(crumble) - s)]
    return normalize(trim_silence(wet_dry(mix(crack, body, crumble * 0.7), BIG_WATER, 0.5)), 0.9)


def scrape():
    d = 0.5
    n = bandpass(noise(d), 900, 1.2)
    am = 0.6 + 0.4 * np.sin(2 * np.pi * 37 * t_axis(d)) * RNG.uniform(0.5, 1, seconds(d))
    return normalize(n * am * env_adsr(d, 0.03, 0.1, 0.6, 0.2), 0.5)


def hull_hit():
    d = 1.4
    clang = _clang(170, d, 0.4)
    body = _thud(80, 40, d, 0.15)
    crunch = lowpass(noise(d), 2000) * env_exp(d, 0.05)
    return normalize(trim_silence(wet_dry(mix(clang * 0.7, body, crunch * 0.6), SMALL_ROOM, 0.4)), 0.9)


def implosion():
    d = 4.0
    boom = sine(_sweep(70, 22, d, 0.4)) * env_exp(d, 0.9, 0.005)
    rumble = lowpass(noise(d, "brown"), 300) * env_exp(d, 1.2, 0.01)
    metal = _clang(95, d, 0.9) * 0.5 + _clang(233, d, 0.5) * 0.3
    crack = highpass(noise(0.15), 1500) * env_exp(0.15, 0.03)
    return normalize(trim_silence(wet_dry(mix(boom * 1.2, rumble, metal, crack, _bubbles(d, 70, 200, 900) * 0.4),
                                          HUGE_WATER, 0.5)), 0.95)


def scan_complete():
    out = np.zeros(seconds(0.9))
    for i, f in enumerate([1046.5, 1318.5, 1568.0]):
        b = sine(f, 0.4) * env_exp(0.4, 0.12, 0.003) + sine(f * 2, 0.4) * env_exp(0.4, 0.05) * 0.2
        s = seconds(i * 0.075)
        out[s:s + len(b)] += b
    return normalize(trim_silence(wet_dry(out, SMALL_ROOM, 0.35)), 0.55)


def harpoon_fire():
    d = 0.5
    whoosh = bandpass(noise(d), 1200, 1.0) * env_exp(d, 0.12, 0.005)
    thunk = _thud(160, 60, d, 0.05)
    return normalize(mix(whoosh * 0.8, thunk), 0.75)


def harpoon_wall():
    d = 0.6
    clink = _clang(900, d, 0.08)
    tick = highpass(noise(0.05), 3000) * env_exp(0.05, 0.01)
    return normalize(trim_silence(wet_dry(mix(clink * 0.6, tick), SMALL_ROOM, 0.3)), 0.6)


def harpoon_hook():
    d = 0.6
    clank = _clang(420, d, 0.12)
    rattle = bandpass(noise(d), 3000, 2) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 28 * t_axis(d)))) * env_exp(d, 0.15)
    return normalize(mix(clank * 0.7, rattle * 0.4), 0.6)


def harpoon_flesh():
    d = 0.4
    wet = lowpass(noise(d, "pink"), 900) * env_exp(d, 0.07, 0.002)
    body = _thud(140, 70, d, 0.06)
    return normalize(mix(wet, body * 0.8), 0.75)


def tool_cycle():
    out = np.zeros(seconds(0.12))
    for i in range(2):
        c = highpass(noise(0.02), 2500) * env_exp(0.02, 0.004)
        s = seconds(i * 0.05)
        out[s:s + len(c)] += c
    return normalize(out, 0.4)


def flare_launch():
    d = 1.2
    pop = _thud(300, 120, 0.2, 0.03)
    fizz = highpass(noise(d), 2500) * env_adsr(d, 0.05, 0.2, 0.4, 0.7) * 0.4
    return normalize(mix(pop, fizz), 0.6)


def torpedo_launch():
    d = 1.3
    whoosh = bandpass(noise(d), 700, 0.8) * env_adsr(d, 0.02, 0.3, 0.4, 0.8)
    whine = saw(_sweep(300, 900, d, 0.7), n_harm=8) * env_adsr(d, 0.1, 0.2, 0.5, 0.8) * 0.25
    thunk = _thud(120, 50, 0.4, 0.06)
    return normalize(trim_silence(wet_dry(mix(whoosh, lowpass(whine, 2500), thunk), SMALL_ROOM, 0.3)), 0.75)


def explosion():
    d = 3.5
    boom = sine(_sweep(90, 28, d, 0.35)) * env_exp(d, 0.6, 0.002)
    body = lowpass(noise(d, "brown"), 500) * env_exp(d, 0.8, 0.003)
    crack = lowpass(noise(0.3), 3000) * env_exp(0.3, 0.05)
    return normalize(trim_silence(wet_dry(mix(boom * 1.2, body, crack * 0.8, _bubbles(d, 40, 200, 800) * 0.3),
                                          BIG_WATER, 0.45)), 0.95)


def shock():
    d = 0.8
    buzz = fm(110, 2.01, 6 * env_exp(d, 0.25), d) * env_exp(d, 0.3, 0.003)
    crackle = highpass(noise(d), 3000) * (RNG.random(seconds(d)) > 0.93) * env_exp(d, 0.25) * 3
    zap = sine(_sweep(2400, 300, 0.25, 0.5)) * env_exp(0.25, 0.08)
    return normalize(mix(buzz * 0.6, crackle * 0.5, zap * 0.6), 0.8)


def creature_hit():
    d = 0.35
    squelch = bandpass(noise(d, "pink"), 600, 1.5) * env_exp(d, 0.06, 0.002)
    tone = sine(_sweep(400, 200, d)) * env_exp(d, 0.05)
    return normalize(mix(squelch, tone * 0.4), 0.65)


def creature_die():
    d = 1.6
    f = _sweep(260, 90, d, 0.7) * (1 + 0.04 * np.sin(2 * np.pi * 7 * t_axis(d)))
    groan = lowpass(saw(f, n_harm=12), 1200) * env_adsr(d, 0.03, 0.2, 0.6, 0.8)
    return normalize(trim_silence(wet_dry(mix(groan * 0.7, _bubbles(d, 25, 300, 1000) * 0.4), BIG_WATER, 0.4)), 0.7)


def puffer_puff():
    # A quick gulping swell: a rising bloop over a burst of bubbles.
    d = 0.5
    bloop = sine(_sweep(170, 560, d, 0.6)) * env_adsr(d, 0.01, 0.15, 0.3, 0.3)
    return normalize(trim_silence(wet_dry(mix(bloop, _bubbles(d, 14, 500, 1600) * 0.5), SMALL_ROOM, 0.35)), 0.6)


def puffer_burst():
    d = 1.0
    pop = _thud(260, 80, 0.25, 0.04)
    needles = np.zeros(seconds(d))
    for _ in range(18):
        s = seconds(RNG.uniform(0.0, 0.25))
        f = RNG.uniform(2500, 5200)
        c = sine(f, 0.06) * env_exp(0.06, 0.012) * RNG.uniform(0.2, 0.6)
        needles[s:s + len(c)] += c
    return normalize(trim_silence(wet_dry(mix(pop, needles, _bubbles(d, 20, 400, 1500) * 0.4), SMALL_ROOM, 0.4)), 0.75)


def lancer_windup():
    d = 0.6
    out = np.zeros(seconds(d))
    t = 0.0
    gap = 0.09
    while t < d - 0.02:
        c = bandpass(noise(0.012), 4000, 2) * env_exp(0.012, 0.003)
        s = seconds(t)
        out[s:s + len(c)] += c
        t += gap
        gap = max(gap * 0.8, 0.018)
    return normalize(out, 0.6)


def lancer_dash():
    d = 0.5
    return normalize(bandpass(noise(d), 1500, 1.2) * env_adsr(d, 0.02, 0.1, 0.5, 0.35), 0.6)


def jelly_shock():
    d = 0.6
    zap = fm(600, 3.3, 4 * env_exp(d, 0.1), d) * env_exp(d, 0.15, 0.002)
    sparkle = highpass(noise(d), 5000) * env_exp(d, 0.08) * 0.6
    return normalize(trim_silence(wet_dry(mix(zap, sparkle), SMALL_ROOM, 0.3)), 0.65)


def lurelight_snap():
    d = 0.7
    chomp = _thud(180, 50, d, 0.08)
    crunch = lowpass(noise(d, "pink"), 2500) * env_exp(d, 0.06, 0.001)
    rush = bandpass(noise(d), 500, 1) * env_adsr(d, 0.01, 0.1, 0.3, 0.4) * 0.5
    return normalize(mix(chomp, crunch * 0.8, rush), 0.9)


def gulper_strike():
    d = 0.7
    hiss = bandpass(noise(d), 2200, 1.0) * env_adsr(d, 0.01, 0.15, 0.3, 0.4)
    snap = _thud(220, 60, 0.3, 0.04)
    return normalize(mix(hiss * 0.6, snap), 0.8)


def isopod_leap():
    d = 0.35
    out = np.zeros(seconds(d))
    for i in range(5):
        c = bandpass(noise(0.015), 3500, 3) * env_exp(0.015, 0.004)
        s = seconds(i * 0.035 + RNG.uniform(0, 0.01))
        out[s:s + len(c)] += c
    return normalize(out, 0.5)


def isopod_latch():
    d = 0.8
    clamp = _clang(520, d, 0.1) * 0.6
    grind = bandpass(noise(d), 1800, 2) * (0.5 + 0.5 * np.sin(2 * np.pi * 18 * t_axis(d))) * env_adsr(d, 0.05, 0.1, 0.6, 0.3)
    return normalize(mix(clamp, grind * 0.6), 0.65)


def stalker_roar():
    d = 3.0
    t = t_axis(d)
    f = 55 * (1 + 0.25 * np.sin(np.pi * t / d)) * (1 + 0.03 * np.sin(2 * np.pi * 5.5 * t))
    growl = np.zeros(seconds(d))
    ph = phase_from_freq(f)
    amps = formant_amps(55, VOWELS["o"], 60)
    for k, a in enumerate(amps):
        growl += a * np.sin(ph * (k + 1))
    rasp = lowpass(noise(d, "pink"), 700) * (0.6 + 0.4 * np.sin(2 * np.pi * 31 * t))
    env = env_adsr(d, 0.25, 0.5, 0.75, 1.2)
    sig = soft_clip(mix(growl * 0.8, rasp * 0.5) * env, 2.0)
    return normalize(trim_silence(wet_dry(sig, HUGE_WATER, 0.5)), 0.95)


def stalker_bite():
    d = 1.0
    chomp = _thud(110, 35, d, 0.12)
    crunch = lowpass(noise(d, "pink"), 3000) * env_exp(d, 0.1, 0.001)
    metal = _clang(140, d, 0.3) * 0.5
    return normalize(trim_silence(wet_dry(mix(chomp * 1.2, crunch, metal), SMALL_ROOM, 0.35)), 0.95)


def shoal_scatter():
    d = 0.8
    swish = bandpass(noise(d), 1800, 0.9) * env_adsr(d, 0.05, 0.2, 0.3, 0.5)
    return normalize(mix(swish * 0.5, _bubbles(d, 12, 700, 1800) * 0.4), 0.45)


# --- Pickups and world ---------------------------------------------------------------

def pickup_salvage():
    d = 0.5
    ding = sine(1760, d) * env_exp(d, 0.12, 0.002) + sine(2637, d) * env_exp(d, 0.07, 0.002) * 0.5
    return normalize(trim_silence(wet_dry(ding, SMALL_ROOM, 0.25)), 0.5)


def pickup_power():
    d = 0.7
    f = _sweep(500, 1500, d, 0.6)
    shimmer = additive(f, [1, 0.3, 0.15]) * env_adsr(d, 0.03, 0.2, 0.5, 0.4)
    return normalize(trim_silence(wet_dry(shimmer, SMALL_ROOM, 0.4)), 0.55)


def pickup_repair():
    d = 0.7
    ratchet = np.zeros(seconds(d))
    for i in range(4):
        c = _clang(1200, 0.06, 0.015)
        s = seconds(i * 0.06)
        ratchet[s:s + len(c)] += c
    chime = sine(1318, d) * env_exp(d, 0.2) * 0.5
    chime = np.concatenate([np.zeros(seconds(0.25)), chime])[: seconds(d)]
    return normalize(mix(ratchet * 0.5, chime), 0.55)


def bulb_harvest():
    d = 1.3
    glass = sum(sine(f, d) * env_exp(d, 0.5 / (i + 1), 0.002) / (i + 1) for i, f in enumerate([1975, 2637, 3520]))
    whoosh = bandpass(noise(d), 900, 0.8) * env_adsr(d, 0.1, 0.2, 0.3, 0.8) * 0.4
    return normalize(trim_silence(wet_dry(mix(glass, whoosh), BIG_WATER, 0.4)), 0.6)


def cache_open():
    d = 1.2
    latch = _clang(300, 0.4, 0.06)
    hiss = highpass(noise(0.8), 1500) * env_adsr(0.8, 0.02, 0.2, 0.4, 0.5) * 0.4
    chime = sum(sine(f, d) * env_exp(d, 0.3) for f in [1046, 1318, 1568]) / 3
    chime = np.concatenate([np.zeros(seconds(0.2)), chime])[: seconds(d)]
    return normalize(trim_silence(wet_dry(mix(latch, hiss, chime * 0.8), SMALL_ROOM, 0.3)), 0.7)


def log_found():
    d = 1.6
    out = np.zeros(seconds(d))
    notes = [659, 784, 988, 1319, 988, 1319]
    for i, f in enumerate(notes):
        b = square(f, 0.09, 7) * env_exp(0.09, 0.03, 0.002)
        s = seconds(i * 0.07)
        out[s:s + len(b)] += b * 0.6
    static = bandpass(noise(d), 3000, 1.5) * env_exp(d, 0.4) * 0.15
    return normalize(trim_silence(wet_dry(lowpass(mix(out, static), 5000), BIG_WATER, 0.35)), 0.55)


def zone_exit():
    d = 3.0
    whoosh = lowpass(noise(d, "pink"), 900) * env_adsr(d, 0.6, 0.6, 0.6, 1.5)
    drop = sine(_sweep(180, 40, d, 0.7)) * env_adsr(d, 0.2, 0.5, 0.6, 1.5) * 0.6
    return normalize(trim_silence(wet_dry(mix(whoosh, drop, _bubbles(d, 40, 200, 1000) * 0.4), BIG_WATER, 0.4)), 0.8)


def dock():
    d = 2.0
    clunk = _thud(120, 50, 0.6, 0.1) + _clang(200, 0.6, 0.15) * 0.4
    hiss = highpass(noise(1.2), 1200) * env_adsr(1.2, 0.05, 0.4, 0.3, 0.6) * 0.4
    ding = sine(1568, d) * env_exp(d, 0.4) * 0.4
    return normalize(trim_silence(mix(clunk, np.concatenate([np.zeros(seconds(0.2)), hiss]),
                                      np.concatenate([np.zeros(seconds(0.7)), ding]))), 0.75)


def creak():
    d = 2.0
    t = t_axis(d)
    f = 90 + 40 * np.sin(2 * np.pi * 0.4 * t) + RNG.uniform(-5, 5)
    stick = (np.sin(phase_from_freq(f) * 1.0) > 0.7).astype(float)
    tone = bandpass(stick - stick.mean(), 400, 1.2) * env_adsr(d, 0.3, 0.4, 0.6, 0.8)
    return normalize(trim_silence(wet_dry(tone, BIG_WATER, 0.5)), 0.5)


# --- UI ----------------------------------------------------------------------------------

def ui_click():
    d = 0.08
    return normalize(sine(1800, d) * env_exp(d, 0.015, 0.001) + highpass(noise(d), 4000) * env_exp(d, 0.004) * 0.5, 0.45)


def ui_hover():
    d = 0.06
    return normalize(sine(1200, d) * env_exp(d, 0.012, 0.002), 0.25)


def module_install():
    d = 1.5
    chord = np.zeros(seconds(d))
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        s = seconds(i * 0.06)
        n = sine(f, d - i * 0.06) * env_exp(d - i * 0.06, 0.5, 0.005)
        chord[s:s + len(n)] += n
    rise = sine(_sweep(200, 800, 0.4)) * env_adsr(0.4, 0.05, 0.1, 0.5, 0.2) * 0.3
    return normalize(trim_silence(wet_dry(mix(chord, rise), SMALL_ROOM, 0.35)), 0.6)


def repair():
    return pickup_repair()


def purchase():
    d = 1.0
    out = np.zeros(seconds(d))
    for i, f in enumerate([1318.5, 1975.5]):
        n = sine(f, 0.6) * env_exp(0.6, 0.18, 0.002) + sine(f * 2, 0.6) * env_exp(0.6, 0.05) * 0.3
        s = seconds(i * 0.09)
        out[s:s + len(n)] += n
    return normalize(trim_silence(wet_dry(out, SMALL_ROOM, 0.3)), 0.55)


# --- Loops ---------------------------------------------------------------------------------

def engine_loop():
    """Seamless 2 s engine hum (pitched by speed at runtime)."""
    d = 2.0
    t = t_axis(d)
    hum = additive(55.0, [1.0, 0.5, 0.35, 0.2, 0.12, 0.08], d)
    whir = sine(440, d) * 0.08 * (1 + 0.5 * np.sin(2 * np.pi * 4 * t))
    water = lowpass(noise(d, "pink"), 600) * 0.25
    sig = mix(hum * 0.6, whir, water)
    # Crossfade the ends so the loop is seamless.
    k = seconds(0.25)
    sig[:k] = sig[:k] * np.linspace(0, 1, k) + sig[-k:] * np.linspace(1, 0, k)
    sig = sig[: len(sig) - k]
    return normalize(sig, 0.6)




def plate_step():
    """The Ironclad's stride: a heavy thud through the rock and its plates
    clattering against each other, dulled by the water."""
    d = 0.7
    thud = _thud(70, 32, 0.5, 0.09) * 1.2
    clatter = np.zeros(seconds(d))
    for k in range(5):
        tick = _clang(RNG.uniform(600, 1100), 0.18, 0.03) * RNG.uniform(0.15, 0.3)
        i = seconds(0.03 + k * RNG.uniform(0.03, 0.06))
        clatter[i:i + len(tick)] += tick[: len(clatter) - i]
    grit = lowpass(noise(d, "pink"), 700) * env_exp(d, 0.08, 0.001) * 0.35
    out = np.zeros(seconds(d))
    out[: len(thud)] += thud
    out = mix(out, lowpass(clatter, 2500), grit)
    return normalize(trim_silence(wet_dry(out, SMALL_ROOM, 0.25)), 0.75)


def station_hum():
    """Meridian Deep's failing power: a 4 s seamless transformer drone (50 Hz with
    buzzy odd harmonics), a relay ticking, metal ticking as it cools, all dulled
    by the water. Ducked at runtime whenever the circuit drops out (MeridianStation)."""
    d = 4.0
    t = t_axis(d)
    drone = additive(50.0, [1.0, 0.45, 0.6, 0.2, 0.35, 0.1, 0.18, 0.05, 0.1], d)
    # A slow beat between two near-identical mains tones keeps it alive.
    beat = 1.0 + 0.18 * np.sin(2 * np.pi * 0.5 * t)
    buzz = lowpass(square(100.0, d) * 0.12, 900) * (1.0 + 0.3 * np.sin(2 * np.pi * 0.25 * t))
    out = mix(drone * beat * 0.7, buzz)
    for k in range(4):
        tick = highpass(noise(0.02, "white"), 1500) * env_exp(0.02, 0.004, 0.001) * 0.35
        i = seconds(0.3 + k * 1.0)
        out[i:i + len(tick)] += tick
    for start in (1.35, 3.1):
        ping = _clang(RNG.uniform(900, 1400), 0.5, 0.08) * 0.06
        i = seconds(start)
        out[i:i + len(ping)] += ping[: len(out) - i]
    out = lowpass(out, 1400) + lowpass(noise(d, "pink"), 400) * 0.08
    k = seconds(0.3)
    out[:k] = out[:k] * np.linspace(0, 1, k) + out[-k:] * np.linspace(1, 0, k)
    out = out[: len(out) - k]
    return normalize(out, 0.55)


def vent_rumble():
    """A thermal vent building up: a deep, swelling rumble with rising bubbles."""
    d = 1.4
    t = t_axis(d)
    rumble = lowpass(noise(d, "brown"), 120) * (t / d) ** 1.5 * 2.0
    groan = sine(_sweep(32, 46, d)) * (t / d) * 0.6
    return normalize(trim_silence(mix(rumble, groan, _bubbles(d, 25, 200, 700) * 0.35)), 0.8)


def vent_erupt():
    """The eruption: a roaring, hissing column of boiling water."""
    d = 2.8
    roar = lowpass(noise(d, "pink"), 900) * env_adsr(d, 0.05, 0.3, 0.8, 1.2)
    hiss = highpass(noise(d, "white"), 3000) * env_adsr(d, 0.02, 0.4, 0.35, 1.0) * 0.25
    boom = _thud(70, 30, 0.8, 0.25) * 1.2
    sig = mix(roar, hiss, _bubbles(d, 90, 250, 1600) * 0.5)
    sig[: len(boom)] += boom
    return normalize(trim_silence(wet_dry(sig, BIG_WATER, 0.4)), 0.9)


def heartbeat_loop():
    """Two muffled lub-dub beats at 72 bpm; exact length, so it loops cleanly.
    Played under a hunting Stalker and sped up as it closes in."""
    beat = 60.0 / 72.0
    d = beat * 2
    out = np.zeros(seconds(d))
    for k in range(2):
        for offset, f0, f1, gain in ((0.0, 62, 34, 1.0), (0.17, 74, 40, 0.6)):
            thud = _thud(f0, f1, 0.32, 0.07) * gain
            thud = thud + lowpass(noise(0.32, "pink"), 180) * env_exp(0.32, 0.04, 0.001) * 0.3 * gain
            i = seconds(k * beat + offset)
            out[i:i + len(thud)] += thud[: len(out) - i]
    return normalize(lowpass(out, 300), 0.8)


# --- The Choir ------------------------------------------------------------------------

def _choir_voice(f0: float, d: float, vowel: str = "o", vib: float = 5.0) -> np.ndarray:
    t = t_axis(d)
    ph = phase_from_freq(f0 * (1 + 0.008 * np.sin(2 * np.pi * vib * t)))
    out = np.zeros(seconds(d))
    for k, a in enumerate(formant_amps(f0, VOWELS[vowel], 40)):
        if a > 0.003:
            out += a * np.sin(ph * (k + 1))
    return out


def alert():
    d = 0.5
    out = np.zeros(seconds(d))
    for i, f in enumerate([740, 988]):
        b = sine(f, 0.12) * env_exp(0.12, 0.04, 0.002)
        s = seconds(i * 0.06)
        out[s:s + len(b)] += b
    return normalize(trim_silence(wet_dry(out, SMALL_ROOM, 0.3)), 0.45)


def choir_wave():
    d = 2.2
    v = mix(_choir_voice(185, d, "o"), _choir_voice(277, d, "u") * 0.6, _choir_voice(370, d, "a") * 0.3)
    return normalize(trim_silence(wet_dry(v * env_adsr(d, 0.05, 0.4, 0.5, 1.4), BIG_WATER, 0.5)), 0.7)


def choir_answer():
    d = 1.6
    v = mix(_choir_voice(554, d, "a") * 0.6, sine(1250, d) * env_exp(d, 0.35) * 0.8, _choir_voice(740, d, "e") * 0.3)
    return normalize(trim_silence(wet_dry(v * env_adsr(d, 0.01, 0.3, 0.4, 1.0), BIG_WATER, 0.45)), 0.7)


def choir_call():
    d = 4.0
    f = 123 * (1 + 0.12 * np.sin(np.pi * np.linspace(0, 1, seconds(d))))
    v = mix(_choir_voice(123, d, "o") * 0.8, _choir_voice(185, d, "a") * 0.5, sine(f) * 0.3)
    return normalize(trim_silence(wet_dry(v * env_adsr(d, 0.6, 0.8, 0.7, 1.8), HUGE_WATER, 0.55)), 0.85)


def choir_tone():
    """The Choir's tone changing pitch under the station (log_05): a low hum in
    two voices that slides to a new note and holds it."""
    d = 3.6
    t = np.linspace(0, 1, seconds(d))
    slide = 1 + 0.19 * np.clip((t - 0.25) / 0.35, 0, 1) ** 2
    v = np.zeros(seconds(d))
    for f, a in [(73.4, 1.0), (110.0, 0.55), (146.8, 0.25)]:
        ph = phase_from_freq(f * slide * (1 + 0.004 * np.sin(2 * np.pi * 3.1 * t_axis(d))))
        v += a * (np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph))
    v = lowpass(v, 700) * env_adsr(d, 0.7, 0.5, 0.8, 1.2)
    return normalize(trim_silence(wet_dry(v, HUGE_WATER, 0.6)), 0.6)


def choir_echo():
    """The sub's own ping coming back up from far below eleven seconds later,
    slowed down and stretched into something like a word (log_03)."""
    d = 4.2
    t = np.linspace(0, 1, seconds(d))
    tone = sine(_sweep(560, 420, d)) * env_exp(d, 1.3, 0.02) * 0.55
    f0 = 140 * (1 - 0.12 * t)
    ph = phase_from_freq(f0)
    o = formant_amps(140, VOWELS["o"], 36)
    a = formant_amps(140, VOWELS["a"], 36)
    w = np.clip((t - 0.3) / 0.4, 0, 1)
    voice = np.zeros(seconds(d))
    for k in range(36):
        voice += (o[k] * (1 - w) + a[k] * w) * np.sin(ph * (k + 1))
    out = mix(tone, voice * env_adsr(d, 0.45, 0.6, 0.7, 1.6) * 0.8)
    return normalize(trim_silence(wet_dry(lowpass(out, 2500), HUGE_WATER, 0.6)), 0.7)


def trench_song():
    """The Choir singing far below while the trench reshapes itself: low voices
    gliding down a fifth and back, heard through a lot of water."""
    d = 6.5
    t = np.linspace(0, 1, seconds(d))
    glide = 1 - 0.33 * np.sin(np.pi * t) ** 2
    v = np.zeros(seconds(d))
    for f, vw, a in [(98, "o", 0.9), (147, "u", 0.55), (196, "a", 0.3)]:
        tt = t_axis(d)
        ph = phase_from_freq(f * glide * (1 + 0.006 * np.sin(2 * np.pi * 4.3 * tt)))
        for k, amp in enumerate(formant_amps(f, VOWELS[vw], 30)):
            if amp > 0.003:
                v += a * amp * np.sin(ph * (k + 1))
    v = lowpass(v, 900) * env_adsr(d, 1.2, 1.0, 0.8, 2.6)
    return normalize(trim_silence(wet_dry(v, HUGE_WATER, 0.65)), 0.75)


def rock_flow():
    """Rock moving like something alive: a slow grinding groan with creaks and
    falling grit."""
    d = 5.0
    t = t_axis(d)
    groan = lowpass(noise(d, "brown"), 220) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.7 * t + 1.3 * np.sin(2 * np.pi * 0.23 * t)))
    tone = sine(_sweep(52, 38, d, 0.8)) * 0.35
    creaks = np.zeros(seconds(d))
    for _ in range(7):
        start = RNG.uniform(0.2, d - 0.8)
        cd = RNG.uniform(0.25, 0.5)
        c = bandpass(saw(_sweep(RNG.uniform(140, 260), RNG.uniform(90, 140), cd, 0.6)), 420, 1.2) \
            * env_adsr(cd, 0.05, 0.1, 0.5, 0.15) * RNG.uniform(0.2, 0.45)
        i = seconds(start)
        creaks[i:i + len(c)] += c[: max(0, len(creaks) - i)]
    grit = highpass(noise(d, "white"), 2500) * env_adsr(d, 0.8, 1.0, 0.25, 1.5) * 0.05
    out = mix(groan, tone, creaks, grit) * env_adsr(d, 0.6, 0.8, 0.85, 1.4)
    return normalize(trim_silence(wet_dry(soft_clip(out * 1.4), BIG_WATER, 0.4)), 0.8)


def choir_death():
    d = 7.0
    t = np.linspace(0, 1, seconds(d))
    v = np.zeros(seconds(d))
    for f, vw in [(123, "o"), (185, "a"), (246, "u"), (370, "e")]:
        voice = _choir_voice(f, d, vw)
        v += voice * (1 - t) ** 0.5
    rise = sine(220 * (1 + 3 * t ** 2)) * env_adsr(d, 1.0, 1.0, 0.4, 3.0) * 0.2
    return normalize(trim_silence(wet_dry(mix(v * env_adsr(d, 0.2, 1.0, 0.8, 4.0), rise), HUGE_WATER, 0.6)), 0.9)


def organ_burst():
    d = 2.5
    burst = lowpass(noise(d, "pink"), 1500) * env_exp(d, 0.3, 0.002)
    wail = _choir_voice(330, d, "a") * env_adsr(d, 0.01, 0.2, 0.5, 1.5) * 0.5
    return normalize(trim_silence(wet_dry(mix(burst, wail, _bubbles(d, 30, 300, 1200) * 0.4), BIG_WATER, 0.5)), 0.85)


def glass_ring():
    """Volcanic glass ringing where a ping has reached it: a struck-glass tone
    with the inharmonic partials of a bowl, beating slowly, and a long tail."""
    d = 6.0
    t = t_axis(d)
    f0 = 587.0
    out = np.zeros(seconds(d))
    for ratio, amp, decay in [(1.0, 1.0, 2.2), (2.76, 0.42, 1.2), (5.4, 0.2, 0.6), (8.93, 0.08, 0.3)]:
        beat = 1 + 0.0018 * np.sin(2 * np.pi * (0.9 + ratio * 0.35) * t)
        out += amp * np.sin(phase_from_freq(f0 * ratio * beat)) * env_exp(d, decay, 0.003)
    tick = highpass(noise(0.04), 4000) * env_exp(0.04, 0.008) * 0.25
    return normalize(trim_silence(wet_dry(mix(out, tick), BIG_WATER, 0.45)), 0.7)


def glass_shatter():
    """A seam of volcanic glass shattering: a sharp crack, a shower of bright
    shards ringing as they fall, and the rock behind giving way."""
    d = 2.4
    crack = highpass(noise(0.08), 2500) * env_exp(0.08, 0.02)
    body = _thud(150, 40, d, 0.3) * 0.6
    shards = np.zeros(seconds(d))
    for _ in range(46):
        start = seconds(RNG.uniform(0.0, d * 0.75))
        sd = RNG.uniform(0.15, 0.5)
        f = RNG.uniform(1800, 5200)
        s = np.sin(phase_from_freq(np.full(seconds(sd), f))) * env_exp(sd, RNG.uniform(0.04, 0.12)) \
            * RNG.uniform(0.08, 0.3)
        shards[start:start + len(s)] += s[: max(0, len(shards) - start)]
    out = mix(crack, body, shards, _glass_ring_tail(d) * 0.35)
    return normalize(trim_silence(wet_dry(out, BIG_WATER, 0.5)), 0.9)


def _glass_ring_tail(d: float) -> np.ndarray:
    """The chord the glass rang, dying away under the shatter."""
    out = np.zeros(seconds(d))
    for f in [587.0, 740.0, 880.0]:
        out += np.sin(phase_from_freq(np.full(seconds(d), f))) * env_exp(d, 0.9, 0.002)
    return out


def whale_click():
    """A sperm whale's echolocation click heard across open water: a sharp
    broadband snap with a short ringing tail."""
    snap = bandpass(noise(0.012), 4000, 0.8) * env_exp(0.012, 0.003)
    ring = np.sin(phase_from_freq(np.full(seconds(0.06), 900.0))) * env_exp(0.06, 0.012) * 0.4
    out = np.zeros(seconds(0.3))
    out[: len(snap)] += snap
    out[: len(ring)] += ring
    return normalize(trim_silence(wet_dry(out, BIG_WATER, 0.35)), 0.6)


def whale_creak():
    """A sperm whale homing in on something: clicks quickening into a creak."""
    d = 1.6
    out = np.zeros(seconds(d))
    t, gap = 0.0, 0.09
    while t < 1.3:
        c = bandpass(noise(0.006), 3500, 0.9) * env_exp(0.006, 0.002) * (0.4 + 0.6 * t / 1.3)
        i = seconds(t)
        out[i:i + len(c)] += c[: max(0, len(out) - i)]
        t += gap
        gap = max(0.012, gap * 0.9)
    return normalize(trim_silence(wet_dry(out, BIG_WATER, 0.3)), 0.55)


def wonder_chime():
    """A wonder of the trench witnessed: four soft bell tones rising through a
    major seventh, ringing on in a lot of water."""
    d = 3.2
    out = np.zeros(seconds(d))
    for i, f in enumerate([523.3, 659.3, 784.0, 987.8]):
        n = d - i * 0.16
        b = (sine(f, n) + 0.3 * sine(f * 2.76, n) * env_exp(n, 0.25)) * env_exp(n, 1.1, 0.004)
        s = seconds(i * 0.16)
        out[s:s + len(b)] += b * (0.8 - i * 0.1)
    return normalize(trim_silence(wet_dry(out, HUGE_WATER, 0.5)), 0.5)


# Okafor's lullaby (log_08): MIDI note and length in beats, three to a bar.
LULLABY = [(69, 1), (74, 1), (78, 1), (76, 2), (74, 1), (71, 1), (74, 1), (69, 1), (69, 3),
           (67, 1), (71, 1), (74, 1), (73, 2), (71, 1), (69, 1), (66, 1), (64, 1), (62, 3)]


def _hz(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


def lullaby_speaker():
    """Okafor's lullaby as Meridian's hull speakers still play it: a music-box
    melody through a small, tired speaker, with hiss and crackle."""
    beat = 60 / 92
    d = sum(b for _, b in LULLABY) * beat + 2.0
    t = t_axis(d)
    wow = 1 + 0.003 * np.sin(2 * np.pi * 0.7 * t)
    out = np.zeros(seconds(d))
    at = 0.0
    for midi, beats in LULLABY:
        n = min(2.2, d - at)
        f = _hz(midi)
        i = seconds(at)
        w = wow[i:i + seconds(n)]
        tone = (np.sin(phase_from_freq(f * w)) + 0.35 * np.sin(phase_from_freq(f * 3.01 * w)) * env_exp(n, 0.3)
                + 0.15 * np.sin(phase_from_freq(f * 5.4 * w)) * env_exp(n, 0.12)) * env_exp(n, 0.9, 0.004)
        out[i:i + len(tone)] += tone[: max(0, len(out) - i)] * 0.5
        at += beats * beat
    out = lowpass(highpass(out, 380), 3200)
    hiss = highpass(noise(d), 2000) * 0.015
    crackle = np.zeros(seconds(d))
    for _ in range(60):
        k = seconds(RNG.uniform(0, d - 0.01))
        crackle[k:k + 40] += RNG.uniform(-0.25, 0.25) * np.exp(-np.arange(40) / 6.0)
    return normalize(trim_silence(wet_dry(mix(out, hiss, crackle), BIG_WATER, 0.3)), 0.6)


def lullaby_choir():
    """The lullaby sung back from far below, an octave down and slower, in the
    Choir's voice (log_08: "It sang it back. Perfectly.")."""
    beat = 60 / 70
    d = sum(b for _, b in LULLABY) * beat + 3.5
    f = np.zeros(seconds(d))
    amp = np.zeros(seconds(d))
    at = 0.0
    prev = _hz(LULLABY[0][0] - 12)
    for midi, beats in LULLABY:
        n = beats * beat
        i, j = seconds(at), seconds(at + n)
        target = _hz(midi - 12)
        glide = min(seconds(0.09), j - i)
        f[i:i + glide] = np.linspace(prev, target, glide)
        f[i + glide:j] = target
        env = np.ones(j - i)
        env[: seconds(0.12)] = np.linspace(0.3, 1.0, seconds(0.12))
        # A breath at the end of each phrase.
        if beats == 3:
            tail = seconds(0.45)
            env[-tail:] *= np.linspace(1.0, 0.0, tail)
        amp[i:j] = env
        prev = target
        at += n
    f[seconds(at):] = prev
    amp[seconds(at):] = np.linspace(1.0, 0.0, len(amp) - seconds(at)) ** 2
    t = t_axis(d)
    out = np.zeros(seconds(d))
    for ratio, gain, vowel in [(1.0, 1.0, "o"), (2 / 3, 0.45, "u"), (2.0, 0.18, "a")]:
        ph = phase_from_freq(f * ratio * (1 + 0.007 * np.sin(2 * np.pi * (4.6 + ratio) * t)))
        for k, a in enumerate(formant_amps(150 * ratio, VOWELS[vowel], 36)):
            if a > 0.003:
                out += gain * a * np.sin(ph * (k + 1))
    out = lowpass(out * amp, 1800)
    return normalize(trim_silence(wet_dry(out, HUGE_WATER, 0.65)), 0.8)


ALL = {name: fn for name, fn in list(globals().items())
       if callable(fn) and not name.startswith("_") and fn.__module__ == __name__}
