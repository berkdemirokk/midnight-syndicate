extends Node3D
## STREET EMPIRE showroom: the player's selected car on a graphite studio floor, lit like a car-maker reveal.
## Used behind the main menu (inside a SubViewport). Original set, built in code from Mobile-renderer features:
## - dark glossy floor (ShowroomSet floor shader) with a planar mirror on Medium/High, fading into depth fog;
## - three long overhead soft strips, two side panels and a thin racing-red horizon line low behind the car;
## - a key spot with one soft shadow (not on Low), cool side fills, a pearl rim from behind;
## - a generated studio panorama mirrored in the paint (CarMaterials.set_reflection), so the body shows the strips;
## - a slow cinematic camera path, drag to orbit with inertia, auto-resume after the player lets go.
## Tiers (quality): "full" mirror + shadow + reflection; "lite" (Low preset or phone fallback) no mirror, no shadow,
## reflection kept (one cheap extra pass on the paint only).
## Car frame: model nose toward +Z, tyre contact plane at y = 0.

const SHOWROOM_SET: Script = preload("res://world/garage_set/showroom_set.gd")
const PLANAR: Script = preload("res://fx/planar_reflection.gd")

const TARGET: Vector3 = Vector3(0.0, 0.62, 0.0)
const CAMERA_FOV: float = 34.0  ## long lens: flatter, more premium perspective on the body
const BASE_YAW_DEG: float = 38.0  ## front three-quarter, driver side toward the camera
const YAW_SWING_DEG: float = 26.0  ## the slow path swings this far either way
const PATH_PERIOD_S: float = 46.0
const BASE_PITCH_DEG: float = 9.0
const PITCH_SWING_DEG: float = 3.0
const BASE_DIST: float = 8.6
const DIST_SWING: float = 0.45
const INTRO_DIST_ADD: float = 3.2  ## the camera starts this much farther out and settles in
const INTRO_S: float = 2.4
const DRAG_YAW_PER_PX: float = 0.0045
const DRAG_PITCH_PER_PX: float = 0.0025
const PITCH_MIN_DEG: float = 2.0
const PITCH_MAX_DEG: float = 32.0
const INERTIA: float = 3.5  ## 1/s decay of the flick velocity
const RESUME_AFTER_S: float = 4.0
const RESUME_RATE: float = 0.6  ## 1/s blend back onto the cinematic path
const H_OFFSET: float = -0.55  ## frames the car right of centre (menu column on the left)

const BG: Color = Color(0.018, 0.020, 0.025)
const KEY_COLOUR: Color = Color(1.0, 0.975, 0.95)
const FILL_COLOUR: Color = Color(0.80, 0.86, 0.95)
const RIM_COLOUR: Color = Color(0.96, 0.96, 0.98)
const RED: Color = Color(0.941, 0.267, 0.196)
const PANO_W: int = 512
const PANO_H: int = 256

var quality: String = "full"
var car: Node3D = null
var car_id: String = ""
var camera: Camera3D
var floor_material: ShaderMaterial
var planar: Node = null
var env: Environment

var _yaw_off: float = 0.0  ## player's drag offset from the cinematic path, radians
var _pitch_off: float = 0.0
var _yaw_vel: float = 0.0
var _idle_s: float = 100.0
var _t: float = 0.0
var _intro: float = 0.0
var _pivot: Node3D

static var _pano: ImageTexture = null


func _init(q: String = "full") -> void:
	quality = q
	name = "Showroom"


func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_lights()
	_build_set()
	_pivot = Node3D.new()
	_pivot.name = "CarPivot"
	add_child(_pivot)
	_pivot.add_child(SHOWROOM_SET.make_contact_shadow(0.006))
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = CAMERA_FOV
	camera.h_offset = H_OFFSET
	camera.near = 0.1
	camera.far = 80.0
	add_child(camera)
	camera.current = true
	show_car(CarCatalog.race_car_id())
	_update_camera(0.0)


func _process(delta: float) -> void:
	_t += delta
	_intro = minf(_intro + delta / INTRO_S, 1.0)
	_idle_s += delta
	if absf(_yaw_vel) > 0.0001:
		_yaw_off += _yaw_vel * delta
		_yaw_vel *= exp(-INERTIA * delta)
	if _idle_s > RESUME_AFTER_S:
		var k: float = 1.0 - exp(-RESUME_RATE * delta)
		_yaw_off = lerpf(_yaw_off, 0.0, k)
		_pitch_off = lerpf(_pitch_off, 0.0, k)
	_update_camera(delta)


## Drag from the menu's orbit area, in screen pixels.
func orbit_drag(rel: Vector2) -> void:
	_idle_s = 0.0
	_yaw_off -= rel.x * DRAG_YAW_PER_PX
	_pitch_off += rel.y * DRAG_PITCH_PER_PX
	_yaw_vel = -rel.x * DRAG_YAW_PER_PX * 30.0


func orbit_release() -> void:
	_idle_s = 0.0


## Current camera yaw in degrees (tests, captures).
func camera_yaw_deg() -> float:
	return rad_to_deg(_path_yaw() + _yaw_off)


func _path_yaw() -> float:
	return deg_to_rad(BASE_YAW_DEG + YAW_SWING_DEG * sin(TAU * _t / PATH_PERIOD_S))


func _update_camera(_delta: float) -> void:
	var yaw: float = _path_yaw() + _yaw_off
	var base_pitch: float = BASE_PITCH_DEG + PITCH_SWING_DEG * sin(TAU * _t / (PATH_PERIOD_S * 0.73) + 1.3)
	var pitch: float = clampf(deg_to_rad(base_pitch) + _pitch_off, deg_to_rad(PITCH_MIN_DEG), deg_to_rad(PITCH_MAX_DEG))
	_pitch_off = pitch - deg_to_rad(base_pitch)
	var ease_in: float = 1.0 - pow(1.0 - _intro, 3.0)
	var dist: float = BASE_DIST + DIST_SWING * sin(TAU * _t / (PATH_PERIOD_S * 1.31)) + INTRO_DIST_ADD * (1.0 - ease_in)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = TARGET + dir * dist
	camera.look_at(TARGET, Vector3.UP)


## Swaps the car on the stage to `id` with the player's saved paint and rims.
func show_car(id: String) -> void:
	if car != null:
		car.queue_free()
		car = null
	car_id = id
	var path: String = CarCatalog.scene_path(id)
	if not ResourceLoader.exists(path):
		return
	var packed: PackedScene = load(path) as PackedScene
	var node: Node = packed.instantiate()
	car = node as Node3D
	var setup: Dictionary = GameState.get_setup(id)
	if node is CarLod:
		(node as CarLod).force_lod0 = quality == "full"
		(node as CarLod).paint_colour = Color.from_string(str(setup["paint_color"]), CarMaterials.DEFAULT_PAINT)
	_pivot.add_child(car)
	CarMaterials.set_rim_color(car, Color.from_string(str(setup["rim_color"]), CarMaterials.DEFAULT_RIM))
	CarMaterials.set_reflection(car, studio_pano(), 0.85, 1.4, 2.2)


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.11, 0.115, 0.13)
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = BG
	env.fog_density = 0.035
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.4
	env.glow_hdr_scale = 1.6
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)


func _build_floor() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(70.0, 70.0)
	mi.mesh = mesh
	floor_material = SHOWROOM_SET.make_floor_material(4.2, 22.0)
	floor_material.set_shader_parameter("fade_start", 6.0)
	mi.material_override = floor_material
	mi.layers = SHOWROOM_SET.MIRROR_LAYER_BIT
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if quality == "full":
		planar = PLANAR.new()
		planar.name = "FloorMirror"
		planar.set("plane_height", 0.0)
		planar.set("resolution_fraction", 0.5)
		planar.set("max_distance_m", 40.0)
		add_child(planar)
		planar.call("add_target_material", floor_material)
		planar.call("set_enabled", true)


func _spot(pos: Vector3, colour: Color, energy: float, angle: float, shadow: bool) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.light_color = colour
	s.light_energy = energy
	s.spot_angle = angle
	s.spot_range = 22.0
	s.spot_attenuation = 0.6
	s.shadow_enabled = shadow
	s.shadow_blur = 2.0
	add_child(s)
	s.position = pos
	s.look_at(TARGET, Vector3.UP if absf(pos.normalized().y) < 0.99 else Vector3.FORWARD)
	return s


func _build_lights() -> void:
	_spot(Vector3(0.6, 7.5, 1.2), KEY_COLOUR, 7.0, 34.0, quality == "full").name = "Key"
	_spot(Vector3(-6.5, 2.6, 2.5), FILL_COLOUR, 3.2, 30.0, false).name = "FillL"
	_spot(Vector3(5.5, 3.2, 4.5), FILL_COLOUR, 1.4, 24.0, false).name = "FillR"
	_spot(Vector3(0.0, 2.2, -7.5), RIM_COLOUR, 5.5, 32.0, false).name = "Rim"


func _build_set() -> void:
	# Three long strips overhead along the car: the long highlights on the roof, bonnet and shoulders.
	for x: float in [-1.5, 0.0, 1.5]:
		var s: MeshInstance3D = SHOWROOM_SET.softbox(Vector3(x, 6.2, 0.0), Vector2(0.35, 9.0), Vector3.DOWN, KEY_COLOUR, 2.6)
		s.name = "Strip"
		add_child(s)
	# The brand light: a broad, faint racing-red wash on the far wall behind the car (a backlit cyclorama), so the
	# silhouette sits on red-tinted dark instead of a void. Mirrored softly by the floor.
	var wash: MeshInstance3D = SHOWROOM_SET.softbox(Vector3(0.0, 3.2, -16.0), Vector2(34.0, 9.0), Vector3.BACK, RED, 0.22)
	wash.name = "RedWash"
	wash.layers = SHOWROOM_SET.MIRROR_LAYER_BIT | 1
	add_child(wash)


## Equirectangular studio panorama for the paint mirror (u: atan(x, z), v: 0 up .. 1 down; see car_reflection.gdshader).
## Bright strips overhead, two side panels, the red line low behind the car, dark floor. Made once per run.
static func studio_pano() -> ImageTexture:
	if _pano != null:
		return _pano
	var img := Image.create(PANO_W, PANO_H, false, Image.FORMAT_RGB8)
	for y: int in PANO_H:
		var v: float = (float(y) + 0.5) / float(PANO_H)
		var elev: float = (0.5 - v) * PI  ## +pi/2 up
		for x: int in PANO_W:
			var u: float = (float(x) + 0.5) / float(PANO_W)
			var az: float = (u - 0.5) * TAU  ## 0 = +Z (front of the car), +-pi = behind
			var c := Color(0.020, 0.021, 0.025)
			if elev > 0.0:
				c = c.lerp(Color(0.045, 0.047, 0.055), elev / (PI * 0.5))
				# overhead strips: long along Z, so they spread over every azimuth at high elevation
				if elev > 0.85:
					var across: float = sin(az) * cos(elev) / maxf(sin(elev), 0.05)  ## x / height on the ceiling
					var strip: float = 0.0
					for sx: float in [-0.25, 0.0, 0.25]:
						strip = maxf(strip, 1.0 - smoothstep(0.03, 0.06, absf(across - sx)))
					c = c.lerp(Color(1.0, 0.98, 0.95), strip * smoothstep(0.85, 1.05, elev))
				# side panels at +-90 degrees, a little above the horizon
				var side: float = (1.0 - smoothstep(0.30, 0.42, absf(absf(az) - PI * 0.5))) * (1.0 - smoothstep(0.10, 0.32, absf(elev - 0.22)))
				c = c.lerp(Color(0.70, 0.74, 0.80), side * 0.55)
			else:
				c = c.lerp(Color(0.012, 0.012, 0.014), clampf(-elev / 0.4, 0.0, 1.0))
			# red horizon line behind (az near +-pi)
			var behind: float = 1.0 - smoothstep(0.55, 0.9, PI - absf(az))
			var line: float = 1.0 - smoothstep(0.012, 0.03, absf(elev - 0.02))
			c = c.lerp(Color(0.94, 0.27, 0.20), behind * line)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	_pano = ImageTexture.create_from_image(img)
	return _pano
