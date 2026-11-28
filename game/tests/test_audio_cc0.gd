extends "res://tests/test_case.gd"
## CC0 audio: the shipped OGG file loads and loops, the police siren starts on a car and stops with the chase, and the
## pursuit hooks are in place.

const SHIPPED: Array[String] = ["police_siren_wail.ogg"]


func test_cc0_files_load_as_ogg() -> void:
	for n: String in SHIPPED:
		var path: String = "res://assets/audio/cc0/" + n
		check(ResourceLoader.exists(path), "missing CC0 file %s" % path)
		var s := load(path) as AudioStreamOggVorbis
		check(s != null, "CC0 file does not load as OGG: %s" % path)
		if s != null:
			check(s.get_length() > 0.1, "CC0 file is empty: %s" % path)


func test_siren_file_is_a_loop() -> void:
	var s := load(PursuitSiren.STREAM_PATH) as AudioStreamOggVorbis
	check(s != null, "siren file does not load")
	if s != null:
		s.loop = true
		check(absf(s.get_length() - 1.5) < 0.1, "siren wail should be one 1.5 s sweep, got %.3f" % s.get_length())


func test_siren_starts_on_car_and_stops_with_chase() -> void:
	var car := Node3D.new()
	add(car)
	var siren: PursuitSiren = PursuitSiren.attach(car)
	check(siren.get_parent() == car, "siren was not added under the police car")
	check(siren.playing, "siren did not start on the police car")
	check(siren.max_distance > 0.0 and siren.unit_size > 0.0, "siren has no distance falloff")
	PursuitSiren.stop_all([car])
	check(not siren.playing, "siren kept playing after the chase ended")
	var again: PursuitSiren = PursuitSiren.attach(car)
	PursuitSiren.stop_all([null, car])
	check(not again.playing, "stop_all skipped a siren next to a null car")
	await cleanup([car])


func test_pursuit_hooks_are_in_place() -> void:
	var src := FileAccess.get_file_as_string("res://race/pursuit/pursuit_mode.gd")
	check(src.count("PursuitSiren.attach(car)") == 1, "pursuit_mode.gd must attach the siren once, on spawn")
	check(src.count("PursuitSiren.stop_all(police)") == 1, "pursuit_mode.gd must stop the sirens in _stop_chase")

