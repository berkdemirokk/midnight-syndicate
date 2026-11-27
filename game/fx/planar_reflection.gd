class_name PlanarReflection
extends Node
## Optional High-preset feature: renders a mirrored view of the main camera about a horizontal plane
## into a SubViewport at a fraction of the screen size and feeds it to the wet asphalt material.
## Off by default; the caller turns it on with set_enabled(true) and attaches materials with
## add_target_material(). Geometry that must reflect the scene but not the road stays on the default
## layer; the road must be put on layer bit 1 (layers = 2) by its owner, so the mirror skips it.

@export var plane_height: float = 0.0
@export_range(0.1, 1.0, 0.01) var resolution_fraction: float = 0.33
@export var every_second_frame: bool = false
## The mirror camera's far plane is min(main far, this): distant buildings do not reach a wet road reflection.
@export_range(10.0, 1000.0, 1.0) var max_distance_m: float = 150.0
## Layer bits left out of the mirror view: the road (bit 1), the car LOD0 detail meshes (bit 2, the mirror
## sees the mirror-only LOD1 copy on bit 3 instead), small props, dressing and parked cars (bit 4) and rain
## particles (bit 9) and the car fill bit (19: LOD0 and the other car meshes keep bit 0 or 3 for the mirror). See the layer table at the top of race_scene.gd.
## Bit 0 (default layer of every VisualInstance3D) must stay in, or the mirror shows nothing.
@export var excluded_layers: int = (1 << 1) | (1 << 2) | (1 << 4) | (1 << 9) | (1 << 19)

var _vp: SubViewport
var _cam: Camera3D
var _materials: Array[ShaderMaterial] = []
var _enabled: bool = false
var _frame: int = 0
var _env_made: bool = false


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = false
	_vp.handle_input_locally = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# No shadowed omni/spot light exists (headlights cast no shadow), so the mirror needs no shadow atlas.
	_vp.positional_shadow_atlas_size = 0
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.cull_mask = 0xFFFFF & ~excluded_layers
	# The mirror camera is moved in _process, not in physics: interpolating it warns every frame.
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_vp.add_child(_cam)
	_cam.current = true
	set_enabled(false)


func set_enabled(on: bool) -> void:
	_enabled = on
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("planar_enabled", 1.0 if on else 0.0)


func is_enabled() -> bool:
	return _enabled


## Hands the mirror texture to a wet asphalt material (uniforms planar_reflection, planar_enabled, planar_vp).
func add_target_material(mat: ShaderMaterial) -> void:
	if mat in _materials:
		return
	_materials.append(mat)
	mat.set_shader_parameter("planar_reflection", _vp.get_texture())
	mat.set_shader_parameter("planar_enabled", 1.0 if _enabled else 0.0)


func texture() -> Texture2D:
	return _vp.get_texture()


func _process(_delta: float) -> void:
	if not _enabled:
		return
	var main := get_viewport().get_camera_3d()
	if main == null:
		return
	var size: Vector2 = get_viewport().get_visible_rect().size * resolution_fraction
	var target := Vector2i(maxi(16, int(size.x)), maxi(16, int(size.y)))
	if _vp.size != target:
		_vp.size = target
	_make_far_environment()
	_cam.fov = main.fov
	_cam.keep_aspect = main.keep_aspect
	_cam.near = main.near
	_cam.far = minf(main.far, max_distance_m)
	# Mirror the camera position about the plane. The mirror view is a plain rotated camera (no
	# reflected world), so its projection is used directly to look up the texture in the shader.
	var p: Vector3 = main.global_position
	var mirrored_pos := Vector3(p.x, 2.0 * plane_height - p.y, p.z)
	var fwd: Vector3 = -main.global_transform.basis.z
	var mirrored_fwd := Vector3(fwd.x, -fwd.y, fwd.z)
	_cam.global_position = mirrored_pos
	_cam.look_at(mirrored_pos + mirrored_fwd, Vector3(0.0, -1.0, 0.0))
	var view := Projection(_cam.global_transform.affine_inverse())
	var vp: Projection = _cam.get_camera_projection() * view
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("planar_vp", vp)
	_frame += 1
	# Re-rendered on even frames only; the texture keeps the last frame on the others.
	if every_second_frame:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if (_frame % 2 == 0) else SubViewport.UPDATE_DISABLED
	else:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


## Beyond the far clip the mirror camera would show the night sky (a bright violet band on the far road). The mirror
## camera gets a copy of the world environment whose background is the fog colour, which the far city fades to anyway.
func _make_far_environment() -> void:
	if _env_made:
		return
	var world: World3D = get_viewport().world_3d
	if world == null or world.environment == null:
		return
	_env_made = true
	var env: Environment = world.environment.duplicate() as Environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = env.fog_light_color if env.fog_enabled else world.environment.background_color
	# The main pass blooms and tonemaps the reflected neon again: a second glow and ACES here only flatten it.
	env.glow_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	_cam.environment = env
