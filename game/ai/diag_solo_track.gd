extends SceneTree
## Diagnostic (not a test): one AI car, skill 1.0, 2 laps on the test circuit (tests/helpers/test_track.gd),
## the same setup as test_ai_race::test_single_ai_two_laps. Prints the state of the first ticks (TICK), and the
## track progress, lateral offset, speed, steer and throttle every time the car is more than 5 m from the line (DIAG).
## Option --nohold sets grid_hold_m to 0 (AIDriver only).
## godot --headless --fixed-fps 60 --path game -s res://ai/diag_solo_track.gd [-- --nohold]

const SPEC_PATH: String = "res://vehicles/specs/noctra_sable.tres"
const TestTrack = preload("res://tests/helpers/test_track.gd")
const HZ: float = 60.0
const MAX_TICKS: int = 60 * 150
const TICK_LOG_MAX: int = 240
const TICK_LOG_EVERY: int = 20


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	var track: Track = TestTrack.build()
	root.add_child(track)
	var car := ArcadeCar.new()
	car.spec = load(SPEC_PATH) as CarSpec
	root.add_child(car)
	var d := AIDriver.new()
	d.name = "AIDriver"
	d.skill = 1.0
	d.noise_seed = 1
	if OS.get_cmdline_user_args().has("--nohold"):
		d.grid_hold_m = 0.0
	car.add_child(d)
	var manager := RaceManager.new()
	manager.total_laps = 2
	root.add_child(manager)
	var cars: Array[ArcadeCar] = [car]
	manager.setup(track, cars, null, PackedStringArray(["Solo"]))
	print("DIAG grid0 lateral %.2f" % track.get_lateral_offset(track.get_grid_transform(0).origin))
	manager.start_countdown()
	var ticks: int = 0
	var max_lat: float = 0.0
	var max_s: float = 0.0
	while manager.state != RaceManager.State.FINISHED and ticks < MAX_TICKS:
		await physics_frame
		ticks += 1
		var s: float = track.get_progress(car.global_position)
		var lat: float = track.get_lateral_offset(car.global_position, s)
		if absf(lat) > max_lat:
			max_lat = absf(lat)
			max_s = s
		if ticks <= TICK_LOG_MAX and ticks % TICK_LOG_EVERY == 0:
			print("TICK %d s=%.2f lat=%.4f v=%.4f thr=%.4f brk=%.4f st=%.4f pos=%.3f,%.3f" % [ticks, s, lat, car.forward_speed, car.input.throttle, car.input.brake, car.input.steer, car.global_position.x, car.global_position.z])
		if absf(lat) > 5.0 and ticks % 6 == 0:
			print("DIAG t=%.2f s=%.1f lat=%.2f kmh=%.1f thr=%.2f brk=%.2f steer=%.2f shift=%.2f" % [
				float(ticks) / HZ, s, lat, car.speed_kmh, car.input.throttle, car.input.brake, car.input.steer, float(d.get("_shift"))])
	print("DIAG max |lat| %.2f at s %.1f, race %.2f s, laps %d" % [max_lat, max_s, manager.race_time, 2])
	quit(0)
