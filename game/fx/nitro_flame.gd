class_name NitroFlame
extends Node3D
## Two tight additive flames at the exhaust tips: a bright core cone (white-hot base, electric blue, magenta
## tip) with a wider halo, an ignition surge and one small OmniLight. Unshaded, so the scene does not light
## them. Drive with set_active(), set_strength() and pop(); is_emitting() reports the active state.
## The flames are meshes, not particles: a particle puff read as white smoke at speed (see FX_AND_SHADERS.md).

const LEN_MIN: float = 0.6  ## metres at ignition
const LEN_MAX: float = 1.2  ## metres at full strength
const CORE_RADIUS: float = 0.06  ## base radius: 0.12 m wide
const HALO_RADIUS: float = 0.16
const HALO_LEN: float = 0.8  ## the halo is shorter than the core
const RINGS: int = 4
const SIDES: int = 12
const POP_TIME: float = 0.15
const POP_LEN_MUL: float = 1.35
const POP_GLOW_MUL: float = 2.5
const POP_LIGHT_MUL: float = 2.0
const FLICKER_HZ: float = 23.0
const FLICKER_LEN: float = 0.07  ## length jitter from the sine
const FLICKER_NOISE: float = 0.05  ## random jitter per frame
const WHITE: Color = Color(1.0, 1.0, 1.0)
const BLUE: Color = Color(0.1, 0.5, 1.0)
const MAGENTA: Color = Color(1.0, 0.1, 0.9)

@export var light_energy: float = 3.0
@export var light_range: float = 4.0
@export var core_glow: float = 3.5  ## HDR brightness of the core; above 1.0 it blooms
@export var halo_glow: float = 2.0

var _holders: Array[Node3D] = []
var _cores: Array[MeshInstance3D] = []
var _halos: Array[MeshInstance3D] = []
var _core_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _light: OmniLight3D
var _strength: float = 0.0
var _pop_timer: float = 0.0
var _active: bool = false
var _time: float = 0.0


func _ready() -> void:
	_core_mat = _flame_material()
	_halo_mat = _flame_material()
	var core_mesh: ArrayMesh = _cone_mesh(CORE_RADIUS, true)
	var halo_mesh: ArrayMesh = _cone_mesh(HALO_RADIUS, false)
	for i: int in 2:
		var holder := Node3D.new()
		# Cone axis is +Y and the tip is at +Y; rotating 90 degrees about X turns the tip to the car's rear (+Z).
		holder.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		add_child(holder)
		_holders.append(holder)
		var halo := _flame_mesh(halo_mesh, _halo_mat)
		holder.add_child(halo)
		_halos.append(halo)
		var core := _flame_mesh(core_mesh, _core_mat)
		holder.add_child(core)
		_cores.append(core)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.3, 0.55, 1.0)
	_light.light_energy = 0.0
	_light.omni_range = light_range
	_light.shadow_enabled = false
	add_child(_light)
	set_active(false)


## Car-local points of the exhaust tips. The flames start there and point back (+Z).
func set_exhaust_points(points: PackedVector3Array) -> void:
	var mid: Vector3 = Vector3.ZERO
	for i: int in mini(points.size(), _holders.size()):
		_holders[i].position = points[i]
		mid += points[i]
	if points.size() > 0:
		_light.position = mid / float(points.size()) + Vector3(0.0, 0.0, 0.5)


func set_active(on: bool) -> void:
	_active = on
	for h: Node3D in _holders:
		h.visible = on
	_light.visible = on
	if on:
		set_process(true)
	else:
		_pop_timer = 0.0
		_light.light_energy = 0.0
		set_process(false)


## Render layers for the flame meshes (CarFx passes the car body's layers).
func set_mesh_layers(mask: int) -> void:
	for mi: MeshInstance3D in _cores:
		mi.layers = mask
	for mi: MeshInstance3D in _halos:
		mi.layers = mask


func is_emitting() -> bool:
	return _active


## Flame length and brightness, 0..1. Grows with car speed while nitro is on.
func set_strength(v: float) -> void:
	_strength = clampf(v, 0.0, 1.0)


## Ignition surge: a short longer, brighter flame and a light flash.
func pop() -> void:
	_pop_timer = POP_TIME
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	var popping: bool = _pop_timer > 0.0
	if popping:
		_pop_timer = maxf(_pop_timer - delta, 0.0)
	if not _active and not popping:
		set_process(false)
		return
	var jitter: float = sin(_time * TAU * FLICKER_HZ) * FLICKER_LEN + randf_range(-FLICKER_NOISE, FLICKER_NOISE)
	var length: float = lerpf(LEN_MIN, LEN_MAX, _strength) * (POP_LEN_MUL if popping else 1.0) * (1.0 + jitter)
	var width: float = 1.0 + 0.5 * jitter
	for i: int in _cores.size():
		_cores[i].scale = Vector3(width, length, width)
		_halos[i].scale = Vector3(width, length * HALO_LEN, width)
	var glow: float = (POP_GLOW_MUL if popping else 1.0) * (1.0 + jitter)
	_core_mat.albedo_color = Color(core_glow, core_glow, core_glow) * glow
	_halo_mat.albedo_color = Color(halo_glow, halo_glow, halo_glow) * glow
	_light.light_energy = light_energy * _strength * (POP_LIGHT_MUL if popping else 1.0) if _active else 0.0


func _flame_mesh(mesh: ArrayMesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Unshaded, additive, two-sided, no depth write: the flame is never lit or sorted against the car.
func _flame_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


## Open cone along +Y, base radius `radius` at y = 0, tip at y = 1. Colour and alpha are per vertex.
func _cone_mesh(radius: float, core: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: int in SIDES:
		var a0: float = TAU * float(s) / float(SIDES)
		var a1: float = TAU * float(s + 1) / float(SIDES)
		for r: int in RINGS:
			var t0: float = float(r) / float(RINGS)
			var t1: float = float(r + 1) / float(RINGS)
			_put(st, radius, t0, a0, core)
			_put(st, radius, t0, a1, core)
			_put(st, radius, t1, a1, core)
			_put(st, radius, t0, a0, core)
			_put(st, radius, t1, a1, core)
			_put(st, radius, t1, a0, core)
	return st.commit()


func _put(st: SurfaceTool, radius: float, t: float, angle: float, core: bool) -> void:
	var rr: float = radius * (1.0 - t)
	st.set_color(_ramp(t, core))
	st.add_vertex(Vector3(cos(angle) * rr, t, sin(angle) * rr))


## Along the flame (t = 0 at the exhaust, 1 at the tip): core is white-hot, then electric blue, then magenta.
func _ramp(t: float, core: bool) -> Color:
	var rgb: Color = WHITE.lerp(BLUE, smoothstep(0.0, 0.2, t)) if core else BLUE
	rgb = rgb.lerp(MAGENTA, smoothstep(0.45, 1.0, t))
	var a: float = pow(1.0 - t, 0.9) if core else 0.6 * pow(1.0 - t, 1.5)
	return Color(rgb.r, rgb.g, rgb.b, a)
