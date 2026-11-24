extends RefCounted
## Test helper: builds a large flat ground (layer 1), an optional uphill slope and a drop platform.
## Usage from a test: const FlatWorld = preload("res://tests/helpers/flat_world.gd"), then FlatWorld.make_ground().
## The ground top surface passes through y = 0. Slopes rise toward -Z (the car's forward direction).

const GROUND_HALF_SIZE: float = 10000.0  ## long enough that a 45 s run at 330 km/h stays on the plane
const GROUND_THICKNESS: float = 2.0


## Flat ground when slope_percent is 0. Positive slope_percent rises toward -Z (e.g. 10.0 = 10 % grade).
static func make_ground(slope_percent: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var size: float = 2.0 * GROUND_HALF_SIZE
	body.add_child(_box(Vector3(size, GROUND_THICKNESS, size), Vector3(0.0, -GROUND_THICKNESS * 0.5, 0.0)))
	body.rotation.x = atan(slope_percent / 100.0)
	return body


## A box platform whose top surface sits at top_height, centred at centre_xz (x, z).
static func make_drop_platform(size_xz: Vector2, top_height: float, centre_xz: Vector2) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var thick: float = GROUND_THICKNESS
	body.position = Vector3(centre_xz.x, top_height - thick * 0.5, centre_xz.y)
	body.add_child(_box(Vector3(size_xz.x, thick, size_xz.y), Vector3.ZERO))
	return body


static func _box(size: Vector3, at: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	return cs
