extends "res://tests/test_case.gd"
## Garage: scene instantiates, paint swatch changes the car and the saved setup, upgrades spend cash only when
## affordable, orbit input stays inside its limits, preset buttons reach their poses, strings exist in both languages.
## GameState writes go to a temporary user:// save; the real profile is restored in memory afterwards.

const GARAGE: String = "res://ui/garage/garage.tscn"
const LAYOUT: String = "res://assets/world/garage/garage_layout.json"
const TEMP_SAVE: String = "user://test_garage_save.json"
const SETTLE: int = 70  ## physics frames: preset transitions take 0.9 s at 60 Hz
const SWATCH_INDEX: int = 1  ## deep blue in the curated list


func _open_temp_profile() -> Dictionary:
	var old: Dictionary = {"path": GameState.save_path, "profile": GameState.profile.duplicate(true), "lang": Settings.language}
	GameState.open_profile(TEMP_SAVE)
	GameState.reset_profile()
	GameState.profile["cash"] = 5000
	return old


func _restore(old: Dictionary) -> void:
	GameState.save_path = str(old["path"])
	GameState.profile = old["profile"]
	Settings.language = str(old["lang"])
	var abs_path: String = ProjectSettings.globalize_path(TEMP_SAVE)
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(TEMP_SAVE + suffix):
			DirAccess.remove_absolute(abs_path + suffix)


func _spawn_garage() -> Variant:
	var packed: PackedScene = load(GARAGE) as PackedScene
	return add(packed.instantiate()) as Node3D


func _mat_named(root: Node, nm: String) -> StandardMaterial3D:
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var m: StandardMaterial3D = mi.get_active_material(s) as StandardMaterial3D
			if m != null and m.resource_name == nm:
				return m
	return null


func test_scene_instantiates() -> void:
	var old: Dictionary = _open_temp_profile()
	var g: Variant = _spawn_garage()
	await frames(3)
	check(g.get("car") != null, "garage spawns the car")
	check(g.get_hud() != null, "garage builds the HUD")
	check(g.get_probe() != null and g.get_probe().box_projection, "room has a box-projected reflection probe")
	var lights: Node3D = g.get_node("Lights") as Node3D
	var omni_spot: int = 0
	var directional: int = 0
	for n: Node in lights.get_children():
		if n is OmniLight3D or n is SpotLight3D:
			omni_spot += 1
		elif n is DirectionalLight3D:
			directional += 1
	check(omni_spot <= 8, "at most 8 omni and spot lights, got %d" % omni_spot)
	var shadowed: int = 0
	for n: Node in lights.get_children():
		if n is DirectionalLight3D and (n as DirectionalLight3D).shadow_enabled:
			shadowed += 1
	check(directional == 2 and shadowed == 1, "one shadowed key and one shadowless fill, got %d lights, %d shadowed" % [directional, shadowed])
	check(_mat_named(g.get_node("Room"), "M_Light_Emit") != null, "room fixtures are bound by material name")
	metric("omni_spot_lights", omni_spot)
	await cleanup([g])
	_restore(old)


## The paint mirrors the workshop panorama (a second pass on M_Paint), on every car put on the turntable, and not on
## the Low preset.
func test_paint_mirrors_the_workshop_except_on_low() -> void:
	var old: Dictionary = _open_temp_profile()
	var prev: String = Settings.get_preset_id()
	Settings.set_preset("high")
	var g: Variant = _spawn_garage()
	await frames(3)
	var paint: StandardMaterial3D = _mat_named(g.get("car"), "M_Paint")
	check(paint != null and paint.next_pass is ShaderMaterial, "no reflection pass on the paint on High")
	if paint != null and paint.next_pass is ShaderMaterial:
		check((paint.next_pass as ShaderMaterial).get_shader_parameter("pano") is Texture2D, "reflection pass has no picture")
	var ids: Array[String] = CarCatalog.available_ids()
	g.show_car(ids[ids.size() - 1])  # another car through the same path as the arrows
	await frames(2)
	paint = _mat_named(g.get("car"), "M_Paint")
	check(paint != null and paint.next_pass is ShaderMaterial, "no reflection pass after switching car")
	Settings.set_preset("low")
	g.show_car(ids[0])
	await frames(2)
	paint = _mat_named(g.get("car"), "M_Paint")
	check(paint != null and paint.next_pass == null, "reflection pass on the Low preset")
	Settings.set_preset(prev)
	await cleanup([g])
	_restore(old)


func test_swatch_changes_paint_and_saved_setup() -> void:
	var old: Dictionary = _open_temp_profile()
	var g: Variant = _spawn_garage()
	await frames(2)
	var swatches: Array[Button] = g.get_hud().get_swatch_buttons()
	check(swatches.size() == 12, "12 curated paint swatches, got %d" % swatches.size())
	var target_paint: Color = Color("0A1A5C")
	swatches[SWATCH_INDEX].pressed.emit()
	await frames(2)
	var mat: StandardMaterial3D = _mat_named(g.car, "M_Paint")
	check(mat != null, "car has an M_Paint material")
	if mat != null:
		check(mat.albedo_color.to_html(false) == target_paint.to_html(false), "car paint became the swatch colour")
	var saved: String = str(GameState.get_setup(g.car_id)["paint_color"])
	check(saved == target_paint.to_html(false), "GameState saved the paint, got %s" % saved)
	check(FileAccess.file_exists(TEMP_SAVE), "the temporary save file was written")
	await cleanup([g])
	_restore(old)


func test_upgrade_buys_when_affordable_only() -> void:
	var old: Dictionary = _open_temp_profile()
	var g: Variant = _spawn_garage()
	await frames(2)
	var car_id: String = g.car_id
	var cost: int = GameState.upgrade_cost("engine", 0)
	var before_cash: int = GameState.get_cash()
	check(g.buy_upgrade("engine"), "engine upgrade succeeds with enough cash")
	check(GameState.get_upgrade_level(car_id, "engine") == 1, "engine level rises to 1")
	check(GameState.get_cash() == before_cash - cost, "cash falls by the upgrade cost")

	GameState.profile["cash"] = 100
	var level_before: int = GameState.get_upgrade_level(car_id, "nitro")
	check(not g.buy_upgrade("nitro"), "nitro upgrade refused with too little cash")
	check(GameState.get_upgrade_level(car_id, "nitro") == level_before, "refused upgrade leaves the level alone")
	check(GameState.get_cash() == 100, "refused upgrade leaves the cash alone")
	check(g.get_hud().get_message() == I18n.t("garage.not_enough"), "refused upgrade shows the cash message")
	await cleanup([g])
	_restore(old)


func test_orbit_stays_inside_limits() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var orbit := GarageOrbit.new()
	orbit.configure(layout)
	for i: int in 400:
		orbit.drag(Vector2(900.0 * (1 if i % 2 == 0 else -1), 700.0))
		orbit.step(1.0 / 60.0)
	check(orbit.pitch >= orbit.min_pitch - 0.001 and orbit.pitch <= orbit.max_pitch + 0.001, "pitch stays in limits, got %.2f" % orbit.pitch)
	for i: int in 200:
		orbit.zoom(0.5)
		orbit.step(1.0 / 60.0)
	check(absf(orbit.dist - orbit.min_dist) < 0.001, "zoom in stops at min distance, got %.3f" % orbit.dist)
	for i: int in 200:
		orbit.zoom(2.0)
		orbit.step(1.0 / 60.0)
	check(absf(orbit.dist - orbit.max_dist) < 0.001, "zoom out stops at max distance, got %.3f" % orbit.dist)
	var cam_dist: float = orbit.camera_position().distance_to(orbit.target)
	check(absf(cam_dist - orbit.dist) < 0.01, "camera sits at the orbit distance")
	orbit.set_pose(0.0, 500.0, 0.0)
	check(orbit.pitch <= orbit.max_pitch and orbit.dist >= orbit.min_dist, "set_pose clamps")
	metric("orbit_pitch_limits", [orbit.min_pitch, orbit.max_pitch])
	metric("orbit_dist_limits", [orbit.min_dist, orbit.max_dist])


func test_preset_views_reach_targets() -> void:
	var old: Dictionary = _open_temp_profile()
	var g: Variant = _spawn_garage()
	await frames(2)
	for view: String in GarageOrbit.PRESETS.keys():
		g.get_hud().get_view_button(view).pressed.emit()
		await frames(SETTLE)
		var want: Dictionary = g.orbit.preset_pose(view)
		check(absf(g.orbit.yaw - float(want["yaw"])) < 0.002, "%s yaw reaches target" % view)
		check(absf(g.orbit.pitch - float(want["pitch"])) < 0.01, "%s pitch reaches target" % view)
		check(absf(g.orbit.dist - float(want["dist"])) < 0.01, "%s distance reaches target" % view)
		check(not g.orbit.is_preset_moving(), "%s transition has finished" % view)
	await cleanup([g])
	_restore(old)


func test_strings_exist_in_both_languages() -> void:
	var old: Dictionary = _open_temp_profile()
	var garage_keys: Array = []
	for key: Variant in I18n.all_keys():
		if str(key).begins_with("garage."):
			garage_keys.append(key)
			var entry: Dictionary = I18n.DICT[key]
			check(entry.has("tr") and not str(entry["tr"]).is_empty(), "%s has Turkish text" % key)
			check(entry.has("en") and not str(entry["en"]).is_empty(), "%s has English text" % key)
	check(garage_keys.size() >= 30, "garage strings defined, got %d" % garage_keys.size())
	var g: Variant = _spawn_garage()
	await frames(2)
	for lang: String in ["tr", "en"]:
		Settings.language = lang
		g.get_hud().apply_language()
		var bad: Array[String] = []
		for n: Node in g.get_hud().find_children("*", "", true, false):
			var text: String = ""
			if n is Label:
				text = (n as Label).text
			elif n is Button:
				text = (n as Button).text
			if text.begins_with("garage.") or text.begins_with("menu.") or text.begins_with("common."):
				bad.append(text)
		check(bad.is_empty(), "%s HUD shows raw keys: %s" % [lang, str(bad)])
	await cleanup([g])
	_restore(old)


func test_stats_grow_with_upgrades() -> void:
	var spec: CarSpec = load("res://vehicles/specs/noctra_sable.tres") as CarSpec
	var base: Dictionary = GarageStats.compute(spec, {"engine": 0, "tires": 0, "nitro": 0, "weight": 0})
	var up: Dictionary = GarageStats.compute(spec, {"engine": 5, "tires": 5, "nitro": 5, "weight": 5})
	for s: String in ["speed", "accel", "handling", "nitro"]:
		check(float(up[s]) > float(base[s]) or float(up[s]) >= 1.0, "%s rises with upgrades" % s)
		check(float(base[s]) >= 0.0 and float(base[s]) <= 1.0 and float(up[s]) <= 1.0, "%s stays in 0..1" % s)
	metric("stats_base", base)
	metric("stats_max", up)
