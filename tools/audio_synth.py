#!/usr/bin/env python3
"""Procedural audio for Midnight Syndicate. Python standard library only, deterministic seeds.

  py -3.10 tools/audio_synth.py              # generate everything into game/assets/audio/
  py -3.10 tools/audio_synth.py --only=ui    # only groups/files whose name contains "ui"
  py -3.10 tools/audio_synth.py --no-music

Everything is original: additive/subtractive synthesis and noise, no samples, no external data.
SFX are 44.1 kHz 16-bit mono. Music is 16-bit stereo (race 32 kHz, menu 24 kHz to keep size down).
Loops carry a RIFF 'smpl' chunk so Godot's WAV importer flags them as looping, and are built so
the last sample flows into the first (integer cycles or an equal-gain crossfade of the tail).
Writes game/assets/audio/audio_manifest.json (rate, channels, length, loop, sha256 per file).
"""
import hashlib
import json
import math
import os
import random
import struct
import sys
from array import array

SR = 44100
TAU = 2.0 * math.pi
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "game", "assets", "audio"))


# ----------------------------------------------------------------------------- io
def write_wav(path, chans, sr, loop=False, peak=0.89):
    """chans: list of float lists (1 or 2). Normalised jointly to `peak`."""
    m = max(max(max(c), -min(c)) for c in chans) or 1.0
    g = peak * 32767.0 / m
    n = len(chans[0])
    nch = len(chans)
    pcm = array("h", [0]) * (n * nch)
    for k, c in enumerate(chans):
        pcm[k::nch] = array("h", [int(max(-32767.0, min(32767.0, v * g))) for v in c])
    if sys.byteorder == "big":
        pcm.byteswap()
    data = pcm.tobytes()
    fmt = struct.pack("<HHIIHH", 1, nch, sr, sr * nch * 2, nch * 2, 16)
    body = b"WAVE" + b"fmt " + struct.pack("<I", 16) + fmt
    body += b"data" + struct.pack("<I", len(data)) + data
    if loop:
        smpl = struct.pack("<IIIIIIIII", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<IIIIII", 0, 0, 0, n - 1, 0, 0)
        body += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)
    return {
        "sample_rate": sr, "channels": nch, "frames": n,
        "seconds": round(n / sr, 3), "loop": loop,
        "bytes": os.path.getsize(path),
        "sha256": hashlib.sha256(open(path, "rb").read()).hexdigest(),
    }


# ----------------------------------------------------------------------------- dsp
def lp(x, fc, sr=SR):
    a = 1.0 - math.exp(-TAU * fc / sr)
    y = 0.0
    out = []
    for v in x:
        y += a * (v - y)
        out.append(y)
    return out


def lp_var(x, fcs, sr=SR):
    """One-pole low-pass with a per-sample cutoff list."""
    y = 0.0
    out = []
    for v, fc in zip(x, fcs):
        y += (1.0 - math.exp(-TAU * fc / sr)) * (v - y)
        out.append(y)
    return out


def hp(x, fc, sr=SR):
    return [a - b for a, b in zip(x, lp(x, fc, sr))]


def bp(x, lo, hi, sr=SR):
    return lp(hp(x, lo, sr), hi, sr)


def noise(n, seed):
    r = random.Random(seed)
    return [r.uniform(-1.0, 1.0) for _ in range(n)]


def loopify(g, n):
    """g has n + xf samples. Equal-gain crossfade of the overshoot into the head; returns n samples."""
    xf = len(g) - n
    out = g[:n]
    for i in range(xf):
        t = i / xf
        out[i] = g[i] * t + g[n + i] * (1.0 - t)
    return out


def norm(x, peak=1.0):
    m = max(max(x), -min(x)) or 1.0
    return [v * peak / m for v in x]


def tanh_clip(x, drive):
    d = math.tanh(drive)
    return [math.tanh(v * drive) / d for v in x]


def expenv(n, tau, sr=SR):
    return [math.exp(-i / (tau * sr)) for i in range(n)]


def fade(x, a_ms=2.0, r_ms=8.0, sr=SR):
    n = len(x)
    a = max(1, int(a_ms * sr / 1000))
    r = max(1, int(r_ms * sr / 1000))
    out = list(x)
    for i in range(min(a, n)):
        out[i] *= i / a
    for i in range(min(r, n)):
        out[n - 1 - i] *= i / r
    return out


def mix(*parts):
    """mix(a, (b, gain), ...) -> list; parts may differ in length."""
    parts = [p if isinstance(p, tuple) else (p, 1.0) for p in parts]
    out = [0.0] * max(len(p[0]) for p in parts)
    for p, g in parts:
        for i, v in enumerate(p):
            out[i] += v * g
    return out


def sweep(f0, f1, tau, n, sr=SR):
    """Sine whose frequency decays exponentially from f0 to f1."""
    ph = 0.0
    out = []
    for i in range(n):
        ph += TAU * (f1 + (f0 - f1) * math.exp(-i / (tau * sr))) / sr
        out.append(math.sin(ph))
    return out


def harm_loop(period, cycles, harm_amps, jitter, seed, phases=None):
    """Periodic engine-style waveform. Per-cycle amplitude jitter is part of the loop (integer cycles)."""
    r = random.Random(seed)
    tab = []
    for i in range(period):
        s = 0.0
        for h, a in enumerate(harm_amps, 1):
            s += a * math.sin(TAU * h * i / period + (phases[h - 1] if phases else 0.0))
        tab.append(s)
    out = []
    for _ in range(cycles):
        a = 1.0 + jitter * r.uniform(-1, 1)
        out.extend(v * a for v in tab)
    return out


# --- band-limited wavetable oscillators (music + stings) ---
_WT = {}


def wavetable(kind, freq, sr):
    key = (kind, round(freq, 3), sr)
    t = _WT.get(key)
    if t is not None:
        return t
    size = 1024
    nh = max(1, min(48, int(sr * 0.45 / freq)))
    t = [0.0] * size
    for h in range(1, nh + 1):
        if kind == "saw":
            a = 1.0 / h
        elif kind == "square":
            a = 0.0 if h % 2 == 0 else 1.0 / h
        elif kind == "tri":
            a = 0.0 if h % 2 == 0 else (1.0 / (h * h)) * (1 if (h // 2) % 2 == 0 else -1)
        else:
            a = 1.0 if h == 1 else 0.0
        if a:
            for i in range(size):
                t[i] += a * math.sin(TAU * h * i / size)
    m = max(max(t), -min(t))
    t = [v / m for v in t]
    _WT[key] = t
    return t


def osc(kind, freq, n, sr, detune_cents=(0.0,), ph0=0.0):
    out = [0.0] * n
    k = 1.0 / len(detune_cents)
    for d, dc in enumerate(detune_cents):
        f = freq * 2 ** (dc / 1200.0)
        t = wavetable(kind, f, sr)
        inc = f / sr
        ph = (ph0 + d * 0.37) % 1.0
        for i in range(n):
            x = ph * 1024.0
            i0 = int(x)
            out[i] += (t[i0] + (t[(i0 + 1) & 1023] - t[i0]) * (x - i0)) * k
            ph += inc
            if ph >= 1.0:
                ph -= 1.0
    return out


def adsr(n, a, d, s, r, sr):
    """Linear attack, exponential decay to sustain, linear release over the last r seconds."""
    ai = max(1, int(a * sr))
    ri = max(1, int(r * sr))
    out = []
    for i in range(n):
        v = i / ai if i < ai else s + (1.0 - s) * math.exp(-(i - ai) / (max(d, 1e-3) * sr))
        left = n - i
        if left < ri:
            v *= left / ri
        out.append(v)
    return out


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


# ----------------------------------------------------------------------------- engine
def gen_engine():
    res = {}
    # idle rumble ~40 Hz, lumpy, 2.0 s (80 cycles of 1102 samples)
    amps = [1.0, 0.85, 0.7, 0.5, 0.42, 0.3, 0.22, 0.16, 0.1, 0.07]
    ph = [0.0, 0.7, 1.9, 0.3, 2.2, 1.1, 0.5, 2.6, 1.4, 0.2]
    low = harm_loop(1102, 80, amps, 0.30, 11, ph)
    n = len(low)
    rough = loopify(lp(noise(n + 4000, 21), 260), n)
    res["engine_low_loop"] = ([tanh_clip(mix(norm(low), (norm(rough), 0.22)), 1.9)], SR, True)
    # mid layer ~110 Hz, 1.0 s
    amps = [1.0 / (h ** 0.85) for h in range(1, 17)]
    amps[3] *= 1.6
    amps[5] *= 1.5
    mid = harm_loop(401, 110, amps, 0.14, 12, [h * 0.9 % TAU for h in range(16)])
    n = len(mid)
    rough = loopify(bp(noise(n + 3000, 22), 300, 2400), n)
    res["engine_mid_loop"] = ([tanh_clip(mix(norm(mid), (norm(rough), 0.10)), 2.6)], SR, True)
    # high layer ~300 Hz with whine, 1.0 s
    amps = [1.0 / (h ** 0.95) for h in range(1, 31)]
    amps[5] *= 3.2
    amps[8] *= 2.4
    amps[11] *= 2.0
    hi = harm_loop(147, 300, amps, 0.06, 13, [h * 1.3 % TAU for h in range(30)])
    n = len(hi)
    hiss = loopify(bp(noise(n + 3000, 23), 2500, 9000), n)
    res["engine_high_loop"] = ([tanh_clip(mix(norm(hi), (norm(hiss), 0.09)), 1.7)], SR, True)
    # turbo spool whoosh 1.4 s
    n = int(1.4 * SR)
    cut = [700 + 3600 * math.sin(math.pi * 0.5 * i / n) ** 1.5 for i in range(n)]
    w = hp(lp_var(noise(n, 31), cut), 350)
    env = [math.sin(math.pi * (i / n) ** 0.7) ** 1.4 for i in range(n)]
    whine = sweep(2200, 5200, 0.9, n)
    w = [a * e + 0.05 * s * e for a, e, s in zip(w, env, whine)]
    res["turbo_whoosh"] = ([fade(norm(w), 8, 40)], SR, False)
    # blow-off psshh-chu-chu 0.9 s
    n = int(0.9 * SR)
    cut = [7500 * math.exp(-i / (0.35 * SR)) + 1800 for i in range(n)]
    s = hp(lp_var(noise(n, 32), cut), 900)
    out = []
    for i in range(n):
        k = min(1.0, i / (0.12 * SR))
        am = (0.55 + 0.45 * math.sin(TAU * 26 * i / SR)) * k + (1 - k)
        out.append(s[i] * am * math.exp(-i / (0.3 * SR)))
    res["blowoff"] = ([fade(norm(out), 2, 30)], SR, False)
    # backfire pops
    for k in range(3):
        n = int((0.30 + 0.05 * k) * SR)
        r = random.Random(40 + k)
        burst = lp(noise(n, 50 + k), 2600 + 800 * k)
        e = expenv(n, 0.028 + 0.006 * k)
        thump = sweep(150 - 15 * k, 48, 0.05, n)
        te = expenv(n, 0.09)
        body = [b * ee + t * q * 0.9 for b, ee, t, q in zip(burst, e, thump, te)]
        crack = [0.0] * n
        for _ in range(3 + k):
            at = int(r.uniform(0.02, 0.22) * SR)
            amp = r.uniform(0.15, 0.5)
            for j in range(int(0.012 * SR)):
                if at + j < n:
                    crack[at + j] += amp * r.uniform(-1, 1) * math.exp(-j / (0.003 * SR))
        res["backfire_%d" % (k + 1)] = ([fade(norm(mix(body, crack)), 1, 20)], SR, False)
    return res


# ----------------------------------------------------------------------------- tyres, nitro, impacts
def gen_tyres():
    res = {}
    T = 1.5
    n = int(T * SR)
    cyc = [1800, 2715, 3600]  # 1200, 1810, 2400 Hz: integer cycles in T so the loop is exact
    mod = [9, 15, 21]
    amp = [1.0, 0.6, 0.35]
    out = [0.0] * n
    for k in range(3):
        for i in range(n):
            wob = 2.2 * math.sin(TAU * mod[k] * i / n)
            out[i] += amp[k] * math.sin(TAU * cyc[k] * i / n + wob)
    out = tanh_clip(norm(out), 3.0)
    scr = norm(loopify(bp(noise(n + 4000, 61), 1500, 5500), n))
    out = [(o * 0.9 + s * 0.35) * (0.75 + 0.25 * math.sin(TAU * 7 * i / n + 1.0))
           for i, (o, s) in enumerate(zip(out, scr))]
    res["tyre_squeal_loop"] = ([out], SR, True)
    n = int(2.5 * SR)
    h = norm(loopify(bp(noise(n + 6000, 62), 1800, 9500), n))
    res["tyre_hiss_wet_loop"] = ([[v * (0.8 + 0.2 * math.sin(TAU * 3 * i / n) * math.sin(TAU * 5 * i / n + 0.5))
                                   for i, v in enumerate(h)]], SR, True)
    return res


def gen_nitro():
    res = {}
    n = int(1.1 * SR)
    cut = [500 + 6000 * (1 - math.exp(-i / (0.12 * SR))) for i in range(n)]
    jet = hp(lp_var(noise(n, 71), cut), 250)
    env = [min(1.0, i / (0.015 * SR)) * math.exp(-max(0, i - 0.2 * SR) / (0.55 * SR)) for i in range(n)]
    thump = sweep(180, 40, 0.07, n)
    te = expenv(n, 0.22)
    snap = [math.sin(TAU * 1400 * i / SR) * math.exp(-i / (0.004 * SR)) for i in range(n)]
    ign = [j * e + 0.9 * t * q + 0.25 * s for j, e, t, q, s in zip(jet, env, thump, te, snap)]
    res["nitro_ignite"] = ([fade(norm(ign), 1, 60)], SR, False)
    # sustained roar loop 2.0 s: ~85 Hz buzz (170 cycles of 519) + turbulent noise
    amps = [1.0 / (h ** 0.7) for h in range(1, 24)]
    buzz = harm_loop(519, 170, amps, 0.10, 72, [h * 0.7 % TAU for h in range(23)])
    n = len(buzz)
    tur = norm(loopify(lp(noise(n + 5000, 73), 1800), n))
    tur2 = norm(loopify(hp(noise(n + 5000, 74), 1200), n))
    roar = [(b * 0.6 + t * 1.2 + h * 0.18) * (0.8 + 0.2 * math.sin(TAU * 11 * i / n + 0.3))
            for i, (b, t, h) in enumerate(zip(norm(buzz), tur, tur2))]
    res["nitro_loop"] = ([tanh_clip(norm(roar), 1.8)], SR, True)
    return res


def gen_impacts():
    res = {}
    for name, dur, f0, f1, ttau, ntau, nlp, ping, crunch, seed in (
        ("impact_light", 0.45, 150, 70, 0.06, 0.05, 4200, 0.25, 4, 81),
        ("impact_heavy", 1.1, 90, 32, 0.22, 0.20, 2600, 0.15, 14, 82),
    ):
        n = int(dur * SR)
        r = random.Random(seed)
        thump = [a * b for a, b in zip(sweep(f0, f1, ttau * 0.5, n), expenv(n, ttau))]
        nz = [a * b for a, b in zip(lp(noise(n, seed + 10), nlp), expenv(n, ntau))]
        metal = [0.0] * n
        for fr, aa in ((1830, 1.0), (2760, 0.7), (3410, 0.5), (4870, 0.3)):
            f = fr * r.uniform(0.97, 1.03)
            for i in range(n):
                metal[i] += aa * math.sin(TAU * f * i / SR) * math.exp(-i / (0.09 * SR))
        cr = [0.0] * n
        for _ in range(crunch):
            at = int(r.uniform(0.0, dur * 0.55) * SR)
            amp = r.uniform(0.2, 0.7)
            for j in range(int(r.uniform(0.006, 0.02) * SR)):
                if at + j < n:
                    cr[at + j] += amp * r.uniform(-1, 1) * math.exp(-j / (0.004 * SR))
        body = mix(thump, (nz, 0.9), (norm(metal), ping), (cr, 0.6))
        res[name] = ([fade(norm(tanh_clip(body, 1.6)), 1, 40)], SR, False)
    n = int(1.5 * SR)
    grind = norm(loopify(bp(noise(n + 5000, 91), 600, 3000), n))
    sc = [g * (0.55 + 0.25 * math.sin(TAU * 41 * i / n) + 0.2 * math.sin(TAU * 67 * i / n + 2.0))
          + 0.12 * math.sin(TAU * 2250 * i / n) for i, g in enumerate(grind)]
    res["scrape_loop"] = ([tanh_clip(norm(sc), 1.5)], SR, True)
    return res


def gen_rain():
    n = int(4.0 * SR)
    tot = n + 8000
    body = lp(hp(hp(noise(tot, 101), 700), 1500), 9500)
    low = lp(noise(tot, 102), 600)
    r = random.Random(103)
    drops = [0.0] * tot
    for _ in range(560):
        at = r.randrange(0, tot - 400)
        amp = r.uniform(0.2, 1.0)
        f = r.uniform(1500, 4500)
        for j in range(240):
            drops[at + j] += amp * math.sin(TAU * f * j / SR) * math.exp(-j / (0.0015 * SR + 10))
    x = mix(norm(body), (norm(low), 0.25), (norm(drops), 0.4))
    return {"rain_loop": ([norm(loopify(x, n))], SR, True)}


# ----------------------------------------------------------------------------- ui
def _tone(freqs, dur, tau, gains=None, attack_ms=3, harm=0.25):
    n = int(dur * SR)
    out = [0.0] * n
    for k, f in enumerate(freqs):
        g = gains[k] if gains else 1.0
        for i in range(n):
            t = i / SR
            out[i] += g * (math.sin(TAU * f * t) + harm * math.sin(TAU * 2 * f * t)) * math.exp(-i / (tau * SR))
    return fade(out, attack_ms, 10)


def gen_ui():
    res = {}
    n = int(0.07 * SR)
    tick = [math.sin(TAU * 1900 * i / SR) * math.exp(-i / (0.012 * SR)) for i in range(n)]
    tick = mix(tick, [a * math.exp(-i / (0.0015 * SR)) * 0.8 for i, a in enumerate(noise(n, 111))])
    res["ui_click"] = ([fade(norm(tick), 1, 10)], SR, False)
    a = _tone([659.3], 0.22, 0.09)
    b = _tone([987.8, 1318.5], 0.4, 0.14, [1.0, 0.45])
    res["ui_confirm"] = ([norm(mix(a, [0.0] * int(0.09 * SR) + b))], SR, False)
    a = _tone([784.0], 0.16, 0.07)
    b = _tone([523.3, 659.3], 0.3, 0.1, [1.0, 0.4])
    res["ui_back"] = ([norm(mix(a, [0.0] * int(0.075 * SR) + b))], SR, False)
    n = int(0.2 * SR)
    beep = [math.sin(TAU * 880 * i / SR) + 0.3 * math.sin(TAU * 2640 * i / SR) for i in range(n)]
    res["countdown_beep"] = ([fade(norm(beep), 4, 25)], SR, False)
    go = _tone([1320.0, 1980.0, 2640.0], 0.8, 0.28, [1.0, 0.5, 0.3], 4, 0.15)
    go = [v + 0.4 * math.sin(TAU * 660 * i / SR) * math.exp(-i / (0.3 * SR)) for i, v in enumerate(go)]
    res["countdown_go"] = ([fade(norm(go), 3, 40)], SR, False)
    # finish sting: rising Am(add9) arpeggio into a held chord
    n = int(2.6 * SR)
    st = [0.0] * n
    for m, t0 in ((57, 0.00), (60, 0.10), (64, 0.20), (69, 0.30), (71, 0.40), (76, 0.50)):
        s0 = int(t0 * SR)
        ln = n - s0
        o = lp(osc("saw", midi_hz(m), ln, SR, (-7.0, 7.0)), 2600 if m < 70 else 4500)
        e = adsr(ln, 0.006, 0.75 if m < 65 else 0.6, 0.30, 0.9, SR)
        for i in range(ln):
            st[s0 + i] += o[i] * e[i] * (0.9 if m < 70 else 0.6)
    st = [v + 0.5 * math.sin(TAU * 110 * i / SR) * math.exp(-i / (0.9 * SR)) for i, v in enumerate(st)]
    res["race_finish_sting"] = ([fade(norm(tanh_clip(st, 1.3)), 2, 200)], SR, False)
    cash = mix(_tone([1568.0], 0.16, 0.04, None, 1, 0.1), [0.0] * int(0.05 * SR) + _tone([2093.0], 0.3, 0.09, None, 1, 0.1))
    res["cash_tick"] = ([fade(norm(cash), 1, 15)], SR, False)
    return res


# ----------------------------------------------------------------------------- music
def render_track(cfg):
    sr = cfg["sr"]
    sps = int(round(60.0 / cfg["bpm"] / 4.0 * sr))  # samples per 16th
    bars = cfg["bars"]
    total = bars * 16 * sps
    bus = {k: ([0.0] * total, [0.0] * total) for k in ("duck", "arp", "lead", "drums")}
    cache = {}

    def put(dst, seg, start, gain, pan=0.0):
        gl = gain * (1.0 - max(0.0, pan))
        gr = gain * (1.0 + min(0.0, pan))
        dl, dr = dst
        for i, v in enumerate(seg):
            j = (start + i) % total  # wraps: tails fold onto the head for a seamless loop
            dl[j] += v * gl
            dr[j] += v * gr

    def cached(key, fn):
        if key not in cache:
            cache[key] = fn()
        return cache[key]

    def kick():
        n = int(0.38 * sr)
        ph = 0.0
        out = []
        for i in range(n):
            ph += TAU * (46 + 120 * math.exp(-i / (0.03 * sr))) / sr
            out.append(math.sin(ph) * math.exp(-i / (0.13 * sr)) + 0.35 * math.sin(TAU * 3100 * i / sr) * math.exp(-i / (0.0012 * sr)))
        return fade(out, 0.5, 10, sr)

    def snare():
        n = int(0.30 * sr)
        nz = bp(noise(n, 201), 220, 7000, sr)
        tone = sweep(230, 170, 0.03, n, sr)
        return fade([nz[i] * math.exp(-i / (0.07 * sr)) * 0.9 + tone[i] * math.exp(-i / (0.045 * sr)) * 0.7 for i in range(n)], 0.5, 15, sr)

    def hat(openh, seed):
        n = int((0.30 if openh else 0.07) * sr)
        nz = hp(hp(noise(n, 210 + seed), 5500, sr), 5500, sr)
        tau = 0.09 if openh else 0.018
        return fade([v * math.exp(-i / (tau * sr)) for i, v in enumerate(nz)], 0.3, 6, sr)

    def clap():
        n = int(0.25 * sr)
        nz = bp(noise(n, 230), 900, 5000, sr)
        out = []
        for i in range(n):
            t = i / sr
            e = sum(math.exp(-(t - d) / 0.012) for d in (0.0, 0.011, 0.022) if t >= d) * 0.5 + math.exp(-t / 0.08)
            out.append(nz[i] * e * 0.6)
        return out

    def synth_note(kind, midi, n, detune, cutoff, fenv, a, d, s, r, ph0=0.0):
        o = osc(kind, midi_hz(midi), n, sr, detune, ph0)
        e = adsr(n, a, d, s, r, sr)
        y = 0.0
        out = []
        for i in range(n):
            fc = cutoff + fenv * math.exp(-i / (0.18 * sr))
            y += (1.0 - math.exp(-TAU * fc / sr)) * (o[i] - y)
            out.append(y * e[i])
        return out

    def sub_note(m, ln):
        return [a * b for a, b in zip(osc("sine", midi_hz(m), ln, sr), adsr(ln, 0.004, 0.3, 0.8, 0.03, sr))]

    roots, chords, sec = cfg["roots"], cfg["chords"], cfg["sections"]
    kick_s = cached("kick", kick)
    snare_s = cached("snare", snare)
    clap_s = cached("clap", clap)
    hats = [cached(("hat", 0, k), lambda k=k: hat(False, k)) for k in range(3)]
    ohat = cached(("hat", 1), lambda: hat(True, 0))

    for b in range(bars):
        layers = sec(b)
        bs = b * 16 * sps
        ci = b % len(chords)
        ch = chords[ci]
        if "pad" in layers:
            ln = 16 * sps + int(0.6 * sr)
            for m in ch:
                for side, dets in ((-1, (-9.0, -3.0)), (1, (3.0, 9.0))):
                    seg = cached(("pad", m, side, ln), lambda m=m, dets=dets, side=side: synth_note(
                        "saw", m, ln, dets, cfg["pad_lp"], 0.0, 0.5, 0.5, 0.85, 0.55, 0.13 * side))
                    put(bus["duck"], seg, bs, cfg["pad_gain"], 0.35 * side)
        if "bass" in layers:
            for s, steps in enumerate(cfg["bass_pat"]):
                if steps:
                    ln = int(steps * sps)
                    m = roots[ci] + (12 if (s % 8 == 7 and cfg.get("bass_oct")) else 0)
                    seg = cached(("bass", m, ln), lambda m=m, ln=ln: synth_note(
                        "saw", m, ln, (-6.0, 6.0), 190, cfg["bass_env"], 0.004, 0.2, 0.7, 0.03))
                    sub = cached(("sub", m, ln), lambda m=m, ln=ln: sub_note(m, ln))
                    put(bus["duck"], [x + y * 0.8 for x, y in zip(seg, sub)], bs + s * sps, cfg["bass_gain"])
        if "arp" in layers:
            tones = [ch[0] + 12, ch[1] + 12, ch[2] + 12, ch[1] + 24, ch[2] + 24, ch[0] + 24]
            for s, idx in enumerate(cfg["arp_pat"]):
                if idx is None:
                    continue
                m = tones[idx % 6]
                ln = int(cfg["arp_len"] * sps)
                seg = cached(("arp", m, ln), lambda m=m, ln=ln: synth_note(
                    cfg["arp_wave"], m, ln, (-5.0, 5.0), 700, cfg["arp_env"], 0.002, 0.09, 0.15, 0.02))
                put(bus["arp"], seg, bs + s * sps, cfg["arp_gain"], 0.4 if s % 2 else -0.4)
        if "lead" in layers and b % 4 == 0:
            for (bb, s, m, ln16) in cfg["lead"]:
                ln = ln16 * sps + int(0.12 * sr)
                seg = cached(("lead", m, ln), lambda m=m, ln=ln: synth_note(
                    "saw", m, ln, (-10.0, 0.0, 10.0), 1900, 2500, 0.01, 0.4, 0.55, 0.09))
                put(bus["lead"], seg, bs + (bb * 16 + s) * sps, cfg["lead_gain"], 0.05)
        d = bus["drums"]
        if "kick" in layers:
            for beat in cfg["kick_steps"]:
                put(d, kick_s, bs + beat * sps, cfg["kick_gain"])
        if "snare" in layers:
            for beat in (4, 12):
                put(d, snare_s, bs + beat * sps, cfg["snare_gain"])
                if cfg.get("clap"):
                    put(d, clap_s, bs + beat * sps, cfg["snare_gain"] * 0.45, 0.1)
        if "hat" in layers:
            for s in range(16):
                if s % 4 == 2:
                    put(d, ohat, bs + s * sps, cfg["hat_gain"] * 0.8, 0.2)
                elif s % 4 == 0:
                    put(d, hats[(s + b) % 3], bs + s * sps, cfg["hat_gain"], -0.15)
                else:
                    put(d, hats[(s + b) % 3], bs + s * sps, cfg["hat_gain"] * 0.5, -0.15)
        if "fill" in layers:
            for k in range(8):
                put(d, snare_s, bs + (8 + k) * sps, cfg["snare_gain"] * (0.3 + 0.1 * k))

    # sidechain duck on pad/bass bus, keyed to the kicks
    duck = [1.0] * total
    dn = int(0.26 * sr)
    shape = [min(1.0, 1.0 - cfg["duck_depth"] * math.exp(-i / (0.07 * sr))) for i in range(dn)]
    for b in range(bars):
        if "kick" in sec(b):
            for beat in cfg["kick_steps"]:
                st = b * 16 * sps + beat * sps
                for i in range(dn):
                    j = (st + i) % total
                    if shape[i] < duck[j]:
                        duck[j] = shape[i]

    def echo(buf, delay, fb, taps):
        l, r = buf
        ol, orr = list(l), list(r)
        for k in range(1, taps + 1):
            g = fb ** k
            s = (delay * k) % total
            sl = l[-s:] + l[:-s]
            sr_ = r[-s:] + r[:-s]
            a, c = (sr_, sl) if k % 2 else (sl, sr_)
            for i in range(total):
                ol[i] += a[i] * g
                orr[i] += c[i] * g
        return ol, orr

    el, er = echo(bus["arp"], int(sps * cfg["echo_steps"]), 0.5, 4)
    ll, lr = echo(bus["lead"], int(sps * cfg["echo_steps"]), 0.45, 4)
    dl, dr = bus["duck"]
    drl, drr = bus["drums"]
    ml = [dl[i] * duck[i] + el[i] * (0.55 + 0.45 * duck[i]) + ll[i] + drl[i] for i in range(total)]
    mr = [dr[i] * duck[i] + er[i] * (0.55 + 0.45 * duck[i]) + lr[i] + drr[i] for i in range(total)]
    return [tanh_clip(ml, cfg["sat"]), tanh_clip(mr, cfg["sat"])]


def gen_music():
    res = {}

    def race_sections(b):  # 32 bars, 128 bpm = 60 s
        s = {"pad", "hat"}
        if b < 4:
            s.add("arp")
            if b >= 2:
                s.add("bass")
        elif b < 8:
            s |= {"kick", "bass"}
            if b == 7:
                s.add("fill")
        elif b < 16:
            s |= {"kick", "bass", "arp", "snare"}
            if b == 15:
                s.add("fill")
        elif b < 20:
            s |= {"arp", "lead"}
            if b >= 18:
                s.add("bass")
            if b == 19:
                s.add("fill")
        elif b < 28:
            s |= {"kick", "bass", "arp", "snare", "lead"}
            if b == 23:
                s.add("fill")
        else:
            s |= {"kick", "bass", "arp", "snare"}
            if b == 31:
                s.add("fill")
        return s

    race = {
        "sr": 32000, "bpm": 128, "bars": 32,
        "roots": [33, 29, 36, 31], "chords": [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]],
        "sections": race_sections,
        "bass_pat": [3, 0, 0, 2, 0, 0, 3, 0, 3, 0, 0, 2, 0, 0, 3, 2], "bass_env": 1500, "bass_gain": 0.62, "bass_oct": True,
        "pad_lp": 1500, "pad_gain": 0.11,
        "arp_pat": [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 4, 3, 2, 1, 2, 3], "arp_len": 1.6,
        "arp_wave": "square", "arp_env": 2600, "arp_gain": 0.20, "echo_steps": 3,
        "lead": [(0, 0, 81, 6), (0, 6, 79, 2), (0, 8, 76, 8), (1, 0, 77, 6), (1, 6, 76, 2), (1, 8, 72, 8),
                 (2, 0, 76, 6), (2, 6, 79, 2), (2, 8, 84, 8), (3, 0, 83, 4), (3, 4, 79, 4), (3, 8, 74, 8)],
        "lead_gain": 0.17,
        "kick_steps": [0, 4, 8, 12], "kick_gain": 0.95, "snare_gain": 0.5, "hat_gain": 0.22, "clap": True,
        "duck_depth": 0.62, "sat": 1.15,
    }
    res["music_race_loop"] = (render_track(race), race["sr"], True)

    def menu_sections(b):  # 16 bars, 90 bpm = 42.7 s
        s = {"pad", "bass"}
        if b >= 2:
            s.add("arp")
        if b >= 4:
            s |= {"kick", "hat"}
        if 8 <= b < 12:
            s.add("lead")
        if b >= 12:
            s.add("snare")
        return s

    menu = {
        "sr": 24000, "bpm": 90, "bars": 16,
        "roots": [38, 34, 29, 36], "chords": [[50, 53, 57], [46, 50, 53], [48, 53, 57], [48, 52, 55]],
        "sections": menu_sections,
        "bass_pat": [8, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 2, 0, 0, 0], "bass_env": 400, "bass_gain": 0.55, "bass_oct": False,
        "pad_lp": 1100, "pad_gain": 0.16,
        "arp_pat": [0, None, 1, None, 2, None, 1, None, 3, None, 2, None, 1, None, 0, None], "arp_len": 2.5,
        "arp_wave": "tri", "arp_env": 1200, "arp_gain": 0.26, "echo_steps": 6,
        "lead": [(0, 0, 74, 8), (0, 8, 72, 8), (1, 0, 70, 8), (1, 8, 69, 8), (2, 0, 72, 8), (2, 8, 69, 8), (3, 0, 67, 8), (3, 8, 64, 8)],
        "lead_gain": 0.13,
        "kick_steps": [0, 10], "kick_gain": 0.6, "snare_gain": 0.28, "hat_gain": 0.12,
        "duck_depth": 0.35, "sat": 1.0,
    }
    res["music_menu_loop"] = (render_track(menu), menu["sr"], True)
    return res


# ----------------------------------------------------------------------------- main
GROUPS = [("engine", gen_engine), ("tyres", gen_tyres), ("nitro", gen_nitro), ("impacts", gen_impacts),
          ("rain", gen_rain), ("ui", gen_ui), ("music", gen_music)]
UI_NAMES = ("countdown_beep", "countdown_go", "race_finish_sting", "cash_tick")


def main(argv):
    only = None
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1]
    manifest_path = os.path.join(OUT, "audio_manifest.json")
    files = {}
    if os.path.exists(manifest_path):
        files = json.load(open(manifest_path)).get("files", {})
    for gname, fn in GROUPS:
        if (gname == "music" and "--no-music" in argv) or (only and only not in gname and
                                                         not any(only in k for k in _names(gname))):
            continue
        for name, (chans, sr, loop) in fn().items():
            if only and only not in name and only not in gname:
                continue
            sub = "music" if name.startswith("music_") else ("ui" if name.startswith("ui_") or name in UI_NAMES else "sfx")
            info = write_wav(os.path.join(OUT, sub, name + ".wav"), chans, sr, loop, 0.8 if sub == "music" else 0.89)
            info["path"] = "res://assets/audio/%s/%s.wav" % (sub, name)
            files[name] = info
            print("%-22s %6.2fs %5d Hz %dch %s %5.0f KB" % (name, info["seconds"], sr, info["channels"],
                                                          "LOOP" if loop else "    ", info["bytes"] / 1024))
    meta = {"generator": "tools/audio_synth.py", "license": "original, procedurally synthesised, project-owned"}
    json.dump({"_meta": meta, "files": files}, open(manifest_path, "w"), indent=1, sort_keys=True)
    print("total %.1f MB in %d files" % (sum(v["bytes"] for v in files.values()) / 1048576, len(files)))


def _names(group):
    return {"engine": ["engine", "turbo", "blowoff", "backfire"], "tyres": ["tyre"], "nitro": ["nitro"],
            "impacts": ["impact", "scrape"], "rain": ["rain"], "ui": ["ui_", "countdown", "finish", "cash"],
            "music": ["music"]}[group]


if __name__ == "__main__":
    main(sys.argv[1:])
