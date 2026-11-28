class_name EngineLayers
extends RefCounted
## Engine loop bands (assets/audio/engine/<eng>_<band>_<load>.wav, made by tools/audio_synth/engine_layers.py).
## Six bands centred on REF_RPM. A loop is in tune only inside its zone [REF/MAX, REF*MAX], so a band gets
## weight only inside its zone: it rises across its overlap with the band below and falls across its overlap
## with the band above. Overlaps exist because the neighbour ratio (1.4) is below MAX^2 (1.5625), and no band
## two steps away overlaps, so at most two adjacent bands are ever audible.
## Inside a zone pitch = rpm / REF exactly (no clamp). Shortcut: outside the outer zones (idle below about
## 1200 rpm, above about 9000 rpm) pitch clamps at the edge; upgrade the outer bands if idle or redline need more.
## Equal power: squared weights sum to 1 at every rpm and throttle (cos/sin fades, throttle split by cos/sin).
## Weights index: band * 2 + load, load 0 = off-load, 1 = on-load.

const BANDS: int = 6
const REF_RPM: Array[float] = [1500.0, 2100.0, 2880.0, 4020.0, 5520.0, 7200.0]  ## multiples of 60: f0 = rpm*cyl/120 is an exact integer Hz for 4/6/8/12 cyl, so the 1 s loop is exactly REF
const BAND_PITCH_MAX: float = 1.25  ## loop pitch limit inside a zone (+3.9 semitones / -3.9 semitones)


## Lowest rpm where band is in tune (band 0 has no lower limit).
static func zone_lo(band: int) -> float:
	return 0.0 if band == 0 else REF_RPM[band] / BAND_PITCH_MAX


## Highest rpm where band is in tune (top band has no upper limit).
static func zone_hi(band: int) -> float:
	return INF if band == BANDS - 1 else REF_RPM[band] * BAND_PITCH_MAX


## Equal-power fade over log-rpm between a and b: rising goes 0 to 1, falling goes 1 to 0.
static func _fade(lx: float, a: float, b: float, rising: bool) -> float:
	var t: float = clampf((lx - a) / (b - a), 0.0, 1.0)
	return sin(t * PI * 0.5) if rising else cos(t * PI * 0.5)


## Equal-power band and load weights for an absolute rpm and throttle 0..1. Sum of squares = 1.
static func band_weights(rpm: float, throttle: float) -> PackedFloat32Array:
	var lx: float = log(maxf(rpm, 1.0))
	var wb := PackedFloat32Array()
	wb.resize(BANDS)
	for b: int in BANDS:
		var w: float = 1.0
		if b > 0:  # rise over the overlap with the band below
			w *= _fade(lx, log(zone_lo(b)), log(zone_hi(b - 1)), true)
		if b < BANDS - 1:  # fall over the overlap with the band above
			w *= _fade(lx, log(zone_lo(b + 1)), log(zone_hi(b)), false)
		wb[b] = w
	var th: float = clampf(throttle, 0.0, 1.0)
	var won: float = sin(th * PI * 0.5)
	var woff: float = cos(th * PI * 0.5)
	var out := PackedFloat32Array()
	out.resize(BANDS * 2)
	for b: int in BANDS:
		out[b * 2] = wb[b] * woff
		out[b * 2 + 1] = wb[b] * won
	return out


## Playback pitch multiplier for a loop of this band at this rpm (exact inside the band's zone).
static func band_pitch(rpm: float, band: int) -> float:
	return clampf(rpm / REF_RPM[band], 1.0 / BAND_PITCH_MAX, BAND_PITCH_MAX)

## Engine types, in loop-file order (eng_<name>_b<band>_<on|off> in AudioLib.FILES).
const ENGINE_NAMES: Array[String] = ["i4", "v6", "v8", "hy"]
## Loop RMS as measured by tools/audio_synth (index: engine * 12 + band * 2 + load, load 0 = off, 1 = on).
## The synth uses one global gain, so loudness differs by about 15 dB between loops; CarAudio scales each loop to TARGET_RMS.
const LOOP_RMS: Array[float] = [
	0.0278, 0.0526, 0.0408, 0.0661, 0.0418, 0.0811, 0.0491, 0.0984, 0.0604, 0.1232, 0.0700, 0.1169,
	0.0373, 0.0604, 0.0480, 0.0742, 0.0588, 0.0960, 0.0556, 0.0939, 0.0633, 0.0924, 0.0730, 0.0980,
	0.0342, 0.0785, 0.0452, 0.0857, 0.0458, 0.0822, 0.0569, 0.0904, 0.0553, 0.1014, 0.0623, 0.0937,
	0.0515, 0.0903, 0.0598, 0.1087, 0.0789, 0.1274, 0.0866, 0.1321, 0.0974, 0.1410, 0.1263, 0.1600,
]
const TARGET_RMS: float = 0.10  ## RMS of one full-weight loop after normalising (about -20 dBFS); a level choice, not a listened one

static var _loops_ok: int = -1  ## cache: 1 when all 48 loops load, 0 when any is missing, -1 not checked yet


## AudioLib id of one engine loop. load 0 = off-load, 1 = on-load.
static func loop_id(eng: int, band: int, load: int) -> StringName:
	return StringName("eng_%s_b%d_%s" % [ENGINE_NAMES[eng], band + 1, "on" if load == 1 else "off"])


## Gain that brings one loop to TARGET_RMS.
static func loop_norm(eng: int, band: int, load: int) -> float:
	return TARGET_RMS / LOOP_RMS[eng * BANDS * 2 + band * 2 + load]


## True when all 48 engine loops load. Checked once; a missing loop sends CarAudio to the old single-loop path.
static func loops_ready() -> bool:
	if _loops_ok < 0:
		_loops_ok = 1
		for e: int in ENGINE_NAMES.size():
			for b: int in BANDS:
				for l: int in 2:
					if AudioLib.get_stream(loop_id(e, b, l)) == null:
						_loops_ok = 0
	return _loops_ok == 1


## Engine index (into ENGINE_NAMES) for a car spec. Optional override: spec meta "engine_type" = "i4" | "v6" | "v8" | "hy".
## Otherwise by top speed, since specs carry no engine field. Shortcut: a car's real engine is not in its spec,
## so this is a guess from top speed; add an engine_type meta to a spec to override it.
static func engine_for_spec(spec: CarSpec) -> int:
	if spec == null:
		return 2
	if spec.has_meta(&"engine_type"):
		var k: int = ENGINE_NAMES.find(str(spec.get_meta(&"engine_type")))
		if k >= 0:
			return k
	var kmh: float = spec.top_speed_kmh
	if kmh <= 200.0:
		return 0
	if kmh <= 270.0:
		return 1
	if kmh <= 320.0:
		return 2
	return 3
