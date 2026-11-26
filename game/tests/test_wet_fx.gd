extends "res://tests/test_case.gd"
## Wet-night car FX: WheelSpray (tyre spray), Underglow (coloured pool and player light), RainOnLens (drops on the lens).

const SHADERS: PackedStringArray = [
	"res://shaders/wheel_spray.gdshader",
	"res://shaders/rain_on_lens.gdshader",
	"res://shaders/glow_pool.gdshader",
]


func test_shaders_load() -> void:
	for path: String in SHADERS:
		check(load(path) is Shader, "shader %s does not load" % path)


func test_spray_activity_needs_speed_wet_road_and_grip() -> void:
	check(WheelSpray.activity_for(30.0, 1.0, 1.0) == 0.0, "spray below 40 km/h")
	check(WheelSpray.activity_for(90.0, 0.0, 1.0) == 0.0, "spray on a dry road")
	check(WheelSpray.activity_for(90.0, 1.0, 0.0) == 0.0, "spray with no rear wheel on the ground")
	var mid: float = WheelSpray.activity_for(90.0, 1.0, 1.0)
	check(mid > 0.0 and mid < 1.0, "spray at 90 km/h is %.3f, expected partial" % mid)
	check(WheelSpray.activity_for(200.0, 1.0, 1.0) == 1.0, "spray does not reach full at 200 km/h")
	check(WheelSpray.activity_for(180.0, 1.0, 1.0) > mid, "spray does not grow with speed")


func test_spray_has_two_emitters_and_follows_particle_scale() -> void:
	var ws := WheelSpray.new()
	add(ws)
	await frames(1)
	var emitters: Array = ws.find_children("*", "GPUParticles3D", false, false)
	check(emitters.size() == 2, "spray has %d emitters, budget is 2 draw calls per car" % emitters.size())
	var scale_f: float = Settings.get_preset().particle_amount_scale
	check(ws._mist.amount == maxi(1, int(round(WheelSpray.MIST_AMOUNT * scale_f))), "mist amount %d ignores particle_amount_scale" % ws._mist.amount)
	check(ws._streaks.amount == maxi(1, int(round(WheelSpray.STREAK_AMOUNT * scale_f))), "streak amount %d ignores particle_amount_scale" % ws._streaks.amount)
	await cleanup([ws])


func test_spray_only_nearest_cars_emit() -> void:
	var player := Node3D.new()
	add(player)
	var cars: Array = [player]
	for i: int in 4:
		var c := Node3D.new()
		add(c)
		c.global_position = Vector3(10.0 * (i + 1), 0.0, 0.0)
		cars.append(c)
	for c: Variant in cars:
		var ws := WheelSpray.new()
		ws.name = WheelSpray.NODE_NAME
		(c as Node3D).add_child(ws)
	await frames(1)
	WheelSpray.update_nearest(cars, player, 2)
	var active: int = 0
	for c: Variant in cars:
		var ws: WheelSpray = (c as Node).get_node(WheelSpray.NODE_NAME) as WheelSpray
		if ws.is_active():
			active += 1
	check(active == 3, "%d cars spraying, expected the player plus 2 rivals" % active)
	var near: WheelSpray = cars[1].get_node(WheelSpray.NODE_NAME) as WheelSpray
	var far: WheelSpray = cars[4].get_node(WheelSpray.NODE_NAME) as WheelSpray
	check(near.is_active() and not far.is_active(), "the nearest rival is not the one spraying")
	var nodes: Array[Node] = []
	for c: Variant in cars:
		nodes.append(c as Node)
	await cleanup(nodes)


func test_underglow_only_at_night_and_sunset() -> void:
	var ug := Underglow.new()
	ug.player_light = true
	add(ug)
	await frames(1)
	ug.apply_time_of_day("day")
	check(not ug.is_showing(), "underglow shows by day")
	ug.apply_time_of_day("sunset")
	check(ug.is_showing(), "underglow hidden at sunset")
	ug.apply_time_of_day("night")
	check(ug.is_showing(), "underglow hidden at night")
	check(ug._light.visible, "player light off at night")
	ug.player_light = false
	check(not ug._light.visible, "rival underglow still lights the scene")
	await cleanup([ug])


func test_underglow_colour_is_violet_by_default() -> void:
	var ug := Underglow.new()
	add(ug)
	await frames(1)
	check(ug.color.r > ug.color.g and ug.color.b > ug.color.g, "default underglow colour %s is not violet-magenta" % str(ug.color))
	ug.color = Color(0.1, 0.9, 0.3)
	check(ug._light.light_color.is_equal_approx(Color(0.1, 0.9, 0.3)), "underglow colour change does not reach the light")
	await cleanup([ug])


func test_rain_on_lens_follows_rain_and_preset() -> void:
	var rol := RainOnLens.new()
	add(rol)
	await frames(1)
	rol.set_strength(0.0)
	await frames(30)
	check(rol.level() < 0.001, "lens drops visible with no rain")
	check(not rol._rect.visible, "lens layer drawn with no rain (screen copy every frame)")
	rol.set_strength(1.0)
	await frames(60)
	var preset_id: String = Settings.get_preset_id()
	if preset_id == "low":
		check(rol.level() < 0.001, "lens drops on the Low preset")
	else:
		check(rol.level() > 0.5, "lens drops did not fade in during rain (level %.2f)" % rol.level())
	check(rol.is_allowed() == (Settings.get_preset().rain_enabled and preset_id != "low"), "lens allowed flag ignores the preset")
	check(rol.layer == RainOnLens.LAYER and RainOnLens.LAYER < 10, "lens layer %d must sit under the HUD (10)" % rol.layer)
	await cleanup([rol])
