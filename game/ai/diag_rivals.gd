extends SceneTree
## Rival metrics (diagnostic, not a test). One race of N AI cars on city_01, Bogaz or Maslak. Car 0 is the scripted
## player line: an AIDriver at skill[0] that RaceManager counts as the player (it drives the rubber band). Prints one line
## "RIVALS {json}": overtakes (order flips of any pair, and those with car 0), follow share (car-ticks with a car
## ahead in our lane within follow range), side-by-side pair-seconds, car contacts, stuck recoveries, teleports
## (reset-like jumps), and the finish spread.
## godot --headless --fixed-fps 60 --audio-driver Dummy --path game -s res://ai/diag_rivals.gd -- --track=bogaz --seed=1 --skills=1.0,0.95,0.9

const TRACKS: Dictionary = {
	"city": "res://world/city_01/city_01.tscn",
	"bogaz": "res://world/istanbul_bogaz/istanbul_bogaz.tscn",
	"maslak": "res://world/istanbul_maslak/istanbul_maslak.tscn",
}
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const MAX_TICKS: int = 60 * 400
const PAIR_RANGE_M: float = 80.0  ## m of race distance: pairs farther apart do not count as overtakes
const PAIR_FLIP_M: float = 2.0  ## m of race distance a pair must differ by before its order counts
const FOLLOW_M: float = 15.0  ## m: a car this close ahead in our lane means we follow
const FOLLOW_LAT_M: float = 2.5  ## m, lateral distance that counts as our lane
const SBS_ALONG_M: float = 7.0  ## m: alongside means overlapping longitudinally
const SBS_LAT_MIN_M: float = 2.0  ## and laterally between these (not overlapping, so not contact)
const SBS_LAT_MAX_M: float = 3.6
const TELEPORT_M: float = 5.0  ## m moved in one tick
const STATE_RACING: int = 2  ## RaceManager.State.RACING
const STATE_FINISHED: int = 3  ## RaceManager.State.FINISHED


class Monitor extends Node:
	var city: Track
	var manager: RaceManager
	var cars: Array[ArcadeCar] = []
	var drivers: Array[AIDriver] = []
	var skills: PackedFloat32Array = PackedFloat32Array()
	var half_len: float = 0.0
	var track_len: float = 0.0
	var prog: PackedFloat32Array = PackedFloat32Array()
	var race_m: PackedFloat32Array = PackedFloat32Array()
	var last_pos: Array[Vector3] = []
	var pair_sign: Dictionary = {}
	var touching: Dictionary = {}
	var overtakes: int = 0
	var overtakes_player: int = 0
	var follow_ticks: int = 0
	var car_ticks: int = 0
	var sbs_ticks: int = 0
	var contacts: int = 0
	var teleports: int = 0
	var racing_ticks: int = 0
	var tick: int = 0
	var results: Array = []
	var done: bool = false
	var timed_out: bool = false

	func _physics_process(_delta: float) -> void:
		if done:
			return
		tick += 1
		var st: int = int(manager.state)
		if st == STATE_FINISHED:
			_emit()
			return
		if st != STATE_RACING:
			return
		racing_ticks += 1
		if tick > MAX_TICKS:
			timed_out = true
			_emit()
			return
		var n: int = cars.size()
		var first: bool = racing_ticks == 1
		for i: int in n:
			var pos: Vector3 = cars[i].global_position
			var s: float = city.get_progress(pos, prog[i])
			if not first:
				var step: float = fposmod(s - prog[i] + half_len, track_len) - half_len
				race_m[i] += step
				if pos.distance_to(last_pos[i]) > TELEPORT_M:
					teleports += 1
			prog[i] = s
			last_pos[i] = pos
		if first:
			return
		var lat: PackedFloat32Array = PackedFloat32Array()
		lat.resize(n)
		for i: int in n:
			lat[i] = _lat(cars[i].global_position, prog[i])
		for i: int in n:
			car_ticks += 1
			for j: int in n:
				if j == i:
					continue
				var along: float = fposmod(prog[j] - prog[i] + half_len, track_len) - half_len
				if along > 0.0 and along <= FOLLOW_M and absf(lat[j] - lat[i]) < FOLLOW_LAT_M:
					follow_ticks += 1
					break
		for i: int in n:
			for j: int in range(i + 1, n):
				var dm: float = race_m[i] - race_m[j]
				var key: String = "%d-%d" % [i, j]
				if absf(dm) <= PAIR_RANGE_M and absf(dm) > PAIR_FLIP_M:
					var sg: int = 1 if dm > 0.0 else -1
					var prev: int = int(pair_sign.get(key, 0))
					if prev != 0 and prev != sg:
						overtakes += 1
						if i == 0 or j == 0:
							overtakes_player += 1
					pair_sign[key] = sg
				var along_ij: float = fposmod(prog[j] - prog[i] + half_len, track_len) - half_len
				var dlat: float = absf(lat[j] - lat[i])
				if absf(along_ij) < SBS_ALONG_M and dlat >= SBS_LAT_MIN_M and dlat <= SBS_LAT_MAX_M:
					sbs_ticks += 1
		var now_touch: Dictionary = {}
		for i: int in n:
			for b: Node in cars[i].get_colliding_bodies():
				if not b is ArcadeCar:
					continue
				var j: int = cars.find(b as ArcadeCar)
				if j < 0 or j == i:
					continue
				var k: String = "%d-%d" % [mini(i, j), maxi(i, j)]
				now_touch[k] = true
				if not touching.has(k):
					contacts += 1
		touching = now_touch

	func _lat(world: Vector3, s: float) -> float:
		var c: Vector3 = city.get_point_at(s)
		var t: Vector3 = city.get_tangent_at(s)
		return Vector3(world.x - c.x, 0.0, world.z - c.z).dot(Vector3(-t.z, 0.0, t.x))

	func _on_finished(res: Array[Dictionary]) -> void:
		results = []
		for r: Dictionary in res:
			var idx: int = cars.find(r["car"] as ArcadeCar)
			results.append({"skill": skills[idx] if idx >= 0 else -1.0, "total_s": snappedf(float(r["total_time"]), 0.01), "player": bool(r["is_player"])})

	func _emit() -> void:
		if done:
			return
		done = true
		var stuck: int = 0
		for d: AIDriver in drivers:
			stuck += d.stuck_count
		var spread: float = 0.0
		if results.size() > 1:
			spread = float(results[results.size() - 1]["total_s"]) - float(results[0]["total_s"])
		var summary: Dictionary = {
			"race_time_s": snappedf(manager.race_time, 0.01), "racing_ticks": racing_ticks, "timed_out": timed_out,
			"overtakes": overtakes, "overtakes_with_player": overtakes_player,
			"follow_pct": snappedf(100.0 * float(follow_ticks) / maxf(float(car_ticks), 1.0), 0.1),
			"side_by_side_pair_s": snappedf(float(sbs_ticks) / 60.0, 0.01),
			"contacts": contacts, "stuck": stuck, "teleports": teleports,
			"finish_spread_s": snappedf(spread, 0.01), "results": results,
		}
		print("RIVALS " + JSON.stringify(summary))
		get_tree().quit(0)


## --set / --tset value: a number, or true / false (1 / 0). Anything else stops the run instead of silently giving 0.
static func _num(text: String) -> float:
	if text == "true":
		return 1.0
	if text == "false":
		return 0.0
	assert(text.is_valid_float(), "diag_rivals: value is not a number, true or false: " + text)
	return text.to_float()


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	var track_key: String = "city"
	var seed_v: int = 1
	var skills: PackedFloat32Array = PackedFloat32Array([1.0, 0.97, 0.94, 0.91, 0.88, 0.85])
	var laps: int = 1
	var sets: PackedStringArray = PackedStringArray()
	var tsets: PackedStringArray = PackedStringArray()
	var reverse: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--set="):
			sets.append(a.trim_prefix("--set="))
		if a.begins_with("--tset="):
			tsets.append(a.trim_prefix("--tset="))
		if a == "--reverse":
			reverse = true
		if a.begins_with("--track="):
			track_key = a.trim_prefix("--track=")
		if a.begins_with("--seed="):
			seed_v = int(a.trim_prefix("--seed="))
		if a.begins_with("--laps="):
			laps = int(a.trim_prefix("--laps="))
		if a.begins_with("--skills="):
			skills = PackedFloat32Array()
			for p: String in a.trim_prefix("--skills=").split(","):
				skills.append(float(p))
	var n: int = skills.size()
	var city: Track = (load(TRACKS[track_key]) as PackedScene).instantiate() as Track
	for kv: String in tsets:
		city.set(kv.get_slice("=", 0), _num(kv.get_slice("=", 1)))
	root.add_child(city)
	if reverse:
		city.set_reversed(true)
	var manager := RaceManager.new()
	manager.total_laps = laps
	root.add_child(manager)
	var cars: Array[ArcadeCar] = []
	var names: PackedStringArray = PackedStringArray()
	for i: int in n:
		var car := ArcadeCar.new()
		car.spec = load(SPEC_PATH) as CarSpec
		root.add_child(car)
		var d := AIDriver.new()
		d.name = "AIDriver"
		d.skill = skills[i]
		for kv: String in sets:
			d.set(kv.get_slice("=", 0), _num(kv.get_slice("=", 1)))
		car.add_child(d)
		cars.append(car)
		names.append("S%d" % i)
	manager.setup(city, cars, cars[0], names)
	var drivers: Array[AIDriver] = []
	for i: int in n:
		var d: AIDriver = cars[i].get_node("AIDriver") as AIDriver
		d.noise_seed = seed_v * 10 + i + 1  # RaceManager set i+1; one seed set per race
		d.setup(city)
		d.set_traffic(cars)
		drivers.append(d)
	var mon := Monitor.new()
	mon.process_physics_priority = 1
	mon.city = city
	mon.manager = manager
	mon.cars = cars
	mon.drivers = drivers
	mon.skills = skills
	mon.track_len = city.length
	mon.half_len = city.length * 0.5
	mon.prog.resize(n)
	mon.race_m.resize(n)
	mon.race_m.fill(0.0)
	mon.prog.fill(0.0)
	for car: ArcadeCar in cars:
		mon.last_pos.append(car.global_position)
	manager.race_finished.connect(mon._on_finished)
	manager.race_started.connect(func() -> void: drivers[0].set_racing(true))
	root.add_child(mon)
	manager.start_countdown()
