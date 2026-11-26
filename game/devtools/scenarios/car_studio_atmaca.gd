extends "res://devtools/capture_scenario.gd"
## Evaluation studio for the Bosfor Atmaca (stock, modified, taxi) on the showroom stage.
## Shots per variant: <variant>_front34, <variant>_rear34, <variant>_side; plus modified_wheel,
## modified_lod1, modified_lod2 (forced at 40 m and 100 m) and a paint row of the stock car.

const SCENES: Dictionary = {
	"stock": "res://vehicles/bosfor_atmaca/atmaca_stock.tscn",
	"modified": "res://vehicles/bosfor_atmaca/atmaca_modified.tscn",
	"taxi": "res://vehicles/bosfor_atmaca/atmaca_taxi.tscn",
}
const SETTLE_FRAMES: int = 30
const SHOT_SETTLE_FRAMES: int = 8
const CAM_FOV: float = 42.0
const CAR_SPACING: float = 3.0
const TARGET: Vector3 = Vector3(0.0, 0.62, 0.0)
const EYE_FRONT34: Vector3 = Vector3(-2.9, 1.15, 4.3)
const EYE_REAR34: Vector3 = Vector3(3.0, 1.2, -4.2)
const EYE_SIDE: Vector3 = Vector3(-5.6, 0.9, 0.0)
const EYE_WHEEL: Vector3 = Vector3(2.0, 0.5, 2.4)
const WHEEL_TARGET: Vector3 = Vector3(0.74, 0.3, 1.225)
const EYE_LOD1: Vector3 = Vector3(-14.0, 1.3, 38.0)
const EYE_LOD2: Vector3 = Vector3(-34.0, 1.6, 94.0)
const EYE_PAINT: Vector3 = Vector3(-3.4, 1.5, 7.5)
const PAINTS: Array[Color] = [
	Color(0.84, 0.78, 0.62),  ## cream
	Color(0.9, 0.9, 0.88),  ## white
	Color(0.36, 0.06, 0.1),  ## burgundy
]

var _root: Node3D
var _cam: Camera3D
var _set: ShowroomSet


func run() -> void:
	_root = Node3D.new()
	_root.name = "CarStudioAtmaca"
	tree.root.add_child(_root)
	var we := WorldEnvironment.new()
	we.environment = ShowroomSet.make_environment()
	_root.add_child(we)
	_set = ShowroomSet.new()
	_root.add_child(_set)
	_set.build_studio()
	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	_root.add_child(_cam)
	_cam.current = true

	for variant: String in ["stock", "modified", "taxi"]:
		var car: CarLod = _spawn(variant, Color(-1.0, 0.0, 0.0), true)
		await cap.wait_frames(SETTLE_FRAMES)
		_aim(EYE_FRONT34, TARGET)
		await cap.wait_frames(SHOT_SETTLE_FRAMES)
		await cap.shot("%s_front34" % variant)
		_aim(EYE_REAR34, TARGET)
		await cap.wait_frames(SHOT_SETTLE_FRAMES)
		await cap.shot("%s_rear34" % variant)
		_aim(EYE_SIDE, TARGET)
		await cap.wait_frames(SHOT_SETTLE_FRAMES)
		await cap.shot("%s_side" % variant)
		if variant == "modified":
			_aim(EYE_WHEEL, WHEEL_TARGET)
			await cap.wait_frames(SHOT_SETTLE_FRAMES)
			await cap.shot("modified_wheel")
			car.set_forced(1)
			_aim(EYE_LOD1, TARGET)
			await cap.wait_frames(SHOT_SETTLE_FRAMES)
			await cap.shot("modified_lod1")
			car.set_forced(2)
			_aim(EYE_LOD2, TARGET)
			await cap.wait_frames(SHOT_SETTLE_FRAMES)
			await cap.shot("modified_lod2")
		car.queue_free()
		await cap.wait_frames(2)

	_set.contact_shadow.visible = false
	for i: int in PAINTS.size():
		_spawn("stock", PAINTS[i], false, (i - 1) * CAR_SPACING)
	var tx: CarLod = _spawn("taxi", Color(-1.0, 0.0, 0.0), false, 2.0 * CAR_SPACING)
	tx.position.z = -0.5
	await cap.wait_frames(SETTLE_FRAMES)
	_aim(EYE_PAINT, Vector3(1.5, 0.6, 0.0))
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("paint_row")


## paint.r < 0 keeps the paint the scene file sets.
func _spawn(variant: String, paint: Color, main_car: bool, x: float = 0.0) -> CarLod:
	var packed: PackedScene = load(SCENES[variant]) as PackedScene
	var car: CarLod = packed.instantiate() as CarLod
	if paint.r >= 0.0:
		car.paint_colour = paint
	car.force_lod0 = main_car or x != 0.0
	car.position = Vector3(x, 0.0, 0.0)
	_root.add_child(car)
	if not main_car:
		var sh: Node3D = ShowroomSet.make_contact_shadow(0.006)
		sh.position.x = x
		_root.add_child(sh)
	return car


func _aim(eye: Vector3, target: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(target)
