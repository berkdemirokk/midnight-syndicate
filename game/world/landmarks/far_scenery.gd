class_name FarScenery
extends Node3D
## Far scenery across the Bosphorus on the bogaz track, built from code (no asset files):
## a 1 km suspension bridge over the strait (it replaces the flat skyline_bridge card, see HIDES_ASSET), a far shore
## of hills that reads as a city at night (warm point lights, none by day), a two-deck ferry on a line parallel to the
## shore, and light reflections on the water under the bridge. Positions are world metres of the bogaz frame.
## Add this node under the Track (the Track sits at the origin) and call setup() after the Track has built its city.

const HIDES_ASSET: String = "skyline"  ## the flat skyline cards (bridge, far city with lit windows) that setup() hides: the 3D far shore replaces them
const CENTRE: Vector3 = Vector3(650.0, 0.0, 330.0)  ## bridge centre over the strait
const DECK_Y: float = 75.0  ## deck top above the sea, m
const TOWER_X: float = 300.0  ## tower distance from the centre, m (main span 600 m)
const END_X: float = 500.0  ## deck end distance from the centre, m (1 km deck)
const TOWER_H: float = 130.0  ## tower top above the deck, m
const TOWER_PANEL_M: float = 8.0  ## height of one tower leg panel
const CABLE_Z: float = 10.0  ## cable offset from the centre line, m
const SHORE_X: float = 640.0  ## far shore starts here, sea before it
const SHORE_RISE: float = 380.0  ## m over which the hills climb to full height
const SHORE_CELL: Vector2 = Vector2(26.0, 45.0)  ## hill grid cell, m (x, z)
const SHORE_LIGHTS: int = 900  ## warm point lights on the hillside at night
const FERRY_X: float = 470.0  ## ferry line, m, between the coast road and the far shore
const FERRY_RUN: float = 1040.0  ## m of the out-and-back route, parallel to the shore
const FERRY_SPEED: float = 5.5  ## m/s
const SEED: int = 4417

## Light level: 1 at night, 0.6 at sunset, 0 by day. Lights, emission and reflections follow it.
var _k: float = 0.0
var _lit: bool = false
var _ferry: Node3D = null
var _phase: float = 0.5  ## starts mid-run, so the ferry is on screen early in a capture
static var _glow: ImageTexture = null


## Builds the scene for one time of day ("day", "sunset" or "night"). Safe to call again: it rebuilds.
func setup(track: Track, time_of_day_id: String) -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_ferry = null
	_k = 1.0 if time_of_day_id == "night" else (0.6 if time_of_day_id == "sunset" else 0.0)
	_lit = _k > 0.0
	if track != null:
		for n: Node in track.find_children("*" + HIDES_ASSET + "*", "", true, false):
			if n is Node3D:
				(n as Node3D).visible = false
	_build_bridge()
	_build_shore()
	_build_ferry()
	if _lit:
		_build_reflections()


func _process(delta: float) -> void:
	if _ferry == null:
		return
	_phase = fposmod(_phase + delta * FERRY_SPEED / FERRY_RUN, 2.0)  # one out-and-back run is 2.0
	var going_out: bool = _phase < 1.0
	var p: float = _phase if going_out else 2.0 - _phase
	_ferry.position = Vector3(FERRY_X, -0.2, lerpf(-FERRY_RUN * 0.5, FERRY_RUN * 0.5, p))
	_ferry.basis = Basis.looking_at(Vector3(0.0, 0.0, 1.0 if going_out else -1.0))


## Draw calls and primitives (triangles) of the visible meshes under this node, for the budget checks.
func cost() -> Dictionary:
	var draws: int = 0
	var prims: int = 0
	for n: Node in find_children("*", "", true, false):
		if n is MeshInstance3D and (n as Node3D).is_visible_in_tree():
			draws += 1
			prims += _tris((n as MeshInstance3D).mesh)
		elif n is MultiMeshInstance3D and (n as Node3D).is_visible_in_tree():
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			draws += 1
			prims += _tris(mm.mesh) * mm.instance_count
	return {"draws": draws, "prims": prims}


static func _tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total: int = 0
	for i: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]  # null for unindexed surfaces
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += ((idx as PackedInt32Array).size() if idx != null else verts.size()) / 3
	return total


## Shore height above the sea at world (x, z). Sea (0) before SHORE_X, then a slope of hills.
static func hill_height(x: float, z: float) -> float:
	var ramp: float = clampf((x - SHORE_X) / SHORE_RISE, 0.0, 1.0)
	var ridge: float = 0.6 + 0.4 * sin(z * 0.0061 + 0.8) * cos(x * 0.0043)
	return maxf(120.0 * ramp * ridge + 14.0 * sin(z * 0.023 + x * 0.011) * ramp, 0.0)


## Deck-level cable height above the sea at bridge-local x (parabolic main span, straight side spans).
static func cable_height(lx: float) -> float:
	var a: float = absf(lx)
	if a <= TOWER_X:
		return DECK_Y + 10.0 + (TOWER_H - 10.0) * pow(a / TOWER_X, 2.0)
	var t: float = (a - TOWER_X) / (END_X - TOWER_X)
	return lerpf(DECK_Y + TOWER_H, DECK_Y + 4.0, t)


# --- bridge ----------------------------------------------------------------------------------------

func _build_bridge() -> void:
	var steel_st := SurfaceTool.new()
	steel_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck_st := SurfaceTool.new()
	deck_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tower_st := SurfaceTool.new()
	tower_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sx: float in [-TOWER_X, TOWER_X]:
		var tx: float = CENTRE.x + sx
		var mid: float = (DECK_Y + TOWER_H - 6.0) * 0.5
		var half_h: float = (DECK_Y + TOWER_H + 6.0) * 0.5
		# Legs in 8 m panels: each panel carries its floodlight level as vertex colour (brightest at the deck, where
		# the lamps stand, fading up the tower and down to the water), so the tower reads as lit steel, not a red beam.
		var top_y: float = mid + half_h
		for sz: float in [-CABLE_Z - 1.0, CABLE_Z + 1.0]:
			var y: float = mid - half_h
			var n: int = 0
			while y < top_y:
				var h: float = minf(TOWER_PANEL_M, top_y - y)
				tower_st.set_color(_tower_colour(y + h * 0.5, n))
				_box(tower_st, Vector3(tx, y + h * 0.5, CENTRE.z + sz), Vector3(3.0, h * 0.5 - 0.12, 3.0))
				y += h
				n += 1
		for by: float in [DECK_Y + 25.0, DECK_Y + 75.0, DECK_Y + TOWER_H - 6.0]:
			tower_st.set_color(_tower_colour(by, 0) * 1.15)
			_box(tower_st, Vector3(tx, by, CENTRE.z), Vector3(2.0, 1.6, CABLE_Z + 1.0))
	_box(deck_st, Vector3(CENTRE.x, DECK_Y - 1.5, CENTRE.z), Vector3(END_X, 1.5, 11.0))
	_box(steel_st, Vector3(CENTRE.x, DECK_Y - 5.5, CENTRE.z), Vector3(END_X, 2.5, 2.0))
	for sz: float in [-11.2, 11.2]:
		_box(deck_st, Vector3(CENTRE.x, DECK_Y + 0.6, CENTRE.z + sz), Vector3(END_X, 0.6, 0.2))
	for sz: float in [-CABLE_Z, CABLE_Z]:
		var prev: Vector3 = Vector3.ZERO
		for i: int in 101:
			var lx: float = lerpf(-END_X, END_X, float(i) / 100.0)
			var p: Vector3 = Vector3(CENTRE.x + lx, cable_height(lx), CENTRE.z + sz)
			if i > 0:
				_bar(steel_st, prev, p, 0.45)
			prev = p
		for lx: int in range(-285, 286, 15):
			var top: Vector3 = Vector3(CENTRE.x + lx, cable_height(lx), CENTRE.z + sz)
			_bar(steel_st, top, Vector3(top.x, DECK_Y, top.z), 0.22)
	var steel_mat: StandardMaterial3D = _mat(Color(0.2, 0.22, 0.25), 0.5, 0.5)
	var deck_mat: StandardMaterial3D = _mat(Color(0.26, 0.26, 0.28), 0.0, 0.8)
	var tower_mat: StandardMaterial3D = _mat(Color(0.3, 0.16, 0.14), 0.0, 0.7)
	if _lit:
		tower_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # the floodlight level is baked in the vertex colours
		tower_mat.vertex_color_use_as_albedo = true
		tower_mat.albedo_color = Color(_k, _k, _k)
	add_child(_mesh_node("BridgeSteel", steel_st.commit(), steel_mat))
	add_child(_mesh_node("BridgeDeck", deck_st.commit(), deck_mat))
	add_child(_mesh_node("BridgeTowers", tower_st.commit(), tower_mat))
	if not _lit:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pos := PackedVector3Array()
	var cols := PackedColorArray()
	for sz: float in [-CABLE_Z, CABLE_Z]:
		for i: int in range(-166, 167):
			var lx: float = float(i) * END_X / 166.0
			pos.append(Vector3(CENTRE.x + lx, cable_height(lx) + 0.9, CENTRE.z + sz))
			cols.append(Color(0.7, 0.86, 1.6) * (0.85 + 0.3 * rng.randf()) * _k)
	add_child(_glow_node("BridgeNecklace", pos, cols, 1.5))
	pos = PackedVector3Array()
	cols = PackedColorArray()
	for sz: float in [-10.3, 10.3]:
		for i: int in range(-35, 36):
			pos.append(Vector3(CENTRE.x + float(i) * 14.0, DECK_Y + 1.2, CENTRE.z + sz))
			cols.append(Color(1.6, 1.3, 0.85) * _k)
	add_child(_glow_node("BridgeDeckLamps", pos, cols, 1.1))


## Floodlit red of a tower panel at height y (m above the sea): 1.25 at the deck, 0.4 at the top, 0.3 at the water.
static func _tower_colour(y: float, panel: int) -> Color:
	var level: float = lerpf(1.25, 0.4, clampf((y - DECK_Y) / TOWER_H, 0.0, 1.0)) if y >= DECK_Y else lerpf(0.3, 0.9, clampf(y / DECK_Y, 0.0, 1.0))
	level *= 0.94 if panel % 2 == 0 else 1.06
	return Color(1.0 * level, 0.13 * level, 0.09 * level)


# --- far shore -------------------------------------------------------------------------------------

func _build_shore() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx: int = 25
	var nz: int = 40
	for i: int in nx:
		for j: int in nz:
			var xa: float = 600.0 + SHORE_CELL.x * float(i)
			var za: float = -900.0 + SHORE_CELL.y * float(j)
			var a: Vector3 = _shore_vertex(xa, za)
			var b: Vector3 = _shore_vertex(xa + SHORE_CELL.x, za)
			var c: Vector3 = _shore_vertex(xa, za + SHORE_CELL.y)
			var d: Vector3 = _shore_vertex(xa + SHORE_CELL.x, za + SHORE_CELL.y)
			for v: Vector3 in [a, b, d, a, d, c]:
				st.set_color(_shore_colour(v.x, v.z))
				st.add_vertex(v)
	st.generate_normals()
	var shore_mat: StandardMaterial3D = _mat(Color.WHITE, 0.0, 0.95)
	shore_mat.vertex_color_use_as_albedo = true
	add_child(_mesh_node("FarShore", st.commit(), shore_mat))
	if not _lit:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var pos := PackedVector3Array()
	var cols := PackedColorArray()
	var scales: Array[float] = []
	var tries: int = 0
	while pos.size() < SHORE_LIGHTS and tries < 20000:
		tries += 1
		var x: float = 645.0 + pow(rng.randf(), 1.6) * 380.0  # denser at the water
		var z: float = rng.randf_range(-880.0, 880.0)
		var h: float = hill_height(x, z)
		if h < 3.0:
			continue
		pos.append(Vector3(x, h + rng.randf_range(0.5, 6.0), z))
		cols.append(_lamp_colour(rng.randf()) * (1.4 + 0.8 * rng.randf()) * _k)
		scales.append(rng.randf_range(1.2, 2.8))
	add_child(_glow_node("ShoreLights", pos, cols, 1.0, scales))


func _shore_vertex(x: float, z: float) -> Vector3:
	return Vector3(x, hill_height(x, z) - 0.8, z)  # the sea-level edge sits just under the water


func _shore_colour(x: float, z: float) -> Color:
	var ridge: float = 0.85 + 0.15 * sin(z * 0.0061 + 0.8)
	if _lit:
		return Color(0.035, 0.04, 0.055) * ridge
	return Color(0.13, 0.19, 0.15) * ridge  # day: dark green-grey, lit by the sun


static func _lamp_colour(r: float) -> Color:
	if r < 0.55:
		return Color(1.0, 0.62, 0.26)  # sodium
	if r < 0.85:
		return Color(1.0, 0.84, 0.58)  # warm white
	if r < 0.95:
		return Color(0.82, 0.92, 1.0)  # cool white
	return Color(1.0, 0.22, 0.16)  # red


# --- ferry -----------------------------------------------------------------------------------------

func _build_ferry() -> void:
	_ferry = Node3D.new()
	_ferry.name = "Ferry"
	add_child(_ferry)
	var hull := SurfaceTool.new()
	hull.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := SurfaceTool.new()
	white.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(hull, Vector3(0.0, 2.5, 0.0), Vector3(7.5, 2.5, 29.0))
	_box(white, Vector3(0.0, 6.5, -2.0), Vector3(7.0, 1.5, 26.0))
	_box(white, Vector3(0.0, 10.0, -4.0), Vector3(6.0, 1.5, 18.0))
	_box(white, Vector3(0.0, 13.5, -7.0), Vector3(4.0, 1.2, 6.0))
	for deck_y: float in [6.6, 10.0]:
		var side_x: float = 7.05 if deck_y < 8.0 else 6.05
		for s: float in [-1.0, 1.0]:
			var z: float = -24.0
			while z < 16.0:
				_box(glass, Vector3(s * side_x, deck_y, z), Vector3(0.1, 0.7, 1.1))
				z += 3.2
	_box(glass, Vector3(0.0, 13.5, -13.1), Vector3(3.0, 0.7, 0.1))
	for z: int in range(-20, 11, 6):
		_box(glass, Vector3(0.0, 11.6, float(z)), Vector3(0.3, 0.1, 0.3))
	var win: StandardMaterial3D
	if _lit:
		win = _mat(Color(1.0, 0.75, 0.4), 0.0, 0.4)
		win.emission_enabled = true
		win.emission = Color(1.0, 0.72, 0.35)
		win.emission_energy_multiplier = 2.6 * _k
	else:
		win = _mat(Color(0.05, 0.08, 0.11), 0.4, 0.15)
	_ferry.add_child(_mesh_node("FerryHull", hull.commit(), _mat(Color(0.07, 0.12, 0.2), 0.0, 0.7)))
	_ferry.add_child(_mesh_node("FerryDecks", white.commit(), _mat(Color(0.88, 0.88, 0.86), 0.0, 0.6)))
	_ferry.add_child(_mesh_node("FerryWindows", glass.commit(), win))
	_process(0.0)


# --- reflections -----------------------------------------------------------------------------------

## Stretched additive streaks on the water under the towers and the middle of the necklace.
func _build_reflections() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var red: Color = Color(1.0, 0.22, 0.14) * _k * 1.8
	var blue: Color = Color(0.6, 0.8, 1.4) * _k * 1.8
	_streak(st, CENTRE + Vector3(-TOWER_X, 0.0, 0.0), red)
	_streak(st, CENTRE, blue)
	_streak(st, CENTRE + Vector3(TOWER_X, 0.0, 0.0), red)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(_mesh_node("WaterReflections", st.commit(), mat))


## Two quads, 120 m long and 10 m wide: the streak is brightest at the centre and fades to both ends.
static func _streak(st: SurfaceTool, c: Vector3, col: Color) -> void:
	var y: float = 0.3
	var lo: Color = Color(col.r, col.g, col.b, 0.0)
	var hi: Color = Color(col.r, col.g, col.b, 1.0)
	var l: Vector3 = c + Vector3(-60.0, y, -5.0)
	var m: Vector3 = c + Vector3(0.0, y, -5.0)
	var r: Vector3 = c + Vector3(60.0, y, -5.0)
	var l2: Vector3 = c + Vector3(-60.0, y, 5.0)
	var m2: Vector3 = c + Vector3(0.0, y, 5.0)
	var r2: Vector3 = c + Vector3(60.0, y, 5.0)
	_quad_c(st, [l, m, m2, l2], [lo, hi, hi, lo])
	_quad_c(st, [m, r, r2, m2], [hi, lo, lo, hi])


# --- helpers ---------------------------------------------------------------------------------------

func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _mesh_node(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	return mi


## Round soft-edged glow quads that face the camera, additive. Optional per-instance scale.
func _glow_node(node_name: String, pos: PackedVector3Array, cols: PackedColorArray, size: float,
		scales: Array[float] = []) -> MultiMeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	mm.instance_count = pos.size()
	for i: int in pos.size():
		var s: float = scales[i] if i < scales.size() else 1.0
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), pos[i]))
		mm.set_instance_color(i, cols[i])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _glow_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


static func _glow_texture() -> ImageTexture:
	if _glow == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y: int in 32:
			for x: int in 32:
				var d: float = Vector2(float(x) - 15.5, float(y) - 15.5).length() / 15.5
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, pow(clampf(1.0 - d, 0.0, 1.0), 2.0)))
		_glow = ImageTexture.create_from_image(img)
	return _glow


## Axis-aligned box as 12 triangles (6 quads).
static func _box(st: SurfaceTool, c: Vector3, h: Vector3) -> void:
	for ax: int in 3:
		var u_ax: int = (ax + 1) % 3
		var v_ax: int = (ax + 2) % 3
		for sg: float in [-1.0, 1.0]:
			var m: Vector3 = c
			m[ax] += sg * h[ax]
			var u: Vector3 = Vector3.ZERO
			var v: Vector3 = Vector3.ZERO
			u[u_ax] = h[u_ax]
			v[v_ax] = h[v_ax]
			_quad(st, [m - u - v, m + u - v, m + u + v, m - u + v])


## Square-section bar from a to b (a cable or a hanger): four side quads, no caps.
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var d: Vector3 = b - a
	if d.length_squared() < 1e-6:
		return
	d = d.normalized()
	var ref: Vector3 = Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var u: Vector3 = d.cross(ref).normalized() * w
	var v: Vector3 = d.cross(u).normalized() * w
	var dirs: Array[Vector3] = [u, v, -u, -v]
	for k: int in 4:
		var p0: Vector3 = a + dirs[k]
		var p1: Vector3 = a + dirs[(k + 1) % 4]
		var p2: Vector3 = b + dirs[(k + 1) % 4]
		var p3: Vector3 = b + dirs[k]
		_quad(st, [p0, p1, p2, p3])


static func _quad(st: SurfaceTool, p: Array[Vector3]) -> void:
	var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.add_vertex(p[k])


static func _quad_c(st: SurfaceTool, p: Array[Vector3], c: Array[Color]) -> void:
	var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_color(c[k])
		st.add_vertex(p[k])
