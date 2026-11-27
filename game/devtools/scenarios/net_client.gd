extends "res://devtools/capture_scenario.gd"
## Online race, in-game path, rendered: this process is a real game client that joins a LAN server on 127.0.0.1,
## readies, and enters the race through the same RaceConfig as the lobby menu (net_hold_grid, NetRaceGlue). The
## player car drives on autopilot so the run is unattended. Another client (devtools/net_smoke.gd, headless) and the
## server must be running: tools/net_ingame_check.py starts all three.
## Shots: net_grid (after the start message), net_racing (5 s after GO, chase view), net_remote (a camera behind the
## remote car), net_results (the server's results). Fails without a remote car or without server results.
## Options: --port=N (default NetConfig.DEFAULT_PORT), --name=X.

const SCENE: String = "res://race/race_scene.tscn"
const WAIT_JOIN_S: float = 30.0
const WAIT_GO_S: float = 30.0
const RACING_SHOT_S: float = 5.0
const WAIT_RESULTS_S: float = 200.0

var _session: NetSession
var _info: Dictionary = {}
var _results: Array = []


func run() -> void:
	var port: int = NetConfig.DEFAULT_PORT
	var player_name: String = "Rendered"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))
		elif a.begins_with("--name="):
			player_name = a.trim_prefix("--name=")
	_session = NetSession.get_or_create(tree)
	_session.welcomed.connect(func(_pid: int) -> void: _session.send_ready(true))
	_session.race_starting.connect(func(info: Dictionary) -> void: _info = info)
	_session.results_received.connect(func(rows: Array) -> void: _results = rows)
	var err: String = _session.connect_to_server(NetConfig.DEFAULT_BIND, port, player_name)
	if err != "":
		cap.fail("connect: " + err)
		return
	var t: float = 0.0
	while _info.is_empty() and t < WAIT_JOIN_S:
		await cap.wait_seconds(0.1)
		t += 0.1
	if _info.is_empty():
		cap.fail("no start message from the server")
		return
	# the lobby menu's RaceConfig, autopilot on for an unattended run
	var cfg := RaceConfig.new()
	cfg.net_hold_grid = true
	cfg.opponent_count = 0
	cfg.laps = int(_info.get("laps", 1))
	cfg.track_scene = ""
	cfg.autopilot = true
	cfg.traffic_enabled = false
	cfg.event_id = "online_lan"
	var race: RaceScene = (load(SCENE) as PackedScene).instantiate() as RaceScene
	race.config = cfg
	tree.root.add_child(race)
	await cap.wait_frames(10)
	var glue: Node = race.find_child("NetRaceGlue", true, false)
	if glue == null:
		cap.fail("NetRaceGlue not attached")
		return
	await cap.shot("net_grid")
	t = 0.0
	while race.race.state != RaceManager.State.RACING and t < WAIT_GO_S:
		await cap.wait_seconds(0.1)
		t += 0.1
	if race.race.state != RaceManager.State.RACING:
		cap.fail("countdown never reached GO")
		return
	await cap.wait_seconds(RACING_SHOT_S)
	await cap.shot("net_racing")
	var cars: Dictionary = glue.get("_cars")
	if cars == null or cars.is_empty():
		cap.fail("no remote car")
		return
	var remote: ArcadeCar = cars.values()[0] as ArcadeCar
	var fwd: Vector3 = -remote.global_transform.basis.z
	var cam := Camera3D.new()
	cam.fov = 55.0
	race.add_child(cam)
	var eye: Vector3 = remote.global_position - fwd * 6.0 + Vector3.UP * 1.6
	cam.global_transform = Transform3D(Basis.looking_at(remote.global_position + Vector3.UP * 0.5 - eye, Vector3.UP), eye)
	cam.make_current()
	await cap.wait_frames(3)
	await cap.shot("net_remote")
	print("[net_client] remote car at %s, speed %.1f km/h from snapshots" % [str(remote.global_position), remote.linear_velocity.length() * 3.6])
	cam.queue_free()
	t = 0.0
	while _results.is_empty() and t < WAIT_RESULTS_S:
		await cap.wait_seconds(0.25)
		t += 0.25
	if _results.is_empty():
		cap.fail("no server results")
		return
	print("[net_client] server results: %s" % str(_results))
	await cap.wait_frames(10)
	await cap.shot("net_results")
