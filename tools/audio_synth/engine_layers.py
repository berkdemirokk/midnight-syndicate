#!/usr/bin/env python3
"""Layered engine loops: 4 engine types x 4 RPM bands x (on-load, off-load) = 32 seamless 1.0 s loops.

Synthesis is done in the frequency domain on an exact 1 s buffer (bin spacing = 1 Hz), so every firing
harmonic and every noise bin is periodic: each loop is seamless by construction.
Firing fundamental f0 = rpm / 60 * cylinders / 2 (4-stroke). Band reference rpms are multiples of 300,
so f0 is an exact integer for 4, 6, 8 and 12 cylinders. Intake noise is a lorentzian band; exhaust
resonance is a sum of peaks applied to every spectral line. Off-load: softer harmonics, more crackle.

Run: py -3.10 tools/audio_synth/engine_layers.py [--evidence <dir>]
Writes game/assets/audio/engine/<eng>_<band>_<load>.wav and prints a manifest JSON to stdout.
Nobody has listened to these: the checks are spectral and numerical only.
"""
import hashlib
import json
import math
import os
import struct
import sys

import numpy as np

SR = 44100
N = SR  # exactly one second
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "game", "assets", "audio", "engine"))

REF_RPM = (1500, 2700, 4500, 7200)  # band centres; neighbour ratio <= 1.8
BANDS = ("b1", "b2", "b3", "b4")
BAND_LEVEL = (0.55, 0.8, 1.0, 1.0)  # harmonic level per band (low rpm is softer)
BAND_NOISE = (0.5, 0.7, 0.9, 1.0)   # intake/turbo noise grows with rpm
TARGET_RMS = 0.16
LOADS = ("on", "off")

ENGINES = {
    # cyl; harmonic slope (on, off); intake centre and width Hz; noise level; wail boost; exhaust peaks (Hz, width, gain)
    "i4": dict(cyl=4, slope=(1.00, 1.35), intake=(850, 500), noise=0.10, wail=0.0,
               res=((180, 70, 1.0), (420, 110, 0.6))),
    "v6": dict(cyl=6, slope=(0.90, 1.25), intake=(1200, 700), noise=0.12, wail=0.0,
               res=((150, 60, 1.0), (520, 140, 0.5))),
    "v8": dict(cyl=8, slope=(0.75, 1.10), intake=(600, 400), noise=0.08, wail=0.0,
               res=((110, 50, 1.2), (330, 90, 0.7))),
    "hy": dict(cyl=12, slope=(0.55, 0.95), intake=(2000, 1000), noise=0.16, wail=1.0,
               res=((260, 80, 0.8), (900, 260, 0.9))),
}


def band_f0(eng, band):
    return int(round(REF_RPM[band] / 60.0 * ENGINES[eng]["cyl"] / 2.0))


def build_spectrum(eng, band, load, rng):
    e = ENGINES[eng]
    li = 0 if load == "on" else 1
    f0 = band_f0(eng, band)
    freqs = np.arange(N // 2 + 1, dtype=np.float64)  # bin k == k Hz
    spec = np.zeros(N // 2 + 1, dtype=np.complex128)
    k = 1
    while k * f0 <= 6000:
        f = k * f0
        a = (k ** -e["slope"][li]) * BAND_LEVEL[band]
        if load == "off":
            a *= 0.6 * (0.7 + 0.6 * rng.random())  # overrun: softer, uneven, crackly firing
        if e["wail"] > 0.0:
            a *= 1.0 + e["wail"] * 0.8 * math.exp(-((f - 3000.0) / 1500.0) ** 2)
        phase = rng.random() * 2.0 * math.pi
        spec[f] += (N / 2.0) * a * complex(math.cos(phase), math.sin(phase))
        k += 1
    # intake / turbo noise: lorentzian band, complex Gaussian per bin
    centre, width = e["intake"]
    shape = 0.25 + 1.0 / (1.0 + ((freqs - centre) / width) ** 2)
    noise_amp = 0.1 * e["noise"] * BAND_NOISE[band] * (1.0 if load == "on" else 1.8) * shape  # per-bin, ~-20 dB under harmonics
    noise_amp[:20] = 0.0
    noise_amp[7000:] = 0.0
    gauss = (rng.standard_normal(len(freqs)) + 1j * rng.standard_normal(len(freqs))) / math.sqrt(2.0)
    spec += (N / 2.0) * noise_amp * gauss
    # exhaust resonance on every line (on-load full, off-load softer)
    gain = np.ones_like(freqs)
    scale = 1.0 if load == "on" else 0.6
    for fc, w, g in e["res"]:
        gain += scale * g / (1.0 + ((freqs - fc) / w) ** 2)
    spec *= gain
    spec[0] = 0.0
    return spec


def synth(eng, band, load, rng):
    return np.fft.irfft(build_spectrum(eng, band, load, rng), n=N)


def write_wav(path, x):
    pcm = np.clip(x * 32767.0, -32767, 32767).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    body = b"WAVE" + b"fmt " + struct.pack("<I", 16) + fmt
    body += b"data" + struct.pack("<I", len(pcm)) + pcm
    smpl = struct.pack("<IIIIIIIII", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
    smpl += struct.pack("<IIIIII", 0, 0, 0, N - 1, 0, 0)
    body += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def evidence(out_dir, loops):
    from PIL import Image, ImageDraw
    os.makedirs(out_dir, exist_ok=True)
    win, hop = 2048, 512
    win_fn = np.hanning(win)
    tw, th = 320, 160
    for eng in ENGINES:
        sheet = Image.new("RGB", (tw * 2 + 10, (th + 22) * 4 + 10), (20, 20, 24))
        d = ImageDraw.Draw(sheet)
        for band in range(4):
            for j, load in enumerate(LOADS):
                x = loops[(eng, band, load)]
                frames = [np.abs(np.fft.rfft(x[i:i + win] * win_fn)) for i in range(0, N - win, hop)]
                s = np.array(frames[:60]).T[:360]  # 0..~7.7 kHz, first ~0.7 s
                db = 20 * np.log10(s + 1e-6)
                img = np.clip((db + 40) / 80.0, 0, 1)
                arr = (img[::-1] * 255).astype(np.uint8)
                im = Image.fromarray(arr).resize((tw, th)).convert("RGB")
                x0 = j * (tw + 10)
                y0 = band * (th + 22) + 20
                sheet.paste(im, (x0, y0))
                d.text((x0 + 4, y0 - 16), f"{eng} {BANDS[band]} {load}-load  f0={band_f0(eng, band)} Hz", fill=(230, 230, 230))
        sheet.save(os.path.join(out_dir, f"spectrogram_{eng}.jpg"), quality=85)


def main(argv):
    ev = argv[argv.index("--evidence") + 1] if "--evidence" in argv else None
    loops = {}
    manifest = {}
    for ei, eng in enumerate(ENGINES):
        for band in range(4):
            for li, load in enumerate(LOADS):
                rng = np.random.default_rng(20261128 + ei * 100 + band * 10 + li)
                loops[(eng, band, load)] = synth(eng, band, load, rng)
    # one global gain keeps relative levels between bands and loads (loudness balance is set in the game)
    rms_max = max(float(np.sqrt(np.mean(v * v))) for v in loops.values())
    g = TARGET_RMS / rms_max
    for (eng, band, load), x in loops.items():
        y = x * g
        peak = float(np.max(np.abs(y)))
        assert peak < 0.98, f"clip risk {eng} {band} {load} peak {peak:.3f}"
        name = f"{eng}_{BANDS[band]}_{load}"
        path = os.path.join(OUT, name + ".wav")
        write_wav(path, y)
        raw = open(path, "rb").read()
        manifest[name] = {
            "path": f"res://assets/audio/engine/{name}.wav",
            "engine": eng, "band": BANDS[band], "load": load,
            "ref_rpm": REF_RPM[band], "f0_hz": band_f0(eng, band),
            "rms": round(float(np.sqrt(np.mean(y * y))), 4), "peak": round(peak, 4),
            "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(),
        }
    if ev:
        evidence(ev, {k: v * g for k, v in loops.items()})
    json.dump(manifest, sys.stdout, indent=1)
    print()


if __name__ == "__main__":
    main(sys.argv[1:])
