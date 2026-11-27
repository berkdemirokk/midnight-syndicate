class_name NetRaceAuthority
extends RefCounted
## Server-side race truth. Lap progress comes from validated car positions on the track (Track.get_progress),
## laps and finish order from the server clock only. Clients never send progress, laps or times.
## Pure logic: no nodes, no network. Unit tested with a real Track (game/tests/test_net_race.gd).

const PROGRESS_JUMP_M: float = 25.0  ## largest believable progress change in one tick, plus speed * dt
const CREDIT_BURST_S: float = 0.5  ## forward credit can bank this many seconds at MAX_SPEED_MS (late or bunched states)

class NetDriver extends RefCounted:
	var pid: int = 0
	var display_name: String = ""
	var grid: int = 0
	var has_state: bool = false
	var last_state: Dictionary = {}  ## last accepted state (see NetProtocol.make_state)
	var last_t: float = 0.0  ## race clock of the last accepted state
	var progress: float = 0.0  ## metres along the line, last sample
	var distance: float = 0.0  ## metres along the race, unwrapped
	var finished: bool = false
	var finish_seq: int = 0
	var finish_t: float = -1.0
	var dnf: bool = false
	var dnf_reason: String = ""
	var progress_jumps: int = 0  ## track samples that moved the car implausibly far in one tick (ignored)
	var credit_budget: float = 0.0  ## metres of forward distance the server may still credit (refills at MAX_SPEED_MS)

	func racing() -> bool:
		return not finished and not dnf


var race_t: float = 0.0  ## server race clock in seconds, 0 at GO
var total_laps: int = 1

var _track: Track
var _drivers: Dictionary = {}  ## pid -> NetDriver, join order
var _finish_seq: int = 0
var _first_finish_t: float = -1.0


## grid: pid -> grid index (0..7). Positions are read from the track's grid transforms.
func setup(track: Track, laps: int, names: Dictionary, grid: Dictionary) -> void:
	_track = track
	total_laps = maxi(laps, 1)
	race_t = 0.0
	_drivers.clear()
	_finish_seq = 0
	_first_finish_t = -1.0
	for pid: int in grid:
		var d := NetDriver.new()
		d.pid = pid
		d.display_name = str(names.get(pid, "Driver %d" % pid))
		d.grid = int(grid[pid])
		var origin: Vector3 = _track.get_grid_transform(d.grid).origin
		d.progress = _track.get_progress(origin)
		d.distance = d.progress if d.progress <= _track.length * 0.5 else d.progress - _track.length
		_drivers[pid] = d


func has_driver(pid: int) -> bool:
	return _drivers.has(pid)


func driver(pid: int) -> NetDriver:
	return _drivers.get(pid) as NetDriver


## "" when accepted. Rejected states leave the driver's last accepted state unchanged.
func is_racing(pid: int) -> bool:
	var d: NetDriver = driver(pid)
	return d != null and d.racing()


## "" when accepted. Rejected states leave the driver's last accepted state unchanged.
func submit(pid: int, st: Dictionary, reset: bool = false) -> String:
	var d: NetDriver = driver(pid)
	if d == null or not d.racing():
		return "not racing"
	# A flagged reset (R key, respawn) may move the car anywhere, and the sequence and speed checks still apply.
	var reason: String = NetProtocol.validate_state(d.last_state, st, race_t - d.last_t, reset)
	if reason != "":
		return reason
	if reset and d.has_state:
		# Progress follows the new spot, but a reset never adds distance: a forward reset gains nothing and a
		# backward one takes metres back. Repeated resets therefore cannot shorten a lap.
		var p: float = _track.get_progress((st["xf"] as Transform3D).origin, d.progress)
		d.distance += minf(_wrap_signed(p - d.progress), 0.0)
		d.progress = p
	d.last_state = st
	d.last_t = race_t
	d.has_state = true
	return ""


## Advances the race clock and the cars' progress. Call once per frame while racing.
func tick(dt: float) -> void:
	race_t += dt
	for pid: int in _drivers:
		var d: NetDriver = _drivers[pid]
		if not d.racing() or not d.has_state:
			continue
		var xf: Transform3D = d.last_state["xf"]
		var p: float = _track.get_progress(xf.origin, d.progress)
		var step: float = _wrap_signed(p - d.progress)
		if absf(step) > PROGRESS_JUMP_M + 2.0 * NetConfig.MAX_SPEED_MS * dt:
			_count_jump(d)  ## a bad projection, not a car: keep the last good progress
			continue
		# Forward credit never outruns MAX_SPEED_MS on the server clock, whatever speed the states claim
		# (the per-state teleport limit alone allows bursts well above it at the rate cap).
		d.credit_budget = minf(d.credit_budget + NetConfig.MAX_SPEED_MS * dt, NetConfig.MAX_SPEED_MS * CREDIT_BURST_S)
		if step > 0.0:
			step = minf(step, d.credit_budget)
			d.credit_budget -= step
		d.distance += step
		d.progress = p
		if d.distance >= float(total_laps) * _track.length:
			_finish(d)
	if _first_finish_t >= 0.0 and race_t >= _first_finish_t + NetConfig.FINISH_WAIT_S:
		for pid: int in _drivers:
			var rest: NetDriver = _drivers[pid]
			if rest.racing():
				mark_dnf(pid, "time limit after the first finish")


func mark_dnf(pid: int, reason: String) -> void:
	var d: NetDriver = driver(pid)
	if d == null or not d.racing():
		return
	d.dnf = true
	d.dnf_reason = reason


func all_over() -> bool:
	for pid: int in _drivers:
		if (_drivers[pid] as NetDriver).racing():
			return false
	return true


## Finished cars by finish order, then running cars by distance, then DNF. Position is 1-based.
func results() -> Array[Dictionary]:
	var order: Array[NetDriver] = []
	for pid: int in _drivers:
		order.append(_drivers[pid])
	order.sort_custom(_rank)
	var out: Array[Dictionary] = []
	for i: int in order.size():
		var d: NetDriver = order[i]
		out.append({
			"pid": d.pid,
			"name": d.display_name,
			"position": i + 1,
			"finished": d.finished,
			"dnf": d.dnf,
			"time": d.finish_t,
			"distance": d.distance,
			"progress_jumps": d.progress_jumps,
		})
	return out


## Too many bad projections in one race means the car cannot be placed honestly: DNF, with the reason in the results.
func _count_jump(d: NetDriver) -> void:
	d.progress_jumps += 1
	if d.progress_jumps == NetConfig.MAX_PROGRESS_JUMPS:
		mark_dnf(d.pid, "track projection failed")


func _finish(d: NetDriver) -> void:
	d.finished = true
	_finish_seq += 1
	d.finish_seq = _finish_seq
	d.finish_t = race_t
	if _first_finish_t < 0.0:
		_first_finish_t = race_t


func _rank(a: NetDriver, b: NetDriver) -> bool:
	var ra: int = _rank_group(a)
	var rb: int = _rank_group(b)
	if ra != rb:
		return ra < rb
	if a.finished:
		return a.finish_seq < b.finish_seq
	return a.distance > b.distance


func _rank_group(d: NetDriver) -> int:
	if d.finished:
		return 0
	if not d.dnf:
		return 1
	return 2


func _wrap_signed(delta_m: float) -> float:
	var half: float = _track.length * 0.5
	return fposmod(delta_m + half, _track.length) - half
