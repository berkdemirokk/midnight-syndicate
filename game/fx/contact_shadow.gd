class_name ContactShadow
extends MeshInstance3D
## Soft contact shadow under a car: a flat quad of the car's footprint with darker spots at the wheels, just above the
## road. The Mobile renderer has no ambient occlusion, so without it cars look like they float. Race cars carry one
## blob that follows them (attach(car, true)); traffic cars one child blob (attach(car, false)); parked cars share one
## MultiMesh per cell (shadow_multimesh). All blobs share one material; its strength follows the time of day.
## Layer: MIRROR_SKIP_BIT, so the planar wet-road mirror leaves them out, like props and parked cars.

const LIFT_M: float = 0.03  ## above the road, so it does not z-fight the asphalt
const QUAD_HALF_M: Vector2 = Vector2(1.25, 2.7)  ## the quad is wider and longer than the car for the soft falloff
const BODY_HALF_M: Vector2 = Vector2(0.92, 2.25)
const WHEEL_XZ_M: Vector2 = Vector2(0.8, 1.4)
const WHEEL_R_M: float = 0.36
const MIRROR_SKIP_BIT: int = 1 << 4
const WORLD_LAYER_MASK: int = 1  ## the road is physics layer 1
const GROUND_RAY_UP_M: float = 0.8
const GROUND_RAY_DOWN_M: float = 80.0  ## long enough to find the road under a car in the air
const AIR_FADE_BEGIN_M: float = 0.8  ## height above the road where the blob starts to fade (a car at rest sits at ~0.47)
const AIR_FADE_END_M: float = 2.2
const DEFAULT_STRENGTH: float = 0.6
const SHADER: Shader = preload("res://shaders/contact_shadow.gdshader")

static var _material: ShaderMaterial = null
static var _mesh: PlaneMesh = null

var follow_ground: bool = false  ## race cars: a ray to the road each physics tick, aligned to the ground normal
var _car: Node3D = null


## Strength by time of day (TimeOfDay ids): strong and tight at noon and at night under the lamps, softer at sunset.
static func set_time_of_day(tod_id: String) -> void:
	var s: float = DEFAULT_STRENGTH
	match tod_id:
		"day":
			s = 0.7
		"sunset":
			s = 0.45
		"night":
			s = 0.85
	shared_material().set_shader_parameter("strength", s)


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("strength", DEFAULT_STRENGTH)
		_material.set_shader_parameter("quad_half", QUAD_HALF_M)
		_material.set_shader_parameter("body_half", BODY_HALF_M)
		_material.set_shader_parameter("wheel_xz", WHEEL_XZ_M)
		_material.set_shader_parameter("wheel_r", WHEEL_R_M)
	return _material


static func shared_mesh() -> PlaneMesh:
	if _mesh == null:
		_mesh = PlaneMesh.new()
		_mesh.size = QUAD_HALF_M * 2.0
	return _mesh


## Adds a blob to car. follow: the blob tracks the road under a moving race car; otherwise it is a child at the car
## origin (the car origin is the road contact for traffic cars). far_m > 0 hides it beyond that distance.
static func attach(car: Node3D, follow: bool, far_m: float = 0.0) -> ContactShadow:
	var s := ContactShadow.new()
	s.name = "ContactShadow"
	s.mesh = shared_mesh()
	s.material_override = shared_material()
	s.layers = MIRROR_SKIP_BIT
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.follow_ground = follow
	s.visibility_range_end = far_m
	s.visibility_range_end_margin = 4.0 if far_m > 0.0 else 0.0
	s.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if follow:
		s._car = car
	else:
		s.position = Vector3(0.0, LIFT_M, 0.0)
	car.add_child(s)
	if follow:
		s.top_level = true
	return s


## One MultiMesh of blobs for parked cars. model_xfs are the cars' transforms in the parent's space (any yaw, any
## nose direction: the blob is symmetric). far_m is the distance the blobs stop being drawn.
static func shadow_multimesh(model_xfs: Array[Transform3D], far_m: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = shared_mesh()
	mm.instance_count = model_xfs.size()
	for i: int in model_xfs.size():
		mm.set_instance_transform(i, blob_xf(model_xfs[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ContactShadowParked"
	mmi.multimesh = mm
	mmi.material_override = shared_material()
	mmi.layers = MIRROR_SKIP_BIT
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = far_m
	mmi.visibility_range_end_margin = 4.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mmi


## Flat blob at the car's footprint: keeps the yaw of the car, drops its pitch and roll.
static func blob_xf(xf: Transform3D) -> Transform3D:
	var z: Vector3 = Vector3(xf.basis.z.x, 0.0, xf.basis.z.z).normalized()
	var x: Vector3 = Vector3.UP.cross(z)
	return Transform3D(Basis(x, Vector3.UP, z), xf.origin + Vector3.UP * LIFT_M)


func _physics_process(_delta: float) -> void:
	if not follow_ground or _car == null or not is_instance_valid(_car) or not is_inside_tree():
		return
	var origin: Vector3 = _car.global_position
	var exclude: Array[RID] = []
	if _car is CollisionObject3D:
		exclude.append((_car as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * GROUND_RAY_UP_M, origin + Vector3.DOWN * GROUND_RAY_DOWN_M, WORLD_LAYER_MASK, exclude)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var ground: Vector3 = hit["position"] if not hit.is_empty() else Vector3(origin.x, origin.y - 0.47, origin.z)
	var normal: Vector3 = (hit["normal"] as Vector3) if not hit.is_empty() else Vector3.UP
	var height: float = (origin - ground).dot(normal)
	var z_axis: Vector3 = _car.global_basis.z
	z_axis = (z_axis - normal * z_axis.dot(normal)).normalized()
	if z_axis.length_squared() < 0.5:
		z_axis = Vector3.BACK
	var x_axis: Vector3 = normal.cross(z_axis)
	global_transform = Transform3D(Basis(x_axis, normal, z_axis), ground + normal * LIFT_M)
	set_instance_shader_parameter("lift_fade", 1.0 - smoothstep(AIR_FADE_BEGIN_M, AIR_FADE_END_M, height))
