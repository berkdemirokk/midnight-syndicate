extends SceneTree
## Diagnostic (not a test): six AI cars, skills 1.0 to 0.85, one lap on city_01. Logs every stuck
## recovery and every car-to-car contact start to evidence/logs/stuck_events.json.
## godot --headless --fixed-fps 60 --path game -s res://ai/diag_ai_stuck.gd

const SCENE_PATH: String = "res://world/city_01/city_01.tscn"
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
var SKILLS: PackedFloat32Array = PackedFloat32Array([1.0, 0.97, 0.94, 0.91, 0.88, 0.85, 0.9, 0.87])
const HIST_TICKS: int = 180  ## last 3 s at 60 Hz
const MAX_TICKS: int = 60 * 200
const OUT_REL: String = "../evidence/logs/stuck_events.json"


class Monitor extends Node:
	var city: CityBuilder
	var manager: RaceManager
	var cars: Array[ArcadeCar] = []
	var drivers: Array[AIDriver] = []
	var hist: Array = []
	var last_stuck: PackedInt32Array = PackedInt32Array()
	var last_pos: Array[Vector3] = []
	var touching: Dictionary = {}
	var events: Array = []
	var trace: Array = []
	var contacts: Array = []
	var laps: Array = []
	var results: Array = []
	var tick: int = 0
	var min_up_y: float = 1.0
	var teleports: int = 0
	var done: bool = false
	var out_name: String = "stuck_events.json"
	var trace_s0: float = 1100.0  ## trace every car while its track progress is in [trace_s0, trace_s1] m
	var trace_s1: float = 1190.0

	func _physics_process(_delta: float) -> void:
		if done:
			return
		tick += 1
		var now_touch: Dictionary = {}
		for i: int in cars.size():
			var c: ArcadeCar = cars[i]
			var inp: VehicleInput = c.input
			var rev: bool = int(drivers[i].get("_mode")) == 1
			var h: Array = hist[i]
			h.append([tick, snappedf(inp.throttle, 0.01), snappedf(inp.brake, 0.01), snappedf(inp.steer, 0.01), snappedf(c.speed_kmh, 0.1), c.gear, rev])
			if h.size() > HIST_TICKS:
				h.remove_at(0)
			min_up_y = minf(min_up_y, c.global_transform.basis.y.y)
			if tick > 1 and c.global_position.distance_to(last_pos[i]) > 5.0:
				teleports += 1
			last_pos[i] = c.global_position
			for b: Node in c.get_colliding_bodies():
				if not b is ArcadeCar:
					continue
				var j: int = cars.find(b as ArcadeCar)
				if j > i:
					var key: String = "%d-%d" % [i, j]
					now_touch[key] = true
					if not touching.has(key):
						contacts.append(_contact(i, j))
				elif j >= 0 and j < i:
					var key2: String = "%d-%d" % [j, i]
					now_touch[key2] = true
					if not touching.has(key2):
						contacts.append(_contact(j, i))
			var sp: float = city.get_progress(c.global_position)
			if sp >= trace_s0 and sp <= trace_s1:
				var tg: Vector3 = city.get_tangent_at(sp)
				var fw: Vector3 = -c.global_transform.basis.z
				var yaw_err: float = rad_to_deg(atan2(fw.x * tg.z - fw.z * tg.x, fw.x * tg.x + fw.z * tg.z))
				var lat_v: float = c.linear_velocity.dot(Vector3(-tg.z, 0.0, tg.x))
				trace.append([tick, i, snappedf(sp, 0.1), snappedf(city.get_lateral_offset(c.global_position, sp), 0.01), snappedf(c.speed_kmh, 0.1), snappedf(inp.throttle, 0.01), snappedf(inp.brake, 0.01), snappedf(inp.steer, 0.01), snappedf(float(drivers[i].get("_shift")), 0.01), snappedf(city.get_target_speed(sp) * 3.6, 0.1), c.get_colliding_bodies().size(), rev, snappedf(yaw_err, 0.1), snappedf(lat_v, 0.01), snappedf(c.steer_angle_rad, 0.001)])
			var st: int = drivers[i].stuck_count
			if st > last_stuck[i]:
				last_stuck[i] = st
				events.append(_stuck_event(i))
		touching = now_touch
		if manager.state == RaceManager.State.FINISHED or tick >= MAX_TICKS:
			_finish_run()

	func _stuck_event(i: int) -> Dictionary:
		var c: ArcadeCar = cars[i]
		var d: AIDriver = drivers[i]
		var pos: Vector3 = c.global_position
		var s: float = city.get_progress(pos)
		var nearest: int = -1
		var nd: float = INF
		for j: int in cars.size():
			if j != i:
				var dd: float = pos.distance_to(cars[j].global_position)
				if dd < nd:
					nd = dd
					nearest = j
		var bodies: Array = []
		for b: Node in c.get_colliding_bodies():
			bodies.append(String(b.name))
		var tp: Vector3 = city.get_point_at(s)
		var v: float = maxf(c.forward_speed, 0.0)
		return {
			"car": i, "skill": d.skill, "tick": tick, "race_time_s": snappedf(manager.race_time, 0.01),
			"s_m": snappedf(s, 0.1), "lap": manager.get_lap(c), "lat_m": snappedf(city.get_lateral_offset(pos, s), 0.01),
			"shift_m": snappedf(float(d.get("_shift")), 0.01), "speed_kmh": snappedf(c.speed_kmh, 0.1),
			"forward_speed_ms": snappedf(c.forward_speed, 0.01), "gear": c.gear, "reversing": int(d.get("_mode")) == 1,
			"wheel_contact": [c.wheel_contact[0], c.wheel_contact[1], c.wheel_contact[2], c.wheel_contact[3]],
			"nearest_car": nearest, "nearest_dist_m": snappedf(nd, 0.01),
			"target_point": [snappedf(tp.x, 0.1), snappedf(tp.y, 0.1), snappedf(tp.z, 0.1)],
			"target_speed_ms": snappedf(city.get_target_speed(s), 0.01),
			"target_speed_ahead_ms": snappedf(city.get_target_speed(s + clampf(0.6 * v, 0.0, 40.0)), 0.01),
			"curvature": snappedf(city.get_curvature(s), 0.0001),
			"colliding": bodies, "upright_y": snappedf(c.global_transform.basis.y.y, 0.001),
			"history_last_3s": hist[i].duplicate(true),
		}

	func _contact(i: int, j: int) -> Dictionary:
		var a: ArcadeCar = cars[i]
		var b: ArcadeCar = cars[j]
		return {
			"tick": tick, "race_time_s": snappedf(manager.race_time, 0.01), "pair": [i, j],
			"s_a_m": snappedf(city.get_progress(a.global_position), 0.1), "s_b_m": snappedf(city.get_progress(b.global_position), 0.1),
			"speed_a_kmh": snappedf(a.speed_kmh, 0.1), "speed_b_kmh": snappedf(b.speed_kmh, 0.1),
			"dist_m": snappedf(a.global_position.distance_to(b.global_position), 0.01),
		}

	func _on_lap(car: ArcadeCar, lap: int, lap_time: float) -> void:
		laps.append({"car": cars.find(car), "lap": lap, "time_s": snappedf(lap_time, 0.01), "race_time_s": snappedf(manager.race_time, 0.01)})

	func _on_finished(r: Array[Dictionary]) -> void:
		for e: Dictionary in r:
			results.append({"car": cars.find(e["car"]), "position": e["position"], "total_time_s": snappedf(float(e["total_time"]), 0.01), "best_lap_s": snappedf(float(e["best_lap"]), 0.01)})

	func _finish_run() -> void:
		done = true
		var summary: Dictionary = {
			"ticks": tick, "race_time_s": snappedf(manager.race_time, 0.01), "finished_state": manager.state == RaceManager.State.FINISHED,
			"stuck_events": events.size(), "car_contacts": contacts.size(), "teleports_over_5m_per_tick": teleports,
			"min_upright_y": snappedf(min_up_y, 0.0001), "laps": laps, "results": results,
			"stuck_per_car": Array(last_stuck),
		}
		var out: Dictionary = {"summary": summary, "events": events, "contacts": contacts, "trace_cols": "tick,car,s,lat_line,kmh,thr,brk,steer,shift,track_target_kmh,n_contacts,reversing,yaw_err_deg,lat_vel_ms,steer_angle_rad", "trace": trace}
		var path: String = ProjectSettings.globalize_path("res://").path_join("../evidence/logs/" + out_name).simplify_path()
		var fa := FileAccess.open(path, FileAccess.WRITE)
		if fa != null:
			fa.store_string(JSON.stringify(out, "  "))
			fa.close()
		print("DIAG summary: %s" % JSON.stringify(summary))
		get_tree().quit(0)


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	var n: int = 6
	var out_name: String = "stuck_events.json"
	var trace_s: PackedStringArray = PackedStringArray(["1100", "1190"])
	var slide: float = -1.0  ## --slide=<m/s> overrides AIDriver.slide_lift_ms (a huge value turns the rule off)
	var nitro_kmh: float = 0.0  ## --nitro=<kmh> sets AIDriver.nitro_min_start_kmh for every car (test settings 0, 100, 140)
	var reversed_order: bool = false  ## --order=b gives the skills in reverse grid order (test order B)
	var set_args: PackedStringArray = PackedStringArray()  ## --set=<property>=<value>, any AIDriver export, for experiments
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--slide="):
			slide = float(a.trim_prefix("--slide="))
		if a.begins_with("--s="):
			trace_s = a.trim_prefix("--s=").split(",")
		if a.begins_with("--cars="):
			n = clampi(int(a.trim_prefix("--cars=")), 1, SKILLS.size())
		if a.begins_with("--out="):
			out_name = a.trim_prefix("--out=")
		if a.begins_with("--nitro="):
			nitro_kmh = float(a.trim_prefix("--nitro="))
		if a.begins_with("--set="):
			set_args.append(a.trim_prefix("--set="))
		if a == "--order=b":
			reversed_order = true
	var city: CityBuilder = (load(SCENE_PATH) as PackedScene).instantiate() as CityBuilder
	root.add_child(city)
	var manager := RaceManager.new()
	manager.total_laps = 1
	root.add_child(manager)
	var cars: Array[ArcadeCar] = []
	var names: PackedStringArray = PackedStringArray()
	for i: int in n:
		var car := ArcadeCar.new()
		car.spec = load(SPEC_PATH) as CarSpec
		root.add_child(car)
		var d := AIDriver.new()
		d.name = "AIDriver"
		d.skill = SKILLS[SKILLS.size() - 1 - i] if reversed_order else SKILLS[i]
		d.nitro_min_start_kmh = nitro_kmh
		for kv: String in set_args:
			d.set(kv.get_slice("=", 0), kv.get_slice("=", 1).to_float())
		if slide >= 0.0:
			d.slide_lift_ms = slide
			d.slide_cut_ms = slide + 1.5
		car.add_child(d)
		cars.append(car)
		names.append("S%d" % i)
	manager.setup(city, cars, null, names)
	var mon := Monitor.new()
	mon.process_physics_priority = 1
	mon.city = city
	mon.manager = manager
	mon.cars = cars
	mon.out_name = out_name
	mon.trace_s0 = float(trace_s[0])
	mon.trace_s1 = float(trace_s[1])
	for car: ArcadeCar in cars:
		mon.drivers.append(car.get_node("AIDriver") as AIDriver)
		mon.hist.append([])
		mon.last_pos.append(car.global_position)
	mon.last_stuck.resize(cars.size())
	mon.last_stuck.fill(0)
	manager.lap_completed.connect(mon._on_lap)
	manager.race_finished.connect(mon._on_finished)
	root.add_child(mon)
	manager.start_countdown()
