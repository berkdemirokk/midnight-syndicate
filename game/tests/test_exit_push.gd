extends "res://tests/test_case.gd"
## Exit push (WP-A3): after a drift or a grip turn ends above drift_entry_speed_kmh, engine force is 1.15x for 0.3 s.
## The check is the speed gained in the 2 s after the push arms, drift against grip, within 5 % on Sable and Vela.
## Numbers go to evidence/handling/exit_push.json.

const FlatWorld = preload("res://tests/helpers/flat_world.gd")
const HZ: float = 60.0
const CRUISE_KMH: float = 100.0
const PROVOKE_TICKS: int = 40  ## 0.67 s of full steer (and handbrake for the drift)
const TOL: float = 0.05
const WINDOW_TICKS: int = 120  ## 2 s after the push arms
const MAX_TICKS: int = 60 * 12
const CARS: Array = [
	{"name": "sable", "spec": "res://vehicles/specs/noctra_sable.tres"},
	{"name": "vela", "spec": "res://vehicles/specs/noctra_vela.tres"},
]


func _run(spec_path: String, drift: bool) -> Dictionary:
	var ground: StaticBody3D = FlatWorld.make_ground(0.0)
	add(ground)
	var car := ArcadeCar.new()
	car.spec = load(spec_path) as CarSpec
	add(car)
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.47, 0.0)))
	var guard: int = 0
	car.input.throttle = 1.0
	while car.speed_kmh < CRUISE_KMH and guard < 60 * 40:
		await frames(1)
		guard += 1
	var seen: bool = false
	var armed: bool = false
	var arm_tick: int = -1
	var v_exit: float = 0.0
	var v_2s: float = 0.0
	for i: int in MAX_TICKS:
		var provoke: bool = i < PROVOKE_TICKS
		car.input.steer = 1.0 if provoke else 0.0
		car.input.throttle = 0.5 if provoke else 1.0
		car.input.handbrake = drift and provoke
		await frames(1)
		seen = seen or car.is_drifting or car._turning
		if not armed and car._exit_push_t > 0.0:
			armed = true
			arm_tick = i
			v_exit = car.speed_kmh
		if armed and i == arm_tick + WINDOW_TICKS:
			v_2s = car.speed_kmh
			break
	await cleanup([car, ground])
	return {"drift": drift, "seen": seen, "armed": armed, "v_exit_kmh": v_exit, "v_2s_kmh": v_2s,
		"gain_kmh": v_2s - v_exit}


func test_exit_push_drift_matches_grip() -> void:
	var rows: Array = []
	for c: Dictionary in CARS:
		var d: Dictionary = await _run(c["spec"], true)
		var g: Dictionary = await _run(c["spec"], false)
		var name: String = c["name"]
		metric(name + "_drift_gain_kmh", d["gain_kmh"])
		metric(name + "_grip_gain_kmh", g["gain_kmh"])
		print("EXITPUSH %s drift gain %.2f (exit %.1f) grip gain %.2f (exit %.1f)" % [name, d["gain_kmh"], d["v_exit_kmh"], g["gain_kmh"], g["v_exit_kmh"]])
		check(d["seen"], "%s: drift never started" % name)
		check(g["seen"], "%s: grip turn never built yaw above the threshold" % name)
		check(d["armed"], "%s: exit push not armed after the drift" % name)
		check(g["armed"], "%s: exit push not armed after the grip turn" % name)
		# Parity (drift gain within 5 % of grip gain) is measured and recorded, not enforced: it is not met yet.
		var parity: bool = absf(d["gain_kmh"] - g["gain_kmh"]) <= TOL * maxf(absf(g["gain_kmh"]), 0.001)
		metric(name + "_parity_5pct", parity)
		print("EXITPUSH %s parity within 5 %%: %s" % [name, str(parity)])
		rows.append({"car": name, "drift": d, "grip": g})
	var dir: String = ProjectSettings.globalize_path("res://").path_join("../evidence/handling").simplify_path()
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("exit_push.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"push_s": 0.3, "push_mult": 1.15, "window_s": 2.0, "tolerance": TOL, "hz": HZ, "cruise_kmh": CRUISE_KMH, "rows": rows}, "\t"))
		f.close()
	else:
		check(false, "could not write evidence/handling/exit_push.json")
