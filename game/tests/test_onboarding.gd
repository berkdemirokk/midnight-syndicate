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
	h._finish()
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
