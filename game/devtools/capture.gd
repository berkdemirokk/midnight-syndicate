class_name CaptureHarness
extends Node
## Screenshot and perf harness. Autoload "Capture". Inert unless the user args contain --capture=<scenario>.
## Only screenshots written here count as evidence.
## Usage (from the repo root):
##   Godot_v4.7.2-stable_win64_console.exe --path "game" --resolution 1920x1080 --position 40,40 res://devtools/capture_boot.tscn -- --capture=<scenario> [--size=WxH] [--preset=low|medium|high]

const OFFSCREEN_MARGIN_PX: int = 200  ## gap between the hidden capture window and the rightmost monitor
const SCENARIO_DIR: String = "res://devtools/scenarios/"
const EVIDENCE_REL: String = "../evidence/screens/"
const SHOT_PROBE_FRAMES: int = 60
const DEFAULT_PRESET: String = "high"
const ARG_CAPTURE: String = "--capture="
const ARG_SIZE: String = "--size="
const ARG_PRESET: String = "--preset="
const EXIT_OK: int = 0
const EXIT_FAIL: int = 1
const EXIT_TIMEOUT: int = 2

@export_range(5.0, 600.0, 1.0) var timeout_s: float = 120.0
@export_range(0.0, 1.0, 0.01) var min_luma_range: float = 0.02
@export_range(4, 128, 1) var sample_grid: int = 32

var scenario_name: String = ""
var _size: Vector2i = Vector2i.ZERO
var _preset: String = DEFAULT_PRESET
var _shots: int = 0
var _errors: int = 0
var _done: bool = false
var _scene_node: Node = null
var _probe: PerfProbe = PerfProbe.new()


func _ready() -> void:
	_parse_args()
	if scenario_name.is_empty():
		return
	_hide_window()
	get_tree().create_timer(timeout_s).timeout.connect(_on_timeout)
	_run.call_deferred()


## Captures must not pop up on the owner's desktop or steal focus while they work: the window never
## takes focus, stays out of the taskbar and lives to the right of every monitor. The GPU still
## renders it, so the screenshots are unchanged. --show-window keeps it visible for debugging.
func _hide_window() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--show-window"):
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	var right: int = 0
	for i: int in DisplayServer.get_screen_count():
		var r: Rect2i = DisplayServer.screen_get_usable_rect(i)
		right = maxi(right, r.position.x + r.size.x)
	DisplayServer.window_set_position(Vector2i(right + OFFSCREEN_MARGIN_PX, 0))


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(ARG_CAPTURE):
			scenario_name = arg.trim_prefix(ARG_CAPTURE)
		elif arg.begins_with(ARG_SIZE):
			var parts: PackedStringArray = arg.trim_prefix(ARG_SIZE).split("x")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				_size = Vector2i(int(parts[0]), int(parts[1]))
			else:
				push_warning("Capture: bad --size, expected WxH")
		elif arg.begins_with(ARG_PRESET):
			_preset = arg.trim_prefix(ARG_PRESET)
		elif arg.begins_with("--timeout="):
			# Long scenarios (a full 2-lap race) need more than the default; still capped by the export range.
			var t: String = arg.trim_prefix("--timeout=")
			if t.is_valid_float():
				timeout_s = clampf(float(t), 5.0, 600.0)
	if not scenario_name.is_empty() and not scenario_name.is_valid_identifier():
		push_error("Capture: scenario name must be an identifier")
		scenario_name = ""


func _run() -> void:
	var script_path: String = SCENARIO_DIR + scenario_name + ".gd"
	if not ResourceLoader.exists(script_path):
		fail("no scenario script " + script_path)
		_finish(EXIT_FAIL)
		return
	var scenario: CaptureScenario = load(script_path).new()
	scenario.cap = self
	scenario.tree = get_tree()
	if _size != Vector2i.ZERO:
		set_size(_size.x, _size.y)
	Settings.autosave = false
	if not Settings.set_preset(_preset):
		fail("unknown preset " + _preset)
	Settings.attach_viewport(get_tree().root)
	await scenario.run()
	_finish(EXIT_FAIL if _errors > 0 or _shots == 0 else EXIT_OK)


## Scenario API ---------------------------------------------------------------

## Frees the previous scene from load_scene, instantiates path under the root and returns it.
func load_scene(path: String) -> Node:
	if is_instance_valid(_scene_node):
		_scene_node.queue_free()
		await get_tree().process_frame
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		fail("cannot load scene " + path)
		return null
	var node: Node = packed.instantiate()
	get_tree().root.add_child(node)
	_scene_node = node
	await get_tree().process_frame
	return node


func wait_frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func wait_seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func set_size(width: int, height: int) -> void:
	get_window().size = Vector2i(width, height)


## Saves the viewport after the frame is drawn to evidence/screens/<scenario>/<name>.png,
## plus <name>.json with a 60-frame perf probe. Fails if the frame is uniform (blank or grey).
func shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		fail("no image for shot " + shot_name)
		return
	var dir: String = _output_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var png_path: String = dir.path_join(shot_name + ".png")
	if img.save_png(png_path) != OK:
		fail("cannot save " + png_path)
		return
	var luma: Vector2 = _luma_range(img)
	var perf: Dictionary = await _probe.measure(get_tree(), SHOT_PROBE_FRAMES)
	_write_json(dir.path_join(shot_name + ".json"), {
		"scenario": scenario_name,
		"name": shot_name,
		"png": png_path,
		"preset": Settings.get_preset_id(),
		"image_size": [img.get_width(), img.get_height()],
		"luma_min": snappedf(luma.x, 0.001),
		"luma_max": snappedf(luma.y, 0.001),
		"perf": perf,
	})
	if luma.y - luma.x < min_luma_range:
		fail("frame looks uniform (blank or grey): " + shot_name)
	_shots += 1


## Writes a longer perf run to evidence/screens/<scenario>/<name>.json.
func measure(measure_name: String, frames: int) -> void:
	var perf: Dictionary = await _probe.measure(get_tree(), frames)
	_write_json(_output_dir().path_join(measure_name + ".json"), {
		"scenario": scenario_name,
		"name": measure_name,
		"preset": Settings.get_preset_id(),
		"perf": perf,
	})


func fail(msg: String) -> void:
	_errors += 1
	push_error(msg)
	print("[CAPTURE] FAIL: " + msg)


## Internals ------------------------------------------------------------------

func _output_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join(EVIDENCE_REL + scenario_name).simplify_path()


func _luma_range(img: Image) -> Vector2:
	var lo: float = 1.0
	var hi: float = 0.0
	var w: int = img.get_width()
	var h: int = img.get_height()
	for gy: int in sample_grid:
		for gx: int in sample_grid:
			var px: int = int((gx + 0.5) * w / sample_grid)
			var py: int = int((gy + 0.5) * h / sample_grid)
			var l: float = img.get_pixel(px, py).get_luminance()
			lo = minf(lo, l)
			hi = maxf(hi, l)
	return Vector2(lo, hi)


func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		fail("cannot write " + path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func _on_timeout() -> void:
	fail("timeout after %.0f s" % timeout_s)
	_finish(EXIT_TIMEOUT)


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	print("[CAPTURE] scenario=%s shots=%d errors=%d exit=%d" % [scenario_name, _shots, _errors, code])
	get_tree().quit(code)
