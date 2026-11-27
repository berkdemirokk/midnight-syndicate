class_name PursuitMode
extends Node
## Opt-in police pursuit for one race. race_scene.gd adds this node only when RaceConfig.pursuit is true and
## ENABLED is true. The rules come from PursuitState (heat, chase, cooldown, escaped, busted). This node spawns and
## removes police cars, places roadblocks, drives the heat HUD and pays the escape reward. RaceManager never sees the
## police, so positions, laps and results do not change.

## Kill switch: false keeps pursuit off even when RaceConfig.pursuit is set. A static var, not a const, so a capture
## or a test can turn it on for one run.
static var ENABLED: bool = false

const POLICE_SCENE: String = "res://vehicles/bosfor_atmaca/atmaca_stock.tscn"  ## Istanbul sedan, fictional brand
const POLICE_SPEC: String = "res://vehicles/specs/atmaca_stock.tres"
const POLICE_PAINT: Color = Color("#16305C")  ## dark blue body; the light bar carries the red and blue
const LIGHT_RED: Color = Color("#FF2A2A")
const LIGHT_BLUE: Color = Color("#2A7BFF")
const LIGHT_FLASH_S: float = 0.12  ## half period of the light bar
const LIGHT_BAR_Y_M: float = 1.25  ## light bar height above the car origin when the body has no mesh to measure
const LIGHT_BAR_HALF_H_M: float = 0.07  ## half the lamp height: the bar sits on the roof
const LIGHT_BAR_X_M: float = 0.3  ## each lamp this far left or right of the centre line
const DRIVER_NAME: String = "PoliceDriver"
const SKILL_BASE: float = 0.94
const SKILL_PER_HEAT: float = 0.01
const SPAWN_DISTANCES_M: PackedFloat32Array = [75.0, 82.0, 88.0]  ## behind the player, all inside PursuitState.ESCAPE_DISTANCE_M
const SPAWN_SIDE_M: PackedFloat32Array = [0.0, 3.0, -3.0]  ## lane offsets tried at each distance
const SPAWN_CLEAR_M: float = 6.0  ## no car this close to a spawn point
const SPAWN_INTERVAL_S: float = 4.0
const SPAWN_HEIGHT_M: float = 0.47  ## car origin height, as AIDriver.reset_height
const DESPAWN_M: float = 250.0  ## police this far behind or ahead of the player are removed
const ROADBLOCK_AHEAD_M: PackedFloat32Array = [150.0, 175.0, 200.0]
const ROADBLOCK_COOLDOWN_S: float = 30.0
const ROADBLOCK_PASSED_M: float = 40.0  ## the player this far past the barriers removes them
const ESCAPE_REWARD_PER_HEAT: int = 200  ## cash on ESCAPED, through GameState.add_cash

var state: PursuitState = PursuitState.new()
var police: Array[ArcadeCar] = []
var player: ArcadeCar = null
var roadblock: Roadblock = null
var escape_reward: int = 0
var last_spawn_hidden: bool = false  ## the last police spawn was out of the camera view (best effort, see the doc)

var _track: Track = null
var _cars: Array[ArcadeCar] = []  ## the race cars, player included: avoidance and spawn clearance
var _hud: PursuitHud = null
var _red: StandardMaterial3D = null
var _blue: StandardMaterial3D = null
var _active: bool = false
var _player_s: float = -1.0  ## track progress of the player, search hint
var _spawn_t: float = 0.0
var _roadblock_cd: float = 0.0
var _flash_t: float = 0.0
var _hints: Dictionary = {}  ## police car -> last track progress, search hint
var _had_police: bool = false  ## a police car existed in this chase: no cooldown or escape before that


## Police cars allowed at a heat level: 1 / 2 / 2 / 3 / 3 for heat 1..5, none at heat 0.
static func max_police_for_heat(heat: int) -> int:
	match clampi(heat, 0, PursuitState.MAX_HEAT):
		1:
			return 1
		2, 3:
			return 2
		4, 5:
			return 3
	return 0


func setup(track: Track, race_player: ArcadeCar, race_cars: Array[ArcadeCar], race: RaceManager) -> void:
	_track = track
	player = race_player
	_cars = race_cars
	_red = _lamp_material(LIGHT_RED)
	_blue = _lamp_material(LIGHT_BLUE)
	_hud = PursuitHud.new()
	add_child(_hud)
	if race != null and not race.race_started.is_connected(start):
		race.race_started.connect(start)


## Begins the chase at heat 1. The first police car is spawned on the next step. Called on GO.
func start() -> void:
	_active = true
	state.start(1)
	_spawn_t = 0.0
	_roadblock_cd = 0.0
	_had_police = false
	_update_hud()


func _physics_process(delta: float) -> void:
	if _active:
		step(delta)


## One simulation step. Public so tests can drive the rules without waiting for physics frames.
func step(delta: float) -> void:
	if not _active or _track == null or player == null:
		return
	_spawn_t = maxf(_spawn_t - delta, 0.0)
	_roadblock_cd = maxf(_roadblock_cd - delta, 0.0)
	_player_s = _track.get_progress(player.global_position, _player_s)
	cull()
	# Spawn before the rules tick, so the first police car exists when the chase is judged (no false escape on GO).
	if _spawn_t <= 0.0 and police.size() < max_police_for_heat(state.heat) and spawn_police():
		_spawn_t = SPAWN_INTERVAL_S
	if police.is_empty() and not _had_police:
		return  # every spawn spot blocked so far: no chase to escape from, so no reward
	_had_police = true
	var nearest: float = INF
	for c: ArcadeCar in police:
		nearest = minf(nearest, c.global_position.distance_to(player.global_position))
	state.tick(delta, nearest, player.speed_kmh)
	if state.phase == PursuitState.Phase.BUSTED or state.phase == PursuitState.Phase.ESCAPED:
		_finish()
		return
	for c: ArcadeCar in police:
		var drv: PoliceDriver = c.get_node_or_null(DRIVER_NAME) as PoliceDriver
		if drv != null:
			drv.heat = state.heat
			drv.skill = SKILL_BASE + SKILL_PER_HEAT * float(state.heat)
			drv.player_s = _player_s
	if roadblock != null and _wrap(_player_s - roadblock.progress) > ROADBLOCK_PASSED_M:
		roadblock.queue_free()
		roadblock = null
	if state.can_request_roadblock() and roadblock == null and _roadblock_cd <= 0.0:
		try_roadblock()
	_update_hud()


## Spawns police until the heat cap is reached (no interval). Returns how many were spawned.
func top_up() -> int:
	var n: int = 0
	while police.size() < max_police_for_heat(state.heat) and spawn_police():
		n += 1
	return n


## Spawns one police car behind the player, out of the camera view when a candidate spot allows it.
## Returns false when every candidate spot is blocked by a car.
func spawn_police() -> bool:
	var model: Dictionary = _police_model()
	if model.is_empty() or _track == null or player == null:
		return false
	_player_s = _track.get_progress(player.global_position, _player_s)
	var lateral: float = _track.get_lateral_offset(player.global_position, _player_s)
	var half: float = _track.width * 0.5 - 1.5
	var view: Camera3D = get_viewport().get_camera_3d()
	var spot: Transform3D = Transform3D.IDENTITY
	var found: bool = false
	var hidden: bool = false
	for dist: float in SPAWN_DISTANCES_M:
		for side: float in SPAWN_SIDE_M:
			var s: float = _player_s - dist
			var t: Vector3 = _track.get_tangent_at(s)
			var lat: float = clampf(lateral + side, -half, half)
			var pos: Vector3 = _track.get_point_at(s) + Vector3(-t.z, 0.0, t.x) * lat
			pos.y += SPAWN_HEIGHT_M
			if not _spot_free(pos):
				continue
			spot = Transform3D(Basis.looking_at(t, Vector3.UP), pos)
			found = true
			hidden = view == null or not view.is_position_in_frustum(pos)
			if hidden:
				break
		if hidden:
			break
	if not found:
		return false
	last_spawn_hidden = hidden
	var car: ArcadeCar = CarFactory.create(str(model["scene"]), model["spec"] as CarSpec, POLICE_PAINT)
	add_child(car)
	car.global_transform = spot
	_add_lights(car)
	var drv := PoliceDriver.new()
	drv.name = DRIVER_NAME
	drv.noise_seed = police.size() + 1
	car.add_child(drv)
	drv.setup(_track)
	drv.set_traffic(_cars)
	drv.player = player
	drv.set_racing(true)
	police.append(car)
	return true


## Removes police that fell DESPAWN_M behind the player or ran that far ahead. Returns how many were removed.
func cull() -> int:
	var removed: int = 0
	for i: int in range(police.size() - 1, -1, -1):
		var c: ArcadeCar = police[i]
		if not is_instance_valid(c):
			police.remove_at(i)
			continue
		if absf(_wrap(_progress_of(c) - _player_s)) > DESPAWN_M:
			police.remove_at(i)
			_hints.erase(c)
			c.queue_free()
			removed += 1
	return removed


## Places barriers ahead of the player. Only meaningful at heat 3+ (PursuitState.can_request_roadblock is the gate
## in step). Returns false when one is already up or no safe spot exists.
func try_roadblock() -> bool:
	if roadblock != null or _track == null or player == null:
		return false
	for dist: float in ROADBLOCK_AHEAD_M:
		var rb: Roadblock = Roadblock.build(_track, _player_s + dist, _car_positions())
		if rb != null:
			add_child(rb)
			roadblock = rb
			_roadblock_cd = ROADBLOCK_COOLDOWN_S
			return true
	return false


func _finish() -> void:
	_active = false
	for c: ArcadeCar in police:
		var drv: AIDriver = c.get_node_or_null(DRIVER_NAME) as AIDriver
		if drv != null:
			drv.enabled = false
	if state.phase == PursuitState.Phase.ESCAPED:
		escape_reward = ESCAPE_REWARD_PER_HEAT * state.heat
		GameState.add_cash(escape_reward)
	_update_hud()


func _update_hud() -> void:
	if _hud == null:
		return
	_hud.set_heat(state.heat, PursuitState.MAX_HEAT)
	if state.phase == PursuitState.Phase.BUSTED:
		_hud.set_banner("BUSTED")
	elif state.phase == PursuitState.Phase.ESCAPED:
		_hud.set_banner("ESCAPED  +%d cash" % escape_reward)
	else:
		_hud.set_banner("")


func _process(delta: float) -> void:
	if police.is_empty() or _red == null:
		return
	_flash_t += delta
	var red_on: bool = int(_flash_t / LIGHT_FLASH_S) % 2 == 0
	_red.emission_energy_multiplier = 3.0 if red_on else 0.15
	_blue.emission_energy_multiplier = 0.15 if red_on else 3.0


func _progress_of(c: ArcadeCar) -> float:
	var hint: float = _hints.get(c, -1.0)
	var s: float = _track.get_progress(c.global_position, hint)
	_hints[c] = s
	return s


## Signed distance along the track, wrapped to half a lap either way.
func _wrap(d: float) -> float:
	var lap: float = _track.length
	return fposmod(d + lap * 0.5, lap) - lap * 0.5


func _spot_free(p: Vector3) -> bool:
	for c: ArcadeCar in _cars:
		if c.global_position.distance_to(p) < SPAWN_CLEAR_M:
			return false
	for c: ArcadeCar in police:
		if c.global_position.distance_to(p) < SPAWN_CLEAR_M:
			return false
	return true


func _car_positions() -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for c: ArcadeCar in _cars:
		out.append(c.global_position)
	for c: ArcadeCar in police:
		out.append(c.global_position)
	return out


## Preferred: the Istanbul sedan. Fallback: the first available catalog car, so a build without it still runs.
func _police_model() -> Dictionary:
	var scene_path: String = POLICE_SCENE
	var spec_path: String = POLICE_SPEC
	if not (ResourceLoader.exists(POLICE_SCENE) and ResourceLoader.exists(POLICE_SPEC)):
		var ids: Array[String] = CarCatalog.available_ids()
		if ids.is_empty():
			return {}
		scene_path = CarCatalog.scene_path(ids[0])
		spec_path = CarCatalog.spec_path(ids[0])
	var spec: CarSpec = load(spec_path) as CarSpec
	if spec == null:
		return {}
	return {"scene": scene_path, "spec": spec}


func _add_lights(car: ArcadeCar) -> void:
	var bar := Node3D.new()
	bar.name = "LightBar"
	bar.position = Vector3(0.0, _roof_y(car) + LIGHT_BAR_HALF_H_M, 0.0)
	car.add_child(bar)
	for side: float in [-1.0, 1.0]:
		var lamp := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.14, 0.22)
		lamp.mesh = box
		lamp.position = Vector3(LIGHT_BAR_X_M * side, 0.0, 0.0)
		lamp.material_override = _red if side < 0.0 else _blue
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar.add_child(lamp)


## Top of the car body meshes in car space, so the light bar sits on the roof of whichever model is used.
func _roof_y(car: ArcadeCar) -> float:
	var top: float = -INF
	var inv: Transform3D = car.global_transform.affine_inverse()
	for n: Node in car.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n as MeshInstance3D
		if m.mesh != null:
			top = maxf(top, (inv * m.global_transform * m.get_aabb()).end.y)
	return top if top > -INF else LIGHT_BAR_Y_M


func _lamp_material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour.darkened(0.7)
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = 3.0
	return m
