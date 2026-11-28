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
