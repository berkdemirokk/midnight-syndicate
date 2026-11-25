class_name MusicPlayer
extends Node
## Menu / race music with crossfade and a ducking hook. Works as an autoload
## (MusicPlayer="*res://audio/music_player.gd" is NOT needed: MusicPlayer.get_instance() creates it).
## Usage: MusicPlayer.get_instance().play_race(); .duck(-9.0, 0.15) on a stinger; .unduck(0.6).

const TRACK_MENU := &"music_menu_loop"
const TRACK_RACE := &"music_race_loop"

static var _inst: MusicPlayer

## Level of the music relative to the SFX bus (the Music bus carries the user's volume setting).
@export var track_volume_db: float = -3.0

var _players: Array[AudioStreamPlayer] = []
var _levels: Array[float] = [0.0, 0.0]
var _targets: Array[float] = [0.0, 0.0]
var _rates: Array[float] = [1.0, 1.0]
var _ids: Array[StringName] = [&"", &""]
var _active: int = 0
var _duck_db: float = 0.0
var _duck_target_db: float = 0.0
var _duck_speed: float = 60.0


func _init() -> void:
	name = "MusicPlayer"
	for i: int in 2:
		var p := AudioStreamPlayer.new()
		p.bus = AudioLib.BUS_MUSIC
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)


func _ready() -> void:
	AudioLib.ensure_buses()
	for i: int in 2:
		_start(i)


static func get_instance() -> MusicPlayer:
	if is_instance_valid(_inst):
		return _inst
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_inst = MusicPlayer.new()
	tree.root.add_child.call_deferred(_inst)
	return _inst


func play_menu(fade: float = 1.5) -> void:
	play_track(TRACK_MENU, fade)


func play_race(fade: float = 1.0) -> void:
	play_track(TRACK_RACE, fade)


## Crossfade to `id`. No-op when it already plays. fade <= 0 switches instantly.
func play_track(id: StringName, fade: float = 1.5, restart: bool = false) -> void:
	if id == _ids[_active] and _targets[_active] > 0.0 and not restart:
		return
	var old: int = _active
	var nw: int = 1 - _active
	_targets[old] = 0.0
	_rates[old] = 1.0 / maxf(fade, 0.001)
	_players[nw].stop()
	_players[nw].stream = AudioLib.get_stream(id)
	_ids[nw] = id
	_targets[nw] = 1.0
	_rates[nw] = 1.0 / maxf(fade, 0.001)
	_levels[nw] = 0.0
	_active = nw
	if fade <= 0.0:
		_levels[old] = 0.0
		_levels[nw] = 1.0
	_start(nw)
	_apply()


func stop(fade: float = 1.0) -> void:
	for i: int in 2:
		_targets[i] = 0.0
		_rates[i] = 1.0 / maxf(fade, 0.001)


## Lower the music by `db` (negative) over `time` seconds, e.g. under a finish sting or a pause menu.
func duck(db: float = -10.0, time: float = 0.15) -> void:
	_duck_target_db = minf(db, 0.0)
	_duck_speed = absf(_duck_target_db - _duck_db) / maxf(time, 0.001)


func unduck(time: float = 0.6) -> void:
	duck(0.0, time)


func current_track() -> StringName:
	return _ids[_active] if _targets[_active] > 0.0 else &""


func current_player() -> AudioStreamPlayer:
	return _players[_active]


func duck_db() -> float:
	return _duck_db


func _start(i: int) -> void:
	var p: AudioStreamPlayer = _players[i]
	if is_inside_tree() and p.stream != null and not p.playing:
		p.play()


func _process(delta: float) -> void:
	_duck_db = move_toward(_duck_db, _duck_target_db, _duck_speed * delta)
	for i: int in 2:
		_levels[i] = move_toward(_levels[i], _targets[i], _rates[i] * delta)
	_apply()


func _apply() -> void:
	for i: int in 2:
		var p: AudioStreamPlayer = _players[i]
		p.volume_db = linear_to_db(maxf(_levels[i], 0.0001)) + track_volume_db + _duck_db
		if _levels[i] <= 0.0 and _targets[i] <= 0.0 and p.playing:
			p.stop()
