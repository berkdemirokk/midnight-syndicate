class_name PhotoFronts
extends StreetFronts
## Buildings with photo-textured fronts on the first-row frontages of a track: each kit building is replaced (its
## collider and occluder stay) by a row of plain bodies whose street face carries one building of a straight-on facade
## picture (res://assets/world/kits/photo_fronts/, generated for this project, see ASSET_MANIFEST.json and
## docs/art/PHOTO_TEXTURE_PIPELINE.md). A body is about 20 triangles and the bodies of one frontage are merged into one
## mesh per picture, so the rows need no LODs. At night the night picture of the same facade is the glow map.

const ATLAS_DIR: String = "res://assets/world/kits/photo_fronts/"
const HOUSES_PER_ATLAS: int = 4  ## buildings side by side in one picture, 384 x 1024 px each
## Per track (key = part of the track scene path): its layout file and its groups. A group serves the kit buildings whose
## asset name starts with one of "match" (empty = every building no earlier group took): pictures (<name>.jpg and
## <name>_night.jpg), the size of one building of a picture, its depth and its roof rise (0 = flat roof).
const SETS: Dictionary = {
	"istanbul_bogaz": {"layout": "res://assets/world/istanbul_bogaz/istanbul_bogaz_layout.json", "groups": [
		{"match": [], "atlases": ["facade_row_01", "facade_row_02"], "w": 5.4, "h": 14.4, "depth": 7.0, "roof": 1.7}]},
	"istanbul_maslak": {"layout": "res://assets/world/istanbul_maslak/istanbul_maslak_layout.json", "groups": [
		{"match": ["bld_downtown"], "atlases": ["tower_row_01"], "w": 25.0, "h": 66.7, "depth": 20.0, "roof": 0.0},
		{"match": [], "atlases": ["modern_row_01", "neon_row_01"], "w": 8.0, "h": 21.3, "depth": 9.0, "roof": 0.0}]},
	"city_01": {"layout": "res://assets/world/city_01/city_01_layout.json", "groups": [
		{"match": ["bld_downtown"], "atlases": ["tower_row_01"], "w": 25.0, "h": 66.7, "depth": 20.0, "roof": 0.0},
		{"match": ["bld_waterfront", "bld_parking"], "atlases": [], "w": 1.0, "h": 1.0, "depth": 1.0, "roof": 0.0},
		{"match": [], "atlases": ["neon_row_01", "market_row_01"], "w": 6.6, "h": 17.6, "depth": 8.0, "roof": 0.0}]},
}
const EAVE_M: float = 0.4  ## a pitched roof comes this far out over the street face
const FACADE_SHADER: Shader = preload("res://world/street_fronts/photo_facade.gdshader")
const ROOF_COLOUR: Color = Color(0.2, 0.07, 0.045)  ## linear terracotta (pitched roofs)
const FLAT_ROOF_COLOUR: Color = Color(0.12, 0.12, 0.13)  ## linear bitumen grey (flat roofs)
const WALL_COLOUR: Color = Color(0.3, 0.27, 0.23)  ## linear plaster grey: side and back walls
const NIGHT_GLOW: float = 1.6
const SUNSET_GLOW: float = 0.7
const NIGHT_TINT: Vector3 = Vector3(0.55, 0.5, 0.5)  ## unlit walls keep a little of the street's warm light

var _facades: Array[ShaderMaterial] = []
var _groups: Array[Dictionary] = []  ## the track's groups with "mats": indices into _facades of the shipped pictures


## True when this track has a picture set with at least one shipped picture.
static func has_set(track_scene_path: String) -> bool:
	for group: Dictionary in _set_for(track_scene_path).get("groups", []):
		if not _shipped(group).is_empty():
			return true
	return false


static func _set_for(track_scene_path: String) -> Dictionary:
	for key: String in SETS:
		if track_scene_path.contains(key):
			return SETS[key]
	return {}


## The pictures of a group that exist in this build.
static func _shipped(group: Dictionary) -> Array:
	return (group["atlases"] as Array).filter(func(n: Variant) -> bool: return ResourceLoader.exists(ATLAS_DIR + String(n) + ".jpg"))


func setup(track: Track, time_of_day_id: String) -> void:
	_tod = time_of_day_id
	var found: Dictionary = _set_for(track.scene_file_path)
	if found.is_empty():
		return
	_load_groups(found["groups"])
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(String(found["layout"])))
	var kit: Array[Node3D] = _kit_roots(track)
	var fronts := Node3D.new()
	fronts.name = "Fronts"
	add_child(fronts)
	for v: Variant in layout["instances"]:
		var d: Dictionary = v
		if String(d["kind"]) != "building":
			continue
		var group: Dictionary = _group_for(String(d["asset"]))
		if group.is_empty() or (group["mats"] as Array).is_empty():  # no picture for this kind of building: the kit stays
			continue
		var root: Node3D = _nearest_root(kit, String(d["asset"]), _vec(d["position"]))
		if root != null and not _replaced.has(root):  # second-row buildings have no first-row root: they stay
			_replace_with(group, track, root, d, fronts)
	if _tod == "night" and not _shop_fronts.is_empty():
		_add_pools()
		_add_lights(layout)
	_apply_time()


func _load_groups(groups: Array) -> void:
	_pool_mat = ShaderMaterial.new()
	_pool_mat.shader = POOL_SHADER
	_pool_mat.set_shader_parameter("tint", WARM)
	_pool_mat.set_shader_parameter("strength", POOL_STRENGTH)
	_pool_mat.set_shader_parameter("radius_m", POOL_RADIUS_M)
	var by_name: Dictionary = {}  # picture name -> index into _facades (a picture may serve two groups)
	for g: int in groups.size():
		var group: Dictionary = (groups[g] as Dictionary).duplicate()
		var mats: Array[int] = []
		for atlas_name: Variant in _shipped(group):
			if not by_name.has(atlas_name):
				var facade := ShaderMaterial.new()
				facade.shader = FACADE_SHADER
				facade.set_shader_parameter("albedo_tex", load(ATLAS_DIR + String(atlas_name) + ".jpg"))
				var night_path: String = ATLAS_DIR + String(atlas_name) + "_night.jpg"
				if ResourceLoader.exists(night_path):
					facade.set_shader_parameter("night_tex", load(night_path))
				var relief_path: String = ATLAS_DIR + String(atlas_name) + "_normal.png"
				if ResourceLoader.exists(relief_path):  # relief derived from the picture: recesses and trim catch the light
					facade.set_shader_parameter("normal_tex", load(relief_path))
					facade.set_shader_parameter("relief", 1.0)
				by_name[atlas_name] = _facades.size()
				_facades.append(facade)
			mats.append(int(by_name[atlas_name]))
		group["mats"] = mats
		group["id"] = g
		group["meshes"] = []
		for h: int in HOUSES_PER_ATLAS:
			(group["meshes"] as Array).append(_house_mesh(h, group))
		_groups.append(group)


func _group_for(asset: String) -> Dictionary:
	for group: Dictionary in _groups:
		var prefixes: Array = group["match"]
		if prefixes.is_empty() or prefixes.any(func(p: Variant) -> bool: return asset.begins_with(String(p))):
			return group
	return {}


func _apply_time() -> void:
	super._apply_time()
	var glow: float = NIGHT_GLOW if _tod == "night" else (SUNSET_GLOW if _tod == "sunset" else 0.0)
	for facade: ShaderMaterial in _facades:
		facade.set_shader_parameter("night", glow)
		facade.set_shader_parameter("tint", NIGHT_TINT if _tod == "night" else Vector3.ONE)


## A row of buildings sized to the frontage, picked from every picture of the group; seeded, so a frontage always gets
## the same row.
func _slots(group: Dictionary, width: float, seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[Dictionary] = []
	var house_w: float = float(group["w"])
	var kinds: int = (group["mats"] as Array).size() * HOUSES_PER_ATLAS
	var n: int = maxi(1, roundi(width / house_w))
	var seg: float = width / float(n)
	var first: int = rng.randi() % kinds
	var step: int = 1 + 2 * (rng.randi() % 2)  # 1 or 3: both walk every building, neighbours never repeat
	for i: int in n:
		var k: int = (first + i * step) % kinds
		out.append({"id": "g%d" % int(group["id"]), "mat": int(group["mats"][k / HOUSES_PER_ATLAS]), "house": k % HOUSES_PER_ATLAS,
				"x": -width / 2.0 + seg * (float(i) + 0.5), "sx": seg / house_w})
	return out


## Hides the kit's LOD0 and LOD1 and puts the row there as ONE mesh (one surface per picture used). A frontage whose
## buildings would reach into the race corridor keeps its kit building.
func _replace_with(group: Dictionary, track: Track, root: Node3D, d: Dictionary, parent: Node3D) -> void:
	_info["g%d" % int(group["id"])] = {"width_m": float(group["w"]), "depth_m": float(group["depth"])}
	var slots: Array[Dictionary] = _slots(group, float(d["width_m"]),
			int(round(float(d["s_offset_m"]) * 10.0)) * 31 + int(root.global_position.x * 7.0))
	for slot: Dictionary in slots:
		if not _clear_of_road(track, root.global_transform, slot):
			_kept += 1
			return
	for lod_name: String in ["LOD0", "LOD1"]:
		for mi: Node in root.find_children(lod_name, "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visible = false
	_replaced.append(root)
	var tools: Dictionary = {}  # facade index -> SurfaceTool
	for slot: Dictionary in slots:
		var mat: int = int(slot["mat"])
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		var sx: float = float(slot["sx"])
		# the model's street face is -Z (as in StreetFronts); width and height scale together, the picture keeps its shape
		var local := Transform3D(Basis(Vector3.UP, PI) * Basis.from_scale(Vector3(sx, sx, 1.0)), Vector3(float(slot["x"]), 0.0, 0.0))
		(tools[mat] as SurfaceTool).append_from(group["meshes"][int(slot["house"])], 0, local)
		_shop_fronts.append(root.global_transform * local)
	var mesh := ArrayMesh.new()
	for mat: int in tools:
		var st: SurfaceTool = tools[mat]
		st.set_material(_facades[mat])
		st.commit(mesh)
	var row := MeshInstance3D.new()
	row.name = "Row_%03d" % _buildings.size()
	row.mesh = mesh
	row.set_meta("houses", slots.size())
	row.visibility_range_end = maxf(LOD1_END_M, float(group["h"]) * 6.0)  # towers stay in view from further away
	row.visibility_range_end_margin = FADE_M
	row.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(row)
	row.global_transform = root.global_transform
	_buildings.append(row)


## One building, one surface: the street face with the picture of building `index` (vertex alpha 1: textured), then side
## walls, back wall and the roof in plain vertex colours (alpha 0: the shader skips the picture there).
func _house_mesh(index: int, group: Dictionary) -> ArrayMesh:
	var w: float = float(group["w"]) / 2.0
	var h: float = float(group["h"])
	var d: float = float(group["depth"])
	var rise: float = float(group["roof"])
	var eave: float = EAVE_M if rise > 0.0 else 0.0
	var u0: float = float(index) / float(HOUSES_PER_ATLAS)
	var u1: float = float(index + 1) / float(HOUSES_PER_ATLAS)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# seen from the street (looking along +Z) the model's +X is on the left: u0 goes there
	_quad(st, [Vector3(w, h, 0.0), Vector3(-w, h, 0.0), Vector3(-w, 0.0, 0.0), Vector3(w, 0.0, 0.0)],
			[Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0)], Vector3(0.0, 0.0, -1.0), Color.WHITE)
	var wall := Color(WALL_COLOUR, 0.0)
	var roof := Color(ROOF_COLOUR if rise > 0.0 else FLAT_ROOF_COLOUR, 0.0)
	var no_uv: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	_quad(st, [Vector3(w, h, 0.0), Vector3(w, h, d), Vector3(w, 0.0, d), Vector3(w, 0.0, 0.0)], no_uv, Vector3(1.0, 0.0, 0.0), wall)
	_quad(st, [Vector3(-w, h, d), Vector3(-w, h, 0.0), Vector3(-w, 0.0, 0.0), Vector3(-w, 0.0, d)], no_uv, Vector3(-1.0, 0.0, 0.0), wall)
	_quad(st, [Vector3(-w, h, d), Vector3(w, h, d), Vector3(w, 0.0, d), Vector3(-w, 0.0, d)], no_uv, Vector3(0.0, 0.0, 1.0), wall)
	var ridge: float = h + rise
	var front_n: Vector3 = Vector3(0.0, d / 2.0 + eave, -rise).normalized()
	var back_n: Vector3 = Vector3(0.0, d / 2.0, rise).normalized()
	_quad(st, [Vector3(w, ridge, d / 2.0), Vector3(-w, ridge, d / 2.0), Vector3(-w, h, -eave), Vector3(w, h, -eave)], no_uv, front_n, roof)
	_quad(st, [Vector3(-w, ridge, d / 2.0), Vector3(w, ridge, d / 2.0), Vector3(w, h, d), Vector3(-w, h, d)], no_uv, back_n, roof)
	if rise > 0.0:
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
