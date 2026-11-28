extends "res://tests/test_case.gd"
## First-launch flow and the first-race hints. Every test uses its own user:// profile and never the real save.
## The screen and hints get the test profile through their store field, not the GameState autoload.

const GS: GDScript = preload("res://core/game_state.gd")
const FIRST_RACE: String = "ortakoy_night"
const OTHER_RACE: String = "wharf_sprint"


func _path(tag: String) -> String:
	return "user://test_onboarding_%s.json" % tag


func _wipe(path: String) -> void:
	for p: String in [path, path + ".bak", path + ".tmp", path + ".bak.tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _write_text(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _open(path: String) -> Node:
	var gs: Node = GS.new()
	gs.open_profile(path)
	return gs


func test_new_profile_onboards_once() -> void:
	var path := _path("fresh")
	_wipe(path)
	var gs: Node = _open(path)
	check(not gs.is_onboarded(), "a new profile still needs onboarding")
	check(not gs.hints_done(), "a new profile has its hints to show")
	gs.set_onboarded()
	gs.free()
	var again: Node = _open(path)
	check(again.is_onboarded(), "finished onboarding is saved")
	check(not again.hints_done(), "finishing onboarding does not mark the hints done")
	again.free()
	_wipe(path)


func test_old_save_counts_as_onboarded() -> void:
	var path := _path("old")
	_wipe(path)
	# A version 2 save from before the flow: no onboarded or hints_done field.
	_write_text(path, JSON.stringify({"version": 2, "cash": 1234, "owned_cars": [CarCatalog.STARTER], "selected_car": CarCatalog.STARTER}))
	var gs: Node = _open(path)
	check(gs.is_onboarded(), "a save from before the flow is already onboarded")
	check(gs.hints_done(), "and its hints are already done")
	check(gs.get_cash() == 1234, "the old save's cash is kept")
	gs.free()
	_wipe(path)


func test_onboarding_screen_steps_and_language() -> void:
	var saved_auto: bool = Settings.autosave
	var saved_lang: String = Settings.language
	Settings.autosave = false
	var path := _path("screen")
	_wipe(path)
	var gs: Node = _open(path)
	var screen := OnboardingScreen.new()
	screen.store = gs
	add(screen)
	await frames(2)
	check(screen.step == OnboardingScreen.STEP_LANGUAGE, "the first step is the language")
	var want: String = "tr" if OS.get_locale_language() == "tr" else "en"
	check(OnboardingScreen.default_language() == want, "language preselected from the OS locale")
	check(Settings.language == want, "the screen applies the preselected language")
	screen.set_step(OnboardingScreen.STEP_CONTROLS)
	check(screen._touch != null and is_instance_valid(screen._touch), "the second step shows the touch layout")
	screen.set_step(OnboardingScreen.STEP_LANGUAGE)
	check(screen._touch == null, "leaving the second step removes the touch layout")
	metric("default_language", Settings.language)
	# The real buttons: language, CONTINUE, START (scene change recorded, not performed).
	var calls: Array = []
	screen.nav = func(scene: String, params: Dictionary) -> void: calls.append([scene, params])
	(screen._lang_btns["en"] as Button).pressed.emit()
	check(Settings.language == "en", "the EN button switches the language")
	(screen._lang_btns["tr"] as Button).pressed.emit()
	check(Settings.language == "tr", "the TR button switches the language")
	screen._next_btn.pressed.emit()
	check(screen.step == OnboardingScreen.STEP_CONTROLS and calls.is_empty(), "CONTINUE opens the controls step")
	screen._next_btn.pressed.emit()
	check(gs.is_onboarded(), "START saves onboarding as done")
	check(calls.size() == 1 and calls[0][0] == LoadingScreen.SCENE, "START goes through the loading card")
	check(calls.size() == 1 and (calls[0][1] as Dictionary)[LoadingScreen.TARGET_KEY] == OnboardingScreen.RACE_SCENE, "the card loads the race scene")
	var cfg: RaceConfig = ((calls[0][1] as Dictionary)[LoadingScreen.NEXT_KEY] as Dictionary).get(RaceScene.CONFIG_PARAM) if calls.size() == 1 else null
	check(cfg != null and cfg.event_id == FIRST_RACE, "START opens Ortakoy Night")
	await cleanup([screen as Node])
	gs.free()
	_wipe(path)
	Settings.set_language(saved_lang)
	Settings.autosave = saved_auto


func test_hints_show_once_in_first_race() -> void:
	var saved_auto: bool = Settings.autosave
	Settings.autosave = false
	var path := _path("hints")
	_wipe(path)
	var gs: Node = _open(path)
	gs.set_onboarded()
	var parent := Node.new()
	add(parent)
	check(OnboardingHints.attach(parent, EventCatalog.config_for(OTHER_RACE), null, gs) == null, "no hints in other races")
	var h: OnboardingHints = OnboardingHints.attach(parent, EventCatalog.config_for(FIRST_RACE), null, gs)
	check(h != null, "hints attach to the first race once onboarded")
	h._process(OnboardingHints.FIRST_DELAY_S + 0.1)
	check(h.is_showing() and h.current_step() == 0, "the steer hint shows after the grid")
	h._process(OnboardingHints.HINT_S + 0.1)
	check(not h.is_showing() and h.current_step() == 1, "the steer hint ends and the nitro hint waits")
	h._process(OnboardingHints.GAP_S + 0.1)
	check(h.is_showing() and h.current_step() == 1, "the nitro hint shows after the gap")
	h._ok.pressed.emit()
	check(not h.is_showing() and h.current_step() == 2, "OK dismisses the nitro hint")
	check(gs.hints_done(), "the set is saved as done once a hint has shown (quitting mid-race keeps it done)")
	h._skip.pressed.emit()
	check(h.is_done(), "skipping ends the set")
	check(gs.hints_done(), "the set is saved as done")
	check(OnboardingHints.attach(parent, EventCatalog.config_for(FIRST_RACE), null, gs) == null, "hints never come back")
	Settings.autosave = saved_auto
	await cleanup([parent])
	gs.free()
	_wipe(path)


func test_hints_end_when_results_show() -> void:
	var path := _path("results")
	_wipe(path)
	var gs: Node = _open(path)
	gs.set_onboarded()
	var parent := Node.new()
	add(parent)
	var results := Control.new()
	parent.add_child(results)
	results.visible = false
	var h: OnboardingHints = OnboardingHints.attach(parent, EventCatalog.config_for(FIRST_RACE), results, gs)
	check(h != null, "hints attach with a results screen")
	results.visible = true
	check(h.is_done() and gs.hints_done(), "the results screen ends the hints and saves it")
	await cleanup([parent])
	gs.free()
	_wipe(path)


func test_main_menu_first_launch_redirect_and_records_button() -> void:
	var old: Dictionary = {"path": GameState.save_path, "profile": GameState.profile.duplicate(true)}
	var path := _path("menu")
	_wipe(path)
	GameState.open_profile(path)  # fresh: no save file yet
	var menu: Node = (load("res://ui/menus/main_menu.tscn") as PackedScene).instantiate()
	var calls: Array = []
	menu.set("nav", func(scene: String, _params: Dictionary) -> void: calls.append(scene))
	var prev: Node = tree.current_scene
	add(menu)
	tree.current_scene = menu  # the redirect only fires for the running scene
	await frames(3)
	check(calls == ["res://ui/menus/onboarding.tscn"], "a fresh profile is sent to onboarding once")
	calls.clear()
	GameState.set_onboarded()
	menu.call("_maybe_onboard")
	check(calls.is_empty(), "an onboarded profile stays on the menu")
	(menu.get("_records_btn") as Button).pressed.emit()
	check(calls == ["res://ui/menus/records_screen.tscn"], "the RECORDS button opens the records screen")
	tree.current_scene = prev
	await cleanup([menu])
	GameState.save_path = str(old["path"])
	GameState.profile = old["profile"]
	_wipe(path)
