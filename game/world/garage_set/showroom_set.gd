class_name ShowroomSet
extends Node3D
## Night showroom presentation for the hero car: glossy floor with a planar mirror, a soft contact shadow under
## the body and tyres, three-point lighting (large soft key, cool fill, warm rim) with emissive softbox panels,
## a gradient backdrop and neon accents in the game palette. Mobile-renderer features only.
## Two uses: build_studio() makes the whole stage (devtools car_studio); attach_garage() dresses the existing
## garage room (floor and turntable plate get the mirror, plus contact shadow, rim lights and neon ring).
## Car frame: origin at the tyre contact plane, nose toward +Z.

const FLOOR_SHADER: String = "res://world/garage_set/showroom_floor.gdshader"
const MIRROR_LAYER_BIT: int = 1 << 1  ## floor and shadow sit here: PlanarReflection leaves them out of the mirror
const MIRROR_DISTANCE_GARAGE: float = 8.5  ## keeps the garage mirror from re-drawing the whole room (Medium budget: 350 draws)
const WHEEL_X: float = 0.815
const WHEEL_Z: float = 1.33  ## front axle; the rear axle is at -1.33 (wheelbase 2.66)
const SHADOW_BODY: Vector2 = Vector2(2.7, 5.4)
const SHADOW_TYRE: Vector2 = Vector2(0.95, 1.5)
const PALETTE_MAGENTA: Color = Color(1.0, 0.08, 0.62)
const PALETTE_CYAN: Color = Color(0.1, 0.85, 1.0)
const PALETTE_AMBER: Color = Color(1.0, 0.6, 0.12)
const HORIZON: Color = Color(0.05, 0.03, 0.09)
const KEY_COLOUR: Color = Color(1.0, 0.96, 0.92)
const FILL_COLOUR: Color = Color(0.55, 0.72, 1.0)
const RIM_COLOUR: Color = Color(1.0, 0.62, 0.28)

var floor_material: ShaderMaterial = null
var planar: PlanarReflection = null
var contact_shadow: Node3D = null
var lights: Array[Light3D] = []

static var _soft_tex: GradientTexture2D = null


## Whole stage around a car at the origin: floor (60 m disc-like plane), mirror, probe, lights, panels, neon, backdrop.
func build_studio(floor_size: float = 60.0) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(floor_size, floor_size)
	mi.mesh = mesh
	floor_material = make_floor_material(5.5, 24.0)
	mi.material_override = floor_material
	mi.layers = MIRROR_LAYER_BIT
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_add_planar(0.0, 0.6, 60.0)
	add_child(_probe())
	_add_studio_lights()
	_add_softboxes()
	_add_backdrop_cards()
	_add_neon()
	contact_shadow = make_contact_shadow(0.006)
	add_child(contact_shadow)


## Dresses the garage room. `room` holds the GLB, `pivot_parent` receives the contact shadow (it turns with the car).
func attach_garage(room: Node3D, pivot: Node3D, plane_y: float, mirror: bool) -> void:
	floor_material = make_floor_material(3.6, 16.0)
	floor_material.set_shader_parameter("fade_start", 9.0)
	floor_material.set_shader_parameter("reflection_strength", 0.7)
	floor_material.set_shader_parameter("reflection_cap", 0.4)
	floor_material.set_shader_parameter("reflection_floor", 0.15)
	floor_material.set_shader_parameter("light_specular", 0.08)  # the room key and ceiling strips glared white on the plate from behind
	floor_material.set_shader_parameter("roughness_base", 0.3)
	var bound: int = 0
	for n: Node in room.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		var hit: bool = false
		for s: int in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(s)
			if src != null and src.resource_name == "M_Floor_Epoxy":
				mi.set_surface_override_material(s, floor_material)
				hit = true
				bound += 1
		if hit:
			mi.layers = MIRROR_LAYER_BIT
	if mirror and bound > 0:
		_add_planar(plane_y, 0.5, MIRROR_DISTANCE_GARAGE)
	contact_shadow = make_contact_shadow(0.004)
	pivot.add_child(contact_shadow)
	_add_garage_lights()
	_add_garage_neon(plane_y)


## One shared dark glossy floor material. pool_radius: size of the faint lit pad under the car.
static func make_floor_material(pool_radius: float, fade_end: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(FLOOR_SHADER) as Shader
	m.set_shader_parameter("pool_radius", pool_radius)
	m.set_shader_parameter("fade_end", fade_end)
	m.set_shader_parameter("fade_start", fade_end * 0.25)
	return m


## Studio environment: gradient sky for the backdrop, depth fog in the horizon colour so the floor melts into it,
## ACES so highlights roll off, and a glow that only picks up the genuinely hot pixels.
static func make_environment() -> Environment:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.008, 0.01, 0.028)
	sky_mat.sky_horizon_color = HORIZON
	sky_mat.ground_horizon_color = HORIZON
	sky_mat.ground_bottom_color = Color(0.012, 0.01, 0.02)
	sky_mat.sky_curve = 0.18
	sky_mat.sun_angle_max = 0.0
	sky_mat.sky_energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.07, 0.07, 0.12)
	env.ambient_light_energy = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = HORIZON
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.6
	env.glow_hdr_scale = 1.5
	return env


## Soft round shadow: one wide body ellipse plus four tyre blobs, black with a radial alpha ramp. No decal needed.
static func make_contact_shadow(lift: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ContactShadow"
	root.position = Vector3(0.0, lift, 0.0)
	root.add_child(_shadow_quad(Vector2.ZERO, SHADOW_BODY, 0.8, 0))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			root.add_child(_shadow_quad(Vector2(sx * WHEEL_X, sz * WHEEL_Z), SHADOW_TYRE, 0.95, 1))
	return root


static func _shadow_quad(at: Vector2, size: Vector2, strength: float, prio: int) -> MeshInstance3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	g.colors = PackedColorArray([
		Color(0, 0, 0, strength), Color(0, 0, 0, strength * 0.55),
		Color(0, 0, 0, strength * 0.14), Color(0, 0, 0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color.BLACK
	m.albedo_texture = tex
	m.no_depth_test = false
	m.disable_receive_shadows = true
	m.render_priority = prio
	var q := QuadMesh.new()
	q.size = size
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = Vector3(at.x, float(prio) * 0.001, at.y)
	mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	mi.layers = MIRROR_LAYER_BIT
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Emissive panel with a soft edge (square gradient), facing along `dir`. Energy above 1 reads as lit, below the clip.
static func softbox(pos: Vector3, size: Vector2, dir: Vector3, colour: Color, energy: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(colour.r * energy, colour.g * energy, colour.b * energy)
	m.albedo_texture = _soft_texture()
	m.cull_mode = BaseMaterial3D.CULL_BACK
	var q := QuadMesh.new()
	q.size = size
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up: Vector3 = Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD
	# Quad front is +Z, so aim -Z away from `dir`. Built as a transform: look_at needs the node in the tree.
	mi.transform = Transform3D(Basis.looking_at(-dir, up), pos)
	return mi


## Glowing tube: a thin box, emission in HDR so it blooms softly and mirrors in the floor.
static func neon(pos: Vector3, size: Vector3, colour: Color, energy: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour * 0.15
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = energy
	var b := BoxMesh.new()
	b.size = size
	b.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _soft_texture() -> GradientTexture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.8, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1), Color(0.92, 0.92, 0.95), Color(0.25, 0.25, 0.3), Color(0.04, 0.04, 0.06)])
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient = g
		_soft_tex.fill = GradientTexture2D.FILL_SQUARE
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(1.0, 0.5)
		_soft_tex.width = 128
		_soft_tex.height = 128
	return _soft_tex


static func _spot(pos: Vector3, target: Vector3, colour: Color, energy: float, angle: float, shadow: bool) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.light_color = colour
	s.light_energy = energy
	s.spot_range = 20.0
	s.spot_angle = angle
	s.spot_angle_attenuation = 0.8
	s.shadow_enabled = shadow
	if shadow:
		s.shadow_blur = 2.5
	var to: Vector3 = target - pos
	var up: Vector3 = Vector3.FORWARD if absf(to.x) + absf(to.z) < 0.1 else Vector3.UP
	s.transform = Transform3D(Basis.looking_at(to, up), pos)
	return s


func _add_planar(plane_y: float, fraction: float, max_dist: float) -> void:
	planar = PlanarReflection.new()
	planar.name = "FloorMirror"
	planar.plane_height = plane_y
	planar.resolution_fraction = fraction
	planar.max_distance_m = max_dist
	add_child(planar)
	planar.add_target_material(floor_material)
	planar.set_enabled(true)


func _probe() -> ReflectionProbe:
	var probe := ReflectionProbe.new()
	probe.name = "StudioProbe"
	probe.size = Vector3(34.0, 12.0, 34.0)
	probe.position = Vector3(0.0, 5.0, 0.0)
	probe.intensity = 1.0
	probe.box_projection = true  # without it the whole floor and roof reflect one cubemap direction: a flat grey wash
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.cull_mask = ((1 << 20) - 1) & ~MIRROR_LAYER_BIT  # the floor stays out: the paint should reflect panels and neon
	return probe


func _track(l: Light3D) -> Light3D:
	lights.append(l)
	add_child(l)
	return l


func _add_studio_lights() -> void:
	var target := Vector3(0.0, 0.5, 0.0)
	_track(_spot(Vector3(-1.2, 5.6, 1.6), target, KEY_COLOUR, 6.0, 42.0, true)).name = "Key"
	for sx: float in [-1.0, 1.0]:
		_track(_spot(Vector3(sx * 4.6, 2.2, 0.0), target, FILL_COLOUR, 5.0, 38.0, false)).name = "Fill%s" % ("L" if sx < 0.0 else "R")
	for sz: float in [-1.0, 1.0]:
		var o: SpotLight3D = _spot(Vector3(sz * 2.8, 1.5, sz * -5.2), target, RIM_COLOUR, 4.0, 30.0, false)
		o.name = "Rim%s" % ("F" if sz > 0.0 else "B")
		_track(o)


func _add_softboxes() -> void:
	# Key: large overhead panel. Sides: tall cool panels that paint long highlights down the flanks.
	add_child(softbox(Vector3(-1.2, 5.7, 1.6), Vector2(7.0, 3.4), Vector3.DOWN, KEY_COLOUR, 1.0))
	add_child(softbox(Vector3(-4.9, 2.4, 0.0), Vector2(6.5, 2.4), Vector3.RIGHT, FILL_COLOUR, 0.8))
	add_child(softbox(Vector3(4.9, 2.4, 0.0), Vector2(6.5, 2.4), Vector3.LEFT, FILL_COLOUR, 0.8))
	# Warm kicker strips low behind each end of the car: the rim light seen on the bodywork.
	add_child(softbox(Vector3(0.0, 1.6, -6.5), Vector2(5.0, 1.3), Vector3.BACK, RIM_COLOUR, 0.8))
	add_child(softbox(Vector3(0.0, 1.6, 6.5), Vector2(5.0, 1.3), Vector3.FORWARD, RIM_COLOUR, 0.8))


func _add_backdrop_cards() -> void:
	# Four huge dim radial glows in a ring: the backdrop gradient reads violet, cyan and magenta, not a flat void.
	var cards: Array[Dictionary] = [
		{"pos": Vector3(0.0, 4.5, -19.0), "dir": Vector3.BACK, "col": PALETTE_MAGENTA},
		{"pos": Vector3(0.0, 4.5, 19.0), "dir": Vector3.FORWARD, "col": PALETTE_CYAN},
		{"pos": Vector3(-19.0, 4.5, 0.0), "dir": Vector3.RIGHT, "col": Color(0.45, 0.25, 1.0)},
		{"pos": Vector3(19.0, 4.5, 0.0), "dir": Vector3.LEFT, "col": PALETTE_AMBER},
	]
	for c: Dictionary in cards:
		var card: MeshInstance3D = softbox(c["pos"] as Vector3, Vector2(30.0, 11.0), c["dir"] as Vector3, c["col"] as Color, 0.16)
		card.layers = MIRROR_LAYER_BIT | 1  # visible in the mirror too: the floor picks up the glow
		add_child(card)


func _add_neon() -> void:
	add_child(neon(Vector3(-4.7, 0.04, 0.0), Vector3(0.08, 0.06, 15.0), PALETTE_CYAN, 3.0))
	add_child(neon(Vector3(4.7, 0.04, 0.0), Vector3(0.08, 0.06, 15.0), PALETTE_MAGENTA, 3.0))
	var cols: Array[Color] = [PALETTE_MAGENTA, PALETTE_AMBER, PALETTE_CYAN]
	for end: float in [-1.0, 1.0]:
		for i: int in 3:
			var c: Color = cols[i] if end < 0.0 else cols[2 - i]
			add_child(neon(Vector3((i - 1) * 3.0, 1.9, end * 11.0), Vector3(0.09, 3.8, 0.09), c, 3.0))
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 3.35
	t.outer_radius = 3.41
	t.rings = 64
	t.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.albedo_color = PALETTE_AMBER * 0.15
	m.emission_enabled = true
	m.emission = PALETTE_AMBER
	m.emission_energy_multiplier = 1.5
	t.material = m
	ring.mesh = t
	ring.scale = Vector3(1.0, 0.12, 1.0)
	ring.position = Vector3(0.0, 0.01, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


func _add_garage_lights() -> void:
	# Warm rim from behind each side plus a cool low fill: the garage's own ceiling strips stay the key.
	var target := Vector3(0.0, 0.6, 0.0)
	_track(_spot(Vector3(-3.4, 1.7, -4.0), target, RIM_COLOUR, 4.0, 32.0, false)).name = "RimL"
	_track(_spot(Vector3(3.4, 1.7, 4.0), target, RIM_COLOUR, 3.5, 32.0, false)).name = "RimR"
	_track(_spot(Vector3(3.8, 1.4, -1.0), target, FILL_COLOUR, 2.6, 40.0, false)).name = "CoolFill"


func _add_garage_neon(plane_y: float) -> void:
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 2.62
	t.outer_radius = 2.68
	t.rings = 64
	t.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.albedo_color = PALETTE_CYAN * 0.15
	m.emission_enabled = true
	m.emission = PALETTE_CYAN
	m.emission_energy_multiplier = 1.8
	t.material = m
	ring.mesh = t
	ring.scale = Vector3(1.0, 0.12, 1.0)
	ring.position = Vector3(0.0, plane_y + 0.005, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	add_child(neon(Vector3(-3.6, 0.03, 0.0), Vector3(0.07, 0.05, 7.0), PALETTE_MAGENTA, 2.6))
	add_child(neon(Vector3(3.6, 0.03, 0.0), Vector3(0.07, 0.05, 7.0), PALETTE_AMBER, 2.6))
