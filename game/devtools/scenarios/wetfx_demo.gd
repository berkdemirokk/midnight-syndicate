extends "res://devtools/capture_scenario.gd"
## Wet-night car FX on the Bogaz road: WheelSpray on every car (only the player and the two nearest rivals emit),
## Underglow with the player light, and RainOnLens. This scenario attaches them itself, so the race_scene wiring is
## not needed to see them. The player is held at 60 and 180 km/h (velocity set every frame) and shot from a rear
## chase view and a side view with the FX on, plus one rear shot at 180 km/h with the FX off as the base.
## Shots: wetfx_bogaz_night_<kmh>_<view>.png and wetfx_bogaz_night_180_rear_base.png; each JSON has the perf peaks.
## Optional: --preset=high|medium is passed by the harness; the default is high.

const SCENE: String = "res://race/race_scene.tscn"
const CAR_SCENE: String = "res://vehicles/noctra_sable/noctra_sable.tscn"
const CAR_SPEC: String = "res://vehicles/specs/noctra_sable.tres"
const TRACK: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const OPPONENTS: int = 3
const SETTLE_FRAMES: int = 20
const GO_WAIT_MAX_S: float = 30.0
const HOLD_FRAMES: int = 60  ## frames at the held speed before the shot: the spray and the mist need about a second to fill
const KMH_TO_MS: float = 1.0 / 3.6
const SPEEDS_KMH: PackedFloat32Array = [60.0, 180.0]
## Camera offsets in the car frame (forward is -Z, so +Z is behind the car).
const VIEWS: Dictionary = {
	"rear": Vector3(0.0, 1.5, 6.0),
	"side": Vector3(-7.0, 1.2, 0.0),
}

var _scene: RaceScene = null
var _go_seen: bool = false
var _cam: Camera3D = null
var _fx: Array[Node] = []
var _with_fx: bool = true


func run() -> void:
	tree.auto_accept_quit = false
	var cfg := RaceConfig.new()
	cfg.use_garage_paint = false
	cfg.autopilot = true
	cfg.laps = 2
	cfg.opponent_count = OPPONENTS
	cfg.track_scene = TRACK
	cfg.car_scene = CAR_SCENE
	cfg.car_spec_path = CAR_SPEC
	cfg.time_of_day = "night"
	_scene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	_scene.config = cfg
	tree.root.add_child(_scene)
	await cap.wait_frames(SETTLE_FRAMES)
	if _scene.dev_track_used or _scene.dev_car_used or _scene.find_child("DevWatermark", true, false) != null:
		cap.fail("dev track, dev mule or DevWatermark present")
		return
	_scene.race.race_started.connect(_on_go)
	var waited: float = 0.0
	while not _go_seen and waited < GO_WAIT_MAX_S:
		await cap.wait_seconds(0.1)
		waited += 0.1
	if not _go_seen:
		cap.fail("race never started")
		return
	_scene.hud.visible = false  ## the shots are of the car and the road, not the HUD
	_cam = Camera3D.new()
	_cam.fov = 70.0
	tree.root.add_child(_cam)
	_with_fx = not ("--nofx" in OS.get_cmdline_user_args())  ## --nofx: same shots without the FX, for the cost comparison
	if _with_fx:
		_attach_fx()
	for kmh: float in SPEEDS_KMH:
		for view: String in VIEWS.keys():
			await _shot(kmh, view, _with_fx)
	_detach_fx()
	await cap.wait_frames(5)
	await _shot(60.0, "side", false)
	await _shot(180.0, "rear", false)
	_scene.hud.visible = true
	_cam.queue_free()
	_scene.queue_free()
	await cap.wait_frames(5)


func _shot(kmh: float, view: String, fx_on: bool) -> void:
	var tag: String = "wetfx_bogaz_night_%d_%s%s%s" % [int(kmh), view, "" if fx_on else "_base", "" if _with_fx else "_nofx"]
	_cam.current = true
	for i: int in HOLD_FRAMES:
		_hold(kmh)
		_place_camera(view)
		if fx_on:
			WheelSpray.update_nearest(_scene.cars, _scene.player)
		await cap.wait_frames(1)
	await cap.shot(tag)


## Holds the player's speed along the car's heading and keeps the chase camera current.
func _hold(kmh: float) -> void:
	var car: ArcadeCar = _scene.player
	car.linear_velocity = -car.global_transform.basis.z * kmh * KMH_TO_MS


func _place_camera(view: String) -> void:
	var xf: Transform3D = _scene.player.global_transform
	_cam.global_position = xf * (VIEWS[view] as Vector3)
	_cam.look_at(xf.origin + Vector3.UP * 0.6, Vector3.UP)


func _attach_fx() -> void:
	for c: ArcadeCar in _scene.cars:
		var ws := WheelSpray.new()
		ws.name = WheelSpray.NODE_NAME
		ws.set_wetness(_scene.tod.audio_wetness)
		c.add_child(ws)
		_fx.append(ws)
	var ug := Underglow.new()
	ug.name = "Underglow"
	ug.player_light = true
	_scene.player.add_child(ug)
	ug.apply_time_of_day(_scene.tod.id)
	_fx.append(ug)
	var rol := RainOnLens.new()
	rol.name = "RainOnLens"
	_scene.add_child(rol)
	rol.set_strength(1.0 if _scene.tod.rain else 0.0)
	_fx.append(rol)


func _detach_fx() -> void:
	for n: Node in _fx:
		if is_instance_valid(n):
			n.queue_free()
	_fx.clear()


func _on_go() -> void:
	_go_seen = true
