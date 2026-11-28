extends "res://tests/test_case.gd"
## WP-A4 steer assist: a zero-input lap of istanbul_bogaz with the assist steer on finishes within 15 % of the AI
## autopilot's lap and makes at most 2 body contacts. Settings.steering_mode is set to "assist" for the player lap and
## restored after. Run at --fixed-fps 60 (physics ticks = frames). Writes evidence/handling/steer_assist.json.

const SCENE_PATH: String = "res://world/istanbul_bogaz/istanbul_bogaz.tscn"
const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const HZ: float = 60.0
const LAP_LIMIT_S: float = 240.0
const SETTLE_FRAMES: int = 60
const TIME_TOL: float = 0.15
const MAX_HITS: int = 2
const EVIDENCE_PATH: String = "../evidence/handling/steer_assist.json"
const DRIVE_ACTIONS: PackedStringArray = ["accelerate", "brake", "steer_left", "steer_right", "handbrake", "nitro"]

var _hits: int = 0


func _on_hit(_impulse: float, _at: Vector3) -> void:
	_hits += 1


## One lap from the grid with no input from the test. Returns finished, seconds, body contacts and the largest assist.
func _lap(track: CityBuilder, use_assist: bool) -> Dictionary:
	_hits = 0
	for action: String in DRIVE_ACTIONS:  # other tests leave keys held (test_driver_camera): a zero-input lap needs none
		Input.action_release(action)
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	add(car)
	car.global_transform = track.get_grid_transform(0)
	car.hit.connect(_on_hit)
	var ai: AIDriver = null
	var pd: PlayerDriver = null
	var settings: Node = tree.root.get_node_or_null("Settings")
	var saved_mode: String = ""
	var saved_auto: Variant = null
	if use_assist:
		pd = PlayerDriver.new()
		pd.name = "PlayerDriver"
		pd.enabled = false
		car.add_child(pd)
		pd.set_track(track)
		if settings != null:
			saved_mode = str(settings.get("steering_mode"))
			saved_auto = settings.get("auto_accelerate")
			settings.set("steering_mode", "assist")
			settings.set("auto_accelerate", true)  # the lap is zero input: the throttle must come from the assist
	else:
		ai = AIDriver.new()
		ai.name = "AIDriver"
		ai.skill = 1.0
		ai.noise_seed = 1
		car.add_child(ai)
		ai.setup(track)
	await frames(SETTLE_FRAMES)
	if ai != null:
		ai.set_racing(true)
	if pd != null:
		pd.enabled = true
	var last_s: float = track.get_progress(car.global_position)
	var dist: float = 0.0
	var ticks: int = 0
	var max_assist: float = 0.0
	var limit: int = roundi(LAP_LIMIT_S * HZ)
	while dist < track.length and ticks < limit:
		await frames(1)
		ticks += 1
		var s: float = track.get_progress(car.global_position, last_s)
		var step: float = s - last_s
		if step < -track.length * 0.5:
			step += track.length
		elif step > track.length * 0.5:
			step -= track.length
		dist += step
		last_s = s
		if pd != null:
			max_assist = maxf(max_assist, absf(pd._assist_steer()))
	if settings != null and use_assist:
		settings.set("steering_mode", saved_mode)
		settings.set("auto_accelerate", saved_auto)
	car.hit.disconnect(_on_hit)
	var out: Dictionary = {"finished": dist >= track.length, "s": float(ticks) / HZ, "hits": _hits, "max_assist": max_assist}
	await cleanup([car])
	return out


func test_steer_assist_laps_near_the_autopilot() -> void:
	var track: CityBuilder = (load(SCENE_PATH) as PackedScene).instantiate() as CityBuilder
	add(track)
	await frames(2)
	var ai_lap: Dictionary = await _lap(track, false)
	var assist_lap: Dictionary = await _lap(track, true)
	var ratio: float = float(assist_lap["s"]) / maxf(float(ai_lap["s"]), 0.001)
	metric("autopilot_lap_s", snappedf(float(ai_lap["s"]), 0.01))
	metric("assist_lap_s", snappedf(float(assist_lap["s"]), 0.01))
	metric("assist_over_autopilot", snappedf(ratio, 0.001))
	metric("assist_body_contacts", int(assist_lap["hits"]))
	metric("assist_max_steer_units", snappedf(float(assist_lap["max_assist"]), 0.001))
	check(bool(ai_lap["finished"]), "autopilot lap did not finish in %.0f s" % LAP_LIMIT_S)
	check(bool(assist_lap["finished"]), "assist lap did not finish in %.0f s" % LAP_LIMIT_S)
	check(ratio <= 1.0 + TIME_TOL, "assist lap %.1f s is %.1f %% over the autopilot's %.1f s" % [float(assist_lap["s"]), (ratio - 1.0) * 100.0, float(ai_lap["s"])])
	check(int(assist_lap["hits"]) <= MAX_HITS, "assist lap made %d body contacts, limit %d" % [int(assist_lap["hits"]), MAX_HITS])
	var ev: Dictionary = {
		"track": "istanbul_bogaz", "car": "noctra_sable", "assist_cap_deg": 6.0, "look_ahead_m": 30.0,
		"machine": "dev PC, Windows 11, RTX 5060 Ti 8 GB, Godot 4.7.2 (headless, no GPU render)",
		"autopilot_lap_s": snappedf(float(ai_lap["s"]), 0.01), "assist_lap_s": snappedf(float(assist_lap["s"]), 0.01),
		"assist_over_autopilot": snappedf(ratio, 0.001), "assist_body_contacts": int(assist_lap["hits"]),
		"assist_max_steer_units": snappedf(float(assist_lap["max_assist"]), 0.001),
	}
	var abs_path: String = ProjectSettings.globalize_path("res://").path_join(EVIDENCE_PATH)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(ev, "\t"))
		f.close()
	var nodes: Array[Node] = [track]
	await cleanup(nodes)
