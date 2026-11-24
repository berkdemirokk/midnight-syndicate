class_name CarFactory
extends RefCounted
## Builds a driveable car: an ArcadeCar with its model under a "Visual" node turned 180 degrees about Y
## (imported models face +Z), and a CarVisual that drives the model. Uses the imported car scene when it exists,
## else the dev mule. The meta "dev_car" on the result says which one was built.

const VISUAL_NAME: String = "Visual"
const VISUAL_TURN_RAD: float = PI
const CAR_VISUAL_NAME: String = "CarVisual"
const DEV_PAINT_MIX: float = 0.6  ## the dev mule paint is pulled this far toward grey so it still reads as a mule
const DEV_GREY: Color = Color(0.5, 0.52, 0.55)


## The car is not in a tree yet. Add it to the scene after this returns.
static func create(car_scene_path: String, spec: CarSpec, paint: Color) -> ArcadeCar:
	var car := ArcadeCar.new()
	car.spec = spec
	var model: Node3D = _instance_model(car_scene_path)
	var dev: bool = model == null
	if dev:
		model = DevVisual.build()
		paint = paint.lerp(DEV_GREY, DEV_PAINT_MIX)
	var visual := Node3D.new()
	visual.name = VISUAL_NAME
	visual.rotation.y = VISUAL_TURN_RAD
	car.add_child(visual)
	visual.add_child(model)
	var cv := CarVisual.new()
	cv.name = CAR_VISUAL_NAME
	car.add_child(cv)
	cv.setup(car, model)
	cv.set_paint(paint)
	car.set_meta("dev_car", dev)
	return car


static func _instance_model(path: String) -> Node3D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D
