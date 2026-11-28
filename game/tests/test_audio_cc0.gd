extends "res://tests/test_case.gd"
## CC0 audio: the shipped OGG files load and loop, the city and Maslak tracks get their ambience loop, the Bosphorus
## track stays silent, the police siren starts on a car and stops with the chase, and the hooks are in place.

const CITY: String = "res://world/city_01/city_01.tscn"
const MASLAK: String = "res://world/istanbul_maslak/istanbul_maslak.tscn"
const BOGAZ: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const SHIPPED: Array[String] = ["ambience_city_loop.ogg", "ambience_rain_loop.ogg", "police_siren_wail.ogg"]


func test_cc0_files_load_as_ogg() -> void:
	for n: String in SHIPPED:
		var path: String = Ambience.DIR + n
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
		check(absf(s.get_length() - 3.2) < 0.1, "siren wail should be about 3.2 s, got %.3f" % s.get_length())


func test_loop_mapping() -> void:
	check(Ambience.loop_file_for(CITY).ends_with("ambience_city_loop.ogg"), "city track has the wrong loop")
	check(Ambience.loop_file_for(MASLAK).ends_with("ambience_rain_loop.ogg"), "Maslak track has the wrong loop")
	check(Ambience.loop_file_for(BOGAZ) == "", "Bosphorus track should stay silent")
	check(Ambience.loop_file_for("res://world/dev_track/dev.tscn") == "", "dev track should stay silent")


func test_ambience_plays_its_loop_and_stops() -> void:
	var parent := Node.new()
	add(parent)
	var amb: Ambience = Ambience.start(parent, CITY)
	check(amb.get_parent() == parent, "ambience was not added under the parent")
	check(amb.is_playing(), "city ambience did not start")
	var player := amb.get_node("Loop") as AudioStreamPlayer
	check(player != null and (player.stream as AudioStreamOggVorbis).loop, "city ambience stream does not loop")
	amb.stop()
	check(not amb.is_playing(), "ambience did not stop")
	var silent: Ambience = Ambience.start(parent, BOGAZ)
	check(not silent.is_playing(), "Bosphorus ambience should be silent")
	await cleanup([parent])


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


func test_race_scene_hook_starts_ambience() -> void:
	var src := FileAccess.get_file_as_string("res://race/race_scene.gd")
	check(src.count("Ambience.start(_world, config_used.track_scene)") == 1, "race_scene.gd needs exactly one ambience hook")
