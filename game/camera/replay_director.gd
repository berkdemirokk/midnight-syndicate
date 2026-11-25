class_name ReplayDirector
extends RefCounted
## Replay camera direction. Trackside TV spots line both sides of the road, alternating low and high, placed
## from the Track API. The camera uses the spot nearest ahead of the player (MIN_AHEAD_M..MAX_AHEAD_M) with a
## long lens, and cuts when the player leaves that range or the spot loses its view. Every 20 s a 4 s chase or
## bumper insert is cut in (skipped when its view is blocked); the last 6 s orbit the finishing car. Ray tests
## run in the physics tick, so update() must be called from _physics_process.

enum Kind { TV, CHASE, BUMPER, ORBIT }

const SPOT_COUNT: int = 20
const SPOT_LOW_M: float = 1.0
const SPOT_HIGH_M: float = 5.0
const SPOT_HIGH_EVERY: int = 3  ## every third spot is high
const SPOT_SIDE_M: float = 5.0  ## beyond the drivable width
const MIN_AHEAD_M: float = 6.0  ## a spot stops being used when the player is closer than this
const MAX_AHEAD_M: float = 80.0  ## ...or further than this: spots sit about 65 m apart on a 1.3 km lap, so one covers the approach to the next
const LOOK_LEAD_S: float = 0.05  ## the aim leads the car by this much velocity
const LOOK_HEIGHT_M: float = 1.0
const TV_FOV_FAR_DEG: float = 30.0  ## lens at TV_FOV_RANGE_M
const TV_FOV_NEAR_DEG: float = 20.0  ## lens at the spot's closest range
const TV_FOV_RANGE_M: float = 25.0  ## the long lens reaches its far FOV at this range: nearer spots frame the car larger
const LENS_CLEAR_M: float = 3.0  ## no other car may be this close to a TV lens: a car passing the lens fills the frame
const VEHICLE_MASK: int = 2
const VIEW_LOW_M: float = 0.4  ## a second view ray at this height: low walls and railings must not hide the car
const CHASE_BACK_M: float = 6.0
const CHASE_UP_M: float = 2.2
const CHASE_FOV_DEG: float = 62.0
const BUMPER_FWD_M: float = 4.5
const BUMPER_SIDE_M: float = 2.4
const BUMPER_UP_M: float = 0.45  ## a bumper-height camera
const BUMPER_FOV_DEG: float = 58.0
const ORBIT_RADIUS_M: float = 9.0
const ORBIT_UP_M: float = 2.5
const ORBIT_RATE_RAD_S: float = 0.4
const ORBIT_FOV_DEG: float = 50.0
const ORBIT_TAIL_S: float = 6.0  ## the last seconds of the replay orbit the car
const INSERT_EVERY_S: float = 20.0
const INSERT_LEN_S: float = 4.0  ## 3 to 5 s, as the brief asks
const TRACK_RATE: float = 10.0  ## 1/s, how fast the aim follows the target when not cutting
const ORBIT_TRIES: int = 8  ## orbit angles tried per step; the first with a clear view of the car is used
## World (1) and vehicles (2): rival cars block views. The caller excludes only the player's own body.
const RAY_MASK: int = 3

var kind: int = Kind.TV
var pose: Transform3D = Transform3D.IDENTITY
var fov_deg: float = TV_FOV_FAR_DEG
var current_spot: int = -1
var cut_count: int = 0
var spot_positions: PackedVector3Array = PackedVector3Array()
var spot_progress: PackedFloat32Array = PackedFloat32Array()
var spot_road: PackedVector3Array = PackedVector3Array()  ## road point beside each spot: a clear ray from it proves the spot is not behind or inside geometry
var _length: float = 0.0
var _insert_until: float = -1.0
var _insert_kind: int = Kind.CHASE
var _next_insert_t: float = INSERT_EVERY_S
var _insert_count: int = 0
var _orbit_angle: float = 0.0
var _cut: bool = true
var _look_basis: Basis = Basis.IDENTITY
var _forced: int = -1  ## capture hook: a forced insert kind, or -1
var _forced_until: float = -1.0
var _query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()  ## reused: no allocation per tick
var _lens_shape: SphereShape3D = SphereShape3D.new()
var _lens_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()


## Builds the spots from the track. Call once per track.
func setup(track: Track) -> void:
	_length = track.length
	_lens_shape.radius = LENS_CLEAR_M
	_lens_query.shape_rid = _lens_shape.get_rid()
	_lens_query.collision_mask = VEHICLE_MASK
	spot_positions.resize(SPOT_COUNT)
	spot_road.resize(SPOT_COUNT)
	spot_progress.resize(SPOT_COUNT)
	for i: int in SPOT_COUNT:
		var s: float = (float(i) + 0.5) * _length / float(SPOT_COUNT)
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var height: float = SPOT_HIGH_M if i % SPOT_HIGH_EVERY == 0 else SPOT_LOW_M
		var tangent: Vector3 = track.get_tangent_at(s)
		tangent.y = 0.0
		tangent = tangent.normalized()
		var right: Vector3 = tangent.cross(Vector3.UP)
		var lateral: float = track.width * 0.5 + SPOT_SIDE_M
		spot_progress[i] = s
		spot_road[i] = track.get_point_at(s) + Vector3.UP * VIEW_LOW_M
		spot_positions[i] = spot_road[i] + right * side * lateral + Vector3.UP * (height - VIEW_LOW_M)


## Ahead distance of spot i from the player along the lap, wrapped to -L/2..L/2 (negative = passed).
func spot_ahead_m(i: int, player_s: float) -> float:
	var a: float = fposmod(spot_progress[i] - player_s, _length)
	if a > _length * 0.5:
		a -= _length
	return a


## True when the straight ray from `from` to `to` meets no world geometry or vehicle. hit_from_inside makes a
## start point inside a wall count as blocked, so a camera placed inside geometry is rejected.
func ray_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> bool:
	_query.from = from
	_query.to = to
	_query.collision_mask = RAY_MASK
	_query.exclude = exclude
	_query.hit_from_inside = true
	return space.intersect_ray(_query).is_empty()


## A spot is usable when the road beside it is in clear view of it (not behind a barrier or inside a building)
## and the car is in clear view from the spot.
func _spot_usable(space: PhysicsDirectSpaceState3D, i: int, car_pos: Vector3, exclude: Array[RID]) -> bool:
	return ray_clear(space, spot_road[i], spot_positions[i], exclude) and _view_clear(space, spot_positions[i], car_pos, exclude) and _lens_clear(space, spot_positions[i], exclude)


## No other car within LENS_CLEAR_M of the lens (the player is excluded).
func _lens_clear(space: PhysicsDirectSpaceState3D, lens: Vector3, exclude: Array[RID]) -> bool:
	_lens_query.transform = Transform3D(Basis.IDENTITY, lens)
	_lens_query.exclude = exclude
	return space.intersect_shape(_lens_query, 1).is_empty()


## The camera at `from` sees the car: clear rays to the car's upper and lower body.
func _view_clear(space: PhysicsDirectSpaceState3D, from: Vector3, car_pos: Vector3, exclude: Array[RID]) -> bool:
	return ray_clear(space, from, car_pos + Vector3.UP * LOOK_HEIGHT_M, exclude) and ray_clear(space, from, car_pos + Vector3.UP * VIEW_LOW_M, exclude)


## The spot nearest ahead of the player that is in range and has a clear view of the car, or -1.
func choose_spot(player_s: float, car_pos: Vector3, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> int:
	var best: int = -1
	var best_ahead: float = INF
	for i: int in SPOT_COUNT:
		var a: float = spot_ahead_m(i, player_s)
		if a < MIN_AHEAD_M or a > MAX_AHEAD_M or a >= best_ahead:
			continue
		if _spot_usable(space, i, car_pos, exclude):
			best = i
			best_ahead = a
	return best


## Capture hook: forces an insert (Kind.CHASE or Kind.BUMPER) from replay time now for `seconds`.
func force_insert(insert_kind: int, now_t: float, seconds: float) -> void:
	_forced = insert_kind
	_forced_until = now_t + seconds


## One director step at replay time t. car_xf is the player's pose, car_vel its velocity, progress its lap
## position, duration the replay length, dt the step. Call from _physics_process.
func update(t: float, duration: float, car_xf: Transform3D, car_vel: Vector3, progress: float, space: PhysicsDirectSpaceState3D, exclude: Array[RID], dt: float) -> void:
	var car_pos: Vector3 = car_xf.origin
	var next_kind: int = Kind.TV
	if t >= duration - ORBIT_TAIL_S:
		next_kind = _resolve_orbit(space, car_pos, exclude, dt)
	elif _forced >= 0 and t < _forced_until:
		next_kind = _forced
	elif _insert_until >= 0.0 and t < _insert_until:
		next_kind = _insert_kind
	else:
		_insert_until = -1.0
		_forced = -1
		if t >= _next_insert_t:
			_next_insert_t += INSERT_EVERY_S
			_insert_kind = Kind.CHASE if _insert_count % 2 == 0 else Kind.BUMPER
			_insert_count += 1
			_insert_until = t + INSERT_LEN_S
			next_kind = _insert_kind
	if next_kind == Kind.CHASE or next_kind == Kind.BUMPER:
		if not _view_clear(space, _insert_position(next_kind, car_xf), car_pos, exclude):
			_insert_until = -1.0  ## no clear view for this insert: skip it
			_forced = -1
			next_kind = Kind.TV
	var next_spot: int = -1
	if next_kind == Kind.TV:
		next_spot = current_spot
		if next_spot >= 0:
			var a: float = spot_ahead_m(next_spot, progress)
			if a < MIN_AHEAD_M or a > MAX_AHEAD_M or not _spot_usable(space, next_spot, car_pos, exclude):
				next_spot = -1
		if next_spot < 0:
			next_spot = choose_spot(progress, car_pos, space, exclude)
		if next_spot < 0:
			next_kind = Kind.CHASE  ## no spot has a view: a chase shot, never a wall-clipped camera
			if not _view_clear(space, _insert_position(Kind.CHASE, car_xf), car_pos, exclude):
				next_kind = Kind.BUMPER
	if next_spot != current_spot or next_kind != kind:
		if next_spot >= 0 and next_spot != current_spot:
			cut_count += 1
		_cut = true
	kind = next_kind
	current_spot = next_spot if kind == Kind.TV else -1
	_place(car_xf, car_vel, dt)


## Orbit step: the first angle (advancing from the last one) whose camera position has a clear view of the car.
## Returns ORBIT, or TV when no orbit angle is clear (the finishing car is then shot by a trackside spot or chase).
func _resolve_orbit(space: PhysicsDirectSpaceState3D, car_pos: Vector3, exclude: Array[RID], dt: float) -> int:
	var base: float = _orbit_angle + ORBIT_RATE_RAD_S * dt
	for k: int in ORBIT_TRIES:
		var a: float = base + float(k) * TAU / float(ORBIT_TRIES)
		if _view_clear(space, _orbit_point(car_pos, a), car_pos, exclude):
			_orbit_angle = fposmod(a, TAU)
			return Kind.ORBIT
	return Kind.TV


func _orbit_point(car_pos: Vector3, angle: float) -> Vector3:
	return car_pos + Vector3(cos(angle), 0.0, sin(angle)) * ORBIT_RADIUS_M + Vector3.UP * ORBIT_UP_M


## Camera position of a chase or bumper insert, from the car's pose.
func _insert_position(insert_kind: int, car_xf: Transform3D) -> Vector3:
	var fwd: Vector3 = -car_xf.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if insert_kind == Kind.BUMPER:
		return car_xf.origin + fwd * BUMPER_FWD_M + car_xf.basis.x * BUMPER_SIDE_M + Vector3.UP * BUMPER_UP_M
	return car_xf.origin - fwd * CHASE_BACK_M + Vector3.UP * CHASE_UP_M


func _place(car_xf: Transform3D, car_vel: Vector3, dt: float) -> void:
	var car_pos: Vector3 = car_xf.origin
	var target: Vector3 = car_pos + Vector3.UP * LOOK_HEIGHT_M + car_vel * LOOK_LEAD_S
	var pos: Vector3
	match kind:
		Kind.TV:
			pos = spot_positions[current_spot]
			var dist: float = pos.distance_to(car_pos)
			var k: float = clampf(1.0 - dist / TV_FOV_RANGE_M, 0.0, 1.0)
			fov_deg = lerpf(TV_FOV_FAR_DEG, TV_FOV_NEAR_DEG, k)
		Kind.CHASE:
			pos = _insert_position(Kind.CHASE, car_xf)
			fov_deg = CHASE_FOV_DEG
		Kind.BUMPER:
			pos = _insert_position(Kind.BUMPER, car_xf)
			target = car_pos + Vector3.UP * BUMPER_UP_M
			fov_deg = BUMPER_FOV_DEG
		_:
			pos = _orbit_point(car_pos, _orbit_angle)
			target = car_pos + Vector3.UP * LOOK_HEIGHT_M
			fov_deg = ORBIT_FOV_DEG
	var goal: Basis = Basis.looking_at(target - pos, Vector3.UP)
	if _cut:
		_look_basis = goal
		_cut = false
	else:
		var k2: float = 1.0 - exp(-TRACK_RATE * dt)
		_look_basis = Basis(Quaternion(_look_basis).slerp(Quaternion(goal), k2).normalized())
	pose = Transform3D(_look_basis, pos)
