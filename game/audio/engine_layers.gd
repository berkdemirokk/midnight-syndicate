class_name EngineLayers
extends RefCounted
## Engine loop bands (assets/audio/engine/<eng>_<band>_<load>.wav, made by tools/audio_synth/engine_layers.py).
## Four bands centred on REF_RPM, neighbour ratio at most 1.8. Inside a band a loop plays at
## pitch = rpm / REF_RPM[band], clamped to [1/BAND_PITCH_MAX, BAND_PITCH_MAX] (about -4.6 to +4.6 semitones),
## so the band edge is where the next band takes over, not a chipmunk stretch.
## Crossfade: equal power in log-rpm across bands and in throttle across on/off load, so the squared weights sum to 1.
## Weights index: band * 2 + load, load 0 = off-load, 1 = on-load.

const BANDS: int = 4
const REF_RPM: Array[float] = [1500.0, 2700.0, 4500.0, 7200.0]
const BAND_PITCH_MAX: float = 1.3416  ## sqrt(1.8): pitch ratio at the geometric midpoint of the widest band pair


## Equal-power band and load weights for an absolute rpm and throttle 0..1. Sum of squares = 1.
static func band_weights(rpm: float, throttle: float) -> PackedFloat32Array:
	var seg: int = 0
	while seg < BANDS - 2 and rpm >= REF_RPM[seg + 1]:
		seg += 1
	var lo: float = log(REF_RPM[seg])
	var hi: float = log(REF_RPM[seg + 1])
	var t: float = clampf((log(maxf(rpm, 1.0)) - lo) / (hi - lo), 0.0, 1.0)
	var wb := PackedFloat32Array()
	wb.resize(BANDS)
	wb.fill(0.0)
	wb[seg] = cos(t * PI * 0.5)
	wb[seg + 1] = sin(t * PI * 0.5)
	var th: float = clampf(throttle, 0.0, 1.0)
	var won: float = sin(th * PI * 0.5)
	var woff: float = cos(th * PI * 0.5)
	var out := PackedFloat32Array()
	out.resize(BANDS * 2)
	for b: int in BANDS:
		out[b * 2] = wb[b] * woff
		out[b * 2 + 1] = wb[b] * won
	return out


## Playback pitch multiplier for a loop of this band at this rpm.
static func band_pitch(rpm: float, band: int) -> float:
	return clampf(rpm / REF_RPM[band], 1.0 / BAND_PITCH_MAX, BAND_PITCH_MAX)


## Band with the most energy at this rpm (uses the half-throttle mix).
static func dominant_band(rpm: float) -> int:
	var w := band_weights(rpm, 0.5)
	var best: int = 0
	var best_mass: float = -1.0
	for b: int in BANDS:
		var mass: float = w[b * 2] * w[b * 2] + w[b * 2 + 1] * w[b * 2 + 1]
		if mass > best_mass:
			best_mass = mass
			best = b
	return best
