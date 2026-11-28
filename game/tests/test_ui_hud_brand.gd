extends "res://tests/test_case.gd"
## HUD brand pass: the race HUD and the touch layer draw only brand tokens (no cyan, violet or magenta), the speed and
## the position read in the display face, the phone touch targets keep their size, and the pursuit HUD builds with its
## banner in the right colour on desktop and phone.

const MOCK_RACE: String = "res://devtools/scenarios/ui_mock_race.gd"
const TOUCH_PATH: String = "res://vehicles/touch/touch_controls.tscn"
const PHONE_VP: Vector2 = Vector2(2532.0, 1170.0)
const DESKTOP_VP: Vector2 = Vector2(1920.0, 1080.0)

var _saved_language: String = "en"
var _saved_autosave: bool = true


func _begin(phone: bool) -> void:
	_saved_autosave = Settings.autosave
	_saved_language = Settings.language
	Settings.autosave = false
	Settings.set_language("en")
	MSTheme.set_phone(phone)


func _end() -> void:
	MSTheme.set_phone(false)
	Settings.set_language(_saved_language)
	Settings.autosave = _saved_autosave


## Colours a HUD text may use: the brand tokens only.
func _brand_colours() -> Array[Color]:
	return [MSTheme.PEARL, MSTheme.TITANIUM, MSTheme.STEEL, MSTheme.RED, MSTheme.DANGER, MSTheme.GO, MSTheme.GOLD]


func _is_brand(c: Color, palette: Array[Color]) -> bool:
	for p: Color in palette:
		if c.is_equal_approx(p):
			return true
	return false


func _check_hud_brand(hud: RaceHUD, label: String) -> void:
	var texts: Array = hud.get("_texts")
	var palette: Array[Color] = _brand_colours()
	check(texts.size() > 20, "%s: HUD builds its texts (%d)" % [label, texts.size()])
	for t: HudText in texts:
		check(_is_brand(t.color, palette), "%s: text %s uses a colour outside the brand palette %s" % [label, t.text, t.color])
	var speed: HudText = hud.get("_speed_label")
	check(speed.get("_font") == MSTheme.font("display"), "%s: speed is not in the display face" % label)
	var pos: HudText = hud.get("_pos_num")
	check(pos.get("_font") == MSTheme.font("display"), "%s: position is not in the display face" % label)


func test_race_hud_is_brand_on_desktop_and_phone() -> void:
	for phone: bool in [false, true]:
		_begin(phone)
		var race = load(MOCK_RACE).new()
		var car := ArcadeCar.new()
		race.rivals.append(car)
		var hud: RaceHUD = add(RaceHUD.new()) as RaceHUD
		await frames(2)
		hud.bind(car, race, null)
		car.speed_kmh = 187.4
		car.gear = 4
		car.rpm_norm = 0.92
		car.nitro_amount = 1.0
		car.nitro_active = true
		car.is_drifting = true
		car.drift_score = 1240.0
		car.drift_started.emit()
		await frames(3)
		_check_hud_brand(hud, "phone" if phone else "desktop")
		check(hud.get_readout().get("speed", "") == "187", "speed readout changed by the brand pass")
		check(hud.get_readout().get("drift_visible", false) == true, "drift popup not shown in the brand pass")
		await cleanup([hud, car])
		_end()


func test_minimap_and_gauges_use_brand_tokens() -> void:
	check(MiniMap.ARROW_COL.is_equal_approx(MSTheme.RED), "minimap player arrow is not racing red")
	check(MiniMap.RIVAL_COL.is_equal_approx(MSTheme.PEARL), "minimap rival dots are not pearl")
	check(SpeedGauge.REDLINE_COL.r > SpeedGauge.REDLINE_COL.b, "redline band is not red-shifted")
	check(SpeedGauge.TRACK_COL.is_equal_approx(MSTheme.GRAPHITE_3.lerp(MSTheme.TITANIUM, 0.18)), "speed track is not titanium over graphite")


func test_touch_targets_keep_phone_size_and_brand_pause() -> void:
	MSTheme.set_phone(true)
	var t: TouchControls = add((load(TOUCH_PATH) as PackedScene).instantiate()) as TouchControls
	t.force_visible = true
	t._layout(PHONE_VP)
	var pause: Rect2 = t.get_pause_rect()
	check(pause.size.x >= MSTheme.button_h() and pause.size.y >= MSTheme.button_h(),
		"pause button %s is smaller than the 44 pt target %s" % [pause.size, MSTheme.button_h()])
	for z: int in [TouchControls.Zone.NITRO, TouchControls.Zone.DRIFT]:
		var r: Rect2 = t.get_zone_rect(z)
		check(r.size.x >= MSTheme.button_h() and r.size.y >= MSTheme.button_h(),
			"touch zone %d %s is smaller than the 44 pt target" % [z, r.size])
	check(t.idle_color.is_equal_approx(MSTheme.tint(MSTheme.GRAPHITE_2, 0.42)), "touch idle colour is not graphite")
	check(t.pressed_color.is_equal_approx(MSTheme.tint(MSTheme.RED, 0.55)), "touch pressed colour is not racing red")
	MSTheme.set_phone(false)
	await cleanup([t])


func test_pursuit_hud_banner_colours_follow_the_outcome() -> void:
	var hud: PursuitHud = add(PursuitHud.new()) as PursuitHud
	await frames(1)
	hud.set_heat(3, 5)
	hud.set_goal("ESCAPE")
	hud.set_gauges(0.5, 0.25, PackedVector2Array([Vector2(2.0, 14.0)]))
	await frames(2)
	hud.set_banner(I18n.t("pursuit.busted"))
	var banner: Label = hud.get("_banner")
	check(banner.get_theme_color("font_color").is_equal_approx(MSTheme.DANGER), "BUSTED banner is not DANGER")
	hud.set_banner(I18n.t("pursuit.escaped") % 500)
	check(banner.get_theme_color("font_color").is_equal_approx(MSTheme.GO), "ESCAPED banner is not GO")
	check(banner.get_theme_font("font") == MSTheme.font("display"), "banner is not in the display face")
	await frames(2)
	await cleanup([hud])
