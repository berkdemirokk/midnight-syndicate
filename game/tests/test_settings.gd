extends "res://tests/test_case.gd"
## Settings: presets apply to a viewport and an environment, save/load round trip, dynamic resolution bounds.
## Each test writes only its own user:// file, never the real settings.cfg. AudioServer buses are
## global, so every test puts back the dB values it found.

const SETTINGS: GDScript = preload("res://core/settings.gd")
## data_scale is the preset value; the viewport renders at 1.0 until the preset is confirmed on device.
const PRESET_EXPECT: Dictionary = {
	"low": {"data_scale": 0.67, "msaa": Viewport.MSAA_DISABLED, "glow": true, "glow_intensity": 0.35},
	"medium": {"data_scale": 0.85, "msaa": Viewport.MSAA_DISABLED, "glow": true, "glow_intensity": 0.6},
	"high": {"data_scale": 1.0, "msaa": Viewport.MSAA_2X, "glow": true, "glow_intensity": 0.8},
}
const BUS_NAMES: PackedStringArray = ["Master", "Music", "SFX", "Engine"]
const FRAME_S: float = 1.0 / 60.0
const SLOW_MS: float = 30.0
const FAST_MS: float = 8.0
const BAND_MS: float = 16.0


func _path(tag: String) -> String:
	return "user://test_settings_%s.cfg" % tag


func _wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _new(path: String) -> Node:
	var s: Node = SETTINGS.new()
	s.config_path = path
	return s


func _close(s: Node) -> void:
	s.free()


## Creates the test buses if needed and returns their current dB values.
func _snapshot_buses() -> Dictionary:
	var out: Dictionary = {}
	for bus_name: String in BUS_NAMES:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
		out[bus_name] = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus_name))
	return out


func _restore_buses(saved: Dictionary) -> void:
	for bus_name: String in saved:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus_name), saved[bus_name])


## Marks preset id as confirmed on device (a simulated measurement) and makes it the active preset.
func _confirm(s: Node, id: String) -> void:
	s.set_preset(id)
	s.get_preset().scaling_confirmed_on_device = true
	s.set_preset(id)


## Runs `seconds` of frames at FRAME_S with the given frame time. Returns the scale after the run.
func _run_frames(s: Node, frame_ms: float, seconds: float) -> float:
	var frames: int = roundi(seconds / FRAME_S)
	var scale: float = s.get_render_scale()
	for i: int in frames:
		scale = s.dynamic_resolution_tick(frame_ms, FRAME_S)
	return scale


func test_presets_apply_to_viewport_and_environment() -> void:
	var path := _path("presets")
	_wipe(path)
	var s: Node = _new(path)
	var nodes: Array[Node] = []
	for id: String in ["low", "medium", "high"]:
		check(s.set_preset(id), "set_preset(%s) accepted" % id)
		var expect: Dictionary = PRESET_EXPECT[id]
		var p: GraphicsPreset = s.get_preset()
		check(is_equal_approx(p.scaling_3d_scale, expect["data_scale"]), "%s preset scale = %f" % [id, p.scaling_3d_scale])
		var sv := SubViewport.new()
		nodes.append(add(sv))
		s.apply_to_viewport(sv)
		check(is_equal_approx(sv.scaling_3d_scale, 1.0), "%s unconfirmed scale renders at 1.0, got %f" % [id, sv.scaling_3d_scale])
		check(sv.msaa_3d == expect["msaa"], "%s viewport msaa = %d" % [id, sv.msaa_3d])
		var env := Environment.new()
		s.apply_to_environment(env)
		check(env.glow_enabled == expect["glow"], "%s glow enabled" % id)
		check(is_equal_approx(env.glow_intensity, expect["glow_intensity"]), "%s glow intensity = %f" % [id, env.glow_intensity])
		metric("glow_intensity_" + id, env.glow_intensity)
		# A device measurement confirms the scale: the preset value is then used.
		p.scaling_confirmed_on_device = true
		s.set_preset(id)
		s.apply_to_viewport(sv)
		check(is_equal_approx(sv.scaling_3d_scale, expect["data_scale"]), "%s confirmed viewport scale = %f" % [id, sv.scaling_3d_scale])
		p.scaling_confirmed_on_device = false
		s.set_preset(id)
	check(not s.set_preset("ultra"), "unknown preset rejected")
	check(s.get_preset_id() == "high", "unknown preset leaves the current one (high, the last set)")
	await cleanup(nodes)
	_close(s)
	_wipe(path)


func test_save_load_round_trip() -> void:
	var path := _path("roundtrip")
	_wipe(path)
	var buses: Dictionary = _snapshot_buses()
	var s: Node = _new(path)
	s.set_preset("high")
	s.set_volume("music", 0.25)
	s.set_volume("master", 0.0)
	s.set_steering_mode("tilt")
	s.set_camera_shake(0.3)
	s.set_haptics(false)
	s.set_auto_accelerate(false)
	s.set_language("tr")
	check(s.save_settings(), "save_settings writes the file")
	_close(s)

	var again: Node = _new(path)
	again.ensure_audio_buses()
	check(again.load_settings(), "load_settings reads the file")
	check(again.get_preset_id() == "high", "preset survives reload")
	check(is_equal_approx(again.get_volume("music"), 0.25), "music volume survives reload")
	check(again.steering_mode == "tilt", "steering mode survives reload")
	check(is_equal_approx(again.camera_shake, 0.3), "camera shake survives reload")
	check(again.haptics == false, "haptics survive reload")
	check(again.auto_accelerate == false, "auto accelerate survives reload")
	check(again.language == "tr", "language survives reload")
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.25)) < 0.01, "music bus dB matches 0.25")
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")) <= -79.0, "zero master volume mutes the bus")
	_close(again)
	_restore_buses(buses)
	_wipe(path)


## Setters write the file by themselves, so a change made without save_settings() survives a restart.
func test_setters_autosave() -> void:
	var path := _path("autosave")
	_wipe(path)
	var buses: Dictionary = _snapshot_buses()
	var s: Node = _new(path)
	s.set_language("tr")
	s.set_volume("sfx", 0.5)
	_close(s)
	var again: Node = _new(path)
	again.ensure_audio_buses()
	check(again.load_settings(), "setter changes wrote the file without an explicit save")
	check(again.language == "tr", "language change autosaved")
	check(is_equal_approx(again.get_volume("sfx"), 0.5), "volume change autosaved")
	_close(again)
	_restore_buses(buses)
	_wipe(path)


func test_bad_file_values_fall_back() -> void:
	var path := _path("badfile")
	_wipe(path)
	var buses: Dictionary = _snapshot_buses()
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", "ultra")
	cfg.set_value("controls", "steering_mode", 7)
	cfg.set_value("audio", "music", 4.0)
	cfg.save(path)
	var s: Node = _new(path)
	s.load_settings()
	check(s.get_preset_id() == "medium", "unknown preset in file keeps the default")
	check(s.steering_mode == "buttons", "non-string steering mode keeps the default")
	check(is_equal_approx(s.get_volume("music"), 1.0), "out-of-range volume clamps to 1")
	_close(s)
	_restore_buses(buses)
	_wipe(path)


func test_dynamic_resolution_steps_down_and_up_within_bounds() -> void:
	var path := _path("dyn")
	_wipe(path)
	var s: Node = _new(path)
	# The controller only runs on a preset whose scale is confirmed on device (simulated here).
	_confirm(s, "high")
	s.set_dynamic_resolution(true)
	check(s.get_dynamic_resolution(), "dynamic resolution on once confirmed")
	var min_scale: float = s.get_preset().min_scaling_3d_scale
	var max_scale: float = s.get_preset().scaling_3d_scale
	var step: float = s.dyn_step

	# Under one second of slow frames: no step yet (at most one step per second).
	var scale: float = _run_frames(s, SLOW_MS, 0.5)
	check(is_equal_approx(scale, max_scale), "no step within the first second, got %f" % scale)

	# 5 s of slow frames in total: exactly one step per second, so exactly 5 steps down.
	scale = _run_frames(s, SLOW_MS, 4.5)
	check(is_equal_approx(scale, max_scale - 5.0 * step), "exactly 5 steps in 5 s slow, got %f" % scale)
	metric("scale_after_5s_slow", scale)

	# Long slow run: the scale stops at the minimum, never below it.
	scale = _run_frames(s, SLOW_MS, 15.0)
	check(is_equal_approx(scale, min_scale), "scale stops at min %f, got %f" % [min_scale, scale])
	check_range(scale, min_scale, max_scale, "scale stays within bounds while slow")
	metric("min_scale_reached", scale)

	# Fast frames: the scale climbs back to the preset maximum, never above it.
	scale = _run_frames(s, FAST_MS, 15.0)
	check(is_equal_approx(scale, max_scale), "scale returns to max %f, got %f" % [max_scale, scale])
	check_range(scale, min_scale, max_scale, "scale stays within bounds while fast")
	metric("scale_after_recovery", scale)
	_close(s)
	_wipe(path)


func test_dynamic_resolution_hysteresis_and_off() -> void:
	var path := _path("dyn3")
	_wipe(path)
	var s: Node = _new(path)
	_confirm(s, "medium")
	s.set_dynamic_resolution(true)
	var start: float = s.get_render_scale()
	check(is_equal_approx(start, 0.85), "medium starts at 0.85 once confirmed, got %f" % start)
	var scale: float = _run_frames(s, BAND_MS, 5.0)
	check(is_equal_approx(scale, start), "frame time inside the hysteresis band does not step")

	s.set_dynamic_resolution(false)
	scale = _run_frames(s, SLOW_MS, 5.0)
	check(is_equal_approx(scale, s.get_preset().effective_scale()), "dynamic resolution off keeps the preset scale")
	_close(s)
	_wipe(path)


## Without a device confirmation, Low (which asks for dynamic resolution) keeps the 3D scale at 1.0.
func test_dynamic_resolution_stays_off_until_confirmed() -> void:
	var path := _path("dyn_gate")
	_wipe(path)
	var s: Node = _new(path)
	s.set_preset("low")
	check(not s.get_dynamic_resolution(), "low preset does not enable dynamic resolution before confirmation")
	s.set_dynamic_resolution(true)
	check(not s.get_dynamic_resolution(), "set_dynamic_resolution(true) ignored while unconfirmed")
	var scale: float = _run_frames(s, SLOW_MS, 5.0)
	check(is_equal_approx(scale, 1.0), "unconfirmed scale stays 1.0 under slow frames, got %f" % scale)
	_close(s)
	_wipe(path)
