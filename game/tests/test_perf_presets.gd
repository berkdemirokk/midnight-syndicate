extends "res://tests/test_case.gd"
## Mobile GPU pass: per-preset shadow filter, post AA and reflection probes, and the night mirror viewport diet.
## Settings is created with its own user:// file, never the real settings.cfg.

const SETTINGS: GDScript = preload("res://core/settings.gd")
const PLANAR: GDScript = preload("res://fx/planar_reflection.gd")


func test_preset_shadow_filter_aa_and_probes() -> void:
	var low: GraphicsPreset = GraphicsPreset.build("low")
	var med: GraphicsPreset = GraphicsPreset.build("medium")
	var high: GraphicsPreset = GraphicsPreset.build("high")
	check(low.shadow_filter == RenderingServer.SHADOW_QUALITY_HARD, "low: hard directional shadow")
	check(med.shadow_filter == RenderingServer.SHADOW_QUALITY_SOFT_LOW, "medium: engine default soft shadow (unchanged)")
	check(high.shadow_filter == RenderingServer.SHADOW_QUALITY_SOFT_LOW, "high: low soft shadow")
	check(low.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "low: no post AA")
	check(med.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "medium: no post AA (FXAA unmeasured)")
	check(high.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "high: MSAA only, no post AA")
	check(high.msaa_3d == Viewport.MSAA_2X, "high MSAA unchanged at 2X")
	check(not low.reflection_probes_enabled, "low: reflection probes off")
	check(med.reflection_probes_enabled and high.reflection_probes_enabled, "medium and high keep probes")
	check(is_equal_approx(low.scale_on(false), 1.0), "phone scale still waits for the device (1.0)")


func test_settings_apply_post_aa_to_viewport() -> void:
	var s: Node = SETTINGS.new()
	s.config_path = "user://test_perf_presets.cfg"
	var sv := SubViewport.new()
	add(sv)
	for id: String in ["low", "medium", "high"]:
		check(s.set_preset(id), "set_preset(%s)" % id)
		s.apply_to_viewport(sv)
		check(sv.screen_space_aa == GraphicsPreset.build(id).screen_space_aa, "%s viewport post AA" % id)
	await cleanup([sv])
	s.free()


func test_mirror_viewport_is_slim() -> void:
	var pr: Node = PLANAR.new()
	add(pr)
	await frames(2)
	var vp: SubViewport = pr.get("_vp") as SubViewport
	check(vp != null, "mirror has a SubViewport")
	if vp != null:
		check(vp.positional_shadow_atlas_size == 0, "mirror shadow atlas off")
		check(vp.msaa_3d == Viewport.MSAA_DISABLED, "mirror MSAA off")
	await cleanup([pr])


func test_mirror_environment_no_glow_linear_tonemap() -> void:
	var world := World3D.new()
	world.environment = Environment.new()
	world.environment.glow_enabled = true
	world.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	var host := SubViewport.new()
	host.world_3d = world
	add(host)
	var pr: Node = PLANAR.new()
	host.add_child(pr)
	await frames(1)
	pr.call("_make_far_environment")
	var cam: Camera3D = pr.get("_cam") as Camera3D
	check(cam != null and cam.environment != null, "mirror camera has an environment")
	if cam != null and cam.environment != null:
		check(not cam.environment.glow_enabled, "mirror environment has no glow")
		check(cam.environment.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "mirror tonemap linear")
		check(is_equal_approx(cam.environment.tonemap_exposure, 1.0), "mirror exposure 1.0")
	check(world.environment.tonemap_mode == Environment.TONE_MAPPER_ACES, "main environment untouched")
	await cleanup([host])
