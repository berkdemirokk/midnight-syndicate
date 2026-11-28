#!/usr/bin/env python3
"""Offline mix of the layered player engine from the race trace written by test_audio_engine.gd.

Reads the CSV (--audio-log of the headless run), and for every frame applies the logged per-voice gain and pitch to
the matching engine loop (game/assets/audio/engine/v8_b<band>_<on|off>.wav, the Sable's engine family), playing each
loop with its own pitch (resampling) and restarting a voice when its band changes, as the game does. Output: a mono
WAV (22.05 kHz, 16-bit) and a spectrogram PNG. Nobody has listened to the result.

Run: py -3.10 tools/audio_synth/render_race_mix.py <log.csv> <out_dir>
"""
import csv
import os
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
LOOP_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "game", "assets", "audio", "engine"))
ENGINE = "v8"  # the Noctra Sable R maps to v8 (top speed 286 km/h), see EngineLayers.engine_for_spec
SR_IN = 44100
SR_OUT = 22050
FRAME_DT = 1.0 / 60.0


def load_loop(band, load):
    path = os.path.join(LOOP_DIR, f"{ENGINE}_b{band + 1}_{load}.wav")
    with wave.open(path, "rb") as w:
        assert w.getsampwidth() == 2 and w.getnchannels() == 1 and w.getframerate() == SR_IN
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    return x


def render(rows):
    loops = {}
    for b in range(6):
        for load, name in ((0, "off"), (1, "on")):
            loops[(b, load)] = load_loop(b, name)
    n_in = len(rows)
    spf = int(round(SR_IN * FRAME_DT))
    total = n_in * spf
    out = np.zeros(total, dtype=np.float64)
    pos = [0.0] * 4  # read position in each loop (samples)
    prev_band = [-1, -1]
    prev_gain = [0.0] * 4
    prev_pitch = [1.0] * 4
    for i, r in enumerate(rows):
        gains = [float(r[f"v{v}_gain"]) for v in range(4)]
        pitches = [float(r["v0_pitch"]), float(r["v0_pitch"]), float(r["v2_pitch"]), float(r["v2_pitch"])]
        bands = [int(r["slot0_band"]), int(r["slot1_band"])]
        base = i * spf
        t = np.arange(spf) / spf
        for slot in range(2):
            if bands[slot] != prev_band[slot]:
                pos[slot * 2] = 0.0
                pos[slot * 2 + 1] = 0.0
                prev_band[slot] = bands[slot]
        for v in range(4):
            slot = v // 2
            load = v % 2
            b = bands[slot]
            if b < 0:
                prev_gain[v] = gains[v]
                continue
            x = loops[(b, load)]
            n = len(x)
            # per-sample pitch and gain: linear ramps across the frame (the game ramps per frame too)
            ps = np.full(spf, pitches[v], dtype=np.float64)
            pidx = np.concatenate(([pos[v]], pos[v] + np.cumsum(ps)[:-1]))
            pos[v] = pos[v] + float(np.sum(ps))
            pos[v] = pos[v] % n
            idx0 = np.floor(pidx).astype(np.int64) % n
            frac = pidx - np.floor(pidx)
            idx1 = (idx0 + 1) % n
            samp = x[idx0] * (1.0 - frac) + x[idx1] * frac
            g = prev_gain[v] + (gains[v] - prev_gain[v]) * t
            out[base:base + spf] += samp * g
            prev_gain[v] = gains[v]
    return out


def decimate2(x):
    n = len(x) // 2 * 2
    return 0.5 * (x[0:n:2] + x[1:n:2])


def write_wav(path, x):
    pcm = np.clip(x * 32767.0, -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR_OUT)
        w.writeframes(pcm.tobytes())


def spectrogram_png(x, path, title):
    n_fft, hop = 2048, 512
    win = np.hanning(n_fft)
    frames = []
    for s in range(0, len(x) - n_fft, hop):
        seg = x[s:s + n_fft] * win
        frames.append(np.abs(np.fft.rfft(seg)))
    S = np.array(frames).T  # freq x time
    db = 20 * np.log10(S + 1e-9)
    db = db - db.max()
    db = np.clip(db, -70, 0)  # 70 dB range, linear ramps: the harmonics stay distinct instead of going white
    fmax_bin = int(1500 / (SR_OUT / n_fft))
    img = db[:fmax_bin][::-1]  # low at the bottom
    t = (img + 70.0) / 70.0
    r = t
    g = t * t
    b = 1.0 - t
    rgb = (np.stack([r, g, b], axis=-1) * 255).astype(np.uint8)
    im = Image.fromarray(rgb, "RGB").resize((1200, 420), Image.NEAREST)
    canvas = Image.new("RGB", (1260, 480), (20, 20, 24))
    canvas.paste(im, (50, 40))
    d = ImageDraw.Draw(canvas)
    d.text((50, 12), title, fill=(230, 230, 230))
    for hz in (0, 250, 500, 750, 1000, 1250, 1500):
        y = 40 + 420 - int(420 * hz / 1500)
        d.text((4, y - 6), f"{hz}", fill=(200, 200, 200))
    dur = len(x) / SR_OUT
    for sec in range(0, int(dur) + 1, 5):
        xx = 50 + int(1200 * sec / dur)
        d.text((xx - 6, 466), f"{sec}s", fill=(200, 200, 200))
    canvas.save(path, optimize=True)


def main(argv):
    log, out_dir = argv[1], argv[2]
    os.makedirs(out_dir, exist_ok=True)
    with open(log, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    mix = render(rows)
    mix = decimate2(mix)
    peak = float(np.max(np.abs(mix)))
    rms = float(np.sqrt(np.mean(mix * mix)))
    assert peak < 0.98, f"mix clips: peak {peak}"
    wav_path = os.path.join(out_dir, "race20_player_mix.wav")
    png_path = os.path.join(out_dir, "race20_player_spectrogram.png")
    write_wav(wav_path, mix)
    spectrogram_png(mix, png_path, "Player engine mix, 20 s race trace (Sable, v8 loops), 0-1500 Hz")
    print(f"frames {len(rows)} duration_s {len(mix) / SR_OUT:.2f} peak {peak:.4f} rms {rms:.4f}")
    print(wav_path)
    print(png_path)


if __name__ == "__main__":
    main(sys.argv)
