class_name PhotoFronts
extends StreetFronts
## Buildings with photo-textured fronts on the first-row frontages of a track: each kit building is replaced (its
## collider and occluder stay) by a row of plain bodies whose street face carries one building of a straight-on facade
## picture (res://assets/world/kits/photo_fronts/, generated for this project, see ASSET_MANIFEST.json and
## docs/art/PHOTO_TEXTURE_PIPELINE.md). A body is about 30 triangles and the bodies of one frontage are merged into one
## mesh per picture, so the rows need no LODs. At night the night picture of the same facade is the glow map.

const ATLAS_DIR: String = "res://assets/world/kits/photo_fronts/"
const HOUSES_PER_ATLAS: int = 4  ## buildings side by side in one picture, 384 x 1024 px each
## Per track (key = part of the track scene path): its layout file and its groups. A group serves the kit buildings whose
## asset name starts with one of "match" (empty = every building no earlier group took): pictures (<name>.jpg and
## <name>_night.jpg), the size of one building of a picture, its depth and its roof rise (0 = flat roof). "textured" puts
## plaster walls and tile roofs on the side, back and roof planes (metre UVs), instead of the plain vertex colours.
const SETS: Dictionary = {
	"istanbul_bogaz": {"layout": "res://assets/world/istanbul_bogaz/istanbul_bogaz_layout.json", "groups": [
		{"match": [], "atlases": ["facade_row_01", "facade_row_02"], "w": 5.4, "h": 14.4, "depth": 7.0, "roof": 1.7, "textured": true, "shop": 0.22, "stone": Color(0.62, 0.57, 0.5)}]},
	"istanbul_maslak": {"layout": "res://assets/world/istanbul_maslak/istanbul_maslak_layout.json", "groups": [
		{"match": ["bld_downtown"], "atlases": ["tower_row_01"], "w": 25.0, "h": 66.7, "depth": 20.0, "roof": 0.0, "textured": true, "wall_tex": "concrete_wall_006", "roof_tex": "bitumen", "wall": Color(0.6, 0.6, 0.6), "wall_sat": 0.5, "wall_gain": 1.9, "wall_uv": 3.0, "shop": 0.12, "stone": Color(0.36, 0.36, 0.37), "stone_tex": "marble_01"},
		{"match": [], "atlases": ["modern_row_01", "neon_row_01"], "w": 8.0, "h": 21.3, "depth": 9.0, "roof": 0.0, "textured": true, "wall_tex": "concrete_wall_006", "roof_tex": "bitumen", "wall": Color(0.6, 0.6, 0.6), "wall_sat": 0.5, "wall_gain": 1.9, "wall_uv": 3.0, "shop": 0.22, "stone": Color(0.45, 0.44, 0.43), "stone_tex": "marble_01"}]},
	"city_01": {"layout": "res://assets/world/city_01/city_01_layout.json", "groups": [
		{"match": ["bld_downtown"], "atlases": ["tower_row_01"], "w": 25.0, "h": 66.7, "depth": 20.0, "roof": 0.0, "textured": true, "wall_tex": "concrete_wall_006", "roof_tex": "bitumen", "wall": Color(0.6, 0.6, 0.6), "wall_sat": 0.5, "wall_gain": 1.9, "wall_uv": 3.0, "shop": 0.12, "stone": Color(0.36, 0.36, 0.37), "stone_tex": "marble_01"},
		{"match": ["bld_waterfront", "bld_parking"], "atlases": [], "w": 1.0, "h": 1.0, "depth": 1.0, "roof": 0.0},
		{"match": [], "atlases": ["neon_row_01", "market_row_01"], "w": 6.6, "h": 17.6, "depth": 8.0, "roof": 0.0, "textured": true, "wall_tex": "brick_wall_006", "roof_tex": "bitumen", "wall": Color(0.62, 0.6, 0.58), "wall_sat": 0.75, "wall_gain": 1.5, "wall_uv": 1.6, "shop": 0.22, "stone": Color(0.5, 0.46, 0.42)}]},
}
const EAVE_M: float = 0.8  ## a pitched roof comes this far out over the street face
const FASCIA_M: float = 0.22  ## the board under the roof front edge; the soffit runs back from it under the eave
const FACADE_SHADER: Shader = preload("res://world/street_fronts/photo_facade.gdshader")
const WALL_TEX: String = "res://assets/textures/cc0/clay_plaster/basecolor.jpg"
const WALL_NRM: String = "res://assets/textures/cc0/clay_plaster/normal.jpg"
const ROOF_TEX: String = "res://assets/world/kits/istanbul/textures/roof_tile_basecolor.png"
const ROOF_COLOUR: Color = Color(0.2, 0.07, 0.045)  ## linear terracotta (pitched roofs)
const FLAT_ROOF_COLOUR: Color = Color(0.12, 0.12, 0.13)  ## linear bitumen grey (flat roofs)
const ROOF_ALPHA: float = 0.5  ## vertex alpha of a roof plane: the shader roof band (0 wall, 1 street face)
const SOFFIT_COLOUR: Color = Color(0.12, 0.09, 0.07)  ## linear shadowed underside of the eave
const WALL_COLOUR: Color = Color(0.52, 0.48, 0.43)  ## linear warm stone-grey plaster: side and back walls of textured groups (0.45/0.40/0.34 read as mustard with the ochre texture)
const PLAIN_WALL_COLOUR: Color = Color(0.3, 0.27, 0.23)  ## the same walls in the groups without a texture
const WALL_UV_M: float = 2.5  ## metres per texture repeat on walls
const ROOF_UV_M: float = 1.0  ## metres per texture repeat on roofs
const NIGHT_GLOW: float = 1.6
const SUNSET_GLOW: float = 0.7
const GLASS_SHADER_3D: Shader = preload("res://world/street_fronts/storefront_glass.gdshader")
const TRIM_SHADER: Shader = preload("res://world/street_fronts/storefront_trim.gdshader")
const STONE_DIR: String = "res://assets/textures/cc0/"
const SHOP_NIGHT: float = 1.0
const SHOP_SUNSET: float = 0.55
const NIGHT_TINT: Vector3 = Vector3(0.55, 0.5, 0.5)  ## unlit walls keep a little of the street warm light

var _facades: Array[ShaderMaterial] = []
var _shop_glass: Array[ShaderMaterial] = []  ## storefront glass per picture (index as _facades): the picture's shop is the room
var _trims: Dictionary = {}  ## stone texture name -> storefront trim material
var _groups: Array[Dictionary] = []  ## the track groups with "mats": indices into _facades of the shipped pictures


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
		var textured: bool = bool(group.get("textured", false))
		var mats: Array[int] = []
		for atlas_name: Variant in _shipped(group):
			if not by_name.has(atlas_name):
				var facade := ShaderMaterial.new()
				facade.shader = FACADE_SHADER
				facade.set_shader_parameter("albedo_tex", load(ATLAS_DIR + String(atlas_name) + ".jpg"))
				facade.set_shader_parameter("textured_walls", textured)
				if textured:
					var wt: String = String(group.get("wall_tex", ""))
					facade.set_shader_parameter("wall_tex", load(WALL_TEX if wt == "" else STONE_DIR + wt + "/basecolor.jpg"))
					facade.set_shader_parameter("wall_nrm", load(WALL_NRM if wt == "" else STONE_DIR + wt + "/normal.jpg"))
					var rt: String = String(group.get("roof_tex", ""))
					facade.set_shader_parameter("roof_tex", load(ROOF_TEX if rt == "" else STONE_DIR + rt + "/basecolor.jpg"))
					facade.set_shader_parameter("wall_saturation", float(group.get("wall_sat", 0.3)))
					facade.set_shader_parameter("wall_gain", float(group.get("wall_gain", 2.6)))
				var night_path: String = ATLAS_DIR + String(atlas_name) + "_night.jpg"
				if ResourceLoader.exists(night_path):
					facade.set_shader_parameter("night_tex", load(night_path))
				var relief_path: String = ATLAS_DIR + String(atlas_name) + "_normal.png"
				if ResourceLoader.exists(relief_path):  # relief derived from the picture: recesses and trim catch the light
					facade.set_shader_parameter("normal_tex", load(relief_path))
					facade.set_shader_parameter("relief", 1.0)
				by_name[atlas_name] = _facades.size()
				_facades.append(facade)
				var gl := ShaderMaterial.new()
				gl.shader = GLASS_SHADER_3D
				gl.set_shader_parameter("albedo_tex", facade.get_shader_parameter("albedo_tex"))
				gl.set_shader_parameter("night_tex", facade.get_shader_parameter("night_tex") if ResourceLoader.exists(night_path) else facade.get_shader_parameter("albedo_tex"))
				_shop_glass.append(gl)
			mats.append(int(by_name[atlas_name]))
		group["mats"] = mats
		var stone_name: String = String(group.get("stone_tex", "sandstone_blocks_08"))
		if float(group.get("shop", 0.0)) > 0.0 and not _trims.has(stone_name):
			var tm := ShaderMaterial.new()
			tm.shader = TRIM_SHADER
			tm.set_shader_parameter("stone_tex", load(STONE_DIR + stone_name + "/basecolor.jpg"))
			tm.set_shader_parameter("stone_nrm", load(STONE_DIR + stone_name + "/normal.jpg"))
			_trims[stone_name] = tm
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
	for gl: ShaderMaterial in _shop_glass:
		gl.set_shader_parameter("night", SHOP_NIGHT if _tod == "night" else (SHOP_SUNSET if _tod == "sunset" else 0.0))


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


## Hides the kit LOD0 and LOD1 and puts the row there as ONE mesh (one surface per picture used). A frontage whose
## buildings would reach into the race corridor keeps its kit building.
func _replace_with(group: Dictionary, track: Track, root: Node3D, d: Dictionary, parent: Node3D) -> void:
	_info["g%d" % int(group["id"])] = {"width_m": float(group["w"]), "depth_m": float(group["depth"]),
			"eave_m": EAVE_M if float(group["roof"]) > 0.0 else 0.0}
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
	var glass_tools: Dictionary = {}  # facade index -> SurfaceTool of the storefront glass
	var frac: float = float(group.get("shop", 0.0))
	var trim: SurfaceTool = null
	if frac > 0.0:
		trim = SurfaceTool.new()
		trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shop_rng := RandomNumberGenerator.new()
	shop_rng.seed = int(round(float(d["s_offset_m"]) * 10.0)) * 17 + 5
	for slot: Dictionary in slots:
		var mat: int = int(slot["mat"])
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		var sx: float = float(slot["sx"])
		# the model street face is -Z as in StreetFronts; width and height scale together, the picture keeps its shape
		var local := Transform3D(Basis(Vector3.UP, PI) * Basis.from_scale(Vector3(sx, sx, 1.0)), Vector3(float(slot["x"]), 0.0, 0.0))
		(tools[mat] as SurfaceTool).append_from(group["meshes"][int(slot["house"])], 0, local)
		if trim != null:
			if not glass_tools.has(mat):
				var gst := SurfaceTool.new()
				gst.begin(Mesh.PRIMITIVE_TRIANGLES)
				glass_tools[mat] = gst
			var house: int = int(slot["house"])
			Storefront.build(trim, glass_tools[mat], tools[mat], Transform3D(Basis(Vector3.UP, PI), Vector3(float(slot["x"]), 0.0, 0.0)),
					float(group["w"]) * sx, float(group["h"]) * sx, float(house) / float(HOUSES_PER_ATLAS), float(house + 1) / float(HOUSES_PER_ATLAS),
					frac, shop_rng, group.get("stone", Color(0.6, 0.56, 0.5)))
		_shop_fronts.append(root.global_transform * local)
	var mesh := ArrayMesh.new()
	for mat: int in tools:
		var st: SurfaceTool = tools[mat]
		st.generate_tangents()  # the wall and roof normal maps need tangents
		st.set_material(_facades[mat])
		st.commit(mesh)
	for mat: int in glass_tools:
		var gst: SurfaceTool = glass_tools[mat]
		gst.set_material(_shop_glass[mat])
		gst.commit(mesh)
	if trim != null:
		trim.generate_tangents()
		trim.set_material(_trims[String(group.get("stone_tex", "sandstone_blocks_08"))])
		trim.commit(mesh)
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


## The eave overhangs the street face by EAVE_M, so its ends must clear the corridor as well as the wall corners.
func _clear_of_road(track: Track, root_xf: Transform3D, slot: Dictionary) -> bool:
	if not super(track, root_xf, slot):
		return false
	var half: float = float(_info[slot["id"]]["width_m"]) / 2.0 * float(slot["sx"])
	var x: float = float(slot["x"])
	var eave: float = float(_info[slot["id"]]["eave_m"])
	for p: Vector3 in [Vector3(x - half, 0.15, -eave), Vector3(x + half, 0.15, -eave)]:
		if absf(track.get_lateral_offset(root_xf * p)) < CORRIDOR_CLEAR_M:
			return false
	return true


## One building, one surface: the street face with the picture of building `index` (vertex alpha 1: textured), then side
## walls, back wall, gables, roof planes (alpha ROOF_ALPHA), the eave fascia and soffit (alpha 0). Walls and roofs have
## metre UVs and the surface gets tangents, so textured rows can put plaster and tile on them.
func _house_mesh(index: int, group: Dictionary) -> ArrayMesh:
	var w: float = float(group["w"]) / 2.0
	var h: float = float(group["h"])
	var d: float = float(group["depth"])
	var rise: float = float(group["roof"])
	var eave: float = EAVE_M if rise > 0.0 else 0.0
	var fascia: float = FASCIA_M if rise > 0.0 else 0.0
	var ridge: float = h + rise
	var low: float = h - fascia  # the roof front edge; the fascia board hangs from here to the wall top
	var u0: float = float(index) / float(HOUSES_PER_ATLAS)
	var u1: float = float(index + 1) / float(HOUSES_PER_ATLAS)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# seen from the street (looking along +Z) the model +X is on the left: u0 goes there
	var frac: float = float(group.get("shop", 0.0))  # the shop band is a 3D Storefront, the picture starts above it
	var y0: float = frac * h
	_quad(st, [Vector3(w, h, 0.0), Vector3(-w, h, 0.0), Vector3(-w, y0, 0.0), Vector3(w, y0, 0.0)],
			[Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0 - frac), Vector2(u0, 1.0 - frac)], Vector3(0.0, 0.0, -1.0), Color.WHITE)
	# the plaster and tile band (roof alpha, lifted wall colour) is for the textured groups only; other tracks keep the plain look
	var textured: bool = bool(group.get("textured", false))
	var wall := Color(group.get("wall", WALL_COLOUR) if textured else PLAIN_WALL_COLOUR, 0.0)
	var wall_uv_m: float = float(group.get("wall_uv", WALL_UV_M))
	var roof := Color(ROOF_COLOUR if rise > 0.0 else FLAT_ROOF_COLOUR, ROOF_ALPHA if textured else 0.0)
	var wall_uv := func(p: Vector3) -> Vector2: return Vector2(p.x + p.z, -p.y) / wall_uv_m
	var roof_uv := func(p: Vector3) -> Vector2: return Vector2(p.x, Vector2(p.y - ridge, p.z - d / 2.0).length()) / ROOF_UV_M
	var side_r: Array = [Vector3(w, h, 0.0), Vector3(w, h, d), Vector3(w, 0.0, d), Vector3(w, 0.0, 0.0)]
	_quad(st, side_r, _uvs(side_r, wall_uv), Vector3(1.0, 0.0, 0.0), wall)
	var side_l: Array = [Vector3(-w, h, d), Vector3(-w, h, 0.0), Vector3(-w, 0.0, 0.0), Vector3(-w, 0.0, d)]
	_quad(st, side_l, _uvs(side_l, wall_uv), Vector3(-1.0, 0.0, 0.0), wall)
	var back: Array = [Vector3(-w, h, d), Vector3(w, h, d), Vector3(w, 0.0, d), Vector3(-w, 0.0, d)]
	_quad(st, back, _uvs(back, wall_uv), Vector3(0.0, 0.0, 1.0), wall)
	var front_n: Vector3 = Vector3(0.0, d / 2.0 + eave, -(rise + fascia)).normalized()
	var back_n: Vector3 = Vector3(0.0, d / 2.0, rise).normalized()
	var front_roof: Array = [Vector3(w, ridge, d / 2.0), Vector3(-w, ridge, d / 2.0), Vector3(-w, low, -eave), Vector3(w, low, -eave)]
	_quad(st, front_roof, _uvs(front_roof, roof_uv), front_n, roof)
	var back_roof: Array = [Vector3(-w, ridge, d / 2.0), Vector3(w, ridge, d / 2.0), Vector3(w, h, d), Vector3(-w, h, d)]
	_quad(st, back_roof, _uvs(back_roof, roof_uv), back_n, roof)
	if rise > 0.0:
		var fascia_pts: Array = [Vector3(w, h, -eave), Vector3(-w, h, -eave), Vector3(-w, low, -eave), Vector3(w, low, -eave)]
		_quad(st, fascia_pts, _uvs(fascia_pts, wall_uv), Vector3(0.0, 0.0, -1.0), Color(ROOF_COLOUR * 0.6, 0.0))
		var soffit: Array = [Vector3(w, low, 0.0), Vector3(-w, low, 0.0), Vector3(-w, low, -eave), Vector3(w, low, -eave)]
		_quad(st, soffit, _uvs(soffit, wall_uv), Vector3(0.0, -1.0, 0.0), Color(SOFFIT_COLOUR, 0.0))
		for side: float in [1.0, -1.0]:  # gable ends
			for p: Vector3 in [Vector3(side * w, h, 0.0), Vector3(side * w, ridge, d / 2.0), Vector3(side * w, h, d)]:
				st.set_normal(Vector3(side, 0.0, 0.0))
				st.set_color(wall)
				st.set_uv(wall_uv.call(p))
				st.add_vertex(p)
	st.generate_tangents()
	return st.commit()


func _uvs(pts: Array, uv_of: Callable) -> Array:
	return pts.map(uv_of)


func _quad(st: SurfaceTool, p: Array, uv: Array, normal: Vector3, colour: Color) -> void:
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_color(colour)
		st.set_uv(uv[i])
		st.add_vertex(p[i])
