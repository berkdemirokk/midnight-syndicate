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
## Layer bits left out of the mirror view: the road (bit 1, layer 2) and rain particles (bit 9, layer 10).
## Bit 0 (default layer of every VisualInstance3D) must stay in, or the mirror shows nothing.
@export var excluded_layers: int = (1 << 1) | (1 << 9)

var _vp: SubViewport
var _cam: Camera3D
var _materials: Array[ShaderMaterial] = []
var _enabled: bool = false
var _frame: int = 0


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = false
	_vp.handle_input_locally = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.cull_mask = 0xFFFFF & ~excluded_layers
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
	_cam.fov = main.fov
	_cam.keep_aspect = main.keep_aspect
	_cam.near = main.near
	_cam.far = main.far
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
	if every_second_frame:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if (_frame % 2 == 0) else SubViewport.UPDATE_DISABLED
