extends "res://tests/test_case.gd"
## Greenery: tree kit budgets and surfaces, shader contract, placement off the road and the species mix by track.

const TRACKS: Dictionary = {
	"city": "res://world/city_01/city_01.tscn",
	"maslak": "res://world/istanbul_maslak/istanbul_maslak.tscn",
	"bogaz": "res://world/istanbul_bogaz/istanbul_bogaz.tscn",
}
const DIR: String = "res://assets/world/kits/trees/"
const SPECIES: PackedStringArray = ["plane", "judas", "cypress", "street"]
const LOD0_MAX_TRIS: int = 3500
const LOD1_MAX_TRIS: int = 900


func _tris(mesh: Mesh) -> int:
	var total: int = 0
	for i: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += (idx.size() if not idx.is_empty() else verts.size()) / 3
	return total


func test_assets_budget_and_surfaces() -> void:
	for sp: String in SPECIES:
		for lod: int in 3:
			var path: String = DIR + "tree_%s_lod%d.glb" % [sp, lod]
			check(ResourceLoader.exists(path), "missing GLB " + path)
			var mesh: Mesh = Greenery._lod_mesh(sp, lod)
			check(mesh != null, "no mesh for %s lod%d" % [sp, lod])
			if mesh == null:
				continue
			var tris: int = _tris(mesh)
			metric("tris_%s_lod%d" % [sp, lod], tris)
			if lod == 0:
				check(tris <= LOD0_MAX_TRIS, "%s LOD0 %d tris > %d" % [sp, tris, LOD0_MAX_TRIS])
			elif lod == 1:
				check(tris <= LOD1_MAX_TRIS, "%s LOD1 %d tris > %d" % [sp, tris, LOD1_MAX_TRIS])
			else:
				check(tris == 4, "%s LOD2 should be 2 cards (4 tris), got %d" % [sp, tris])
			var want_surfaces: int = 1 if lod == 2 else 2
			check(mesh.get_surface_count() == want_surfaces, "%s lod%d surfaces %d, want %d" % [sp, lod, mesh.get_surface_count(), want_surfaces])
			check(mesh.surface_get_material(want_surfaces - 1) is ShaderMaterial, "%s lod%d leaf surface is not the foliage shader" % [sp, lod])
	check(ResourceLoader.exists(DIR + "leaf_atlas.png"), "leaf atlas missing")


func test_foliage_shader_contract() -> void:
	var src: String = FileAccess.get_file_as_string("res://shaders/foliage.gdshader")
	check("render_mode cull_disabled" in src, "foliage must be two-sided")
	check("discard" in src and "alpha_cut" in src, "foliage must alpha-test (scissor), not blend")
	check("TIME" in src and "MODEL_MATRIX" in src, "sway must use TIME and world position")
	check("COLOR.rgb" in src, "vertex colour AO not used")
	check("translucency" in src and "void light()" in src, "backlit translucency missing")
	check("blend_mix" not in src and "ALPHA =" not in src, "foliage must not use alpha blending")


func _populate(key: String) -> Array:
	var track: Track = (load(TRACKS[key]) as PackedScene).instantiate() as Track
	add(track)
	await frames(2)
	var g := Greenery.new()
	track.add_child(g)
	g.setup(track)
	await frames(3)
	return [track, g]


func test_city_trees_off_road_and_city_mix() -> void:
	var pair: Array = await _populate("city")
	var track: Track = pair[0]
	var g: Greenery = pair[1]
	check(g.placed_count() >= 40, "city: only %d trees placed" % g.placed_count())
	var min_lat: float = INF
	for p: Dictionary in g.placements:
		var lat: float = absf(float(p.lateral))
		min_lat = minf(min_lat, lat)
		check(lat > track.width * 0.5 + 1.0, "tree inside the road corridor at %s" % str(p.pos))
		check(p.species == "street", "city track must use planter trees only, got %s" % p.species)
	metric("city_trees", g.placed_count())
	metric("city_min_lateral_m", snappedf(min_lat, 0.01))
	var lods: int = 0
	for n: Node in g.get_children():
		if n is MultiMeshInstance3D:
			lods += 1
			var mmi: MultiMeshInstance3D = n
			check(mmi.visibility_range_end > mmi.visibility_range_begin, "%s has no visibility range" % mmi.name)
			check(mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts a shadow" % mmi.name)
	check(lods >= 4, "expected LOD and blob nodes, got %d" % lods)
	metric("city_multimesh_nodes", lods)
	var nodes: Array[Node] = [track]
	cleanup(nodes)
	await frames(2)


func test_species_mix_follows_track() -> void:
	var bogaz: Array = await _populate("bogaz")
	for p: Dictionary in (bogaz[1] as Greenery).placements:
		check(["judas", "cypress", "plane"].has(p.species), "bogaz tree %s not in its mix" % p.species)
	metric("bogaz_species", (bogaz[1] as Greenery).species_counts())
	var nodes_b: Array[Node] = [bogaz[0]]
	cleanup(nodes_b)
	await frames(2)
	var maslak: Array = await _populate("maslak")
	for p: Dictionary in (maslak[1] as Greenery).placements:
		check(["street", "plane"].has(p.species), "maslak tree %s not in its mix" % p.species)
	metric("maslak_species", (maslak[1] as Greenery).species_counts())
	var nodes_m: Array[Node] = [maslak[0]]
	cleanup(nodes_m)
	await frames(2)
