class_name RaceManager
extends Node
## Race state machine GRID -> COUNTDOWN -> RACING -> FINISHED on a Track. Places cars on the grid,
## counts laps through 4 virtual gates (25/50/75/100 % of the line, passed in order), ranks cars by
## distance and finish order, and ends the race when the player finishes (rest get finish_wait_s)
## or when everyone has finished. Public names, types and signals are a contract (HUD and menus).

signal countdown_tick(seconds_left: int)  ## 3, 2, 1, then 0 = GO
signal race_started
signal lap_completed(car: ArcadeCar, lap: int, lap_time: float)
signal position_changed(car: ArcadeCar, position: int)  ## 1-based
signal race_finished(results: Array[Dictionary])  ## sorted; keys: car, name, position, total_time, best_lap, is_player
signal wrong_way_changed(is_wrong: bool)  ## player only

enum State { GRID, COUNTDOWN, RACING, FINISHED }

const GATE_COUNT: int = 4  ## virtual gates per lap; the last one is the start/finish line
const MIN_ESTIMATE_FRACTION: float = 0.05  ## floor for progress used in the finish time estimate

class Racer extends RefCounted:
	var car: ArcadeCar
	var display_name: String = ""
	var is_player: bool = false
	var progress: float = 0.0  ## metres along the line, last sample
	var distance: float = 0.0  ## metres along the race, unwrapped; grid slots are negative
	var seg: int = 0  ## quarter of the line the car is in
	var driver: AIDriver = null  ## null for the player
	var gates: int = 0  ## gates passed in order in the current lap
	var laps: int = 0  ## completed laps
	var lap_start: float = 0.0
	var best_lap: float = 0.0
	var finished: bool = false
	var finish_seq: int = 0
	var total_time: float = 0.0
	var place: int = 0

@export var total_laps: int = 3
@export var countdown_seconds: int = 3
@export var finish_wait_s: float = 15.0  ## after the player finishes, the rest may run this long
@export var wrong_way_speed_ms: float = 3.0  ## m/s backwards along the line
@export var wrong_way_time_s: float = 0.5

var state: State = State.GRID
var race_time: float = 0.0
var player_car: ArcadeCar

var _track: Track
var _racers: Array[Racer] = []
var _order: Array[Racer] = []
var _player: Racer
var _countdown_t: float = 0.0
var _last_tick: int = 0
var _finish_deadline: float = -1.0
var _finish_seq: int = 0
var _wrong_t: float = 0.0
var _wrong: bool = false
var _by_order_cmp: Callable = _by_order  ## kept as a member so sort_custom does not allocate each tick


## Register cars before start_countdown(). The track node follows the Track contract.
## Cars are placed on the grid in the order given, frozen, and every non-player car gets an AIDriver
## with its own noise seed (its grid slot). Calling setup again resets the race.
func setup(track: Node3D, cars: Array[ArcadeCar], player: ArcadeCar, driver_names: PackedStringArray) -> void:
	_track = track as Track
	if _track == null:
		push_error("RaceManager.setup needs a Track")
		return
	player_car = player
	_racers.clear()
	_order.clear()
	_player = null
	state = State.GRID
	race_time = 0.0
	_countdown_t = 0.0
	_last_tick = 0
	_finish_deadline = -1.0
	_finish_seq = 0
	_wrong_t = 0.0
	if _wrong:
		_wrong = false
		wrong_way_changed.emit(false)
	for i: int in cars.size():
		var car: ArcadeCar = cars[i]
		var r := Racer.new()
		r.car = car
		r.display_name = driver_names[i] if i < driver_names.size() else "Driver %d" % (i + 1)
		r.is_player = car == player
		if r.is_player:
			_player = r
		_racers.append(r)
		_order.append(r)
		var xf: Transform3D = _track.get_grid_transform(i)
		car.reset_to(xf)
		car.set_frozen_for_grid(true)
		r.progress = _track.get_progress(xf.origin)
		r.seg = _segment_of(r.progress)
		r.distance = r.progress - _track.length if r.progress > _track.length * 0.5 else r.progress
		r.place = i + 1
	for i: int in _racers.size():
		var r: Racer = _racers[i]
		if r.is_player:
			continue
		r.driver = _ai_driver(r.car)
		r.driver.noise_seed = i + 1
		r.driver.setup(_track)
		r.driver.set_traffic(cars)
	set_physics_process(false)


func start_countdown() -> void:
	if state != State.GRID or _track == null:
		push_warning("RaceManager.start_countdown ignored: state %d, call setup first" % state)
		return
	state = State.COUNTDOWN
	_countdown_t = 0.0
	_last_tick = countdown_seconds
	countdown_tick.emit(countdown_seconds)
	set_physics_process(true)


func get_position(car: ArcadeCar) -> int:  ## 1-based, 0 for a car not in the race
	var r: Racer = _racer_of(car)
	return r.place if r != null else 0


func get_lap(car: ArcadeCar) -> int:  ## 1-based current lap, clamped to total_laps
	var r: Racer = _racer_of(car)
	if r == null:
		return 1
	return clampi(r.laps + 1, 1, maxi(total_laps, 1))


func get_current_lap_time(car: ArcadeCar) -> float:
	var r: Racer = _racer_of(car)
	if r == null or state != State.RACING or r.finished:
		return 0.0
	return race_time - r.lap_start


func get_best_lap_time(car: ArcadeCar) -> float:  ## 0.0 when no lap finished
	var r: Racer = _racer_of(car)
	return r.best_lap if r != null else 0.0


func get_car_count() -> int:
	return _racers.size()


## Place order for the HUD leaderboard: car, name, place (1-based) and unwrapped race distance in metres.
func get_standings() -> Array:
	var out: Array = []
	for r: Racer in _order:
		out.append({"car": r.car, "name": r.display_name, "place": r.place, "distance": r.distance})
	return out


## 0..1 progress of a car around the current lap, for the minimap and gap display.
func get_lap_progress(car: ArcadeCar) -> float:
	var r: Racer = _racer_of(car)
	if r == null or _track == null or _track.length <= 0.0:
		return 0.0
	return clampf(r.distance - float(r.laps) * _track.length, 0.0, _track.length) / _track.length


func _physics_process(delta: float) -> void:
	if state == State.COUNTDOWN:
		_tick_countdown(delta)
	elif state == State.RACING:
		_tick_race(delta)


func _tick_countdown(delta: float) -> void:
	_countdown_t += delta
	var left: int = countdown_seconds - int(_countdown_t)
	if left <= 0:
		_go()
	elif left < _last_tick:
		_last_tick = left
		countdown_tick.emit(left)


func _go() -> void:
	state = State.RACING
	race_time = 0.0
	_last_tick = 0
	countdown_tick.emit(0)
	for r: Racer in _racers:
		r.car.set_frozen_for_grid(false)
		r.lap_start = 0.0
		if r.driver != null:
			r.driver.set_racing(true)
	race_started.emit()


func _tick_race(delta: float) -> void:
	race_time += delta
	for r: Racer in _racers:
		_update_progress(r)
	if _player != null:
		for r: Racer in _racers:
			if r.driver != null:
				r.driver.set_reference_gap(_player.distance - r.distance)
	_update_wrong_way(delta)
	_update_places()
	_check_finish()


func _update_progress(r: Racer) -> void:
	var p: float = _track.get_progress(r.car.global_position, r.progress)
	r.distance += _wrap_signed(p - r.progress)
	r.progress = p
	var seg: int = _segment_of(p)
	if seg != r.seg:
		# Only a forward step into the next quarter counts; reversing never passes a gate.
		if seg == posmod(r.seg + 1, GATE_COUNT):
			_cross_gate(r, r.seg)
		r.seg = seg


## Gate k is the boundary from quarter k to quarter k+1; gate 3 is the start/finish line.
func _cross_gate(r: Racer, k: int) -> void:
	if k != r.gates:
		return  # out of order, or the grid line before the first lap
	r.gates += 1
	if r.gates < GATE_COUNT:
		return
	r.gates = 0
	r.laps += 1
	var lap_time: float = race_time - r.lap_start
	r.lap_start = race_time
	if r.best_lap <= 0.0 or lap_time < r.best_lap:
		r.best_lap = lap_time
	lap_completed.emit(r.car, r.laps, lap_time)
	if r.laps >= total_laps:
		_finish(r)


func _finish(r: Racer) -> void:
	if r.finished:
		return
	r.finished = true
	_finish_seq += 1
	r.finish_seq = _finish_seq
	r.total_time = race_time
	if r.is_player:
		if _finish_deadline < 0.0:
			_finish_deadline = race_time + finish_wait_s
	elif r.driver != null:
		r.driver.set_racing(false)


func _check_finish() -> void:
	var all_done: bool = true
	for r: Racer in _racers:
		if not r.finished:
			all_done = false
			break
	if all_done or (_finish_deadline >= 0.0 and race_time >= _finish_deadline):
		_end_race()


func _end_race() -> void:
	state = State.FINISHED
	set_physics_process(false)
	var total_distance: float = float(total_laps) * _track.length
	for r: Racer in _racers:
		if not r.finished:
			# Time estimated from progress: the average pace so far, extended to the full distance.
			var done: float = maxf(r.distance, _track.length * MIN_ESTIMATE_FRACTION)
			r.total_time = race_time * total_distance / done
			if r.driver != null:
				r.driver.set_racing(false)
	var order: Array[Racer] = []
	for r: Racer in _racers:
		order.append(r)
	order.sort_custom(_by_time)
	var results: Array[Dictionary] = []
	for i: int in order.size():
		var r: Racer = order[i]
		r.place = i + 1
		results.append({
			"car": r.car,
			"name": r.display_name,
			"position": i + 1,
			"total_time": r.total_time,
			"best_lap": r.best_lap,
			"is_player": r.is_player,
		})
	race_finished.emit(results)


func _update_places() -> void:
	_order.sort_custom(_by_order_cmp)
	for i: int in _order.size():
		var r: Racer = _order[i]
		var place: int = i + 1
		if r.place != place:
			r.place = place
			position_changed.emit(r.car, place)


func _update_wrong_way(delta: float) -> void:
	if _player == null:
		return
	var tangent: Vector3 = _track.get_tangent_at(_player.progress)
	var backwards: bool = player_car.linear_velocity.dot(tangent) < -wrong_way_speed_ms
	_wrong_t = _wrong_t + delta if backwards else 0.0
	var now_wrong: bool = _wrong_t >= wrong_way_time_s
	if now_wrong != _wrong:
		_wrong = now_wrong
		wrong_way_changed.emit(_wrong)


func _by_order(a: Racer, b: Racer) -> bool:
	if a.finished != b.finished:
		return a.finished
	if a.finished:
		return a.finish_seq < b.finish_seq
	return a.distance > b.distance


func _by_time(a: Racer, b: Racer) -> bool:
	return a.total_time < b.total_time


func _segment_of(p: float) -> int:
	return clampi(int(p / (_track.length / float(GATE_COUNT))), 0, GATE_COUNT - 1)


func _wrap_signed(d: float) -> float:
	var half: float = _track.length * 0.5
	return fposmod(d + half, _track.length) - half


func _racer_of(car: ArcadeCar) -> Racer:
	for r: Racer in _racers:
		if r.car == car:
			return r
	return null


func _ai_driver(car: ArcadeCar) -> AIDriver:
	var d: AIDriver = car.get_node_or_null("AIDriver") as AIDriver
	if d == null:
		d = AIDriver.new()
		d.name = "AIDriver"
		car.add_child(d)
	return d
