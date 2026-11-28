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
	for sp: String in SPECIES:
		check(ResourceLoader.exists(DIR + "leaf_%s.png" % sp), "leaf texture missing for " + sp)
		check(ResourceLoader.exists(DIR + "bark_%s.png" % sp), "bark texture missing for " + sp)
		check(ResourceLoader.exists(DIR + "impostor_%s.png" % sp), "impostor missing for " + sp)


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
			check(mmi.visibility_range_end_margin > 0.0, "%s has a hard end, no fade band" % mmi.name)
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
	var bc: Dictionary = (bogaz[1] as Greenery).species_counts()
	metric("bogaz_species", bc)
	metric("bogaz_rejected", (bogaz[1] as Greenery).rejected)
	# The weights are picked per spot; crown rejections thin planes, so judas (the heaviest weight) must still lead.
	check(int(bc.get("judas", 0)) >= int(bc.get("cypress", 0)) and int(bc.get("judas", 0)) >= int(bc.get("plane", 0)), "bogaz: judas must lead the mix, got %s" % str(bc))
	var nodes_b: Array[Node] = [bogaz[0]]
	cleanup(nodes_b)
	await frames(2)
	var maslak: Array = await _populate("maslak")
	for p: Dictionary in (maslak[1] as Greenery).placements:
		check(["street", "plane"].has(p.species), "maslak tree %s not in its mix" % p.species)
	var mc: Dictionary = (maslak[1] as Greenery).species_counts()
	metric("maslak_species", mc)
	metric("maslak_rejected", (maslak[1] as Greenery).rejected)
	check(int(mc.get("street", 0)) > int(mc.get("plane", 0)), "maslak: street must lead the mix, got %s" % str(mc))
	var nodes_m: Array[Node] = [maslak[0]]
	cleanup(nodes_m)
	await frames(2)


func test_photo_cards_contract() -> void:
	var src: String = FileAccess.get_file_as_string("res://shaders/tree_photo.gdshader")
	check("render_mode cull_disabled" in src, "photo cards must be two-sided")
	check("discard" in src and "alpha_cut" in src, "photo cards must alpha-test (scissor), not blend")
	check("TIME" in src and "MODEL_MATRIX" in src, "photo sway must use TIME and world position")
	check("night_tex" in src and "shade_fill" in src, "night glow must follow the time-of-day value")
	check("blend_mix" not in src and "ALPHA =" not in src, "photo cards must not use alpha blending")
	# Heights from the brief: plane 10 to 13 m, cypress 9 to 12 m, judas 5 to 6 m (judas at 0.9 to 1.1 scale is 4.95 to 6.05).
	var bands: Dictionary = {"plane": [10.0, 13.0], "cypress": [9.0, 12.0], "judas": [4.9, 6.1]}
	for sp: String in Greenery.PHOTO:
		var cfg: Dictionary = Greenery.PHOTO[sp]
		check(ResourceLoader.exists(Greenery.PHOTO_DIR + cfg.tex), "photo texture missing for " + sp)
		if cfg.night != "":
			check(ResourceLoader.exists(Greenery.PHOTO_DIR + cfg.night), "night texture missing for " + sp)
		var mesh: Mesh = Greenery._photo_mesh(sp)
		check(mesh != null, "no photo mesh for " + sp)
		if mesh == null:
			continue
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]  # cards are not indexed
		var tris: int = verts.size() / 3
		metric("photo_tris_%s" % sp, tris)
		check(tris == 6, "%s: three crossed cards should be 6 triangles, got %d" % [sp, tris])
		check(mesh.surface_get_material(0) is ShaderMaterial, "%s photo surface is not the photo shader" % sp)
		var lo: float = float(cfg.h_m) * Greenery.SPECIES[sp].scale.x
		var hi: float = float(cfg.h_m) * Greenery.SPECIES[sp].scale.y
		check(lo >= float(bands[sp][0]) and hi <= float(bands[sp][1]), "%s height %.2f-%.2f m outside %s" % [sp, lo, hi, str(bands[sp])])


func test_photo_trees_in_bogaz() -> void:
	var pair: Array = await _populate("bogaz")
	var track: Track = pair[0]
	var g: Greenery = pair[1]
	var photo_nodes: int = 0
	for n: Node in g.get_children():
		if n is MultiMeshInstance3D and String(n.name).ends_with("_photo"):
			photo_nodes += 1
			var mmi: MultiMeshInstance3D = n
			check(mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s must cast shadows" % mmi.name)
			check(mmi.multimesh.use_custom_data, "%s has no atlas custom data" % mmi.name)
	metric("bogaz_photo_nodes", photo_nodes)
	var planes: int = 0
	for p: Dictionary in g.placements:
		check(int(p.variant) == 0 or int(p.variant) == 1, "bad atlas variant for a tree")
		if p.species == "plane":
			planes += 1
			# The crown (photo reach 5 m) may overhang the pavement, never the corridor.
			check(absf(float(p.lateral)) - float(Greenery.CROWN_CORRIDOR_M["plane"]) > track.width * 0.5, "plane crown reaches the race corridor at %s" % str(p.pos))
	metric("bogaz_planes", planes)
	var nodes: Array[Node] = [track]
	cleanup(nodes)
	await frames(2)
