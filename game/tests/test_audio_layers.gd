extends "res://tests/test_case.gd"
## Engine band layers (audio/engine_layers.gd): equal-power crossfade at every rpm and throttle, the
## dominant band's pitch stays inside the band window, and all 32 synthesised engine loops are registered and load.

const ENGINES: Array[String] = ["i4", "v6", "v8", "hy"]


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


func test_dominant_band_pitch_inside_window() -> void:
	var lo: float = EngineLayers.REF_RPM[0] / EngineLayers.BAND_PITCH_MAX
	var hi: float = EngineLayers.REF_RPM[EngineLayers.BANDS - 1] * EngineLayers.BAND_PITCH_MAX
	var worst_ratio: float = 1.0
	var rpm: float = lo
	while rpm <= hi:
		var b: int = EngineLayers.dominant_band(rpm)
		var ratio: float = rpm / EngineLayers.REF_RPM[b]
		var tol: float = 0.002
		check(ratio >= 1.0 / EngineLayers.BAND_PITCH_MAX - tol and ratio <= EngineLayers.BAND_PITCH_MAX + tol,
			"band %d pitch ratio %f out of window at %f rpm" % [b, ratio, rpm])
		worst_ratio = maxf(worst_ratio, maxf(ratio, 1.0 / ratio))
		rpm += 17.0
	metric("worst_pitch_ratio", snappedf(worst_ratio, 0.001))
	# band_pitch clamps everything, including idle and redline extremes
	for b: int in EngineLayers.BANDS:
		for r: float in [0.0, 800.0, 20000.0]:
			var p: float = EngineLayers.band_pitch(r, b)
			check(p >= 1.0 / EngineLayers.BAND_PITCH_MAX - 1e-4 and p <= EngineLayers.BAND_PITCH_MAX + 1e-4,
				"band_pitch out of window: %f" % p)


func test_engine_loops_registered_and_load() -> void:
	for eng: String in ENGINES:
		for b: int in EngineLayers.BANDS:
			for load: String in ["on", "off"]:
				var id := StringName("eng_%s_b%d_%s" % [eng, b + 1, load])
				check(AudioLib.FILES.has(id), "missing engine loop id " + str(id))
				check(AudioLib.get_stream(id) != null, "engine loop does not load: " + str(id))
				check(AudioLib.is_loop(id), "engine loop not flagged as loop: " + str(id))
