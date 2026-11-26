class_name PhotoFronts
extends StreetFronts
## Istanbul row houses with photo-textured fronts on the frontages StreetFronts fills: the same kit buildings are
## replaced (their collider and occluder stay), but each slot gets a plain house body whose street face carries one
## house of a straight-on facade picture (res://assets/world/kits/photo_fronts/, generated for this project, see
## ASSET_MANIFEST.json). A house costs about 20 triangles, so the row needs no LODs. At night the night picture of the
## same facade is the glow map.

const ATLAS_DIR: String = "res://assets/world/kits/photo_fronts/"
const ATLASES: PackedStringArray = ["facade_row_01", "facade_row_02"]  ## each: <name>.jpg and, when present, <name>_night.jpg
const HOUSES_PER_ATLAS: int = 4
const HOUSE_W_M: float = 5.4  ## one house of the picture is 384 x 1024 px
const HOUSE_H_M: float = 14.4
const HOUSE_DEPTH_M: float = 7.0
const ROOF_RISE_M: float = 1.7
const EAVE_M: float = 0.4  ## the roof comes this far out over the street face
const FACADE_SHADER: Shader = preload("res://world/street_fronts/photo_facade.gdshader")
const ROOF_COLOUR: Color = Color(0.2, 0.07, 0.045)  ## linear terracotta
## side wall colour per house, atlas after atlas (about the wall colour of that house in the picture)
const WALL_COLOURS: Array[Color] = [Color(0.36, 0.31, 0.25), Color(0.38, 0.25, 0.12), Color(0.2, 0.09, 0.07), Color(0.17, 0.19, 0.2),
		Color(0.5, 0.45, 0.37), Color(0.03, 0.09, 0.06), Color(0.6, 0.58, 0.53), Color(0.42, 0.17, 0.13)]  ## linear
const NIGHT_GLOW: float = 1.6
const SUNSET_GLOW: float = 0.7
const NIGHT_TINT: Vector3 = Vector3(0.55, 0.5, 0.5)  ## unlit walls keep a little of the street's warm light

var _facades: Array[ShaderMaterial] = []


func _load_library() -> void:
	_pool_mat = ShaderMaterial.new()
	_pool_mat.shader = POOL_SHADER
	_pool_mat.set_shader_parameter("tint", WARM)
	_pool_mat.set_shader_parameter("strength", POOL_STRENGTH)
	_pool_mat.set_shader_parameter("radius_m", POOL_RADIUS_M)
	var shell := StandardMaterial3D.new()
	shell.vertex_color_use_as_albedo = true
	shell.roughness = 0.9
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	for a: int in ATLASES.size():
		var facade := ShaderMaterial.new()
		facade.shader = FACADE_SHADER
		facade.set_shader_parameter("albedo_tex", load(ATLAS_DIR + ATLASES[a] + ".jpg"))
		var night_path: String = ATLAS_DIR + ATLASES[a] + "_night.jpg"
		if ResourceLoader.exists(night_path):
			facade.set_shader_parameter("night_tex", load(night_path))
		_facades.append(facade)
		for h: int in HOUSES_PER_ATLAS:
			var id: String = "house_%d_%d" % [a, h]
			_info[id] = {"width_m": HOUSE_W_M, "depth_m": HOUSE_DEPTH_M}
			_lods[id] = [_house_mesh(h, facade, shell, WALL_COLOURS[(a * HOUSES_PER_ATLAS + h) % WALL_COLOURS.size()])]


func _apply_time() -> void:
	super._apply_time()
	var glow: float = NIGHT_GLOW if _tod == "night" else (SUNSET_GLOW if _tod == "sunset" else 0.0)
	for facade: ShaderMaterial in _facades:
		facade.set_shader_parameter("night", glow)
		facade.set_shader_parameter("tint", NIGHT_TINT if _tod == "night" else Vector3.ONE)


## A row of houses sized to the frontage, picked from every atlas; seeded, so a frontage always gets the same row.
func _fill(width: float, seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[Dictionary] = []
	var n: int = maxi(1, roundi(width / HOUSE_W_M))
	var seg: float = width / float(n)
	var first: int = rng.randi() % (ATLASES.size() * HOUSES_PER_ATLAS)
	for i: int in n:
		var k: int = (first + i) % (ATLASES.size() * HOUSES_PER_ATLAS)  # neighbours never repeat
		out.append({"id": "house_%d_%d" % [k / HOUSES_PER_ATLAS, k % HOUSES_PER_ATLAS],
				"x": -width / 2.0 + seg * (float(i) + 0.5), "sx": seg / HOUSE_W_M})
	return out


## One house: the model's street face is -Z (as in StreetFronts), scaled in width and height together so the picture
## keeps its proportions.
func _place(root_xf: Transform3D, slot: Dictionary, parent: Node3D) -> void:
	var id: String = slot["id"]
	var sx: float = float(slot["sx"])
	var house := MeshInstance3D.new()
	house.name = "House_%03d" % _buildings.size()
	house.set_meta("asset", id)
	house.mesh = _lods[id][0]
	house.visibility_range_end = LOD1_END_M
	house.visibility_range_end_margin = FADE_M
	house.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(house)
	house.global_transform = root_xf * Transform3D(Basis(Vector3.UP, PI) * Basis.from_scale(Vector3(sx, sx, 1.0)),
			Vector3(float(slot["x"]), 0.0, 0.0))
	_buildings.append(house)
	_shop_fronts.append(house.global_transform)


## Surface 0: the street face with the picture of house `index`. Surface 1: side walls, back wall and a pitched roof in
## vertex colours.
func _house_mesh(index: int, facade: ShaderMaterial, shell: StandardMaterial3D, wall: Color) -> ArrayMesh:
	var w: float = HOUSE_W_M / 2.0
	var h: float = HOUSE_H_M
	var d: float = HOUSE_DEPTH_M
	var u0: float = float(index) / float(HOUSES_PER_ATLAS)
	var u1: float = float(index + 1) / float(HOUSES_PER_ATLAS)
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# seen from the street (looking along +Z) the model's +X is on the left: u0 goes there
	_quad(st, [Vector3(w, h, 0.0), Vector3(-w, h, 0.0), Vector3(-w, 0.0, 0.0), Vector3(w, 0.0, 0.0)],
			[Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0)], Vector3(0.0, 0.0, -1.0), Color.WHITE)
	st.set_material(facade)
	st.commit(mesh)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var no_uv: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	_quad(st, [Vector3(w, h, 0.0), Vector3(w, h, d), Vector3(w, 0.0, d), Vector3(w, 0.0, 0.0)], no_uv, Vector3(1.0, 0.0, 0.0), wall)
	_quad(st, [Vector3(-w, h, d), Vector3(-w, h, 0.0), Vector3(-w, 0.0, 0.0), Vector3(-w, 0.0, d)], no_uv, Vector3(-1.0, 0.0, 0.0), wall)
	_quad(st, [Vector3(-w, h, d), Vector3(w, h, d), Vector3(w, 0.0, d), Vector3(-w, 0.0, d)], no_uv, Vector3(0.0, 0.0, 1.0), wall)
	var ridge: float = h + ROOF_RISE_M
	var front_n: Vector3 = Vector3(0.0, d / 2.0 + EAVE_M, -ROOF_RISE_M).normalized()
	var back_n: Vector3 = Vector3(0.0, d / 2.0, ROOF_RISE_M).normalized()
	_quad(st, [Vector3(w, ridge, d / 2.0), Vector3(-w, ridge, d / 2.0), Vector3(-w, h, -EAVE_M), Vector3(w, h, -EAVE_M)], no_uv, front_n, ROOF_COLOUR)
	_quad(st, [Vector3(-w, ridge, d / 2.0), Vector3(w, ridge, d / 2.0), Vector3(w, h, d), Vector3(-w, h, d)], no_uv, back_n, ROOF_COLOUR)
	for side: float in [1.0, -1.0]:  # gable ends
		st.set_normal(Vector3(side, 0.0, 0.0))
		st.set_color(wall)
		for p: Vector3 in [Vector3(side * w, h, 0.0), Vector3(side * w, ridge, d / 2.0), Vector3(side * w, h, d)]:
			st.set_uv(Vector2.ZERO)
			st.add_vertex(p)
	st.set_material(shell)
	st.commit(mesh)
	return mesh


func _quad(st: SurfaceTool, p: Array, uv: Array, normal: Vector3, colour: Color) -> void:
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_color(colour)
		st.set_uv(uv[i])
		st.add_vertex(p[i])
