extends "res://tests/test_case.gd"
## Layered engine wired into CarAudio: voice cap (4 for the player, 1 for an opponent), crossfade power sums,
## engine mapping per car spec, fallback to the old single loops, the upshift cut, the limiter bounce, and a
## 20 s simulated race trace (written to a CSV only when run with --audio-log=<path>) for the evidence log.

const SPEC_DIR := "res://vehicles/specs/"
const SPECS: Array[String] = ["atmaca_stock", "noctra_vela", "noctra_sable", "bosfor_yildirim"]
const EXPECT_ENGINE: Array[int] = [0, 1, 2, 3]  ## i4, v6, v8, hy (top speed 140, 232, 286, 352 km/h)
const DT: float = 1.0 / 60.0


func _rig(is_player: bool = true, layered: bool = true, spec_name: String = "noctra_sable") -> Array:
	var car := ArcadeCar.new()
	add(car)
	car.spec = load(SPEC_DIR + spec_name + ".tres") as CarSpec
	car.is_grounded = true
	car.speed_kmh = 120.0
	car.input.throttle = 0.0
	var ca := CarAudio.new()
	ca.is_player = is_player
	ca.layered_engine = layered
	car.add_child(ca)
	return [car, ca]


## Sweeps rpm up and down with a changing throttle; returns [max voices playing, max audible bands, max bands seen].
func _sweep(car: ArcadeCar, ca: CarAudio) -> Array:
	var max_voices: int = 0
	var max_bands: int = 0
	var adjacent: bool = true
	var i: int = 0
	var rpm: float = 0.0
	while i < 400:
		rpm = absf(fmod(i * 0.013, 2.0) - 1.0)  # 0 -> 1 -> 0 ...
		car.rpm_norm = rpm
		car.input.throttle = 0.5 + 0.5 * sin(i * 0.37)
		ca.update_audio(DT)
		max_voices = maxi(max_voices, ca.engine_voices_playing())
		var held: Array[int] = []
		for b: int in ca.slot_bands():
			if b >= 0:
				held.append(b)
		max_bands = maxi(max_bands, held.size())
		if held.size() == 2 and absi(held[0] - held[1]) != 1:
			adjacent = false
		i += 1
	return [max_voices, max_bands, adjacent]


func test_layered_path_is_on_with_loops() -> void:
	check(EngineLayers.loops_ready(), "not all 48 engine loops load")
	var rig := _rig()
	var ca: CarAudio = rig[1]
	check(ca.layered, "player did not take the layered path although the loops load")
	check(ca.low == null and ca.high == null, "layered path still builds the old player loops")
	await cleanup([rig[0]])


func test_voice_cap_player_and_rival() -> void:
	var prig := _rig(true)
	var pcar: ArcadeCar = prig[0]
	var pca: CarAudio = prig[1]
	var pres: Array = _sweep(pcar, pca)
	metric("player_max_engine_voices", pres[0])
	metric("player_max_bands_held", pres[1])
	check(pres[0] <= 4, "player plays %d engine voices, cap is 4" % pres[0])
	check(pres[1] == 2, "layered path never held two bands (max %d): crossfade not exercised" % pres[1])
	check(pres[2], "held bands are not adjacent")

	var rrig := _rig(false)
	var rcar: ArcadeCar = rrig[0]
	var rca: CarAudio = rrig[1]
	var rres: Array = _sweep(rcar, rca)
	metric("rival_max_engine_voices", rres[0])
	check(rres[0] <= 1, "rival plays %d engine voices, cap is 1" % rres[0])
	check(not rca.layered and rca.high == null, "rival must use the single old loop")
	await cleanup([pcar, rcar])


func test_crossfade_power_sums() -> void:
	var worst: float = 0.0
	var worst_loop: float = 0.0
	for th: float in [0.0, 0.25, 0.6, 1.0]:
		var rpm: float = 0.0
		while rpm <= 9000.0:
			var w: PackedFloat32Array = EngineLayers.band_weights(rpm, th)
			var s: float = 0.0
			for v: float in w:
				s += v * v
			worst = maxf(worst, absf(s - 1.0))
			rpm += 41.0
	check(worst < 1e-4, "crossfade power sum off by %f" % worst)
	for e: int in 4:
		for b: int in EngineLayers.BANDS:
			for l: int in 2:
				var rms: float = EngineLayers.LOOP_RMS[e * 12 + b * 2 + l]
				worst_loop = maxf(worst_loop, absf(rms * EngineLayers.loop_norm(e, b, l) - EngineLayers.TARGET_RMS))
	check(worst_loop < 1e-6, "loop normalisation does not reach TARGET_RMS: %f" % worst_loop)
	metric("crossfade_power_error", worst)


func test_engine_mapping_per_car() -> void:
	for i: int in SPECS.size():
		var spec: CarSpec = load(SPEC_DIR + SPECS[i] + ".tres") as CarSpec
		check(EngineLayers.engine_for_spec(spec) == EXPECT_ENGINE[i], "%s maps to engine %d, expected %d" % [SPECS[i], EngineLayers.engine_for_spec(spec), EXPECT_ENGINE[i]])
	check(EngineLayers.engine_for_spec(null) == 2, "null spec should map to the default v8")
	var ov: CarSpec = (load(SPEC_DIR + "atmaca_stock.tres") as CarSpec).duplicate() as CarSpec
	ov.set_meta(&"engine_type", "hy")
	check(EngineLayers.engine_for_spec(ov) == 3, "engine_type meta override ignored")
	ov.set_meta(&"engine_type", "bogus")
	check(EngineLayers.engine_for_spec(ov) == 0, "unknown engine_type meta must fall back to top speed")
	var rig := _rig(true, true, "noctra_vela")
	var car: ArcadeCar = rig[0]
	var ca: CarAudio = rig[1]
	car.rpm_norm = 0.5
	ca.update_audio(DT)
	check(ca.engine_index == 1, "Vela should use the v6 loops, got %d" % ca.engine_index)
	await cleanup([car])


func test_fallback_to_old_loops() -> void:
	var rig := _rig(true, false)
	var car: ArcadeCar = rig[0]
	var ca: CarAudio = rig[1]
	check(not ca.layered, "layered_engine=false still uses the layered path")
	check(ca.low != null and ca.mid != null and ca.high != null, "fallback lacks the old player loops")
	var res: Array = _sweep(car, ca)
	check(res[0] <= 3, "fallback plays %d engine voices, old set is 3" % res[0])
	await cleanup([car])


func test_upshift_cut_dips_throttle_and_ducks() -> void:
	var rig := _rig()
	var car: ArcadeCar = rig[0]
	var ca: CarAudio = rig[1]
	car.rpm_norm = 0.6
	car.input.throttle = 1.0
	car.gear = 2
	for i: int in 60:
		ca.update_audio(DT)
	check(absf(ca.duck() - 1.0) < 0.01 and absf(ca.throttle_effective() - 1.0) < 0.01, "no cut before a shift")
	car.gear = 3
	ca.update_audio(0.01)
	check(absf(ca.throttle_effective() - CarAudio.SHIFT_CUT_THROTTLE) < 0.01, "throttle not dipped in the cut: %f" % ca.throttle_effective())
	for i: int in 3:
		ca.update_audio(0.01)
	check(ca.duck() < 0.5, "volume not ducked during the cut: %f" % ca.duck())
	for i: int in 12:
		ca.update_audio(0.01)
	check(absf(ca.throttle_effective() - 1.0) < 0.01, "throttle dip did not end after %.0f ms" % (CarAudio.SHIFT_CUT_TIME * 1000.0))
	check(ca.duck() > 0.95, "volume duck did not recover: %f" % ca.duck())
	await cleanup([car])


func test_rival_level_follows_rpm_and_keeps_a_floor() -> void:
	var rig := _rig(false)
	var car: ArcadeCar = rig[0]
	var ca: CarAudio = rig[1]
	car.input.throttle = 1.0
	car.rpm_norm = 0.3
	for i: int in 180:
		ca.update_audio(DT)
	var low_db: float = ca.mid.volume_db
	car.rpm_norm = 0.99
	for i: int in 180:
		ca.update_audio(DT)
	var red_db: float = ca.mid.volume_db
	metric("rival_mid_db_low_high", [snappedf(low_db, 0.1), snappedf(red_db, 0.1)])
	check(red_db > -25.0, "rival is silent at redline: %f dB" % red_db)
	check(low_db > red_db, "rival level does not follow rpm: low %f red %f" % [low_db, red_db])
	await cleanup([car])


func test_limiter_bounce_only_at_redline() -> void:
	var rig := _rig()
	var car: ArcadeCar = rig[0]
	var ca: CarAudio = rig[1]
	car.input.throttle = 1.0
	car.rpm_norm = 0.5
	for i: int in 120:
		ca.update_audio(1.0 / 240.0)
	check(ca.bounce() > 0.999, "bounce active below the limiter: %f" % ca.bounce())
	car.rpm_norm = 1.0
	var lo: float = 1.0
	var hi: float = 0.0
	for i: int in 240:
		ca.update_audio(1.0 / 240.0)
		lo = minf(lo, ca.bounce())
		hi = maxf(hi, ca.bounce())
	metric("limiter_bounce_min_max", [snappedf(lo, 0.01), snappedf(hi, 0.01)])
	check(lo < 0.75 and hi > 0.95, "limiter does not bounce: min %f max %f" % [lo, hi])
	await cleanup([car])


func test_race_trace_20s() -> void:
	var rig := _rig()
	var car: ArcadeCar = rig[0]
	var ca: CarAudio = rig[1]
	var rows := PackedStringArray()
	rows.append("t_s,gear,rpm_norm,rpm_abs,throttle_in,throttle_eff,duck,bounce,slot0_band,slot1_band,v0_gain,v1_gain,v2_gain,v3_gain,v0_pitch,v2_pitch,voices,update_us")
	var max_voices: int = 0
	var max_us: int = 0
	var sum_us: int = 0
	var shift_frames: int = 0
	var two_band_frames: int = 0
	var frames: int = int(round(20.0 / DT))
	for f: int in frames:
		var t: float = f * DT
		var p: Array = _profile(t)
		car.rpm_norm = p[0]
		car.gear = p[1]
		car.input.throttle = p[2]
		if ca.slot_bands()[0] >= 0 and ca.slot_bands()[1] >= 0:
			two_band_frames += 1
		var t0: int = Time.get_ticks_usec()
		ca.update_audio(DT)
		var us: int = Time.get_ticks_usec() - t0
		max_us = maxi(max_us, us)
		sum_us += us
		var voices: int = ca.engine_voices_playing()
		max_voices = maxi(max_voices, voices)
		if ca.throttle_effective() < p[2] - 0.01:
			shift_frames += 1
		var sb: PackedInt32Array = ca.slot_bands()
		rows.append("%.4f,%d,%.3f,%.0f,%.2f,%.2f,%.3f,%.3f,%d,%d,%.4f,%.4f,%.4f,%.4f,%.3f,%.3f,%d,%d" % [
			t, car.gear, car.rpm_norm, ca.rpm_abs(), car.input.throttle, ca.throttle_effective(), ca.duck(), ca.bounce(),
			sb[0], sb[1], ca.voice_gain(0), ca.voice_gain(1), ca.voice_gain(2), ca.voice_gain(3),
			ca.voice_pitch(0), ca.voice_pitch(2), voices, us])
	var avg_us: float = float(sum_us) / frames
	metric("race20_max_engine_voices", max_voices)
	metric("race20_two_band_seconds", snappedf(two_band_frames * DT, 0.01))
	metric("race20_cut_seconds", snappedf(shift_frames * DT, 0.01))
	metric("race20_update_us_avg_max", [snappedf(avg_us, 0.1), max_us])
	check(max_voices <= 4, "race trace plays %d voices" % max_voices)
	check(shift_frames >= 5 * 2, "upshift cuts not seen in the race trace: %d frames" % shift_frames)
	var path: String = _log_path()
	if path != "":
		var fa := FileAccess.open(path, FileAccess.WRITE)
		check(fa != null, "cannot write audio log " + path)
		if fa != null:
			fa.store_string("\n".join(rows) + "\n")
			fa.close()
	await cleanup([car])


## Race profile: 3 s cycles, each an upshift to the next gear, rpm 0.45 to redline, 0.4 s held at the limiter,
## then 0.2 s lifted off (throttle 0), so the off-load voices carry weight in the trace too.
func _profile(t: float) -> Array:
	var cyc: float = 3.0
	var k: int = int(t / cyc)
	var ph: float = fmod(t, cyc)
	var gear: int = 1 + k % 6
	var rpm: float = 0.45
	var thr: float = 1.0
	if ph >= 2.8:
		rpm = 0.99
		thr = 0.0
	elif ph >= 2.4:
		rpm = 0.99
	elif ph >= 0.2:
		rpm = lerpf(0.45, 0.99, (ph - 0.2) / 2.2)
	return [rpm, gear, thr]


func _log_path() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--audio-log="):
			return a.trim_prefix("--audio-log=")
	return ""
