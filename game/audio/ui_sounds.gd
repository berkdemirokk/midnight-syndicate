class_name UiSounds
extends Node
## One-shot UI / race-flow sounds on the "UI" bus. No autoload needed: the static helpers create
## the node under the scene-tree root on first use. Usage: UiSounds.click(), UiSounds.countdown(3).

const POOL_SIZE := 6

static var _inst: UiSounds

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0


func _init() -> void:
	name = "UiSounds"
	for i: int in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = AudioLib.BUS_UI
		add_child(p)
		_pool.append(p)


func _ready() -> void:
	AudioLib.ensure_buses()


static func get_instance() -> UiSounds:
	if is_instance_valid(_inst):
		return _inst
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_inst = UiSounds.new()
	tree.root.add_child.call_deferred(_inst)
	return _inst


static func play(id: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var u := get_instance()
	if u != null:
		u._play(id, volume_db, pitch)


func _play(id: StringName, volume_db: float, pitch: float) -> void:
	if not is_inside_tree():
		return  # only possible in the very first frame of the app
	var s := AudioLib.get_stream(id)
	if s == null:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


static func click() -> void:
	play(&"ui_click")


static func confirm() -> void:
	play(&"ui_confirm")


static func back() -> void:
	play(&"ui_back")


## Countdown hook: step 3, 2, 1 -> beep (rising pitch), step 0 -> GO.
static func countdown(step: int) -> void:
	if step <= 0:
		play(&"countdown_go")
	else:
		play(&"countdown_beep", 0.0, 1.0 if step > 1 else 1.06)


static func finish() -> void:
	play(&"race_finish_sting")


static func cash() -> void:
	play(&"cash_tick", -2.0, randf_range(0.97, 1.05))
