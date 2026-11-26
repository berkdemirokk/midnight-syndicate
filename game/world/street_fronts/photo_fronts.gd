class_name PhotoFronts
extends StreetFronts
## Row houses with photo-textured fronts on every first-row frontage of a track: each kit building is replaced (its
## collider and occluder stay) by a row of plain house bodies whose street face carries one house of a straight-on
## facade picture (res://assets/world/kits/photo_fronts/, generated for this project, see ASSET_MANIFEST.json and
## docs/art/PHOTO_TEXTURE_PIPELINE.md). A house is about 20 triangles and the houses of one frontage are merged into
## one mesh per picture, so the rows need no LODs. At night the night picture of the same facade is the glow map.

const ATLAS_DIR: String = "res://assets/world/kits/photo_fronts/"
const HOUSES_PER_ATLAS: int = 4
## Per track (key = part of the track scene path): its layout file, its pictures (<name>.jpg and <name>_night.jpg) and
## the size of one house of a picture (384 x 1024 px each).
const SETS: Dictionary = {
	"istanbul_bogaz": {"layout": "res://assets/world/istanbul_bogaz/istanbul_bogaz_layout.json",
		"atlases": ["facade_row_01", "facade_row_02"], "house_w_m": 5.4, "house_h_m": 14.4},
}
const HOUSE_DEPTH_M: float = 7.0
const ROOF_RISE_M: float = 1.7
const EAVE_M: float = 0.4  ## the roof comes this far out over the street face
const FACADE_SHADER: Shader = preload("res://world/street_fronts/photo_facade.gdshader")
const ROOF_COLOUR: Color = Color(0.2, 0.07, 0.045)  ## linear terracotta
const WALL_COLOUR: Color = Color(0.3, 0.27, 0.23)  ## linear plaster grey: side and back walls
const NIGHT_GLOW: float = 1.6
const SUNSET_GLOW: float = 0.7
const NIGHT_TINT: Vector3 = Vector3(0.55, 0.5, 0.5)  ## unlit walls keep a little of the street's warm light

var _facades: Array[ShaderMaterial] = []
var _set: Dictionary = {}
var _house_w: float = 5.4
var _house_h: float = 14.4


## True when this track has a picture set.
static func has_set(track_scene_path: String) -> bool:
	return not _set_for(track_scene_path).is_empty()


static func _set_for(track_scene_path: String) -> Dictionary:
	for key: String in SETS:
		if track_scene_path.contains(key):
			return SETS[key]
	return {}


func setup(track: Track, time_of_day_id: String) -> void:
	_tod = time_of_day_id
	_set = _set_for(track.scene_file_path)
	if _set.is_empty():
		return
	_house_w = float(_set["house_w_m"])
	_house_h = float(_set["house_h_m"])
	_load_library()
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(String(_set["layout"])))
	var kit: Array[Node3D] = _kit_roots(track)
	var fronts := Node3D.new()
	fronts.name = "Fronts"
	add_child(fronts)
	for v: Variant in layout["instances"]:
		var d: Dictionary = v
		if String(d["kind"]) != "building":
			continue
		var root: Node3D = _nearest_root(kit, String(d["asset"]), _vec(d["position"]))
		if root != null and not _replaced.has(root):  # second-row buildings have no first-row root: they stay
			_replace(track, root, d, fronts)
	if _tod == "night":
		_add_pools()
		_add_lights(layout)
	_apply_time()


func _load_library() -> void:
	_pool_mat = ShaderMaterial.new()
	_pool_mat.shader = POOL_SHADER
	_pool_mat.set_shader_parameter("tint", WARM)
	_pool_mat.set_shader_parameter("strength", POOL_STRENGTH)
	_pool_mat.set_shader_parameter("radius_m", POOL_RADIUS_M)
	var atlases: Array = _set["atlases"]
	for a: int in atlases.size():
		var facade := ShaderMaterial.new()
		facade.shader = FACADE_SHADER
		facade.set_shader_parameter("albedo_tex", load(ATLAS_DIR + String(atlases[a]) + ".jpg"))
		var night_path: String = ATLAS_DIR + String(atlases[a]) + "_night.jpg"
		if ResourceLoader.exists(night_path):
			facade.set_shader_parameter("night_tex", load(night_path))
		_facades.append(facade)
		for h: int in HOUSES_PER_ATLAS:
			var id: String = "house_%d_%d" % [a, h]
			_info[id] = {"width_m": _house_w, "depth_m": HOUSE_DEPTH_M}
			_lods[id] = [_house_mesh(h)]


func _apply_time() -> void:
	super._apply_time()
	var glow: float = NIGHT_GLOW if _tod == "night" else (SUNSET_GLOW if _tod == "sunset" else 0.0)
	for facade: ShaderMaterial in _facades:
		facade.set_shader_parameter("night", glow)
		facade.set_shader_parameter("tint", NIGHT_TINT if _tod == "night" else Vector3.ONE)


## A row of houses sized to the frontage, picked from every picture; seeded, so a frontage always gets the same row.
func _fill(width: float, seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[Dictionary] = []
	var kinds: int = _facades.size() * HOUSES_PER_ATLAS
	var n: int = maxi(1, roundi(width / _house_w))
	var seg: float = width / float(n)
	var first: int = rng.randi() % kinds
	var step: int = 1 + 2 * (rng.randi() % 2)  # 1 or 3: both walk every house, neighbours never repeat
	for i: int in n:
		var k: int = (first + i * step) % kinds
		out.append({"id": "house_%d_%d" % [k / HOUSES_PER_ATLAS, k % HOUSES_PER_ATLAS], "atlas": k / HOUSES_PER_ATLAS,
				"x": -width / 2.0 + seg * (float(i) + 0.5), "sx": seg / _house_w})
	return out


## Hides the kit's LOD0 and LOD1 and puts the row there as ONE mesh (one surface per picture used). A frontage whose
## houses would reach into the race corridor keeps its kit building.
func _replace(track: Track, root: Node3D, d: Dictionary, parent: Node3D) -> void:
	var slots: Array[Dictionary] = _fill(float(d["width_m"]),
			int(round(float(d["s_offset_m"]) * 10.0)) * 31 + int(root.global_position.x * 7.0))
	for slot: Dictionary in slots:
		if not _clear_of_road(track, root.global_transform, slot):
			_kept += 1
			return
	for lod_name: String in ["LOD0", "LOD1"]:
		for mi: Node in root.find_children(lod_name, "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visible = false
	_replaced.append(root)
	var tools: Dictionary = {}  # atlas index -> SurfaceTool
	for slot: Dictionary in slots:
		var atlas: int = int(slot["atlas"])
		if not tools.has(atlas):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[atlas] = st
		var sx: float = float(slot["sx"])
		# the model's street face is -Z (as in StreetFronts); width and height scale together, the picture keeps its shape
		var local := Transform3D(Basis(Vector3.UP, PI) * Basis.from_scale(Vector3(sx, sx, 1.0)), Vector3(float(slot["x"]), 0.0, 0.0))
		(tools[atlas] as SurfaceTool).append_from(_lods[slot["id"]][0], 0, local)
		_shop_fronts.append(root.global_transform * local)
	var mesh := ArrayMesh.new()
	for atlas: int in tools:
		var st: SurfaceTool = tools[atlas]
		st.set_material(_facades[atlas])
		st.commit(mesh)
	var row := MeshInstance3D.new()
	row.name = "Row_%03d" % _buildings.size()
	row.mesh = mesh
	row.set_meta("houses", slots.size())
	row.visibility_range_end = LOD1_END_M
	row.visibility_range_end_margin = FADE_M
	row.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(row)
	row.global_transform = root.global_transform
	_buildings.append(row)


## One house, one surface: the street face with the picture of house `index` (vertex alpha 1: textured), then side
## walls, back wall and a pitched roof in plain vertex colours (alpha 0: the shader skips the picture there).
func _house_mesh(index: int) -> ArrayMesh:
	var w: float = _house_w / 2.0
	var h: float = _house_h
	var d: float = HOUSE_DEPTH_M
	var u0: float = float(index) / float(HOUSES_PER_ATLAS)
	var u1: float = float(index + 1) / float(HOUSES_PER_ATLAS)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# seen from the street (looking along +Z) the model's +X is on the left: u0 goes there
	_quad(st, [Vector3(w, h, 0.0), Vector3(-w, h, 0.0), Vector3(-w, 0.0, 0.0), Vector3(w, 0.0, 0.0)],
			[Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0)], Vector3(0.0, 0.0, -1.0), Color.WHITE)
	var wall := Color(WALL_COLOUR, 0.0)
	var roof := Color(ROOF_COLOUR, 0.0)
	var no_uv: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	_quad(st, [Vector3(w, h, 0.0), Vector3(w, h, d), Vector3(w, 0.0, d), Vector3(w, 0.0, 0.0)], no_uv, Vector3(1.0, 0.0, 0.0), wall)
	_quad(st, [Vector3(-w, h, d), Vector3(-w, h, 0.0), Vector3(-w, 0.0, 0.0), Vector3(-w, 0.0, d)], no_uv, Vector3(-1.0, 0.0, 0.0), wall)
	_quad(st, [Vector3(-w, h, d), Vector3(w, h, d), Vector3(w, 0.0, d), Vector3(-w, 0.0, d)], no_uv, Vector3(0.0, 0.0, 1.0), wall)
	var ridge: float = h + ROOF_RISE_M
	var front_n: Vector3 = Vector3(0.0, d / 2.0 + EAVE_M, -ROOF_RISE_M).normalized()
	var back_n: Vector3 = Vector3(0.0, d / 2.0, ROOF_RISE_M).normalized()
	_quad(st, [Vector3(w, ridge, d / 2.0), Vector3(-w, ridge, d / 2.0), Vector3(-w, h, -EAVE_M), Vector3(w, h, -EAVE_M)], no_uv, front_n, roof)
	_quad(st, [Vector3(-w, ridge, d / 2.0), Vector3(w, ridge, d / 2.0), Vector3(w, h, d), Vector3(-w, h, d)], no_uv, back_n, roof)
	for side: float in [1.0, -1.0]:  # gable ends
		for p: Vector3 in [Vector3(side * w, h, 0.0), Vector3(side * w, ridge, d / 2.0), Vector3(side * w, h, d)]:
			st.set_normal(Vector3(side, 0.0, 0.0))
			st.set_color(wall)
			st.set_uv(Vector2.ZERO)
			st.add_vertex(p)
	return st.commit()


func _quad(st: SurfaceTool, p: Array, uv: Array, normal: Vector3, colour: Color) -> void:
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_color(colour)
		st.set_uv(uv[i])
		st.add_vertex(p[i])
