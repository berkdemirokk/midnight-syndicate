class_name DevVisual
extends RefCounted
## Temporary stand-in car, built in code. Deliberately a dev mule: a flat grey wedge, four cylinder wheels
## and a "DEV CAR" label. Not final art. Nose faces +Z like an imported model; CarFactory turns it.
## Node names follow the car contract: body, glass, wheel_FL..RR (origin at hub), brake_FL..RR, lights_front, lights_rear.

const HALF_WIDTH: float = 0.93
const HALF_LENGTH: float = 2.15
const WHEEL_X: float = 0.83
const WHEEL_Z: float = 1.33
const WHEEL_RADIUS: float = 0.335
const WHEEL_WIDTH: float = 0.26
const BRAKE_RADIUS: float = 0.22
const WHEEL_NAMES: PackedStringArray = ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]
const BRAKE_NAMES: PackedStringArray = ["brake_FL", "brake_FR", "brake_RL", "brake_RR"]
const GREY: Color = Color(0.5, 0.52, 0.55)
const TYRE: Color = Color(0.08, 0.08, 0.09)
const BRAKE_COLOUR: Color = Color(0.7, 0.2, 0.2)
const LABEL_TEXT: String = "DEV CAR"
const LABEL_COLOUR: Color = Color(1.0, 0.75, 0.2)
const LABEL_PX: int = 40
const LABEL_HEIGHT_M: float = 1.5
const LABEL_PIXEL_SIZE: float = 0.005


## Builds the dev mule. The paint is applied by CarVisual.set_paint through the M_Paint material.
static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "DevCar"
	var body := MeshInstance3D.new()
	body.name = "body"
	body.mesh = _wedge_mesh()
	body.material_override = _material("M_Paint", GREY)
	root.add_child(body)
	var glass := MeshInstance3D.new()
	glass.name = "glass"
	var cabin := BoxMesh.new()
	cabin.size = Vector3(1.5, 0.3, 1.6)
	glass.mesh = cabin
	glass.position = Vector3(0.0, 0.5, -0.2)
	glass.material_override = _material("M_Glass", Color(0.05, 0.07, 0.1))
	root.add_child(glass)
	for i: int in WHEEL_NAMES.size():
		var sx: float = -1.0 if i % 2 == 0 else 1.0
		var front: bool = i < 2
		var z: float = WHEEL_Z if front else -WHEEL_Z
		var wheel := Node3D.new()
		wheel.name = WHEEL_NAMES[i]
		wheel.position = Vector3(sx * WHEEL_X, 0.0, z)
		wheel.add_child(_cylinder(WHEEL_RADIUS, WHEEL_WIDTH, TYRE, "tyre"))
		root.add_child(wheel)
		var brake := Node3D.new()
		brake.name = BRAKE_NAMES[i]
		brake.position = wheel.position
		brake.add_child(_cylinder(BRAKE_RADIUS, WHEEL_WIDTH * 0.2, BRAKE_COLOUR, "disc"))
		root.add_child(brake)
	root.add_child(_light_node("lights_front", Vector3(0.0, 0.3, HALF_LENGTH), Color(1.0, 0.95, 0.8), "M_LightFront"))
	root.add_child(_light_node("lights_rear", Vector3(0.0, 0.3, -HALF_LENGTH), Color(0.9, 0.05, 0.05), "M_LightRear"))
	var label := Label3D.new()
	label.name = "DevLabel"
	label.text = LABEL_TEXT
	label.font_size = LABEL_PX
	label.pixel_size = LABEL_PIXEL_SIZE
	label.modulate = LABEL_COLOUR
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = Vector3(0.0, LABEL_HEIGHT_M, 0.0)
	root.add_child(label)
	return root


## Flat grey wedge: low tail, lower nose. Eight corners, six quads, no collision (the car has its own).
static func _wedge_mesh() -> ArrayMesh:
	var v: Array[Vector3] = [
		Vector3(-HALF_WIDTH, 0.12, -HALF_LENGTH), Vector3(HALF_WIDTH, 0.12, -HALF_LENGTH),
		Vector3(HALF_WIDTH, 0.12, HALF_LENGTH), Vector3(-HALF_WIDTH, 0.12, HALF_LENGTH),
		Vector3(-HALF_WIDTH, 0.62, -HALF_LENGTH), Vector3(HALF_WIDTH, 0.62, -HALF_LENGTH),
		Vector3(HALF_WIDTH, 0.30, HALF_LENGTH), Vector3(-HALF_WIDTH, 0.30, HALF_LENGTH)]
	var quads: Array[PackedInt32Array] = [
		PackedInt32Array([0, 3, 2, 1]), PackedInt32Array([4, 5, 6, 7]),
		PackedInt32Array([0, 1, 5, 4]), PackedInt32Array([1, 2, 6, 5]),
		PackedInt32Array([2, 3, 7, 6]), PackedInt32Array([3, 0, 4, 7])]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q: PackedInt32Array in quads:
		for idx: int in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			st.add_vertex(v[idx])
	st.generate_normals()
	return st.commit()


static func _cylinder(radius: float, width: float, colour: Color, label: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = width
	cyl.radial_segments = 16
	mi.mesh = cyl
	mi.rotation.z = PI * 0.5  # axis along X, the axle
	mi.material_override = _material("M_Tyre" if label == "tyre" else "M_Disc", colour)
	return mi


static func _light_node(node_name: String, at: Vector3, colour: Color, mat_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = at
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 0.12, 0.06)
	mi.mesh = box
	var mat := _material(mat_name, colour * 0.2)
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = 1.0
	mi.material_override = mat
	n.add_child(mi)
	return n


static func _material(mat_name: String, colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.resource_name = mat_name
	mat.albedo_color = colour
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
