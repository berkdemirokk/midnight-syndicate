extends "res://tests/test_case.gd"
## PostFx: speed blur mapping, per-hour grade and the Low preset switch.


func test_blur_mapping_and_low_preset() -> void:
	check(PostFx.blur_for(60.0, false) == 0.0, "no blur at city speed")
	check(PostFx.blur_for(300.0, false) > 0.6, "strong blur at top speed")
	check(PostFx.blur_for(60.0, true) > 0.3, "nitro adds blur")
	var prev: String = Settings.get_preset_id()
	var prev_autosave: bool = Settings.autosave
	Settings.autosave = false
	var fx := PostFx.new()
	add(fx)
	await frames(2)
	Settings.set_preset("low")
	check(not fx.visible, "PostFx must be off on Low")
	Settings.set_preset("high")
	check(fx.visible, "PostFx must be on on High")
	fx.set_time_of_day("night")
	fx.set_speed(300.0, true)
	await frames(60)
	check(fx.get_blur() > 0.5, "blur did not rise toward the target, got %.2f" % fx.get_blur())
	Settings.set_preset(prev)
	Settings.autosave = prev_autosave
	await cleanup([fx])
