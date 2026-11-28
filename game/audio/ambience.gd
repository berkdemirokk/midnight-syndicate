class_name Ambience
extends Node
## Looping CC0 street ambience for one race track. race_scene.gd starts it with one call; it is freed with the world.
## Tracks missing from LOOP_BY_TRACK stay silent (no verified harbour loop yet).

const DIR: String = "res://assets/audio/cc0/"
const VOLUME_DB: float = -16.0  ## under the car sounds
const LOOP_BY_TRACK: Dictionary = {  ## track scene path fragment -> loop file in DIR
	"city_01": "ambience_city_loop.ogg",  # city-loop_0 by wipics, CC0
	"istanbul_maslak": "ambience_rain_loop.ogg",  # rain_in_space_loop by Tsorthan Grove, CC0
}

var _player: AudioStreamPlayer = null


## Creates the ambience under parent for this track and starts it. Returns the node (silent when the track has no loop).
static func start(parent: Node, track_scene: String) -> Ambience:
	var amb := Ambience.new()
	amb.name = "Ambience"
	parent.add_child(amb)
	amb.setup(track_scene)
	return amb


## The loop file for a track scene path, or "" when the track has none.
static func loop_file_for(track_scene: String) -> String:
	for key: String in LOOP_BY_TRACK:
		if track_scene.contains(key):
			return DIR + (LOOP_BY_TRACK[key] as String)
	return ""


func setup(track_scene: String) -> void:
	var path: String = loop_file_for(track_scene)
	if path == "":
		return
	var stream := load(path) as AudioStreamOggVorbis  # a missing file is a broken build: warn, stay silent
	if stream == null:
		push_warning("Ambience: cannot load %s" % path)
		return
	stream.loop = true
	AudioLib.ensure_buses()
	_player = AudioStreamPlayer.new()
	_player.name = "Loop"
	_player.stream = stream
	_player.volume_db = VOLUME_DB
	_player.bus = AudioLib.BUS_SFX
	add_child(_player)
	_player.play()


func is_playing() -> bool:
	return _player != null and _player.playing


func stop() -> void:
	if _player != null:
		_player.stop()
