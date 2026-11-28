extends RefCounted
## STREET EMPIRE garage showroom (owner reference board 2026-11-28): a high-rise car gallery at dusk.
## - floor-to-ceiling glass on a 11 m ring with slim dark mullions and a transom; through it the Istanbul night skyline
##   photo (assets/world/far_photo/far_city_night.jpg) on a far ring, so it parallaxes like a real view;
## - one polished concrete wall section carrying the STREET EMPIRE sign and a red light column;
## - dark ceiling with large soft light panels (the long highlights on the paint);
## - polished concrete floor (ShowroomSet floor shader with the concrete picture, planar mirror on Medium/High);
## - the turntable: satin top, chrome lip and a glowing racing-red ring on the floor around it.
## Built in code from Mobile-renderer features. Everything is added under `parent`.

const SHOWROOM_SET: Script = preload("res://world/garage_set/showroom_set.gd")
const CITY_PHOTO: String = "res://assets/world/far_photo/far_city_night.jpg"
const CONCRETE: String = "res://assets/textures/cc0/brushed_concrete_03/basecolor.jpg"  ## CC0 Poly Haven, polished floor
const WALL_PANELS: String = "res://assets/textures/cc0/concrete_panels/basecolor.jpg"  ## CC0 Poly Haven, sign wall
const GLASS_R: float = 11.0
const CITY_R: float = 60.0
const ROOM_H: float = 6.4
const MULLION_STEP_RAD: float = 0.21  ## about 2.3 m apart on the glass ring
const SIGN_ANGLE: float = 0.80  ## direction (atan2 x, z) of the sign wall: straight behind the car in the overview shot
const SIGN_HALF_RAD: float = 0.36
const RED: Color = Color(0.941, 0.267, 0.196)
const PANEL_COLOUR: Color = Color(1.0, 0.97, 0.93)


static func build(parent: Node3D, floor_material: ShaderMaterial, turntable_r: float, plate_y: float) -> void:
	_floor(floor_material)
	_city(parent)
	_glass_frame(parent)
	_sign_wall(parent)
	_ceiling(parent)
	_turntable_glow(parent, turntable_r, plate_y)


## Polished concrete: the concrete picture under the showroom gloss.
static func _floor(m: ShaderMaterial) -> void:
	if ResourceLoader.exists(CONCRETE):
		m.set_shader_parameter("concrete_tex", load(CONCRETE))
		m.set_shader_parameter("concrete_on", 1.0)
		m.set_shader_parameter("concrete_tile_m", 3.0)
		m.set_shader_parameter("concrete_gain", 0.09)  # dark polished concrete: a hint of texture, not a sandy car park
	m.set_shader_parameter("roughness_base", 0.16)
	m.set_shader_parameter("reflection_strength", 0.85)
	m.set_shader_parameter("pool_radius", 5.0)
	m.set_shader_parameter("fade_start", 9.0)
	m.set_shader_parameter("fade_end", GLASS_R + 1.0)
	m.set_shader_parameter("fade_colour", Color(0.03, 0.03, 0.04))


static func _unshaded(col: Color, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.albedo_texture = tex
	m.disable_fog = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Inward-facing cylinder band: radius r, from y0 to y1, angles a0..a1, u repeats `u_repeat` times over 2 pi.
static func _band(r: float, y0: float, y1: float, a0: float, a1: float, segments: int, u_repeat: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in segments:
		var t0: float = lerpf(a0, a1, float(i) / float(segments))
		var t1: float = lerpf(a0, a1, float(i + 1) / float(segments))
		var p00 := Vector3(sin(t0) * r, y0, cos(t0) * r)
		var p10 := Vector3(sin(t1) * r, y0, cos(t1) * r)
		var p01 := Vector3(sin(t0) * r, y1, cos(t0) * r)
		var p11 := Vector3(sin(t1) * r, y1, cos(t1) * r)
		var u0: float = t0 / TAU * u_repeat
		var u1: float = t1 / TAU * u_repeat
		for v: Array in [[p00, Vector2(u0, 1.0)], [p10, Vector2(u1, 1.0)], [p11, Vector2(u1, 0.0)],
				[p00, Vector2(u0, 1.0)], [p11, Vector2(u1, 0.0)], [p01, Vector2(u0, 0.0)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()


## The skyline photo on a far ring: city lights below eye level, dusk sky above, as from a high floor.
static func _city(parent: Node3D) -> void:
	var tex: Texture2D = load(CITY_PHOTO) as Texture2D if ResourceLoader.exists(CITY_PHOTO) else null
	var mi := MeshInstance3D.new()
	mi.name = "CityView"
	mi.mesh = _band(CITY_R, -17.0, 14.4, 0.0, TAU, 96, 6.0)  # 60 deg per copy at the photo's 2:1: skyline just below eye level
	mi.material_override = _unshaded(Color(0.95, 0.92, 0.9), tex)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = 1
	parent.add_child(mi)


static func _box(parent: Node3D, nm: String, size: Vector3, pos: Vector3, yaw: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Slim dark mullions round the glass ring (skipped behind the sign wall), a transom and a floor sill.
static func _glass_frame(parent: Node3D) -> void:
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.03, 0.032, 0.036)
	frame.metallic = 0.6
	frame.roughness = 0.35
	var root := Node3D.new()
	root.name = "GlassFrame"
	parent.add_child(root)
	var a: float = 0.0
	var n: int = 0
	while a < TAU - 0.001:
		if absf(wrapf(a - SIGN_ANGLE, -PI, PI)) > SIGN_HALF_RAD + 0.05:
			_box(root, "Mullion%d" % n, Vector3(0.12, ROOM_H, 0.16), Vector3(sin(a) * GLASS_R, ROOM_H * 0.5, cos(a) * GLASS_R), a, frame)
			n += 1
		a += MULLION_STEP_RAD
	var sill := MeshInstance3D.new()
	sill.name = "Sill"
	sill.mesh = _band(GLASS_R - 0.05, 0.0, 0.22, 0.0, TAU, 96, 1.0)
	sill.material_override = frame
	root.add_child(sill)
	var transom := MeshInstance3D.new()
	transom.name = "Transom"
	transom.mesh = _band(GLASS_R - 0.05, ROOM_H - 0.5, ROOM_H, 0.0, TAU, 96, 1.0)
	transom.material_override = frame
	root.add_child(transom)


## Polished concrete wall section with the STREET EMPIRE sign (brand face, red blade) and a red light column.
static func _sign_wall(parent: Node3D) -> void:
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.17, 0.17, 0.18)  # dark polished concrete: the sign carries the wall, not the panels
	wall.roughness = 0.55
	if ResourceLoader.exists(WALL_PANELS):
		wall.albedo_texture = load(WALL_PANELS) as Texture2D
		wall.uv1_scale = Vector3(2.4, 2.0, 1.0)
	var r: float = GLASS_R - 0.4
	var width: float = 2.0 * r * sin(SIGN_HALF_RAD)
	var c := Vector3(sin(SIGN_ANGLE) * r, ROOM_H * 0.5, cos(SIGN_ANGLE) * r)
	var w: MeshInstance3D = _box(parent, "SignWall", Vector3(width, ROOM_H, 0.4), c, SIGN_ANGLE, wall)
	var inward: Vector3 = -Vector3(sin(SIGN_ANGLE), 0.0, cos(SIGN_ANGLE))
	var face: Vector3 = c + inward * 0.22
	var basis := Basis.looking_at(-inward, Vector3.UP)  # Label3D faces +Z: point +Z into the room
	var sign := Label3D.new()
	sign.name = "BrandSign"
	sign.text = "STREET EMPIRE"
	sign.font = MSTheme.font("slant")
	sign.font_size = 160
	sign.pixel_size = 0.0042
	sign.outline_size = 0
	sign.modulate = Color(1.3, 1.3, 1.3)  # a touch over white so the glow lifts it like a backlit sign
	sign.shaded = false
	parent.add_child(sign)
	sign.transform = Transform3D(basis, face + Vector3(0.0, 0.55, 0.0))
	var tag := Label3D.new()
	tag.name = "BrandTagline"
	tag.text = "R U L E   T H E   C I T Y"
	tag.font = MSTheme.font("tracked")
	tag.font_size = 64
	tag.pixel_size = 0.0034
	tag.outline_size = 0
	tag.modulate = MSTheme.TITANIUM
	tag.shaded = false
	parent.add_child(tag)
	tag.transform = Transform3D(basis, face + Vector3(0.0, -0.05, 0.0))
	# Red light column at the wall's left edge, floor to ceiling.
	var edge: Vector3 = c + basis.x * (width * 0.5 - 0.15) + inward * 0.25
	var col := _box(parent, "RedColumn", Vector3(0.14, ROOM_H, 0.08), Vector3(edge.x, ROOM_H * 0.5, edge.z), SIGN_ANGLE, _unshaded(Color(1.2, 0.25, 0.18)))
	col.layers = SHOWROOM_SET.MIRROR_LAYER_BIT | 1
	w.layers = 1


## Dark ceiling and four large soft light panels over the car.
static func _ceiling(parent: Node3D) -> void:
	var ceil := MeshInstance3D.new()
	ceil.name = "Ceiling"
	var pm := PlaneMesh.new()
	pm.size = Vector2(GLASS_R * 2.0, GLASS_R * 2.0)
	pm.flip_faces = true
	ceil.mesh = pm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.05, 0.05, 0.055)
	cm.roughness = 0.8
	ceil.material_override = cm
	ceil.position.y = ROOM_H
	ceil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ceil)
	for i: int in 4:
		var x: float = -1.7 if i % 2 == 0 else 1.7
		var z: float = -1.6 if i < 2 else 1.6
		var p: MeshInstance3D = SHOWROOM_SET.softbox(Vector3(x, ROOM_H - 0.02, z), Vector2(2.8, 2.6), Vector3.DOWN, PANEL_COLOUR, 2.2)
		p.name = "CeilingPanel%d" % i
		parent.add_child(p)


## Glowing red ring on the floor round the turntable and a chrome lip on its edge.
static func _turntable_glow(parent: Node3D, r: float, plate_y: float) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "TurntableGlow"
	var tor := TorusMesh.new()
	tor.inner_radius = r + 0.10
	tor.outer_radius = r + 0.135
	tor.rings = 128
	tor.ring_segments = 8
	ring.mesh = tor
	ring.material_override = _unshaded(Color(0.95, 0.10, 0.06))  # deep red: brighter values tone-map to orange
	ring.scale = Vector3(1.0, 0.35, 1.0)
	ring.position.y = 0.012
	ring.layers = 1
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	var lip := MeshInstance3D.new()
	lip.name = "TurntableLip"
	var lt := TorusMesh.new()
	lt.inner_radius = r - 0.02
	lt.outer_radius = r + 0.03
	lt.rings = 128
	lt.ring_segments = 8
	lip.mesh = lt
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.75, 0.76, 0.78)
	chrome.metallic = 1.0
	chrome.roughness = 0.12
	lip.material_override = chrome
	lip.scale = Vector3(1.0, 1.2, 1.0)
	lip.position.y = plate_y - 0.01
	lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(lip)
