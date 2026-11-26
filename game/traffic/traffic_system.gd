class_name TrafficSystem
extends Node3D
## Ambient civilian traffic. Keeps a fixed number of Arden Civic sedans driving on the outer lanes of the track:
## the right lane with the race direction, the left lane against it (oncoming_fraction of the cars). They follow
## each other and the race cars at a safe gap, ease toward the kerb when a faster race car closes in, light their
## brake lamps, and are pushed (TrafficCar) when a race car touches them. Cars that fall behind the player or end
## up lost are respawned ahead of the player, never near a race car, so the grid and the AI are left alone.
## Usage: var t := TrafficSystem.new(); world.add_child(t); t.setup(track, player, race_cars)
## The count follows the graphics preset (Low 6, Medium 10, High 14) unless count_override >= 0.

const COUNT_LOW: int = 6
const COUNT_MEDIUM: int = 10
const COUNT_HIGH: int = 14
const LANE_LAT_M: float = 5.0  ## lane centre from the racing line; the kerb is at 7 m, car half width 0.9
const LANE_NUDGE_M: float = 0.8  ## extra move to the kerb when a race car closes in from behind
const LANE_MAX_M: float = 5.7
const SPAWN_MIN_AHEAD_M: float = 110.0  ## ahead of the player
const SPAWN_MAX_AHEAD_M: float = 620.0
const SPAWN_RACER_CLEAR_M: float = 100.0  ## no spawn within this distance of any race car, either way
const SPAWN_LANE_CLEAR_M: float = 35.0  ## same-lane spacing at spawn
const DESPAWN_BEHIND_M: float = 90.0
const DESPAWN_AHEAD_M: float = 720.0
const LOST_TIME_S: float = 3.0
const SPAWN_TRIES: int = 16
const WARMUP_TICKS: int = 3
const CRUISE_MIN_MS: float = 9.0
const CRUISE_MAX_MS: float = 15.0
const CORNER_LAT_ACCEL: float = 3.0  ## m/s^2: v = sqrt(a / curvature)
const CORNER_LOOK_M: float = 20.0
const FOLLOW_RANGE_M: float = 32.0
const FOLLOW_GAP_M: float = 9.0  ## stop gap, bumper to bumper plus the car length
const FOLLOW_GAIN: float = 0.5
const LANE_OVERLAP_M: float = 2.4
const YIELD_RANGE_M: float = 55.0
const YIELD_CLOSING_MS: float = 6.0

@export var count_override: int = -1  ## >= 0 sets the car count regardless of the preset
@export_range(0.0, 1.0) var oncoming_fraction: float = 0.35
@export var seed_value: int = 11
@export var headlights: bool = true:
	set(v):
		headlights = v
		for c: TrafficCar in cars:
			c.set_headlights(v)

var cars: Array[TrafficCar] = []
var track: Track
var player: Node3D
var race_cars: Array[ArcadeCar] = []
var respawns: int = 0
var hit_count: int = 0

var _rng := RandomNumberGenerator.new()
var _race_s: PackedFloat32Array = PackedFloat32Array()
var _race_v: PackedFloat32Array = PackedFloat32Array()  ## m/s along the race direction
var _player_s: float = 0.0
var _lost_t: Dictionary = {}
var _warmup: int = 0


static func count_for_preset(preset_id: String) -> int:
	match preset_id:
		"low":
			return COUNT_LOW
		"high":
			return COUNT_HIGH
	return COUNT_MEDIUM


func target_count() -> int:
	return count_override if count_override >= 0 else count_for_preset(Settings.get_preset_id())


func setup(track_in: Track, player_in: Node3D, race_cars_in: Array[ArcadeCar]) -> void:
	track = track_in
	player = player_in
	race_cars = race_cars_in
	_rng.seed = seed_value
	_race_s.resize(race_cars.size())
	_race_v.resize(race_cars.size())
	_warmup = WARMUP_TICKS
	for i: int in target_count():
		var c := TrafficCar.new()
		c.name = "TrafficCar%d" % i
		var oncoming: bool = _rng.randf() < oncoming_fraction
		c.dir = -1 if oncoming else 1
		c.lat = _lane_lat(oncoming)
		c.cruise = _rng.randf_range(CRUISE_MIN_MS, CRUISE_MAX_MS)
		c.hit_cb = _on_car_hit
		add_child(c)
		c.build_visual(_rng.randi_range(0, TrafficModels.paint_count() - 1))
		c.set_headlights(headlights)
		cars.append(c)


## The race manager places the cars on the grid during its setup, but the bodies only move a physics tick later:
## the first spawn waits WARMUP_TICKS so that clearances are measured from the real grid.
func _initial_spawn() -> void:
	_update_race_cars()
	for i: int in cars.size():
		var frac: float = (float(i) + 0.5) / float(cars.size())
		_spawn(cars[i], SPAWN_MIN_AHEAD_M + frac * (SPAWN_MAX_AHEAD_M - SPAWN_MIN_AHEAD_M))
	respawns = 0


func _lane_lat(oncoming: bool) -> float:
	var half: float = minf(LANE_LAT_M, track.width * 0.5 - 2.0)
	return -half if oncoming else half


func _physics_process(delta: float) -> void:
	if track == null or cars.is_empty():
		return
	if _warmup > 0:
		_warmup -= 1
		if _warmup == 0:
			_initial_spawn()
		return
	_update_race_cars()
	for c: TrafficCar in cars:
		if not c.placed:  # no free spot yet: retry every tick
			_spawn(c, SPAWN_MIN_AHEAD_M + _rng.randf() * (SPAWN_MAX_AHEAD_M - SPAWN_MIN_AHEAD_M))
			continue
		var lat_target: float = c.lat
		var want: float = _corner_speed(c)
		for o: TrafficCar in cars:
			if o != c:
				want = minf(want, _follow_limit(c, o.s, o.speed * float(o.dir), o.lat))
		for i: int in race_cars.size():
			want = minf(want, _follow_limit(c, _race_s[i], _race_v[i], _lat_of(race_cars[i], _race_s[i])))
			lat_target += _yield_nudge(c, i)
		c.drive(track, delta, want, clampf(lat_target, -LANE_MAX_M, LANE_MAX_M))
		_check_respawn(c, delta)


func _update_race_cars() -> void:
	_player_s = _progress_of(player, _player_s)
	for i: int in race_cars.size():
		var car: ArcadeCar = race_cars[i]
		_race_s[i] = _progress_of(car, _race_s[i])
		_race_v[i] = car.linear_velocity.dot(track.get_tangent_at(_race_s[i]))


func _progress_of(n: Node3D, hint: float) -> float:
	if n == null:
		return 0.0
	return track.get_progress(n.global_position, hint)


func _lat_of(n: Node3D, s: float) -> float:
	return track.get_lateral_offset(n.global_position, s)


func _wrap(d: float) -> float:
	return fposmod(d + track.length * 0.5, track.length) - track.length * 0.5


func _corner_speed(c: TrafficCar) -> float:
	var curv: float = absf(track.get_curvature(c.s + float(c.dir) * CORNER_LOOK_M))
	return minf(c.cruise, sqrt(CORNER_LAT_ACCEL / maxf(curv, 1e-4)))


## Speed cap behind a car at progress o_s with speed o_v along c's direction in lane o_lat.
func _follow_limit(c: TrafficCar, o_s: float, o_v: float, o_lat: float) -> float:
	var ahead: float = _wrap(o_s - c.s) * float(c.dir)
	if ahead <= 0.0 or ahead > FOLLOW_RANGE_M or absf(o_lat - c.lat) > LANE_OVERLAP_M:
		return INF
	var lead_v: float = o_v * float(c.dir)
	return maxf(0.0, lead_v + (ahead - FOLLOW_GAP_M) * FOLLOW_GAIN)


## Lateral move away from the racing line when a faster race car comes up behind in the same lane band.
func _yield_nudge(c: TrafficCar, i: int) -> float:
	var behind: float = -_wrap(_race_s[i] - c.s) * float(c.dir)
	if behind <= 0.0 or behind > YIELD_RANGE_M:
		return 0.0
	var closing: float = _race_v[i] * float(c.dir) - c.speed
	if closing < YIELD_CLOSING_MS:
		return 0.0
	return signf(c.lat) * LANE_NUDGE_M


func _check_respawn(c: TrafficCar, delta: float) -> void:
	var d: float = _wrap(c.s - _player_s)
	var lost: bool = c.lane_err > TrafficCar.LOST_LAT_M or absf(c.global_position.y - track.get_point_at(c.s).y) > 3.0
	if lost:
		_lost_t[c] = float(_lost_t.get(c, 0.0)) + delta
	else:
		_lost_t.erase(c)
	if d < -DESPAWN_BEHIND_M or d > DESPAWN_AHEAD_M or float(_lost_t.get(c, 0.0)) > LOST_TIME_S:
		_lost_t.erase(c)
		_spawn(c, SPAWN_MIN_AHEAD_M + _rng.randf() * (SPAWN_MAX_AHEAD_M - SPAWN_MIN_AHEAD_M) * 0.6)
		respawns += 1


## Places c at offset ahead of the player or the nearest free spot after it. Gives up (car stays) after SPAWN_TRIES.
func _spawn(c: TrafficCar, ahead_m: float) -> bool:
	for k: int in SPAWN_TRIES:
		var try_ahead: float = ahead_m + float(k) * 23.0
		if try_ahead > SPAWN_MAX_AHEAD_M:
			try_ahead = SPAWN_MIN_AHEAD_M + _rng.randf() * (SPAWN_MAX_AHEAD_M - SPAWN_MIN_AHEAD_M)
		var s: float = fposmod(_player_s + try_ahead, track.length)
		if is_spawn_free(s, c):
			c.place(track, s)
			return true
	return false


## True when no race car is within SPAWN_RACER_CLEAR_M and no other car is within the lane spacing of s.
func is_spawn_free(s: float, me: TrafficCar) -> bool:
	for rs: float in _race_s:
		if absf(_wrap(rs - s)) < SPAWN_RACER_CLEAR_M:
			return false
	for o: TrafficCar in cars:
		if o != me and o.placed and o.dir == me.dir and absf(_wrap(o.s - s)) < SPAWN_LANE_CLEAR_M:
			return false
	return true


func _on_car_hit(_c: TrafficCar) -> void:
	hit_count += 1
