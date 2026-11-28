class_name MainMenu
extends Control
## Title screen: wordmark and CAREER / QUICK RACE / POLICE PURSUIT / GARAGE / SETTINGS / RECORDS / QUIT over a live
## night-city backdrop (menu_backdrop shader), the selected car on a slow sway at the right, and a career strip
## (stars, cash, rep). set_backdrop() can still swap in a real 3D scene behind the UI.
## Keyboard, gamepad and touch all reach the buttons through Godot's focus navigation.

const EVENT_SELECT_SCENE: String = "res://ui/menus/event_select.tscn"
const GARAGE_SCENE: String = "res://ui/garage/garage.tscn"
const SETTINGS_SCENE: String = "res://ui/menus/settings_menu.tscn"
const RECORDS_SCENE: String = "res://ui/menus/records_screen.tscn"
const PURSUIT_SELECT_SCENE: String = "res://race/pursuit/pursuit_select.tscn"
const RACE_SCENE: String = "res://race/race_scene.tscn"
const HERO_SPLIT: float = 0.45  ## the car stage takes the right part of the screen, from this fraction of the width
const HERO_FOV: float = 34.0
const HERO_DIST_M: float = 9.0
const HERO_YAW_RAD: float = 0.6  ## three-quarter front view: the key-art angle, not a flat head-on shot
const HERO_SWAY_RAD: float = 0.3  ## the car turns this far each way around HERO_YAW_RAD on a slow sway
const HERO_SWAY_S: float = 9.0  ## seconds for one swing
const PAIR_W: float = (460.0 - 14.0) / 2.0  ## MENU_W split into the RECORDS / SETTINGS pair
const MENU_TOUCH_H: float = 88.0  ## every menu button is at least this tall (touch target)
const RACE_H: float = 104.0  ## the primary RACE button is the tallest: one clear entry point
const SWEEP_S: float = 3.2  ## light sweep across the backdrop: travel time, then a pause before the next pass
const SWEEP_PAUSE_S: float = 2.5
const ONBOARDING_SCENE: String = "res://ui/menus/onboarding.tscn"
const TAGLINE_PX: int = 20
const VERSION_PX: int = 16
const TOAST_PX: int = 22
const STAT_PX: int = 24
const STAT_CAP_PX: int = 16
const LOGO_GAP_PX: float = 36.0
const MENU_GAP_PX: float = 14.0
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 56.0
const MENU_W: float = 460.0
const TOAST_HOLD_S: float = 1.4
const TOAST_FADE_S: float = 0.4
const INTRO_S: float = 0.5
const INTRO_STAGGER_S: float = 0.07

var _holder: Control
var _sweep: LightSweep
var _backdrop: MenuBackdrop
var _race_btn: Button
var _quick_btn: Button
var _garage_btn: Button
var _hero_car: Node3D = null
var _hero_pivot: Node3D = null
var _pursuit_btn: Button
var _records_btn: Button
var nav: Callable = Router.goto  ## scene change; tests swap in a recorder so the runner scene stays
var _settings_btn: Button
var _quit_btn: Button
var _tagline: Label
var _version: Label
var _toast: Label
var _toast_tw: Tween = null
var _stat_stars: Label
var _stat_cash: Label
var _stat_rep: Label
var _stat_caps: Array[Label] = []
var _text_nodes: Array = []  ## [node, i18n key] pairs refreshed on language change


func _ready() -> void:
	MusicPlayer.get_instance().play_menu()
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop = MenuBackdrop.new(0.72)
	add_child(_backdrop)
	_holder = Control.new()
	_holder.name = "Backdrop3D"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_build_hero()
	_sweep = LightSweep.new()
	add_child(_sweep)
	_sweep.run()
	_build_foreground()
	Settings.changed.connect(_on_settings_changed)
	GameState.profile_changed.connect(_refresh_stats)
	_refresh_text()
	_race_btn.grab_focus()
	_play_intro()
	# A lost online connection leaves its reason here once.
	var net: NetSession = get_tree().root.get_node_or_null(NetSession.NODE_NAME) as NetSession
	if net != null and net.last_message != "":
		_show_toast(I18n.t("net.lost") if net.last_message == NetSession.LOST_MESSAGE else net.last_message)
		net.last_message = ""
	call_deferred("_maybe_onboard")


## A player who has not finished the first-launch flow goes there once, before the menu is used.
## Only the menu that is the running scene does this, so a menu loaded by a test or capture stays put.
func _maybe_onboard() -> void:
	if get_tree().current_scene == self and not GameState.is_onboarded():
		nav.call(ONBOARDING_SCENE, {})


func _build_foreground() -> void:
	var ins: Vector4 = MSTheme.safe_insets()
	var margin := MarginContainer.new()
	margin.name = "Foreground"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(ins.x + EDGE_PX))
	margin.add_theme_constant_override("margin_top", int(ins.y + EDGE_Y_PX))
	margin.add_theme_constant_override("margin_right", int(ins.z + EDGE_PX))
	margin.add_theme_constant_override("margin_bottom", int(ins.w + EDGE_Y_PX))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	margin.add_child(col)

	var logo := Logotype.new(1.0 if not MSTheme.phone else 0.95)
	logo.name = "Logo"
	col.add_child(logo)
	_tagline = MSTheme.make_label("", "tracked", TAGLINE_PX, MSTheme.MUTED, false)
	_tagline.name = "Tagline"
	col.add_child(_tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, LOGO_GAP_PX)
	col.add_child(gap)

	var menu := VBoxContainer.new()
	menu.name = "Menu"
	menu.add_theme_constant_override("separation", int(MENU_GAP_PX * (1.4 if MSTheme.phone else 1.0)))
	col.add_child(menu)
	_race_btn = _menu_button(menu, "menu.career", _on_race)
	_race_btn.theme_type_variation = &"PrimaryButton"
	_race_btn.custom_minimum_size.y = maxf(RACE_H, MSTheme.button_h())
	_quick_btn = _menu_button(menu, "menu.quick_race", _on_quick_race)
	_pursuit_btn = _menu_button(menu, "menu.pursuit", _on_pursuit)
	_garage_btn = _menu_button(menu, "menu.garage", _on_garage)
	# Experimental LAN online: only with NetConfig.ENABLED or --experimental-online (see docs/design/ONLINE_LAN.md).
	if NetConfig.is_enabled():
		_menu_button(menu, "net.menu_button", _on_online)
	# RECORDS and SETTINGS share one row; QUIT sits below them, and is hidden on iOS / Android.
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", int(MENU_GAP_PX))
	menu.add_child(pair)
	_records_btn = _menu_button(pair, "menu.records", _on_records, PAIR_W)
	_settings_btn = _menu_button(pair, "menu.settings", _on_settings, PAIR_W)
	_quit_btn = _menu_button(menu, "menu.quit", _on_quit)
	_quit_btn.visible = not (OS.has_feature("ios") or OS.has_feature("android"))

	# Career strip, bottom right: stars, cash, rep on one backing plate.
	var strip_margin := MarginContainer.new()
	strip_margin.name = "CareerStrip"
	strip_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	strip_margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	strip_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip_margin.offset_right = -(ins.z + EDGE_PX * 0.6)
	strip_margin.offset_bottom = -(ins.w + EDGE_Y_PX * 0.8)
	strip_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip_margin)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", MSTheme.box(MSTheme.PLATE_BG, MSTheme.BORDER))
	strip_margin.add_child(plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MSTheme.GRID_PX * 4)
	plate.add_child(row)
	_stat_stars = _stat(row, MSTheme.AMBER, "results.reward_stars")
	_stat_cash = _stat(row, MSTheme.AMBER, "results.reward_cash")
	_stat_rep = _stat(row, MSTheme.CYAN, "results.reward_rep")

	_version = MSTheme.make_label("", "tracked", VERSION_PX, MSTheme.MUTED, false)
	_version.name = "Version"
	_version.anchor_left = 1.0
	_version.anchor_right = 1.0
	_version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_version.offset_top = ins.y + EDGE_Y_PX * 0.5
	_version.offset_right = -(ins.z + EDGE_PX * 0.6)
	_version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_version)

	_toast = MSTheme.make_label("", "bold", TOAST_PX, MSTheme.AMBER, true)
	_toast.name = "Toast"
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = -(ins.w + EDGE_Y_PX * 2.0)
	_toast.offset_bottom = _toast.offset_top + TOAST_PX * 2.0
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)


## One caption over one value, tinted.
func _stat(parent: Container, ink: Color, cap_key: String) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var cap: Label = MSTheme.make_label("", "tracked", MSTheme.px(STAT_CAP_PX), MSTheme.MUTED)
	cap.set_meta("key", cap_key)
	_stat_caps.append(cap)
	var val: Label = MSTheme.make_label("", "digits", MSTheme.px(STAT_PX), ink)
	box.add_child(cap)
	box.add_child(val)
	parent.add_child(box)
	return val


func _menu_button(parent: Container, key: String, handler: Callable, width: float = MENU_W) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, maxf(MENU_TOUCH_H, MSTheme.button_h()))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func() -> void: UiSounds.click())
	b.pressed.connect(handler)
	parent.add_child(b)
	_text_nodes.append([b, key])
	return b


## The column slides in from the left, button by button (skipped when the tree is not running a real frame loop).
func _play_intro() -> void:
	var items: Array[Control] = [_race_btn, _quick_btn, _pursuit_btn, _garage_btn, _records_btn, _settings_btn, _quit_btn]
	for i: int in items.size():
		var b: Control = items[i]
		b.modulate.a = 0.0
		var tw: Tween = create_tween()
		tw.tween_interval(INTRO_STAGGER_S * float(i))
		tw.tween_property(b, "modulate:a", 1.0, INTRO_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The selected car on a slow sway, lit by a key, a fill and a rim light, drawn over the live backdrop.
## The viewport is transparent, so only the car is painted over the night city.
func _build_hero() -> void:
	var car_id: String = CarCatalog.race_car_id()
	var packed: PackedScene = load(CarCatalog.scene_path(car_id)) as PackedScene
	if packed == null:
		return
	var box := SubViewportContainer.new()
	box.name = "Hero"
	box.stretch = true
	box.anchor_left = HERO_SPLIT
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.handle_input_locally = false
	box.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.22, 0.3)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	Settings.apply_to_environment(env)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = HERO_FOV
	cam.position = Vector3(0.0, 1.6, HERO_DIST_M)
	vp.add_child(cam)
	cam.current = true
	cam.look_at_from_position(cam.position, Vector3(0.0, 1.1, 0.0))  # aim above the car so it sits low, on the road
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.96, 0.92)
	key.light_energy = 2.2
	key.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.9, 0.95, 1.0)
	fill.light_energy = 1.1
	fill.rotation_degrees = Vector3(-25.0, 150.0, 0.0)
	vp.add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = MSTheme.CYAN
	rim.light_energy = 3.0
	rim.omni_range = 12.0
	rim.position = Vector3(-3.0, 2.4, -3.5)
	vp.add_child(rim)
	_hero_pivot = Node3D.new()
	_hero_pivot.rotation.y = HERO_YAW_RAD - HERO_SWAY_RAD
	vp.add_child(_hero_pivot)
	var car := packed.instantiate() as CarLod
	car.force_lod0 = true
	var setup: Dictionary = GameState.get_setup(car_id)
	car.paint_colour = Color.from_string(str(setup["paint_color"]), CarMaterials.DEFAULT_PAINT)
	_hero_pivot.add_child(car)
	CarMaterials.set_rim_color(car, Color.from_string(str(setup["rim_color"]), CarMaterials.DEFAULT_RIM))
	_hero_car = car
	var sway := create_tween().set_loops()
	sway.tween_property(_hero_pivot, "rotation:y", HERO_YAW_RAD + HERO_SWAY_RAD, HERO_SWAY_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sway.tween_property(_hero_pivot, "rotation:y", HERO_YAW_RAD - HERO_SWAY_RAD, HERO_SWAY_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Replaces the live backdrop with a 3D scene rendered through a SubViewport behind the UI.
func set_backdrop(node: Node) -> void:
	for c: Node in _holder.get_children():
		c.queue_free()
	if node == null:
		_backdrop.visible = true
		return
	_backdrop.visible = false
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.handle_input_locally = false
	container.add_child(vp)
	_holder.add_child(container)
	vp.add_child(node)


func _refresh_text() -> void:
	for pair: Array in _text_nodes:
		var n: Object = pair[0]
		(n as Button).text = I18n.t(pair[1])
	_tagline.text = I18n.t("menu.tagline")
	_version.text = I18n.t("menu.version") % str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	for cap: Label in _stat_caps:
		cap.text = I18n.t(str(cap.get_meta("key")))
	_refresh_stats()


func _refresh_stats() -> void:
	_stat_stars.text = "%d / %d" % [GameState.total_stars(), EventCatalog.count() * GameState.MAX_STARS]
	_stat_cash.text = I18n.t("garage.money") % GameState.get_cash()
	_stat_rep.text = RaceHUD.group_int(GameState.get_rep())


func _on_settings_changed(section: String) -> void:
	if section == Settings.SECTION_GENERAL:
		_refresh_text()


func _on_race() -> void:
	_open(EVENT_SELECT_SCENE)


func _on_garage() -> void:
	_open(GARAGE_SCENE)


## QUICK RACE: the first unlocked ladder race not yet won (else the first unlocked one), straight to the loading card.
func _on_quick_race() -> void:
	var id: String = quick_race_id()
	var cfg: RaceConfig = EventCatalog.config_for(id) if id != "" else null
	if cfg == null:
		_show_toast(I18n.t("menu.coming_soon"))
		return
	nav.call(LoadingScreen.SCENE, LoadingScreen.params_for(RACE_SCENE, {RaceScene.CONFIG_PARAM: cfg}))


## Id of the race QUICK RACE starts, or "" when none is unlocked. Pursuit runs and showcase events are skipped.
static func quick_race_id() -> String:
	var fallback: String = ""
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		if EventCatalog.is_open(id) or not GameState.is_event_unlocked(id):
			continue
		if bool(EventCatalog.find(id).get("pursuit", false)):
			continue
		if GameState.event_stars(id) == 0:
			return id
		if fallback == "":
			fallback = id
	return fallback


## Police pursuit runs: the select screen lists the open pursuit runs.
func _on_pursuit() -> void:
	_open(PURSUIT_SELECT_SCENE)


func _on_online() -> void:
	var lobby := NetLobbyMenu.new()
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(lobby)


func _on_settings() -> void:
	_open(SETTINGS_SCENE)


func _on_records() -> void:
	_open(RECORDS_SCENE)


func _on_quit() -> void:
	get_tree().quit()


## Opens a scene through Router when it exists. Missing scenes show a short toast instead.
func _open(path: String) -> void:
	if ResourceLoader.exists(path):
		nav.call(path, {})
	else:
		_show_toast(I18n.t("menu.coming_soon"))


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_interval(TOAST_HOLD_S)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE_S)
	_toast_tw.tween_callback(func() -> void: _toast.visible = false)


## A soft diagonal band of light that crosses the backdrop again and again. Drawn in one pass, no textures.
class LightSweep extends Control:
	var pos: float = -0.4  ## band position as a fraction of the width

	func _init() -> void:
		name = "LightSweep"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func run() -> void:
		var tw: Tween = create_tween().set_loops()
		tw.tween_method(_set_pos, -0.4, 1.4, SWEEP_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_interval(SWEEP_PAUSE_S)

	func _set_pos(v: float) -> void:
		pos = v
		queue_redraw()

	func _draw() -> void:
		var w: float = size.x * 0.12
		var cx: float = size.x * pos
		var k: float = size.y * MSTheme.SKEW_RATIO
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx + k, 0.0), Vector2(cx + k + w, 0.0), Vector2(cx + w, size.y), Vector2(cx, size.y)]),
			MSTheme.tint(MSTheme.CYAN, 0.06))
