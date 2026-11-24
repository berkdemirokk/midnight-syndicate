extends RaceManager
## Fixed race values for the HUD tests and the ui_* capture scenarios. Set the fake_* fields before use.
## Not a capture scenario: capture only runs scripts it is asked for by name.

var fake_position: int = 1
var fake_cars: int = 1
var fake_lap: int = 1
var fake_lap_time: float = 0.0
var fake_best: float = 0.0
var fake_progress: Dictionary = {}  ## ArcadeCar instance id -> 0..1 lap progress
var rivals: Array[ArcadeCar] = []  ## returned by get_cars(); the HUD skips the player's own car


func get_position(_car: ArcadeCar) -> int:
	return fake_position


func get_lap(_car: ArcadeCar) -> int:
	return fake_lap


func get_current_lap_time(_car: ArcadeCar) -> float:
	return fake_lap_time


func get_best_lap_time(_car: ArcadeCar) -> float:
	return fake_best


func get_car_count() -> int:
	return fake_cars


func get_lap_progress(car: ArcadeCar) -> float:
	return float(fake_progress.get(car.get_instance_id(), 0.0))


func get_cars() -> Array:
	return rivals


## Dark blurred-gradient backdrop with soft neon blobs, for the HUD and menu captures.
static func make_backdrop() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = -10
	var base := TextureRect.new()
	base.texture = _radial(Color(0.10, 0.13, 0.22), MSTheme.BG)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base.stretch_mode = TextureRect.STRETCH_SCALE
	layer.add_child(base)
	var blobs: Array = [
		[Vector2(0.22, 0.30), 0.55, MSTheme.CYAN],
		[Vector2(0.82, 0.72), 0.50, MSTheme.MAGENTA],
		[Vector2(0.70, 0.12), 0.35, MSTheme.AMBER]]
	for b: Array in blobs:
		var blob := TextureRect.new()
		blob.texture = _radial(MSTheme.tint(b[2], 0.30), MSTheme.tint(b[2], 0.0))
		blob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		blob.stretch_mode = TextureRect.STRETCH_SCALE
		var centre: Vector2 = b[0]
		var diameter: float = 1920.0 * float(b[1])
		blob.anchor_left = centre.x
		blob.anchor_right = centre.x
		blob.anchor_top = centre.y
		blob.anchor_bottom = centre.y
		blob.offset_left = -diameter * 0.5
		blob.offset_right = diameter * 0.5
		blob.offset_top = -diameter * 0.5
		blob.offset_bottom = diameter * 0.5
		layer.add_child(blob)
	return layer


static func _radial(inner: Color, outer: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([inner, outer])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 512
	t.height = 512
	return t
