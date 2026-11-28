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
const REF_RPM: Array[float] = [1500.0, 2100.0, 2900.0, 4000.0, 5500.0, 7200.0]
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
