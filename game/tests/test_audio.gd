extends "res://tests/test_case.gd"
## Audio: every generated stream loads, loops are flagged and seamless, CarAudio reacts to car state.


func _rig(is_player: bool = true, layered: bool = false) -> Array:
	var car := ArcadeCar.new()
	add(car)
	car.is_grounded = true
	car.speed_kmh = 120.0
	var ca := CarAudio.new()
	ca.is_player = is_player
	ca.layered_engine = layered  ## these checks read the old low/mid/high loops; the layered path has its own tests in test_audio_engine.gd
	car.add_child(ca)
	return [car, ca]


func _settle(ca: CarAudio, n: int = 40) -> void:
	for i: int in n:
		ca.update_audio(0.05)


func test_all_streams_load() -> void:
	var n := 0
	for id: StringName in AudioLib.FILES:
		var s := AudioLib.get_stream(id)
		check(s != null, "stream does not load: %s" % id)
		if s != null:
			n += 1
			check(s.get_length() > 0.04, "stream too short: %s" % id)
	metric("streams_loaded", n)
	check(n == AudioLib.FILES.size(), "not all streams loaded")


func test_loops_flagged_and_seamless() -> void:
	var seams := {}
	for id: StringName in AudioLib.FILES:
		var s := AudioLib.get_stream(id) as AudioStreamWAV
		check(s != null, "not an AudioStreamWAV: %s" % id)
		if s == null:
			continue
		if AudioLib.is_loop(id):
			check(s.loop_mode == AudioStreamWAV.LOOP_FORWARD, "loop not flagged: %s" % id)
			check(s.loop_end > 1000, "loop_end not set: %s" % id)
			# seam on the source PCM (44-byte header): last->first frame jump vs typical step
			var raw := FileAccess.get_file_as_bytes(AudioLib.DIR + (AudioLib.FILES[id] as Array)[0])
			var ch: int = raw.decode_u16(22)
			var frames: int = raw.decode_u32(40) / (2 * ch)
			var jump: float = 0.0
			for c: int in ch:
				var last: int = raw.decode_s16(44 + ((frames - 1) * ch + c) * 2)
				var first: int = raw.decode_s16(44 + c * 2)
				jump = maxf(jump, absf(float(last - first)))
			var mean_d: float = 0.0
			for i: int in 3000:
				mean_d += absf(float(raw.decode_s16(44 + (i + 1) * ch * 2) - raw.decode_s16(44 + i * ch * 2)))
			mean_d /= 3000.0
			seams[str(id)] = snappedf(jump / maxf(mean_d, 1.0), 0.1)
			check(jump <= maxf(mean_d * 5.0, 1800.0), "audible loop seam in %s: jump %.0f vs mean step %.0f" % [id, jump, mean_d])
		else:
			check(s.loop_mode == AudioStreamWAV.LOOP_DISABLED, "one-shot is looping: %s" % id)
	metric("seam_jump_over_mean_step", seams)


func test_files_have_smpl_loop_chunk() -> void:
	for id: StringName in AudioLib.FILES:
		var path: String = AudioLib.DIR + (AudioLib.FILES[id] as Array)[0]
		var bytes := FileAccess.get_file_as_bytes(path)
		check(bytes.size() > 100, "missing file " + path)
		var has_smpl: bool = bytes.slice(bytes.size() - 68, bytes.size()).get_string_from_ascii().contains("smpl")
		check(has_smpl == AudioLib.is_loop(id), "smpl chunk mismatch for %s (has=%s)" % [id, has_smpl])


func test_total_size_budget() -> void:
	var total := 0
	for id: StringName in AudioLib.FILES:
		total += FileAccess.get_file_as_bytes(AudioLib.DIR + (AudioLib.FILES[id] as Array)[0]).size()
	metric("total_mb", snappedf(total / 1048576.0, 0.1))
	check(total < 25 * 1048576, "audio over 25 MB: %d" % total)


func test_bus_layout() -> void:
	for b: StringName in [AudioLib.BUS_MUSIC, AudioLib.BUS_SFX, AudioLib.BUS_UI]:
		check(AudioServer.get_bus_index(b) != -1, "missing bus " + b)
	AudioLib.set_bus_linear(AudioLib.BUS_MUSIC, 0.5)
	check_range(AudioLib.get_bus_linear(AudioLib.BUS_MUSIC), 0.49, 0.51, "music bus linear after set 0.5")
	AudioLib.set_bus_linear(AudioLib.BUS_MUSIC, 1.0)


func test_layer_math() -> void:
	var prev_p := Vector3.ZERO
	for i: int in 11:
		var r: float = i / 10.0
		var g: Vector3 = CarAudio.layer_gains(r)
		check_range(g.length(), 0.99, 1.01, "layer gains energy at rpm %.1f" % r)
		var p: Vector3 = CarAudio.layer_pitches(r)
		if i > 0:
			check(p.x > prev_p.x and p.y > prev_p.y and p.z > prev_p.z, "pitch not rising at rpm %.1f" % r)
		prev_p = p
	check(CarAudio.layer_gains(0.0).x > 0.99, "idle is the low layer")
	check(CarAudio.layer_gains(1.0).z > 0.9, "redline is the high layer")


func test_pitch_rises_with_rpm() -> void:
	var rig := _rig()
	var car: ArcadeCar = rig[0]
	var ca: CarAudio = rig[1]
	car.rpm_norm = 0.2
	_settle(ca)
	var lo_p: float = ca.mid.pitch_scale
	var lo_low: float = ca.low.pitch_scale
	car.rpm_norm = 0.85
	_settle(ca)
	metric("mid_pitch_20pct", snappedf(lo_p, 0.01))
	metric("mid_pitch_85pct", snappedf(ca.mid.pitch_scale, 0.01))
	check(ca.mid.pitch_scale > lo_p + 0.3, "mid pitch did not rise with rpm")
	check(ca.high.pitch_scale > 1.2, "high layer pitch low at 85% rpm")
	check(ca.low.pitch_scale > lo_low, "low pitch did not rise")
	# crossfade: idle is low-dominant, redline high-dominant
	car.rpm_norm = 0.0
	_settle(ca)
	check(ca.low.volume_db > ca.high.volume_db + 20.0, "idle should be low-layer dominant")
	car.rpm_norm = 1.0
	_settle(ca)
	check(ca.high.volume_db > ca.low.volume_db + 20.0, "redline should be high-layer dominant")
	await cleanup([car])


func test_gear_shift_dip() -> void:
	var rig := _rig()
	var car: ArcadeCar = rig[0]
	var ca: CarAudio = rig[1]
	car.rpm_norm = 0.9
	car.gear = 2
	_settle(ca)
	var before: float = ca.rpm_smooth
	car.gear = 3
	ca.update_audio(0.1)
	check(ca.shift_timer > 0.0, "shift timer not started on upshift")
	check(ca.rpm_smooth < before - 0.03, "no rpm dip on upshift")
	await cleanup([car])


func test_squeal_rises_with_slip() -> void:
	var rig := _rig()
	var car: ArcadeCar = rig[0]
	var ca: CarAudio = rig[1]
	car.wheel_slip = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	_settle(ca)
	var quiet: float = ca.squeal.volume_db
	car.wheel_slip = PackedFloat32Array([0.5, 0.5, 0.5, 0.5])
	_settle(ca)
	var mid_db: float = ca.squeal.volume_db
	car.wheel_slip = PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	_settle(ca)
	var loud: float = ca.squeal.volume_db
	metric("squeal_db", [snappedf(quiet, 0.1), snappedf(mid_db, 0.1), snappedf(loud, 0.1)])
	check(quiet <= -60.0, "squeal audible without slip: %.1f dB" % quiet)
	check(mid_db > quiet and loud > mid_db, "squeal volume must rise with slip")
	check(loud > -8.0, "full slip squeal too quiet: %.1f dB" % loud)
	await cleanup([car])


func test_nitro_loop_only_with_nitro() -> void:
	var rig := _rig()
	var car: ArcadeCar = rig[0]
	var ca: CarAudio = rig[1]
	car.nitro_active = false
	_settle(ca)
	check(not ca.nitro.playing, "nitro loop playing without nitro")
	check(ca.nitro.volume_db <= -60.0, "nitro audible without nitro")
	car.nitro_active = true
	_settle(ca)
	check(ca.nitro.playing, "nitro loop not playing with nitro")
	check(ca.nitro.volume_db > -6.0, "nitro too quiet: %.1f" % ca.nitro.volume_db)
	car.nitro_active = false
	_settle(ca, 60)
	check(not ca.nitro.playing, "nitro loop did not stop after nitro ended")
	await cleanup([car])


func test_wet_hiss_needs_rain_and_speed() -> void:
	var rig := _rig()
	var car: ArcadeCar = rig[0]
	var ca: CarAudio = rig[1]
	car.speed_kmh = 160.0
	ca.wetness = 0.0
	_settle(ca)
	check(ca.hiss.volume_db <= -60.0, "hiss on dry road")
	ca.wetness = 1.0
	_settle(ca)
	check(ca.hiss.volume_db > -15.0, "no hiss on wet road at speed")
	car.speed_kmh = 5.0
	_settle(ca)
	check(ca.hiss.volume_db <= -60.0, "hiss while crawling")
	await cleanup([car])


func test_opponent_has_fewer_layers_and_is_quieter() -> void:
	var p := _rig(true)
	var o := _rig(false)
	var pc: ArcadeCar = p[0]
	var oc: ArcadeCar = o[0]
	var pa: CarAudio = p[1]
	var oa: CarAudio = o[1]
	pc.rpm_norm = 0.6
	oc.rpm_norm = 0.6
	_settle(pa)
	_settle(oa)
	check(oa.low == null and oa.nitro == null and oa.hiss == null, "opponent has player-only layers")
	check(pa.low != null and pa.nitro != null, "player missing layers")
	check(oa.mid.volume_db < pa.mid.volume_db - 6.0, "opponent engine not quieter")
	check(oa.mid.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE, "opponent not positional")
	await cleanup([pc, oc])


func test_music_player_crossfade_and_duck() -> void:
	var m := MusicPlayer.get_instance()
	check(m != null, "no music player")
	await frames(3)
	m.play_menu(0.5)
	check(m.current_track() == MusicPlayer.TRACK_MENU, "menu track not selected")
	await frames(10)
	m.play_race(0.5)
	check(m.current_track() == MusicPlayer.TRACK_RACE, "race track not selected")
	var pl: AudioStreamPlayer = m.current_player()
	check(pl.stream != null and (pl.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "race music not looping")
	await frames(45)
	var base: float = pl.volume_db
	m.duck(-10.0, 0.1)
	await frames(15)
	check(pl.volume_db < base - 8.0, "duck did not lower music (%.1f -> %.1f)" % [base, pl.volume_db])
	m.unduck(0.1)
	await frames(15)
	check_range(pl.volume_db, base - 0.5, base + 0.5, "unduck restores level")
	m.stop(0.1)


func test_ui_sounds_do_not_error() -> void:
	var u := UiSounds.get_instance()
	check(u != null, "no ui sounds node")
	await frames(3)
	UiSounds.click()
	UiSounds.confirm()
	UiSounds.back()
	UiSounds.countdown(3)
	UiSounds.countdown(0)
	UiSounds.finish()
	UiSounds.cash()
	await frames(2)
	check(true, "")
