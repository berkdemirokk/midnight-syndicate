extends "res://tests/test_case.gd"
## Engine band layers (audio/engine_layers.gd): equal-power crossfade at every rpm and throttle; a band has weight
## only inside its in-tune zone, so every audible loop plays at rpm / REF (no clamp, within 0.5 cents); at most two
## adjacent bands are audible; and all 48 synthesised engine loops are registered and load.

const ENGINES: Array[String] = ["i4", "v6", "v8", "hy"]
const WEIGHT_EPS: float = 0.01  ## amplitude below which a loop counts as silent (-40 dB)
const TOL_CENTS: float = 0.5


func test_weights_equal_power() -> void:
	var worst: float = 0.0
	for th: float in [0.0, 0.3, 0.7, 1.0]:
		var rpm: float = 0.0
		while rpm <= 9000.0:
			var w := EngineLayers.band_weights(rpm, th)
			var s: float = 0.0
			for v: float in w:
				s += v * v
			worst = maxf(worst, absf(s - 1.0))
			rpm += 23.0
	metric("max_power_error", worst)
	check(worst < 1e-4, "band weights are not equal-power: error %f" % worst)


func test_zones_overlap_only_neighbours() -> void:
	for r: float in EngineLayers.REF_RPM:  # synth f0 = rpm*cyl/120 must be an exact integer Hz, else the loop is off REF
		check(fmod(r, 60.0) == 0.0, "REF_RPM %f is not a multiple of 60" % r)
	for b: int in EngineLayers.BANDS - 1:
		check(EngineLayers.zone_hi(b) > EngineLayers.zone_lo(b + 1), "zones %d and %d do not overlap" % [b, b + 1])
	for b: int in EngineLayers.BANDS - 2:
		check(EngineLayers.REF_RPM[b + 2] / EngineLayers.REF_RPM[b] >= EngineLayers.BAND_PITCH_MAX * EngineLayers.BAND_PITCH_MAX,
			"bands %d and %d overlap, so three layers could be audible" % [b, b + 2])


func test_weighted_loops_are_in_tune() -> void:
	var worst_cents: float = 0.0
	var worst_outside: float = 0.0
	var max_active: int = 0
	var rpm: float = 1200.0  # idle floor: below it the outer band clamps (documented shortcut)
	while rpm <= 9000.0:
		for th: float in [0.0, 0.3, 0.7, 1.0]:
			var w := EngineLayers.band_weights(rpm, th)
			var active: Array[int] = []
			for b: int in EngineLayers.BANDS:
				var amp: float = maxf(w[b * 2], w[b * 2 + 1])
				if amp <= WEIGHT_EPS:
					continue
				active.append(b)
				if rpm < EngineLayers.zone_lo(b) or rpm > EngineLayers.zone_hi(b):
					worst_outside = maxf(worst_outside, amp)
				var played: float = EngineLayers.band_pitch(rpm, b)
				var ideal: float = rpm / EngineLayers.REF_RPM[b]
				worst_cents = maxf(worst_cents, absf(1200.0 * log(played / ideal) / log(2.0)))
			max_active = maxi(max_active, active.size())
			check(active.size() <= 2 and (active.size() < 2 or active[1] - active[0] == 1),
				"non-adjacent or >2 bands audible at %f rpm" % rpm)
		rpm += 7.0
	metric("worst_pitch_error_cents", snappedf(worst_cents, 0.001))
	metric("max_audible_bands", max_active)
	check(worst_outside < 1e-6, "a band has weight outside its zone: %f" % worst_outside)
	check(worst_cents < TOL_CENTS, "audible loop off pitch by %f cents" % worst_cents)


func test_engine_loops_registered_and_load() -> void:
	for eng: String in ENGINES:
		for b: int in EngineLayers.BANDS:
			for load: String in ["on", "off"]:
				var id := StringName("eng_%s_b%d_%s" % [eng, b + 1, load])
				check(AudioLib.FILES.has(id), "missing engine loop id " + str(id))
				check(AudioLib.get_stream(id) != null, "engine loop does not load: " + str(id))
				check(AudioLib.is_loop(id), "engine loop not flagged as loop: " + str(id))
