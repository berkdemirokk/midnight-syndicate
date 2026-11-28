extends "res://devtools/capture_scenario.gd"
## Evaluation studio for the three police cars (CC BY 4.0 models): Polis Devriye (patrol), Polis Takip (interceptor),
## Polis SUV (heavy unit). Same stage as car_studio_marten (ShowroomSet). Per car: front34, side, wheel_closeup,
## tail_closeup, lights_on (brake lamps and the light bar). Then one row of the three cars.

const CARS: Array[String] = [
	"res://vehicles/police_patrol/police_patrol.tscn",
	"res://vehicles/police_interceptor/police_interceptor.tscn",
	"res://vehicles/police_suv/police_suv.tscn",
]
const IDS: Array[String] = ["police_patrol", "police_interceptor", "police_suv"]
const SETTLE_FRAMES: int = 30
const SHOT_SETTLE_FRAMES: int = 8
const CAM_FOV: float = 42.0
const CAR_SPACING: float = 4.6
const TARGET: Vector3 = Vector3(0.0, 0.7, 0.0)
const EYE_FRONT34: Vector3 = Vector3(-3.6, 1.4, 5.4)
const EYE_SIDE: Vector3 = Vector3(-6.2, 1.1, 0.0)
const EYE_REAR34: Vector3 = Vector3(3.6, 1.4, -5.0)
const EYE_ROW: Vector3 = Vector3(-4.0, 2.2, 13.0)
const ROW_TARGET: Vector3 = Vector3(0.0, 0.7, 0.0)

var _root: Node3D
var _cam: Camera3D
var _set: ShowroomSet


func run() -> void:
	_root = Node3D.new()
	_root.name = "PoliceStudio"
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
	await cap.wait_frames(SETTLE_FRAMES)

	for k: int in CARS.size():
		var car: CarLod = _spawn(CARS[k], 0.0)
		await cap.wait_frames(SETTLE_FRAMES)
		var p: String = IDS[k]
		_aim_at(EYE_FRONT34, TARGET)
		await cap.wait_frames(SHOT_SETTLE_FRAMES)
		await cap.shot(p + "_front34")
		_aim_at(EYE_REAR34, TARGET)
		await cap.wait_frames(SHOT_SETTLE_FRAMES)
		await cap.shot(p + "_rear34")
		_aim_at(EYE_SIDE, TARGET)
		await cap.wait_frames(SHOT_SETTLE_FRAMES)
		await cap.shot(p + "_side")
		_aim_at(Vector3(2.2, 0.55, 2.7), Vector3(0.8, 0.35, 1.3))
		await cap.wait_frames(SHOT_SETTLE_FRAMES)
		await cap.shot(p + "_wheel_closeup")
		_aim_at(Vector3(1.6, 1.0, -3.9), Vector3(0.0, 0.7, -2.3))
		await cap.wait_frames(SHOT_SETTLE_FRAMES)
		await cap.shot(p + "_tail_closeup")
		CarMaterials.set_brake_lights(car, true)
		_aim_at(EYE_REAR34, TARGET)
		await cap.wait_frames(SHOT_SETTLE_FRAMES)
		await cap.shot(p + "_lights_on")
		CarMaterials.set_brake_lights(car, false)
		car.queue_free()
		await cap.wait_frames(SHOT_SETTLE_FRAMES)

	var row: Array[CarLod] = []
	for k: int in CARS.size():
		row.append(_spawn(CARS[k], (k - 1) * CAR_SPACING))
	await cap.wait_frames(SETTLE_FRAMES)
	_aim_at(EYE_ROW, ROW_TARGET)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("police_row")


func _spawn(scene_path: String, x: float) -> CarLod:
	var packed: PackedScene = load(scene_path) as PackedScene
	var car: CarLod = packed.instantiate() as CarLod
	car.paint_colour = Color("#16305C")
	car.position = Vector3(x, 0.0, 0.0)
	_root.add_child(car)
	return car


func _aim_at(eye: Vector3, target: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(target)
