class_name WheelSpray
extends Node3D
## Tyre spray thrown back and up off the rear wheels on a wet road, and the low mist band it leaves behind the car.
## Two emitters, so two draw calls per car: a soft mist over and behind the rear axle, and droplet streaks over both
## axles. shortcut: the front plumes come from the streak box as well, not from their own emitter, so they are not
## tuned apart from the rear ones; a third emitter would break the 2-draw-call budget. Amount and streak length grow
## with speed. Only update_nearest() decides which cars emit: the player and the two nearest rivals.

const NODE_NAME: String = "WheelSpray"
const MIN_KMH: float = 40.0  ## no spray below this speed
const FULL_KMH: float = 140.0  ## full amount and longest streaks here
const HALF_TRACK_M: float = 0.82  ## rear contacts, from CarFx (noctra_sable)
const HALF_WHEELBASE_M: float = 1.33
const MIST_AMOUNT: int = 90  ## at particle_amount_scale 1.0
const STREAK_AMOUNT: int = 110
const MIST_LIFE_S: float = 0.9
const STREAK_LIFE_S: float = 0.5
const SPRAY_HALF_Y_M: float = 0.08  ## emission box half height
const MIST_CENTER_Z: float = 3.4  ## car frame, behind the rear axle (forward is -Z)
const MIST_HALF_Z_M: float = 1.4
const SPRAY_Y_M: float = -0.3  ## car frame: tread height, about 0.17 m above the road (the car origin is 0.47 m up)
const MIST_RGB: Color = Color(0.5, 0.54, 0.6, 1.0)
const MIST_PEAK_ALPHA: float = 0.17
const STREAK_RGBA: Color = Color(0.24, 0.27, 0.31, 0.5)  ## dark grey spray: a light-coloured plume reads as a flame, with the bloom
## Own render layer (bit 16, layer 17): the Underglow light skips it, so the spray is not tinted violet by the player's light.
const SPRAY_LAYER: int = 1 << 16
const STREAK_LEN_MIN: float = 0.3
const STREAK_LEN_MAX: float = 0.6
const STREAK_DIR_LOCAL: Vector3 = Vector3(0.0, 0.4, 1.0)  ## thrown back and slightly up, car frame
const MIST_DIR_LOCAL: Vector3 = Vector3(0.0, 0.2, 1.0)
const RANGE_M: float = 40.0  ## culling box: trails run 20-40 m behind a car at 180 km/h
const SHADER_PATH: String = "res://shaders/wheel_spray.gdshader"

var car: ArcadeCar = null
var _mist: GPUParticles3D = null
var _streaks: GPUParticles3D = null
var _mist_pm: ParticleProcessMaterial = null
var _streak_pm: ParticleProcessMaterial = null
var _streak_mat: ShaderMaterial = null
var _wetness: float = 1.0  ## road wetness 0..1 (TimeOfDay.audio_wetness); night is 1
var _active: bool = true  ## set by update_nearest


func _ready() -> void:
	car = get_parent() as ArcadeCar
	_mist_pm = _mist_process()
	_streak_pm = _streak_process()
	_streak_mat = ShaderMaterial.new()
	_streak_mat.shader = load(SHADER_PATH) as Shader
	_streak_mat.set_shader_parameter("spray_color", STREAK_RGBA)
	_mist = FxUtil.emitter(MIST_AMOUNT, MIST_LIFE_S, _mist_pm, _mist_material(), Vector2(1.0, 1.0))
	_mist.position = Vector3(0.0, SPRAY_Y_M, MIST_CENTER_Z)
	_mist.layers = SPRAY_LAYER
	_mist.local_coords = true  ## spray moves with the car: its throw is car-relative, the car's speed is not added to it
	_streaks = FxUtil.emitter(STREAK_AMOUNT, STREAK_LIFE_S, _streak_pm, _streak_mat, Vector2(0.03, 1.0))
	_streaks.position = Vector3(0.0, SPRAY_Y_M, 0.0)
	_streaks.layers = SPRAY_LAYER
	_streaks.local_coords = true
	for e: GPUParticles3D in [_mist, _streaks]:
		e.visibility_aabb = AABB(Vector3(-RANGE_M, -RANGE_M, -RANGE_M), Vector3(2.0 * RANGE_M, 2.0 * RANGE_M, 2.0 * RANGE_M))
		add_child(e)
	Settings.changed.connect(_on_settings_changed)
	_apply_settings()
	set_process(car != null)  ## not under an ArcadeCar: no spray, nothing to follow


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)


func _on_settings_changed(_section: String) -> void:
	_apply_settings()


func _apply_settings() -> void:
	var scale_f: float = Settings.get_preset().particle_amount_scale
	_mist.amount = maxi(1, int(round(MIST_AMOUNT * scale_f)))
	_streaks.amount = maxi(1, int(round(STREAK_AMOUNT * scale_f)))


func _process(_delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var kmh: float = car.speed_kmh
	var rear_share: float = 0.5 * (float(car.wheel_contact[ArcadeCar.RL]) + float(car.wheel_contact[ArcadeCar.RR]))
	var k: float = activity_for(kmh, _wetness, rear_share) if _active else 0.0
	_mist.emitting = k > 0.0
	_streaks.emitting = k > 0.0
	_mist.amount_ratio = k
	_streaks.amount_ratio = k
	if k <= 0.0:
		return
	# Throw speed is relative to the car (local coords): spray is flung a few m/s back and up, it does not
	# take the car's 50 m/s with it. Grows a little with speed.
	var v_ms: float = car.linear_velocity.length()
	_mist_pm.initial_velocity_min = 0.5 + v_ms * 0.01
	_mist_pm.initial_velocity_max = 1.0 + v_ms * 0.02
	_streak_pm.initial_velocity_min = 2.0 + v_ms * 0.04
	_streak_pm.initial_velocity_max = 4.0 + v_ms * 0.08
	var ramp_t: float = smoothstep(MIN_KMH, FULL_KMH, kmh)
	_streak_mat.set_shader_parameter("streak_dir", car.global_transform.basis * STREAK_DIR_LOCAL.normalized())
	_streak_mat.set_shader_parameter("streak_len", lerpf(STREAK_LEN_MIN, STREAK_LEN_MAX, ramp_t))


## Spray strength 0..1: none below MIN_KMH, full at FULL_KMH, scaled by the road's wetness and the rear wheels on the ground.
static func activity_for(kmh: float, wetness: float, rear_share: float) -> float:
	return smoothstep(MIN_KMH, FULL_KMH, kmh) * clampf(wetness, 0.0, 1.0) * clampf(rear_share, 0.0, 1.0)


func set_wetness(w: float) -> void:
	_wetness = clampf(w, 0.0, 1.0)


func set_active(on: bool) -> void:
	_active = on


func is_active() -> bool:
	return _active


## Keeps spray on the player's car and the two cars nearest to it; every other car stops emitting.
## cars: every car of the race (Node3D with an optional WheelSpray child), player: the car the camera follows.
static func update_nearest(cars: Array, player: Node3D, rivals: int = 2) -> void:
	var others: Array = []
	for c: Variant in cars:
		if c != player and c is Node3D:
			others.append(c)
	var origin: Vector3 = player.global_position
	others.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	var picked: Array = others.slice(0, rivals)
	for c: Variant in cars:
		var ws: WheelSpray = (c as Node).get_node_or_null(NODE_NAME) as WheelSpray
		if ws != null:
			ws.set_active(c == player or picked.has(c))


func _mist_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL  ## lit: street lights and the car fill shade the mist
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = FxUtil.soft_sprite()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.33, 0.37, 1.0)  ## dim floor so the mist reads on the dark road
	mat.emission_energy_multiplier = 0.1
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 3.0  ## near the lens the mist fades out, as in rain_streak
	mat.distance_fade_max_distance = 7.0
	return mat


func _mist_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(HALF_TRACK_M + 0.1, SPRAY_HALF_Y_M, MIST_HALF_Z_M)
	pm.direction = MIST_DIR_LOCAL.normalized()
	pm.spread = 30.0
	pm.gravity = Vector3(0.0, -0.3, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var grow := Curve.new()  ## small at the tyre, billowing as it falls behind: a low band, not a cloud
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex
	var c: Color = MIST_RGB
	pm.color_ramp = FxUtil.ramp(PackedColorArray([
		Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, MIST_PEAK_ALPHA), Color(c.r, c.g, c.b, 0.0)]))
	return pm


func _streak_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(HALF_TRACK_M + 0.05, SPRAY_HALF_Y_M, HALF_WHEELBASE_M + 0.1)
	pm.direction = STREAK_DIR_LOCAL.normalized()
	pm.spread = 22.0
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	pm.color_initial_ramp = FxUtil.ramp(PackedColorArray([Color(1, 1, 1, 0.25), Color(1, 1, 1, 1.0)]))
	pm.color_ramp = FxUtil.ramp(PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)]))  ## droplets fade as they fly
	return pm
