extends "res://tests/test_case.gd"
## CC0 audio: every processed file loads as a looping OGG, the city and Maslak tracks get their ambience loop, the
## Bosphorus track stays silent, and race_scene.gd starts the ambience with one hook line.

const ONE_SHOTS: Array[String] = ["engine_start.ogg", "impact_metal.ogg", "whoosh_thruster.ogg", "engine_loop_a.ogg",
	"engine_loop_b.ogg", "engine_loop_c.ogg", "engine_loop_d.ogg"]
const CITY: String = "res://world/city_01/city_01.tscn"
const MASLAK: String = "res://world/istanbul_maslak/istanbul_maslak.tscn"
const BOGAZ: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"


func test_cc0_files_load_as_ogg() -> void:
	var names: Array[String] = ONE_SHOTS.duplicate()
	names.append_array(["ambience_city_loop.ogg", "ambience_rain_loop.ogg"])
	for n: String in names:
		var path: String = Ambience.DIR + n
		check(ResourceLoader.exists(path), "missing CC0 file %s" % path)
		var s := load(path) as AudioStreamOggVorbis
		check(s != null, "CC0 file does not load as OGG: %s" % path)
		if s != null:
			check(s.get_length() > 0.1, "CC0 file is empty: %s" % path)


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


func test_race_scene_hook_starts_ambience() -> void:
	var src := FileAccess.get_file_as_string("res://race/race_scene.gd")
	check(src.count("Ambience.start(_world, config_used.track_scene)") == 1, "race_scene.gd needs exactly one ambience hook")
