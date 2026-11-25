extends "res://devtools/capture_scenario.gd"
## Draw calls of the race HUD and the results overlay in isolation (2D only, mock data).
## Prints the frame draw count with the layer visible and hidden; the delta is the layer cost.
## Run: capture_boot.tscn -- --capture=ui_draws

const MockRace = preload("res://devtools/scenarios/ui_mock_race.gd")
const MOCK_TRACK: String = "res://devtools/scenarios/ui_mock_track.gd"
const SAMPLE_FRAMES: int = 30


func _draws() -> int:
	var peak: int = 0
	for i: int in SAMPLE_FRAMES:
		await tree.process_frame
		peak = maxi(peak, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	return peak


func run() -> void:
	cap.set_size(1920, 1080)
	var backdrop: CanvasLayer = MockRace.make_backdrop()
	tree.root.add_child(backdrop)
	var hud: RaceHUD = await cap.load_scene("res://ui/hud/race_hud.tscn") as RaceHUD
	var car := ArcadeCar.new()
	var race = MockRace.new()
	race.total_laps = 3
	race.fake_position = 2
	race.fake_cars = 6
	race.fake_lap = 2
	race.fake_best = 58.61
	race.fake_lap_time = 22.84
	race.race_time = 74.2
	race.rivals.append(car)
	race.fake_progress[car.get_instance_id()] = 0.42
	for i: int in 4:
		var rival := ArcadeCar.new()
		race.rivals.append(rival)
		race.fake_progress[rival.get_instance_id()] = 0.1 + 0.2 * i
	hud.bind(car, race, (load(MOCK_TRACK) as Script).new())
	car.speed_kmh = 187.4
	car.gear = 4
	car.rpm_norm = 0.82
	car.nitro_amount = 0.6
	car.nitro_active = true
	car.is_drifting = true
	car.drift_score = 1240.0
	car.drift_started.emit()
	await cap.wait_frames(30)
	var with_hud: int = await _draws()
	hud.visible = false
	var without: int = await _draws()
	print("[UIDRAWS] hud with=%d without=%d delta=%d" % [with_hud, without, with_hud - without])
	hud.visible = true
	await cap.wait_frames(3)
	await cap.shot("hud")
	hud.queue_free()
	await cap.wait_frames(3)

	var screen: ResultsScreen = await cap.load_scene("res://ui/menus/results_screen.tscn") as ResultsScreen
	var results: Array[Dictionary] = []
	var names: PackedStringArray = ["Vance Reyes", "Kato Mori", "Ilse Brandt", "Rafa Ortiz", "Nina Kowal", "Sol Vidal"]
	for i: int in names.size():
		results.append({"name": names[i], "position": i + 1, "total_time": 241.6 + 3.2 * i,
			"best_lap": 79.4 + 0.6 * i, "is_player": i == 1})
	screen.show_results(results, {"cash": 1800, "rep": 120})
	await cap.wait_frames(90)
	with_hud = await _draws()
	screen.visible = false
	without = await _draws()
	print("[UIDRAWS] results with=%d without=%d delta=%d" % [with_hud, without, with_hud - without])
	screen.visible = true
	await cap.wait_frames(3)
	await cap.shot("results")
