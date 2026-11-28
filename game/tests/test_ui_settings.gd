extends "res://tests/test_case.gd"
## Settings screen: every control changes a real setting, the value is saved to its own config file and reloads,
## the audio bus and frame cap apply, touch targets are at least 88 px (132 px on the phone layout), the five
## tabs show one page each, and the ABOUT panel shows the whole third-party credits file.

const SCENE: String = "res://ui/menus/settings_menu.tscn"
const TEST_CFG: String = "user://test_ui_settings.cfg"
const TARGET_PX: float = 88.0
const LEVEL: float = 0.4
const CAM_SHAKE: float = 0.25
const TAB_COUNT: int = 5
const MIN_TARGETS: int = 15


func _pick(opt: OptionButton, index: int) -> void:
	opt.select(index)
	opt.item_selected.emit(index)


func _snapshot() -> Dictionary:
	var volumes: Dictionary = {}
	for key: String in Settings.AUDIO_BUSES:
		volumes[key] = Settings.get_volume(key)
	return {"preset": Settings.get_preset_id(), "fps": Settings.get_fps_cap(), "volumes": volumes,
		"steering": Settings.steering_mode, "auto_accel": Settings.auto_accelerate, "haptics": Settings.haptics,
		"shake": Settings.camera_shake, "lang": Settings.language}


## Puts every value back without writing any file (autosave is off while this runs).
func _restore(d: Dictionary) -> void:
	Settings.autosave = false
	Settings.set_preset(d["preset"])
	Settings.set_fps_cap(d["fps"])
	for key: String in d["volumes"]:
		Settings.set_volume(key, d["volumes"][key])
	Settings.set_steering_mode(d["steering"])
	Settings.set_auto_accelerate(d["auto_accel"])
	Settings.set_haptics(d["haptics"])
	Settings.set_camera_shake(d["shake"])
	Settings.set_language(d["lang"])


func _targets(node: Node, out: Array) -> void:
	if node is BaseButton or node is Range:
		out.append(node)
	for c: Node in node.get_children():
		_targets(c, out)


func _bus_db(key: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Settings.AUDIO_BUSES[key]))


func test_every_control_persists_and_applies() -> void:
	var before: Dictionary = _snapshot()
	var saved_path: String = Settings.config_path
	var saved_autosave: bool = Settings.autosave
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
	Settings.config_path = TEST_CFG
	Settings.autosave = true
	var menu: SettingsMenu = add(load(SCENE).instantiate()) as SettingsMenu
	await frames(2)

	# GRAPHICS: quality preset and frame cap.
	_pick(menu.get("_preset_opt"), 0)
	check(Settings.get_preset_id() == "low", "quality preset not applied")
	_pick(menu.get("_fps_opt"), 0)
	check(Settings.get_fps_cap() == 30, "frame cap 30 not stored")
	check(Engine.max_fps == 30, "frame cap 30 not applied to Engine.max_fps")
	check(not (menu.get("_preset_desc") as Label).text.is_empty(), "preset description is empty")

	# CONTROLS: steering, auto-accelerate, haptics, camera shake.
	_pick(menu.get("_steer_opt"), 1)
	check(Settings.steering_mode == "tilt", "steering mode not applied")
	var auto: CheckButton = menu.get("_auto_accel")
	auto.button_pressed = not Settings.auto_accelerate
	check(Settings.auto_accelerate == auto.button_pressed, "auto-accelerate toggle not applied")
	var haptic: CheckButton = menu.get("_haptics")
	haptic.button_pressed = not Settings.haptics
	check(Settings.haptics == haptic.button_pressed, "haptics toggle not applied")
	(menu.get("_shake") as HSlider).value = CAM_SHAKE
	check(absf(Settings.camera_shake - CAM_SHAKE) < 0.001, "camera shake not applied")

	# AUDIO: every bus slider drives its bus.
	var sliders: Dictionary = menu.get("_volume_sliders")
	for key: String in sliders:
		(sliders[key] as HSlider).value = LEVEL
		check(absf(Settings.get_volume(key) - LEVEL) < 0.001, "%s slider not stored" % key)
		check(absf(_bus_db(key) - linear_to_db(LEVEL)) < 0.01, "%s bus not at the slider level" % key)

	# LANGUAGE: the whole screen switches to Turkish.
	_pick(menu.get("_lang_opt"), 0)
	check(Settings.language == "tr", "language not stored")
	check(I18n.t("settings.title") == "AYARLAR", "title not translated")
	check((menu.get("_title") as Label).text == "AYARLAR", "title label not refreshed")
	check((menu.get("_tabs")[0] as Button).text == I18n.t("settings.graphics"), "tab text not refreshed")

	# Saved on each change: the file holds every value.
	var cfg := ConfigFile.new()
	check(cfg.load(TEST_CFG) == OK, "settings file not written")
	check(cfg.get_value("graphics", "preset", "") == "low", "preset not saved")
	check(cfg.get_value("graphics", "fps_cap", 0) == 30, "frame cap not saved")
	check(cfg.get_value("controls", "steering_mode", "") == "tilt", "steering not saved")
	check(absf(float(cfg.get_value("controls", "camera_shake", 0.0)) - CAM_SHAKE) < 0.001, "camera shake not saved")
	check(absf(float(cfg.get_value("audio", "master", 0.0)) - LEVEL) < 0.001, "volume not saved")
	check(cfg.get_value("general", "language", "") == "tr", "language not saved")

	# Reload: memory is changed to other values, load_settings() brings the saved ones back.
	Settings.autosave = false
	Settings.set_preset("high")
	Settings.set_fps_cap(60)
	Settings.set_language("en")
	Settings.set_camera_shake(0.9)
	Settings.load_settings()
	check(Settings.get_preset_id() == "low", "preset did not reload")
	check(Settings.get_fps_cap() == 30 and Engine.max_fps == 30, "frame cap did not reload")
	check(Settings.language == "tr", "language did not reload")
	check(absf(Settings.camera_shake - CAM_SHAKE) < 0.001, "camera shake did not reload")

	metric("frame_cap_applied", Engine.max_fps)
	await cleanup([menu])
	Settings.config_path = saved_path
	Settings.autosave = false
	_restore(before)
	Settings.autosave = saved_autosave
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))


func test_tabs_show_one_page_each() -> void:
	var menu: SettingsMenu = add(load(SCENE).instantiate()) as SettingsMenu
	await frames(2)
	var pages: Array = menu.get("_pages")
	var tabs: Array = menu.get("_tabs")
	check(pages.size() == TAB_COUNT and tabs.size() == TAB_COUNT, "expected %d tabs and pages" % TAB_COUNT)
	for i: int in TAB_COUNT:
		menu.show_tab(i)
		var shown: int = 0
		for j: int in pages.size():
			if (pages[j] as Control).visible:
				shown += 1
				check(j == i, "tab %d shows page %d" % [i, j])
		check(shown == 1, "tab %d shows %d pages" % [i, shown])
		check((tabs[i] as Button).button_pressed, "tab %d not marked pressed" % i)
	await cleanup([menu])


func test_touch_targets_are_88_px_and_132_on_phone() -> void:
	for phone: bool in [false, true]:
		MSTheme.set_phone(phone)
		var menu: SettingsMenu = add(load(SCENE).instantiate()) as SettingsMenu
		await frames(2)
		var targets: Array = []
		_targets(menu, targets)
		check(targets.size() >= MIN_TARGETS, "only %d touch targets found" % targets.size())
		var want: float = MSTheme.px(TARGET_PX)
		for t: Node in targets:
			var h: float = (t as Control).custom_minimum_size.y
			check(h >= want - 0.5, "%s target %.0f px, want %.0f (phone=%s)" % [t.get_class(), h, want, str(phone)])
		metric("targets_phone" if phone else "targets_desktop", targets.size())
		await cleanup([menu])
	MSTheme.set_phone(false)


func test_credits_panel_shows_the_credits_file() -> void:
	var file_text: String = FileAccess.get_file_as_string("res://ui/credits_third_party.txt").strip_edges()
	check(not file_text.is_empty(), "credits file missing")
	var panel: CreditsPanel = add(CreditsPanel.new()) as CreditsPanel
	await frames(2)
	check(panel.shown_text() == file_text, "panel does not show the whole credits file")
	check(panel.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED, "credits panel does not scroll")
	check(panel.shown_text().contains("CC BY 4.0"), "CC BY credit line missing from panel")
	await cleanup([panel])
	var menu: SettingsMenu = add(load(SCENE).instantiate()) as SettingsMenu
	await frames(2)
	var inner: CreditsPanel = menu.get("_credits")
	check(inner != null and inner.shown_text() == file_text, "ABOUT tab does not show the credits file")
	await cleanup([menu])
