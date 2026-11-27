extends "res://devtools/capture_scenario.gd"
## Evaluation studio for the Arden Havoc (CC BY 4.0 model, copy of car_studio_kestrel with its own camera marks). Built in code, for looking at the car only (not a game scene).
## The stage is ShowroomSet: glossy mirror floor, contact shadow, three-point softbox lighting, gradient backdrop, neon.
## Shots: empty_studio (car hidden, baseline perf), front34, rear34, side, wheel_closeup, lights_on,
## lod1, lod2 (forced at 40 m and 100 m), paint_variants (three paints side by side).

const CAR_SCENE: String = "res://vehicles/arden_havoc/arden_havoc.tscn"
const SETTLE_FRAMES: int = 30
const SHOT_SETTLE_FRAMES: int = 8
const CAM_FOV: float = 42.0
const CAR_SPACING: float = 3.6
const TARGET: Vector3 = Vector3(0.0, 0.58, 0.0)
const PAINTS: Array[Color] = [
	Color(0.557, 0.059, 0.118),  ## candy red, the brief's #8E0F1E
	Color(0.04, 0.09, 0.36),  ## deep blue
	Color(0.2, 0.21, 0.23),  ## graphite (lifted: at 0.12 it read as black)
]
const EYE_FRONT34: Vector3 = Vector3(-3.3, 1.1, 4.9)
const EYE_REAR34: Vector3 = Vector3(3.4, 1.2, -4.5)
const EYE_SIDE: Vector3 = Vector3(-5.8, 0.9, 0.0)
const EYE_WHEEL: Vector3 = Vector3(2.2, 0.55, 2.7)
const WHEEL_TARGET: Vector3 = Vector3(0.795, 0.35, 1.395)
const EYE_LOD1: Vector3 = Vector3(-14.0, 1.3, 38.0)  ## about 40 m from the car
const EYE_LOD2: Vector3 = Vector3(-34.0, 1.6, 94.0)  ## about 100 m from the car
const EYE_PAINT: Vector3 = Vector3(-3.6, 1.6, 8.0)

var _root: Node3D
var _cam: Camera3D
var _car: CarLod
var _set: ShowroomSet


func run() -> void:
	_root = Node3D.new()
	_root.name = "CarStudio"
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
	_car = _spawn_car(PAINTS[0], false)
	await cap.wait_frames(SETTLE_FRAMES)

	_car.visible = false
	_set.contact_shadow.visible = false
	_aim(EYE_FRONT34)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("empty_studio")
	_car.visible = true
	_set.contact_shadow.visible = true

	_aim(EYE_FRONT34)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("front34")
	_aim(EYE_REAR34)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("rear34")
	_aim(EYE_SIDE)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("side")
	_aim_at(EYE_WHEEL, WHEEL_TARGET)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("wheel_closeup")
	_aim_at(Vector3(1.6, 1.0, -3.9), Vector3(0.0, 0.62, -2.3))
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("tail_closeup")
	_aim_at(Vector3(-1.5, 0.75, 4.5), Vector3(0.0, 0.42, 2.3))
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("nose_closeup")
	_aim_at(Vector3(-3.0, 0.85, 0.2), Vector3(0.0, 0.6, 0.2))
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("flank_closeup")
	_aim_at(Vector3(-2.4, 1.45, 1.6), Vector3(0.0, 1.0, -0.3))
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("cabin_closeup")
	_aim_at(Vector3(-2.5, 0.95, 3.6), Vector3(0.0, 0.55, 0.3))
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("hero34")

	CarMaterials.set_brake_lights(_car, true)
	_aim(EYE_REAR34)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("lights_on")
	CarMaterials.set_brake_lights(_car, false)

	_car.set_forced(1)
	_aim(EYE_LOD1)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("lod1")
	_car.set_forced(2)
	_aim(EYE_LOD2)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("lod2")
	_aim(EYE_REAR34)  # LOD2 up close: it is the road-mirror copy from 10 m and the sun-shadow caster, so a stray triangle shows
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("lod2_close")
	_aim(EYE_FRONT34)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("lod2_close_front")
	_car.set_forced(-1)
	_car.queue_free()
	_set.contact_shadow.visible = false
	await cap.wait_frames(SHOT_SETTLE_FRAMES)

	var row: Array[CarLod] = []
	for i: int in PAINTS.size():
		row.append(_spawn_car(PAINTS[i], true, (i - 1) * CAR_SPACING))
	await cap.wait_frames(SETTLE_FRAMES)
	_aim(EYE_PAINT)
	await cap.wait_frames(SHOT_SETTLE_FRAMES)
	await cap.shot("paint_variants")


func _spawn_car(paint: Color, force0: bool, x: float = 0.0) -> CarLod:
	var packed: PackedScene = load(CAR_SCENE) as PackedScene
	var car: CarLod = packed.instantiate() as CarLod
	car.paint_colour = paint
	car.force_lod0 = force0
	car.position = Vector3(x, 0.0, 0.0)
	_root.add_child(car)
	if force0:  # only the paint row: the main car's shadow is part of the set
		var sh: Node3D = ShowroomSet.make_contact_shadow(0.006)
		sh.position.x = x
		_root.add_child(sh)
	return car


func _aim(eye: Vector3) -> void:
	_aim_at(eye, TARGET)


func _aim_at(eye: Vector3, target: Vector3) -> void:
	_cam.position = eye
	_cam.look_at(target)
