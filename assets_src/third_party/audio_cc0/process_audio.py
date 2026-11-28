import array, os, subprocess, sys, tempfile, wave

RAW = sys.argv[1]
OUT = sys.argv[2]
PEAK = 10 ** (-1 / 20) * 32767  # -1 dBFS in 16-bit

JOBS = [
    # (raw path relative to RAW, output name, is_loop)
    ("racing-car-engine-sound-loops/loop_0.wav", "engine_loop_a", True),
    ("racing-car-engine-sound-loops/loop_2_0.wav", "engine_loop_b", True),
    ("engine-sounds2/engine_sound.mp3", "engine_loop_c", True),
    ("car-sound-effects-pack-low-quality/extracted/Car_Engine_Loop.ogg", "engine_loop_d", True),
    ("car-engine-start-01/generic_car_startengine.wav", "engine_start", False),
    ("city-loop-0/city-loop_0.mp3", "ambience_city_loop", True),
    ("rain-in-space/rain_in_space_loop.wav", "ambience_rain_loop", True),
    ("sci-fi-sounds/extracted/Audio/impactMetal_000.ogg", "impact_metal", False),
    ("sci-fi-sounds/extracted/Audio/thrusterFire_000.ogg", "whoosh_thruster", False),
]


def decode(path):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", "44100", "-"],
                         capture_output=True, check=True).stdout
    a = array.array("h")
    a.frombytes(out)
    return a


def loop_cut(a):
    # rising zero crossings: sample i-1 < 0 <= sample i
    rising = [i for i in range(1, len(a)) if a[i - 1] < 0 <= a[i]]
    if len(rising) < 2:
        return a
    start, end = rising[0], rising[-1]
    if end - start < 44100 * 0.5:
        return a
    return a[start:end]


def normalise(a):
    peak = max(max(a), -min(a)) or 1
    k = PEAK / peak
    return array.array("h", [max(-32767, min(32767, int(round(v * k)))) for v in a]), peak


def write(name, a):
    tmp = os.path.join(tempfile.gettempdir(), name + ".wav")
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes(a.tobytes())
    dst = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
    os.remove(tmp)
    return dst


for rel, name, loop in JOBS:
    a = decode(os.path.join(RAW, rel))
    before = len(a) / 44100.0
    if loop:
        a = loop_cut(a)
    a, peak = normalise(a)
    dst = write(name, a)
    print("%s: %.2fs -> %.2fs, src peak %d, %s (%d bytes)" % (name, before, len(a) / 44100.0, peak, dst, os.path.getsize(dst)))
