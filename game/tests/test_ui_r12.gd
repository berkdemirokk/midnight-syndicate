extends "res://tests/test_case.gd"
## Premium UI pass (round 12): phone sizing, touch targets, live backdrop, wordmark, event-select window,
## results star pop, settings UI bus slider, HUD frame scale.

const MAIN_MENU: String = "res://ui/menus/main_menu.tscn"
const SETTINGS: String = "res://ui/menus/settings_menu.tscn"
const PAUSE: String = "res://ui/menus/pause_menu.tscn"
const EVENTS: String = "res://ui/menus/event_select.tscn"
const RESULTS: String = "res://ui/menus/results_screen.tscn"
const MOCK_RACE: String = "res://devtools/scenarios/ui_mock_race.gd"
const PHONE_TARGET_PX: float = 124.0  ## 44 pt on a 393 pt tall iPhone at the 1080 px base height
const POP_FRAMES: int = 150

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


func _buttons(node: Node, out: Array[Button]) -> void:
	if node is Button and (node as Button).is_visible_in_tree():
		out.append(node as Button)
	for c: Node in node.get_children():
		_buttons(c, out)


func test_phone_theme_scales_type_and_targets() -> void:
	_begin(false)
	var base_h: float = MSTheme.button_h()
	var base_px: int = MSTheme.px(24.0)
	var base_theme: Theme = MSTheme.build()
	var base_size: int = base_theme.default_font_size
	MSTheme.set_phone(true)
	var phone_theme: Theme = MSTheme.build()
	check(MSTheme.button_h() >= PHONE_TARGET_PX, "phone button height %s is under 44 pt" % MSTheme.button_h())
	check(base_h == MSTheme.BUTTON_MIN_H, "desktop button height changed to %s" % base_h)
	check(MSTheme.px(24.0) > base_px, "phone type does not grow")
	check(phone_theme.default_font_size > base_size, "phone theme font size did not grow (%d vs %d)" % [phone_theme.default_font_size, base_size])
	check(phone_theme != base_theme, "theme was not rebuilt for the phone")
	metric("phone_button_px", MSTheme.button_h())
	metric("phone_body_px", phone_theme.default_font_size)
	_end()


func test_main_menu_live_backdrop_wordmark_and_primary() -> void:
	_begin(false)
	var menu: Node = add(load(MAIN_MENU).instantiate())
	await frames(3)
	var back: Node = menu.find_child("Backdrop", false, false)
	check(back is MenuBackdrop, "live backdrop missing")
	if back is ColorRect:
		check((back as ColorRect).material is ShaderMaterial, "backdrop has no shader")
	check(menu.find_child("Logo", true, false) is Logotype, "wordmark missing")
	var race_btn: Button = menu.get("_race_btn")
	check(race_btn.theme_type_variation == &"PrimaryButton", "RACE is not the primary button")
	check(tree.root.gui_get_focus_owner() == race_btn, "RACE does not hold focus")
	# 3D backdrop swap hides the live one and restores it.
	menu.call("set_backdrop", Node3D.new())
	check(not (back as ColorRect).visible, "live backdrop still visible over a 3D backdrop")
	menu.call("set_backdrop", null)
	check((back as ColorRect).visible, "live backdrop not restored")
	await cleanup([menu])
	_end()


func test_every_menu_button_is_a_44pt_target_on_phone() -> void:
	_begin(true)
	var roots: Array[Node] = []
	for path: String in [MAIN_MENU, SETTINGS, PAUSE, EVENTS, RESULTS]:
		var n: Node = add(load(path).instantiate())
		roots.append(n)
	(roots[2] as PauseMenu).pause()
	await frames(4)
	var checked: int = 0
	for r: Node in roots:
		var list: Array[Button] = []
		_buttons(r, list)
		for b: Button in list:
			if b is OptionButton:
				continue
			checked += 1
			check(b.size.y >= PHONE_TARGET_PX - 1.0, "%s button '%s' is %.0f px tall, needs %.0f" % [r.name, b.text, b.size.y, PHONE_TARGET_PX])
	metric("phone_buttons_checked", checked)
	check(checked >= 15, "only %d buttons checked" % checked)
	(roots[2] as PauseMenu).resume()
	await cleanup(roots)
	_end()


func test_every_menu_takes_focus() -> void:
	_begin(false)
	for path: String in [MAIN_MENU, SETTINGS, PAUSE, EVENTS, RESULTS]:
		var n: Node = add(load(path).instantiate())
		if n is PauseMenu:
			(n as PauseMenu).pause()
		await frames(3)
		var f: Control = tree.root.gui_get_focus_owner()
		check(f != null and n.is_ancestor_of(f), "%s: no focused control after open" % path)
		if n is PauseMenu:
			(n as PauseMenu).resume()
		await cleanup([n])
	_end()


func test_event_select_phone_window_follows_selection() -> void:
	_begin(true)
	var es: EventSelect = add(load(EVENTS).instantiate()) as EventSelect
	await frames(3)
	var rows: Array[Button] = es.get("_row_btns")
	var visible_n: int = 0
	for b: Button in rows:
		if b.visible:
			visible_n += 1
	var want: int = mini(EventSelect.PHONE_WINDOW_ROWS, es.get_district_event_count())
	check(visible_n == want, "phone shows %d rows, expected %d" % [visible_n, want])
	var last: int = es.get_row_count() - 1
	es.select(last)
	await frames(2)
	check(rows[last].visible, "selected last row is hidden")
	check(not rows[0].visible, "first row still shown after jumping to the last")
	es.select(0)
	await frames(2)
	check(rows[0].visible and not rows[last].visible, "window did not return to the top")
	await cleanup([es])
	_end()


func test_event_select_desktop_window_follows_selection() -> void:
	_begin(false)
	var es: EventSelect = add(load(EVENTS).instantiate()) as EventSelect
	await frames(3)
	var rows: Array[Button] = es.get("_row_btns")
	check(es.get_visible_row_count() == mini(EventSelect.DESKTOP_WINDOW_ROWS, es.get_district_event_count()), "desktop window bounds the district list")
	var last: int = es.get_row_count() - 1
	es.select(last)
	await frames(2)
	check(rows[last].visible and not rows[0].visible, "desktop can reach final event")
	check(es.get_visible_row_count() == mini(EventSelect.DESKTOP_WINDOW_ROWS, es.get_district_event_count()), "desktop window stays bounded at end")
	es.select(0)
	await frames(2)
	check(rows[0].visible and not rows[last].visible, "desktop window returns to top")
	await cleanup([es])
	_end()


func test_star_pop_curve() -> void:
	check(ResultsScreen.pop_scale(0.0) == 0.0, "pop starts above zero")
	check(ResultsScreen.pop_scale(1.0) == 1.0, "pop does not settle at 1")
	var peak: float = 0.0
	for i: int in 101:
		peak = maxf(peak, ResultsScreen.pop_scale(float(i) / 100.0))
	check(peak > 1.02 and peak < 1.25, "pop overshoot %.3f outside 1.02..1.25" % peak)
	metric("star_pop_peak", peak)


func test_results_stars_animate_to_earned_count() -> void:
	_begin(false)
	var screen: ResultsScreen = add(load(RESULTS).instantiate()) as ResultsScreen
	await frames(2)
	GameState.open_profile("user://test_ui_r12_profile.json")
	GameState.reset_profile()
	var results: Array[Dictionary] = []
	for i: int in 3:
		results.append({"name": "D%d" % i, "position": i + 1, "total_time": 100.0 + float(i), "best_lap": 50.0, "is_player": i == 0})
	var rewards: Dictionary = GameState.record_result("wharf_sprint", 66.0, 1)
	screen.set_event_id("wharf_sprint")
	screen.show_results(results, rewards)
	var early: Array[float] = screen.get_star_pop()
	check(early[0] == 0.0 and early[2] == 0.0, "stars are lit before the animation starts")
	await frames(POP_FRAMES)
	var done: Array[float] = screen.get_star_pop()
	check(done[0] == 1.0 and done[1] == 1.0 and done[2] == 1.0, "three stars did not finish popping: %s" % str(done))
	check(screen.get("_hero_pos").text == "1", "hero position not shown")
	await cleanup([screen])
	for p: String in ["user://test_ui_r12_profile.json", "user://test_ui_r12_profile.json.bak", "user://test_ui_r12_profile.json.tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_end()


func test_settings_has_ui_bus_slider() -> void:
	_begin(false)
	var menu: SettingsMenu = add(load(SETTINGS).instantiate()) as SettingsMenu
	await frames(2)
	var sliders: Dictionary = menu.get("_volume_sliders")
	check(sliders.has("ui"), "no UI sounds slider")
	var before: float = Settings.get_volume("ui")
	(sliders["ui"] as HSlider).value = 0.35
	check(absf(Settings.get_volume("ui") - 0.35) < 0.01, "UI slider does not drive the UI bus setting")
	Settings.set_volume("ui", before)
	await cleanup([menu])
	_end()


func test_hud_frame_scales_on_phone_and_stays_inside_screen() -> void:
	_begin(true)
	var race = load(MOCK_RACE).new()
	var car := ArcadeCar.new()
	race.rivals.append(car)
	var hud: RaceHUD = add(RaceHUD.new()) as RaceHUD
	await frames(2)
	hud.bind(car, race, null)
	await frames(2)
	var frame: Control = hud.get("_frame")
	check(is_equal_approx(frame.scale.x, RaceHUD.PHONE_HUD_SCALE), "HUD frame scale %s on phone" % frame.scale)
	var screen: Vector2 = frame.get_parent_control().size
	var covered: Vector2 = frame.position + frame.size * frame.scale.x
	check(covered.x <= screen.x + 1.0 and covered.y <= screen.y + 1.0, "scaled HUD frame spills off screen: %s of %s" % [covered, screen])
	MSTheme.set_phone(false)
	check(RaceHUD.hud_scale() == 1.0, "desktop HUD scale is not 1")
	await cleanup([hud])
	_end()
