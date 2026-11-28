extends "res://tests/test_case.gd"
## Showroom look: the studio stage builds a mirror floor, a contact shadow, three-point lights and a gradient sky;
## the garage dresses its floor and turntable plate with the mirror material, adds the shadow and neon, and its
## glow threshold keeps lamp strips from clipping. GameState writes go to a temporary user:// save.

const GARAGE: String = "res://ui/garage/garage.tscn"
const TEMP_SAVE: String = "user://test_garage_look_save.json"


func test_studio_stage() -> void:
	var s := ShowroomSet.new()
	add(s)
	s.build_studio()
	await frames(3)
	check(s.floor_material != null and s.floor_material.shader != null, "floor uses the showroom shader")
	check(s.planar != null and s.planar.is_enabled(), "floor mirror is on")
	check(s.floor_material.get_shader_parameter("planar_enabled") == 1.0, "mirror texture reaches the floor material")
	check(s.contact_shadow != null and s.contact_shadow.get_child_count() == 5, "contact shadow: body plus four tyre blobs")
	check(s.lights.size() >= 5 and s.lights.size() <= 8, "three-point rig stays within the 8 lights a mesh can take (%d)" % s.lights.size())
	var shadowed: int = 0
	for l: Light3D in s.lights:
		if l.shadow_enabled:
			shadowed += 1
	check(shadowed == 1, "exactly one shadowed light (the soft key)")
	var env: Environment = ShowroomSet.make_environment()
	check(env.background_mode == Environment.BG_SKY, "gradient sky backdrop, not a flat void")
	check(env.glow_hdr_threshold >= 1.2, "glow only takes hot pixels")
	check(env.tonemap_mode == Environment.TONE_MAPPER_ACES, "ACES tonemap rolls highlights off")
	await cleanup([s])


func test_garage_dressed() -> void:
	var old_path: String = GameState.save_path
	var old_profile: Dictionary = GameState.profile.duplicate(true)
	GameState.open_profile(TEMP_SAVE)
	GameState.reset_profile()
	var g: Variant = add((load(GARAGE) as PackedScene).instantiate()) as Node3D
	await frames(3)
	var showroom: ShowroomSet = g.get_node_or_null("Showroom") as ShowroomSet
	check(showroom != null, "garage builds the showroom set")
	if showroom != null:
		check(showroom.contact_shadow != null and showroom.contact_shadow.get_parent() == g.get_node("Pivot"), "shadow follows the car's pivot")
		var floors: int = 0
		for n: Node in g.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi.material_override == showroom.floor_material:
				floors += 1
				check((mi.layers & ShowroomSet.MIRROR_LAYER_BIT) != 0, "mirrored floor is kept out of its own mirror")
		check(floors > 0, "floor or plate surface carries the mirror material (%d)" % floors)
		check(showroom.planar != null, "garage floor mirror exists")
	var we: WorldEnvironment = g.get_node("Environment") as WorldEnvironment
	check(we.environment.glow_hdr_threshold >= 1.2, "garage glow does not bloom lamp strips into flat sprites")
	g.queue_free()
	await frames(2)
	GameState.save_path = old_path
	GameState.profile = old_profile
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEMP_SAVE + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE + suffix))
