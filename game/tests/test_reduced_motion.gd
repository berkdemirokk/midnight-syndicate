extends "res://tests/test_case.gd"
## Reduced motion: blur taps by preset and level; OFF leaves no blur, no speed shake and no nitro kick (gain 0).


func test_blur_taps_and_motion_gain() -> void:
	check(PostFx.blur_taps_for("low", "high") == 0, "low preset has no blur")
	check(PostFx.blur_taps_for("medium", "high") == 3, "medium preset has 3 taps")
	check(PostFx.blur_taps_for("high", "high") == 5, "high preset has 5 taps")
	check(PostFx.blur_taps_for("high", "off") == 0, "reduced motion off removes the blur")
	check(PostFx.blur_taps_for("high", "low") == 3, "reduced motion low caps the taps at 3")
	check(PostFx.blur_taps_for("medium", "low") == 3, "low never adds taps")
	check(ChaseCamera.motion_gain("off") == 0.0, "off gives zero shake and kick gain")
	check(ChaseCamera.motion_gain("low") == 0.5, "low gives half gain")
	check(ChaseCamera.motion_gain("high") == 1.0, "high gives full gain")


func test_off_gives_zero_blur_and_high_keeps_it() -> void:
	var prev_preset: String = Settings.get_preset_id()
	var prev_motion: String = Settings.reduced_motion
	var prev_autosave: bool = Settings.autosave
	Settings.autosave = false
	check(not Settings.set_reduced_motion("bogus"), "unknown level must be rejected")
	Settings.set_preset("high")
	Settings.set_reduced_motion("off")
	var fx := PostFx.new()
	add(fx)
	await frames(2)
	var mat: ShaderMaterial = fx._rect.material as ShaderMaterial
	fx.set_time_of_day("night")
	fx.set_speed(300.0, true)
	await frames(60)
	check(fx.get_blur() == 0.0, "OFF must give zero blur, got %.3f" % fx.get_blur())
	check(int(mat.get_shader_parameter("blur_taps")) == 0, "OFF must set blur_taps to 0")
	Settings.set_reduced_motion("high")
	fx.set_speed(300.0, false)
	await frames(60)
	check(fx.get_blur() > 0.5, "high must keep the blur, got %.2f" % fx.get_blur())
	check(int(mat.get_shader_parameter("blur_taps")) == 5, "high on the High preset must use 5 taps")
	Settings.set_preset(prev_preset)
	Settings.set_reduced_motion(prev_motion)
	Settings.autosave = prev_autosave
	await cleanup([fx])


## Runs a ChaseCamera at speed_kmh with nitro on under a reduced_motion level.
## Returns [largest speed-shake offset, settled FOV, base FOV for the speed] (the base FOV has no kick).
func _motion_probe(level: String, speed_kmh: float) -> Array:
	Settings.set_reduced_motion(level)
	var cam := ChaseCamera.new()
	add(cam)
	var car := ArcadeCar.new()
	car.speed_kmh = speed_kmh
	car.nitro_active = true
	cam.target = car  # set after add(): snap() in _ready would read a car that is not in the tree
	var shake: float = 0.0
	for i: int in 12:
		cam._shake_clock += 0.0137
		shake = maxf(shake, cam._speed_shake_offset(Basis.IDENTITY).length())
	for i: int in 120:
		cam._update_lens(1.0 / 60.0)
	var result: Array = [shake, cam.fov, cam.compute_base_fov()]
	cam.target = null
	car.free()
	await cleanup([cam])
	return result


func test_reduced_motion_gates_speed_shake_and_nitro_kick() -> void:
	var prev_motion: String = Settings.reduced_motion
	var prev_shake: float = Settings.camera_shake
	var prev_autosave: bool = Settings.autosave
	Settings.autosave = false
	Settings.set_camera_shake(0.6)
	var off_shake: Array = await _motion_probe("off", 280.0)
	var low_shake: Array = await _motion_probe("low", 280.0)
	var high_shake: Array = await _motion_probe("high", 280.0)
	check(off_shake[0] == 0.0, "OFF must give zero speed shake, got %.5f" % off_shake[0])
	check(high_shake[0] > 0.001, "HIGH must keep the speed shake, got %.5f" % high_shake[0])
	check(low_shake[0] > 0.0 and low_shake[0] < high_shake[0], "LOW shake must be between 0 and HIGH")
	var off_fov: Array = await _motion_probe("off", 100.0)
	var high_fov: Array = await _motion_probe("high", 100.0)
	check(absf(off_fov[1] - off_fov[2]) < 0.05, "OFF must give no nitro kick: fov %.2f vs base %.2f" % [off_fov[1], off_fov[2]])
	check(high_fov[1] - high_fov[2] > 1.0, "HIGH must keep the nitro kick: fov %.2f vs base %.2f" % [high_fov[1], high_fov[2]])
	Settings.set_reduced_motion(prev_motion)
	Settings.set_camera_shake(prev_shake)
	Settings.autosave = prev_autosave
