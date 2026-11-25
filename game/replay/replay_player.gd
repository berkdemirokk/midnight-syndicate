class_name ReplayPlayer
extends Node3D
## Plays a ReplayRecorder back after a race. Every car is frozen and driven from its recorded state (pose,
## wheels, steer, nitro, drift, brake input, speed). The ReplayDirector owns the camera. A small overlay shows
## REPLAY, a progress bar, PLAY/PAUSE, RESTART and RESULTS. Runs in the physics tick, so the director's ray
## tests are valid. Leaving (RESULTS, or the node being freed) restores the cars.

signal exited

const UI_LAYER: int = 22  ## above the race overlay (20) and the dev watermark (21)
const TAG_PX: int = 28
const BAR_PX: int = 10
const EDGE_PX: float = 24.0
const BUTTON_GAP_PX: float = 12.0
const LEFT_END: float = 0.0

var _recorder: ReplayRecorder = null
var _cars: Array[ArcadeCar] = []
var _player_index: int = -1
var _track: Track = null
var _director: ReplayDirector = ReplayDirector.new()
var _camera: Camera3D = null
var _buf: PackedFloat32Array = PackedFloat32Array()
var _exclude: Array[RID] = []
var _saved_freeze: Array[bool] = []
var _saved_process: Array[bool] = []
var _prev_nitro: PackedByteArray = PackedByteArray()
var _t: float = 0.0
var _playing: bool = true
var _progress_hint: float = -1.0
var _bar: ProgressBar = null
var _play_btn: Button = null
var _restore_done: bool = false


## Takes over the race for playback. cars includes the player; the recorder must hold data.
func setup(recorder: ReplayRecorder, cars: Array[ArcadeCar], track: Track, player: ArcadeCar) -> void:
	_recorder = recorder
	_track = track
	_cars = cars.duplicate()
	_player_index = _cars.find(player)
	_buf.resize(_cars.size() * ReplayRecorder.STRIDE)
	_prev_nitro.resize(_cars.size())
	_director.setup(track)
	# Only the player's body is excluded from the director's view rays: rival cars are occluders.
	_exclude.clear()
	if player != null:
		_exclude.append(player.get_rid())
	for i: int in _cars.size():
		var c: ArcadeCar = _cars[i]
		_saved_freeze.append(c.freeze)
		_saved_process.append(c.is_physics_processing())
		c.freeze = true
		c.set_physics_process(false)
		c.reset_physics_interpolation()
	_camera = Camera3D.new()
	_camera.name = "ReplayCamera"
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()
	_build_ui()
	seek(LEFT_END)


func duration_s() -> float:
	return _recorder.duration_s() if _recorder != null else 0.0


func time_s() -> float:
	return _t


func is_playing() -> bool:
	return _playing


func director() -> ReplayDirector:
	return _director


func camera() -> Camera3D:
	return _camera


## Jumps the replay clock (clamped to the recording). Used by restart and by tests.
func seek(t: float) -> void:
	_t = clampf(t, 0.0, duration_s())
	_progress_hint = -1.0


func toggle_play() -> void:
	if _t >= duration_s():
		seek(LEFT_END)
		_playing = true
	else:
		_playing = not _playing
	_refresh_buttons()


func restart() -> void:
	seek(LEFT_END)
	_playing = true
	_refresh_buttons()


## Ends the replay: the race scene shows the results again.
func exit_replay() -> void:
	_restore()
	exited.emit()


func _physics_process(delta: float) -> void:
	if _recorder == null or not _recorder.has_data():
		return
	if _playing:
		_t += delta
		if _t >= duration_s():
			_t = duration_s()
			_playing = false
			_refresh_buttons()
	_recorder.read(_t, _buf)
	for i: int in _cars.size():
		_apply_car(i)
	if _player_index < 0:
		return
	var d: int = _player_index * ReplayRecorder.STRIDE
	var origin: Vector3 = Vector3(_buf[d + ReplayRecorder.F_POS], _buf[d + ReplayRecorder.F_POS + 1], _buf[d + ReplayRecorder.F_POS + 2])
	var q: Quaternion = Quaternion(_buf[d + ReplayRecorder.F_QUAT], _buf[d + ReplayRecorder.F_QUAT + 1], _buf[d + ReplayRecorder.F_QUAT + 2], _buf[d + ReplayRecorder.F_QUAT + 3])
	var car_xf: Transform3D = Transform3D(Basis(q), origin)
	var vel: Vector3 = Vector3(_buf[d + ReplayRecorder.F_VEL], _buf[d + ReplayRecorder.F_VEL + 1], _buf[d + ReplayRecorder.F_VEL + 2])
	var progress: float = _track.get_progress(origin, _progress_hint) if _track != null else 0.0
	_progress_hint = progress
	_director.update(_t, duration_s(), car_xf, vel, progress, get_world_3d().direct_space_state, _exclude, delta)
	_camera.global_transform = _director.pose
	_camera.fov = _director.fov_deg
	if _bar != null:
		_bar.value = _t / maxf(duration_s(), 1e-6)


## Writes one car's recorded state onto the frozen body. Nitro and drift signals fire on changes so the FX react.
func _apply_car(i: int) -> void:
	var car: ArcadeCar = _cars[i]
	var d: int = i * ReplayRecorder.STRIDE
	var origin: Vector3 = Vector3(_buf[d + ReplayRecorder.F_POS], _buf[d + ReplayRecorder.F_POS + 1], _buf[d + ReplayRecorder.F_POS + 2])
	var q: Quaternion = Quaternion(_buf[d + ReplayRecorder.F_QUAT], _buf[d + ReplayRecorder.F_QUAT + 1], _buf[d + ReplayRecorder.F_QUAT + 2], _buf[d + ReplayRecorder.F_QUAT + 3])
	car.global_transform = Transform3D(Basis(q), origin)
	car.reset_physics_interpolation()
	car.linear_velocity = Vector3(_buf[d + ReplayRecorder.F_VEL], _buf[d + ReplayRecorder.F_VEL + 1], _buf[d + ReplayRecorder.F_VEL + 2])
	car.steer_angle_rad = _buf[d + ReplayRecorder.F_STEER]
	for w: int in ReplayRecorder.WHEEL_COUNT:
		car.wheel_spin_rad[w] = _buf[d + ReplayRecorder.F_SPIN + w]
		car.wheel_compression[w] = _buf[d + ReplayRecorder.F_COMP + w]
		car.wheel_contact[w] = ((int(_buf[d + ReplayRecorder.F_CONTACT]) >> w) & 1) == 1
	car.speed_kmh = _buf[d + ReplayRecorder.F_SPEED]
	car.drift_angle_deg = _buf[d + ReplayRecorder.F_DRIFT_DEG]
	car.is_drifting = _buf[d + ReplayRecorder.F_DRIFT] > 0.5
	if car.input != null:
		car.input.brake = _buf[d + ReplayRecorder.F_BRAKE]
	var nitro: bool = _buf[d + ReplayRecorder.F_NITRO] > 0.5
	if nitro != car.nitro_active:
		car.nitro_active = nitro
		if nitro:
			car.nitro_started.emit()
		else:
			car.nitro_ended.emit()


func _restore() -> void:
	if _restore_done:
		return
	_restore_done = true
	for i: int in _cars.size():
		var c: ArcadeCar = _cars[i]
		if not is_instance_valid(c):
			continue
		c.freeze = _saved_freeze[i]
		c.set_physics_process(_saved_process[i])
	if is_instance_valid(_camera):
		_camera.current = false


func _exit_tree() -> void:
	_restore()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ReplayUi"
	layer.layer = UI_LAYER
	add_child(layer)
	var root := Control.new()
	root.theme = MSTheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var tag: Label = MSTheme.make_label(I18n.t("replay.tag"), "bold", TAG_PX, MSTheme.AMBER)
	tag.position = Vector2(EDGE_PX, EDGE_PX)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tag)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = EDGE_PX
	bottom.offset_right = -EDGE_PX
	bottom.offset_top = -EDGE_PX * 3.0
	bottom.offset_bottom = -EDGE_PX
	bottom.add_theme_constant_override("separation", int(BUTTON_GAP_PX))
	root.add_child(bottom)
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0.0, BAR_PX)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_bar)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", int(BUTTON_GAP_PX))
	bottom.add_child(row)
	_play_btn = _button(row, func() -> void: toggle_play())
	_button(row, func() -> void: restart()).text = I18n.t("replay.restart")
	_button(row, func() -> void: exit_replay()).text = I18n.t("replay.results")
	_refresh_buttons()


func _button(parent: Container, handler: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(MSTheme.BUTTON_MIN_W * 0.5, MSTheme.BUTTON_MIN_H)
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _refresh_buttons() -> void:
	if _play_btn == null:
		return
	if _playing:
		_play_btn.text = I18n.t("replay.pause")
	elif _t >= duration_s():
		_play_btn.text = I18n.t("replay.again")
	else:
		_play_btn.text = I18n.t("replay.play")
