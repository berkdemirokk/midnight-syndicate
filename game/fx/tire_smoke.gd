class_name TireSmoke
extends Node3D
## Soft grey puffs from the rear wheel contacts while the car slides. CarFx decides when and how much;
## this node places puffs, trails them back with the car's wind and fades them over FADE_S.
## Lit (matte, not unshaded or emissive) so street lights and the car fill light show them at night.
## Puff count follows Settings particle_amount_scale.

const FADE_S: float = 1.6
const PUFF_COLOR: Color = Color(0.62, 0.64, 0.68, 1.0)
const PUFF_PEAK_ALPHA: float = 0.42
const MAX_DRIFT_MS: float = 4.0  ## sideways puff speed cap
const MAX_WIND_MS: float = 8.0  ## trail speed cap, so puffs stay near the car's wake
const QUAD_M: float = 1.2
const TRAIL_M: float = 20.0  ## culling radius around each emitter, longer than any trail
## shortcut: one emitter per rear wheel, drift and wind capped, upgrade if trails need per-wheel tuning
@export var puff_amount: int = 36  ## at particle_amount_scale 1.0; slip ratio scales it down
@export var puff_layer: int = 1  ## render layer of the puffs; CarFx sets the car body's layers

const BURST_PUFFS: int = 6  ## puffs per wheel on the first frame of a slide

var _emitters: Array[GPUParticles3D] = []
var _pms: Array[ParticleProcessMaterial] = []
var _was_on: PackedByteArray = PackedByteArray([0, 0])


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = FxUtil.soft_sprite()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	## A dim self-light floor so the grey stays readable on the night road; lit shading still gives the form.
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.32, 0.36, 1.0)
	mat.emission_energy_multiplier = 0.6
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 1.5  ## fully transparent inside this distance
	mat.distance_fade_max_distance = 5.0  ## fully opaque beyond this distance
	var ramp_colors := PackedColorArray([
		Color(PUFF_COLOR.r, PUFF_COLOR.g, PUFF_COLOR.b, 0.0),
		Color(PUFF_COLOR.r, PUFF_COLOR.g, PUFF_COLOR.b, PUFF_PEAK_ALPHA),
		Color(PUFF_COLOR.r, PUFF_COLOR.g, PUFF_COLOR.b, 0.0),
	])
	var grow := Curve.new()  ## puffs start small at the tyre and billow out as they fall behind
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	for i: int in 2:
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, 1.0, 0.0)
		pm.spread = 25.0
		pm.initial_velocity_min = 0.3
		pm.initial_velocity_max = 0.8
		pm.gravity = Vector3(0.0, 0.3, 0.0)
		pm.scale_min = 0.9
		pm.scale_max = 1.3
		pm.scale_curve = grow_tex
		pm.color_ramp = FxUtil.ramp(ramp_colors)
		var e := FxUtil.emitter(puff_amount, FADE_S, pm, mat, Vector2(QUAD_M, QUAD_M))
		e.layers = 1 << (puff_layer - 1)
		## The default culling box is 8 m around the emitter, and puffs trail up to ~13 m behind it: without this they are culled.
		e.visibility_aabb = AABB(Vector3(-TRAIL_M, -TRAIL_M, -TRAIL_M), Vector3(2.0 * TRAIL_M, 2.0 * TRAIL_M, 2.0 * TRAIL_M))
		add_child(e)
		_emitters.append(e)
		_pms.append(pm)
	Settings.changed.connect(_on_settings_changed)
	_apply_settings()


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)


func _on_settings_changed(_section: String) -> void:
	_apply_settings()


func _apply_settings() -> void:
	var scale_f: float = Settings.get_preset().particle_amount_scale
	for e: GPUParticles3D in _emitters:
		e.amount = maxi(1, int(round(puff_amount * scale_f)))


func set_puff_layers(mask: int) -> void:
	for e: GPUParticles3D in _emitters:
		e.layers = mask


## Positions the puffs at the wheel contacts (world space) and sets their drift. Called by CarFx.
## slip[i] is the puff amount for wheel i, 0..1; a wheel with 0 emits nothing.
## lateral_dir and lateral_speed push puffs off the slide; wind (world, horizontal) is the car's trail.
func update_puffs(world_points: PackedVector3Array, slip: PackedFloat32Array, lateral_dir: Vector3, lateral_speed: float, wind: Vector3 = Vector3.ZERO) -> void:
	var drift: float = clampf(lateral_speed, 0.0, MAX_DRIFT_MS)
	var trail: Vector3 = wind.limit_length(MAX_WIND_MS)
	var vel: Vector3 = trail - lateral_dir * drift
	vel.y = 0.0
	var speed: float = vel.length()
	var dir: Vector3 = (vel.normalized() if speed > 0.001 else Vector3.ZERO) + Vector3.UP * 0.35
	for i: int in mini(_emitters.size(), world_points.size()):
		var e := _emitters[i]
		var on: bool = slip[i] > 0.0
		e.global_position = world_points[i]
		e.emitting = on
		e.amount_ratio = clampf(slip[i], 0.0, 1.0)
		var pm := _pms[i]
		pm.direction = dir.normalized()
		pm.initial_velocity_min = speed * 0.5 + 0.2
		pm.initial_velocity_max = speed * 0.8 + 0.5
		# On the first frame of a slide, puff at once: the continuous emitter needs a moment to fill.
		if on and _was_on[i] == 0:
			for k: int in BURST_PUFFS:
				e.emit_particle(Transform3D(Basis.IDENTITY, world_points[i]), dir.normalized() * (speed * 0.5 + 0.3),
					Color.WHITE, Color.WHITE, GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY)
		_was_on[i] = 1 if on else 0


func stop() -> void:
	for e: GPUParticles3D in _emitters:
		e.emitting = false
