extends "res://tests/test_case.gd"
## Touch survival (ROADMAP step 2): touch zones keep clear of the HUD gauges on phone sizes, the pause button emits,
## the pause menu actions work, online pause does not stop the clock, and focus loss pauses without resuming.
## Run at --fixed-fps 60 so frames are physics ticks.

const SCENE_PATH: String = "res://race/race_scene.tscn"
const PAUSE_PATH: String = "res://ui/menus/pause_menu.tscn"
const TOUCH_PATH: String = "res://vehicles/touch/touch_controls.tscn"
const MISSING_PATH: String = "res://does_not_exist/none.tscn"
const DESKTOP_VP: Vector2 = Vector2(1920.0, 1080.0)
const PHONE_VP: Vector2 = Vector2(2532.0, 1170.0)
const IPAD_VP: Vector2 = Vector2(2732.0, 2048.0)
const ZONE_FIRST: int = 1  ## TouchControls.Zone.STEER_LEFT
const ZONE_LAST: int = 5  ## TouchControls.Zone.DRIFT


func _touch_at(vp: Vector2, phone: bool) -> TouchControls:
	MSTheme.set_phone(phone)
	var t: TouchControls = add((load(TOUCH_PATH) as PackedScene).instantiate()) as TouchControls
	t.force_visible = true
	t._layout(vp)
	return t


## HUD gauge boxes in viewport pixels, from the RaceHUD offsets scaled by the HUD frame scale.
func _hud_boxes(vp: Vector2) -> Array[Rect2]:
	var k: float = RaceHUD.hud_scale()
	var mm: float = (RaceHUD.MM_PAD * 2.0 + RaceHUD.MM_R * 2.0) * k
	var tach_top: float = vp.y - (RaceHUD.TACH_OFF_Y + RaceHUD.TACH_PLATE_R) * k
	var tach_left: float = vp.x - (RaceHUD.TACH_OFF_X + RaceHUD.TACH_PLATE_R) * k
	var tach_w: float = 2.0 * RaceHUD.TACH_PLATE_R * k
	var nitro_c := Vector2(vp.x - RaceHUD.NITRO_OFF_X * k, vp.y - RaceHUD.NITRO_OFF_Y * k)
	var nitro_r: float = RaceHUD.NITRO_R * k
	var boxes: Array[Rect2] = []
	boxes.append(Rect2(Vector2(0.0, vp.y - mm), Vector2(mm, mm)))
	boxes.append(Rect2(Vector2(tach_left, tach_top), Vector2(tach_w, vp.y - tach_top)))
	boxes.append(Rect2(nitro_c - Vector2(nitro_r, nitro_r), Vector2(nitro_r * 2.0, nitro_r * 2.0)))
	return boxes


func _check_clear_of_hud(t: TouchControls, vp: Vector2, label: String) -> void:
	var boxes: Array[Rect2] = _hud_boxes(vp)
	var frame := Rect2(Vector2.ZERO, vp)
	for z: int in range(ZONE_FIRST, ZONE_LAST + 1):
		var r: Rect2 = t.get_zone_rect(z)
		check(r.size.x > 0.0 and r.size.y > 0.0, "%s: zone %d has no rect" % [label, z])
		check(frame.encloses(r), "%s: zone %d leaves the screen" % [label, z])
		for b: Rect2 in boxes:
			check(not r.intersects(b), "%s: zone %d covers a HUD gauge" % [label, z])
		for other: int in range(z + 1, ZONE_LAST + 1):
			check(not r.intersects(t.get_zone_rect(other)), "%s: zones %d and %d overlap" % [label, z, other])
	var p: Rect2 = t.get_pause_rect()
	check(frame.encloses(p), "%s: pause button leaves the screen" % label)
	for b: Rect2 in boxes:
		check(not p.intersects(b), "%s: pause button covers a HUD gauge" % label)
	for z: int in range(ZONE_FIRST, ZONE_LAST + 1):
		check(not p.intersects(t.get_zone_rect(z)), "%s: pause button overlaps zone %d" % [label, z])


func test_layout_clear_of_hud_on_desktop() -> void:
	var t: TouchControls = _touch_at(DESKTOP_VP, false)
	check(t.get_pause_rect().size.x >= 88.0, "desktop pause button below 88 px")
	_check_clear_of_hud(t, DESKTOP_VP, "desktop 1920x1080")
	await cleanup([t])


func test_layout_clear_of_hud_on_iphone_and_ipad() -> void:
	var t: TouchControls = _touch_at(PHONE_VP, true)
	check(t.get_pause_rect().size.x >= 124.0, "phone pause button below the 44 pt target")
	_check_clear_of_hud(t, PHONE_VP, "phone 2532x1170")
	t._layout(IPAD_VP)
	_check_clear_of_hud(t, IPAD_VP, "ipad 2732x2048")
	MSTheme.set_phone(false)
	await cleanup([t])


func test_pause_button_emits_pause_pressed() -> void:
	var t: TouchControls = _touch_at(DESKTOP_VP, false)
	var hits: Array = [0]
	t.pause_pressed.connect(func() -> void: hits[0] += 1)
	t._pause_btn.pressed.emit()
	check(hits[0] == 1, "pause button did not emit pause_pressed once: %d" % hits[0])
	await cleanup([t])


func test_pause_drops_held_touches() -> void:
	var t: TouchControls = _touch_at(DESKTOP_VP, false)
	t._touches[0] = 1  # STEER_LEFT held when the pause starts
	t._touches[1] = 3  # BRAKE held
	t._push()
	t.notification(Node.NOTIFICATION_PAUSED)
	check(t._touches.is_empty() and t._held_mask == 0, "touches held at pause stay stuck after resume")
	await cleanup([t])


func test_pause_menu_actions() -> void:
	var pm: PauseMenu = add((load(PAUSE_PATH) as PackedScene).instantiate()) as PauseMenu
	await frames(1)
	var hits: Dictionary = {"reset": 0, "restart": 0, "quit": 0, "resumed": 0}
	pm.reset_requested.connect(func() -> void: hits["reset"] += 1)
	pm.restart_requested.connect(func() -> void: hits["restart"] += 1)
	pm.quit_requested.connect(func() -> void: hits["quit"] += 1)
	pm.resumed.connect(func() -> void: hits["resumed"] += 1)
	pm.pause()
	check(pm.is_paused_menu_open() and tree.paused, "pause() did not open the menu and pause the tree")
	pm._on_reset()
	check(hits["reset"] == 1, "RESET CAR did not emit reset_requested")
	check(not pm.is_paused_menu_open() and not tree.paused, "RESET CAR must close the menu and unpause")
	pm.pause()
	pm._on_restart()
	check(hits["restart"] == 1, "RESTART did not emit restart_requested")
	check(not pm.is_paused_menu_open() and not tree.paused, "RESTART must close the menu and unpause")
	pm.pause()
	pm._on_quit()
	check(hits["quit"] == 1, "QUIT TO MENU did not emit quit_requested")
	check(not tree.paused, "QUIT TO MENU must unpause before leaving")
	pm.pause()
	pm.resume()
	check(hits["resumed"] == 2 and not tree.paused, "RESUME did not resume (RESET CAR resumes once before it)")
	await cleanup([pm])


func test_online_pause_keeps_the_clock_running() -> void:
	var pm: PauseMenu = add((load(PAUSE_PATH) as PackedScene).instantiate()) as PauseMenu
	await frames(1)
	pm.set_keeps_running(true)
	pm.pause()
	check(pm.is_paused_menu_open(), "online pause did not open the menu")
	check(not tree.paused, "online pause stopped the tree (time must keep running)")
	check(not pm._restart_btn.visible, "online restart must be hidden (no new grid)")
	check(pm._note.visible, "online note must show while the menu is open")
	pm.resume()
	check(not tree.paused, "online resume left the tree paused")
	pm.set_keeps_running(false)
	pm.pause()
	check(tree.paused and pm._restart_btn.visible and not pm._note.visible, "offline pause must stop the tree and show restart")
	pm.resume()
	await cleanup([pm])


func _race_scene() -> RaceScene:
	var c := RaceConfig.new()
	c.autopilot = false
	c.laps = 1
	c.opponent_count = 0
	c.track_scene = MISSING_PATH
	c.car_scene = MISSING_PATH
	var scene: RaceScene = (load(SCENE_PATH) as PackedScene).instantiate() as RaceScene
	scene.config = c
	add(scene)
	return scene


func test_focus_loss_pauses_and_never_resumes() -> void:
	var scene: RaceScene = _race_scene()
	await frames(3)
	scene.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(scene.pause_menu.is_paused_menu_open(), "focus loss did not open the pause menu")
	check(tree.paused, "focus loss did not pause the tree")
	await frames(30)
	check(scene.pause_menu.is_paused_menu_open() and tree.paused, "the race resumed by itself after focus loss")
	scene.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(scene.pause_menu.is_paused_menu_open(), "a second background signal closed the menu")
	scene.pause_menu.resume()
	check(not tree.paused, "RESUME did not unpause after focus loss")
	await cleanup([scene])


func test_touch_pause_toggles_menu() -> void:
	var scene: RaceScene = _race_scene()
	await frames(3)
	scene._on_touch_pause()
	check(scene.pause_menu.is_paused_menu_open() and tree.paused, "touch pause did not open the menu")
	scene._on_touch_pause()
	check(not scene.pause_menu.is_paused_menu_open() and not tree.paused, "second touch pause did not close the menu")
	await cleanup([scene])


func test_new_strings_exist() -> void:
	for key: String in ["pause.reset", "pause.online_note", "touch.pause"]:
		check(I18n.has_key(key), "missing i18n key " + key)
