class_name MainMenu
extends Control
## STREET EMPIRE main screen. The player's selected car stands in the 3D showroom (ui/showroom/showroom_stage.gd)
## and is the centrepiece; the UI frames it:
## - top: wordmark, then REP with the next real car unlock, cash and stars (opens the profile card);
## - left: navigation (CAREER, QUICK RACE, GARAGE, POLICE PURSUIT, RECORDS, ONLINE when enabled, SETTINGS, QUIT on desktop);
## - bottom left: district progress from real event stars (desktop; the career screen has it on phones);
## - bottom right: the featured event (next unfinished career event) and PLAY, which starts it through the loading screen;
## - bottom centre: the car's name and class; drag anywhere on the car to orbit it.
## Without a GPU scene (headless tests) the graphite MenuBackdrop shows instead. set_backdrop() still swaps in any
## 3D scene behind the UI. Keyboard, gamepad and touch reach every control through Godot's focus navigation.

const EVENT_SELECT_SCENE: String = "res://ui/menus/event_select.tscn"
const GARAGE_SCENE: String = "res://ui/garage/garage.tscn"
const SETTINGS_SCENE: String = "res://ui/menus/settings_menu.tscn"
const RECORDS_SCENE: String = "res://ui/menus/records_screen.tscn"
const PURSUIT_SELECT_SCENE: String = "res://race/pursuit/pursuit_select.tscn"
const ONBOARDING_SCENE: String = "res://ui/menus/onboarding.tscn"
const RACE_SCENE: String = "res://race/race_scene.tscn"
const STAGE_SCRIPT: String = "res://ui/showroom/showroom_stage.gd"
const STAR_PIPS: Script = preload("res://ui/theme/star_pips.gd")
const CAREER_SCREEN: Script = preload("res://ui/menus/event_select.gd")  ## one district rule for menu and career

const EDGE_PX: float = 88.0
const EDGE_Y_PX: float = 56.0
const NAV_W: float = 400.0
const NAV_PX: int = 32
const NAV_H_PX: float = 88.0  ## nav row height on desktop too: the release made 88 px the menu touch target
const CARD_W: float = 520.0
const PLAY_H: float = 92.0
const TOAST_HOLD_S: float = 1.6
const TOAST_FADE_S: float = 0.4
const INTRO_S: float = 0.45
const INTRO_STAGGER_S: float = 0.05
const INTRO_RISE_PX: float = 24.0

## Off in headless runs (no GPU, and tests load the menu many times); captures and the game have a display.
static var showroom_enabled: bool = DisplayServer.get_name() != "headless"

var nav: Callable = Router.goto  ## scene change; tests swap in a recorder so the runner scene stays
var stage: Node3D = null  ## the showroom (null without one)

var _backdrop: MenuBackdrop
var _stage_box: SubViewportContainer = null
var _holder: Control
var _orbit: Control
var _fg: Control
var _race_btn: Button  ## PLAY: starts the featured event (kept name: tests and focus rules refer to it)
var _career_btn: Button
var _quick_btn: Button  ## QUICK RACE: the next unwon ladder race (release wp/mainmenu), through the loading screen
var _garage_btn: Button
var _pursuit_btn: Button  ## police pursuit runs (the pursuit select screen)
var _records_btn: Button
var _settings_btn: Button
var _quit_btn: Button
var _online_btn: Button = null
var _profile_btn: Button
var _nav_btns: Array[Button] = []
var _featured_id: String = ""
var _f_caption: Label
var _f_name: Label
var _f_meta: Label
var _f_reward: Label
var _f_stars: Control
var _rep_val: Label
var _rep_next: Label
var _rep_bar: ProgressBar
var _cash_val: Label
var _stars_val: Label
var _car_name: Label
var _car_class: Label
var _hint: Label
var _version: Label
var _toast: Label
var _toast_tw: Tween = null
var _district_rows: Array = []  ## [district id, name label, count label, bar]
var _districts_title: Label
var _profile_card: Control = null
var _intro_items: Array[Control] = []
var _text_nodes: Array = []  ## [node, i18n key] pairs refreshed on language change


func _ready() -> void:
	MusicPlayer.get_instance().play_menu()
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop = MenuBackdrop.new(0.2)
	add_child(_backdrop)
	if showroom_enabled and ResourceLoader.exists(STAGE_SCRIPT):
		_build_stage()
	_holder = Control.new()
	_holder.name = "Backdrop3D"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_build_scrims()
	_orbit = Control.new()
	_orbit.name = "OrbitArea"
	_orbit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_orbit.mouse_filter = Control.MOUSE_FILTER_STOP if stage != null else Control.MOUSE_FILTER_IGNORE
	_orbit.gui_input.connect(_on_orbit_input)
	add_child(_orbit)
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


func _unhandled_input(event: InputEvent) -> void:
	if _profile_card != null and event.is_action_pressed("ui_cancel"):
		_close_profile()
		get_viewport().set_input_as_handled()


# --- 3D showroom ---------------------------------------------------------------------------------

func _build_stage() -> void:
	var lite: bool = MSTheme.phone or Settings.get_preset_id() == "low"
	_stage_box = SubViewportContainer.new()
	_stage_box.name = "Showroom3D"
	_stage_box.stretch = true
	_stage_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.handle_input_locally = false
	vp.audio_listener_enable_3d = false
	Settings.apply_to_viewport(vp)
	if lite:
		vp.scaling_3d_scale = minf(vp.scaling_3d_scale, 0.8)  # mobile fallback: fewer pixels, no mirror, no shadow
	_stage_box.add_child(vp)
	add_child(_stage_box)
	var script: Script = load(STAGE_SCRIPT) as Script
	stage = script.new("lite" if lite else "full") as Node3D
	vp.add_child(stage)
	_backdrop.visible = false  # the showroom covers the screen: skip the full-screen shader pass under it


func _on_orbit_input(event: InputEvent) -> void:
	if stage == null:
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and mm.device == InputEvent.DEVICE_ID_EMULATION:
		return  # touch already arrives as InputEventScreenDrag: do not orbit twice
	if mm != null and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		stage.call("orbit_drag", mm.relative)
		return
	var sd: InputEventScreenDrag = event as InputEventScreenDrag
	if sd != null:
		stage.call("orbit_drag", sd.relative)
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and not mb.pressed:
		stage.call("orbit_release")


# --- build ---------------------------------------------------------------------------------------

## Two soft graphite gradients (left, bottom) so the type reads over the bright car and studio.
func _build_scrims() -> void:
	for side: String in ["left", "bottom", "top"]:
		var g := Gradient.new()
		g.set_color(0, Color(MSTheme.GRAPHITE, 0.82 if side == "left" else 0.7))
		g.set_color(1, Color(MSTheme.GRAPHITE, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 256
		gt.height = 256
		gt.fill_from = Vector2(0.0, 0.0) if side == "left" else (Vector2(0.0, 1.0) if side == "bottom" else Vector2.ZERO)
		gt.fill_to = Vector2(1.0, 0.0) if side == "left" else (Vector2(0.0, 0.0) if side == "bottom" else Vector2(0.0, 1.0))
		var tr := TextureRect.new()
		tr.name = "Scrim_" + side
		tr.texture = gt
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		match side:
			"left":
				tr.anchor_bottom = 1.0
				tr.anchor_right = 0.46
			"bottom":
				tr.anchor_top = 0.62
				tr.anchor_right = 1.0
				tr.anchor_bottom = 1.0
			"top":
				tr.anchor_right = 1.0
				tr.anchor_bottom = 0.2
		add_child(tr)


func _build_foreground() -> void:
	var ins: Vector4 = MSTheme.safe_insets()
	var ex: float = ins.x + EDGE_PX
	var ey: float = ins.y + EDGE_Y_PX
	var exr: float = ins.z + EDGE_PX
	var eyb: float = ins.w + EDGE_Y_PX
	_fg = Control.new()
	_fg.name = "Foreground"
	_fg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fg)

	# Top left: wordmark.
	var logo := Logotype.new(0.62 if not MSTheme.phone else 0.75, true)
	logo.name = "Logo"
	logo.position = Vector2(ex, ey - 8.0)
	_fg.add_child(logo)
	_intro_items.append(logo)

	# Top right: profile strip (REP + next unlock, cash, stars). The panel sizes itself to the stats; a button fills it
	# and opens the profile card.
	var pstrip := PanelContainer.new()
	pstrip.name = "ProfileStrip"
	var psb: StyleBoxFlat = MSTheme.box(MSTheme.tint(MSTheme.GRAPHITE, 0.72), MSTheme.BORDER)
	psb.content_margin_left = MSTheme.px(26)
	psb.content_margin_right = MSTheme.px(26)
	psb.content_margin_top = MSTheme.px(10)
	psb.content_margin_bottom = MSTheme.px(10)
	pstrip.add_theme_stylebox_override("panel", psb)
	pstrip.anchor_left = 1.0
	pstrip.anchor_right = 1.0
	pstrip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pstrip.offset_right = -exr
	pstrip.offset_top = ey
	pstrip.custom_minimum_size = Vector2(0.0, MSTheme.button_h())
	_fg.add_child(pstrip)
	_intro_items.append(pstrip)
	_profile_btn = Button.new()
	_profile_btn.name = "ProfileButton"
	_profile_btn.focus_mode = Control.FOCUS_ALL
	var clear_sb: StyleBoxFlat = MSTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	_profile_btn.add_theme_stylebox_override("normal", clear_sb)
	_profile_btn.add_theme_stylebox_override("hover", MSTheme.box(MSTheme.tint(MSTheme.PEARL, 0.05), Color(0, 0, 0, 0), 0))
	_profile_btn.add_theme_stylebox_override("pressed", MSTheme.box(MSTheme.tint(MSTheme.PEARL, 0.09), Color(0, 0, 0, 0), 0))
	_profile_btn.custom_minimum_size = Vector2(0.0, MSTheme.button_h())
	_profile_btn.pressed.connect(func() -> void: UiSounds.click())
	_profile_btn.pressed.connect(open_profile)
	pstrip.add_child(_profile_btn)
	var strip := HBoxContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_constant_override("separation", MSTheme.px(36))
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	pstrip.add_child(strip)
	var rep_box: VBoxContainer = _stat_box(strip, "results.reward_rep")
	var rep_row := HBoxContainer.new()
	rep_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rep_row.add_theme_constant_override("separation", MSTheme.px(12))
	rep_box.add_child(rep_row)
	_rep_val = MSTheme.make_label("", "display", MSTheme.px(30), MSTheme.PEARL)
	rep_row.add_child(_rep_val)
	var rep_side := VBoxContainer.new()
	rep_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rep_side.add_theme_constant_override("separation", 4)
	rep_side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rep_row.add_child(rep_side)
	_rep_next = MSTheme.make_label("", "tracked", MSTheme.px(12), MSTheme.STEEL)
	rep_side.add_child(_rep_next)
	_rep_bar = ProgressBar.new()
	_rep_bar.show_percentage = false
	_rep_bar.custom_minimum_size = Vector2(MSTheme.px(150), 4.0)
	_rep_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rep_bar.max_value = 1.0
	_rep_bar.step = 0.0
	rep_side.add_child(_rep_bar)
	_cash_val = MSTheme.make_label("", "display", MSTheme.px(30), MSTheme.GOLD)
	_stat_box(strip, "results.reward_cash").add_child(_cash_val)
	_stars_val = MSTheme.make_label("", "display", MSTheme.px(30), MSTheme.PEARL)
	_stat_box(strip, "results.reward_stars").add_child(_stars_val)

	# Left: navigation.
	var navbox := VBoxContainer.new()
	navbox.name = "Menu"
	navbox.add_theme_constant_override("separation", 0 if not MSTheme.phone else 8)
	navbox.anchor_top = 0.5
	navbox.anchor_bottom = 0.5
	navbox.offset_left = ex - MSTheme.px(16)
	navbox.offset_top = -400.0 if not MSTheme.phone else -380.0
	_fg.add_child(navbox)
	_career_btn = _nav_button(navbox, "menu.career", _on_career)
	_quick_btn = _nav_button(navbox, "menu.quick_race", _on_quick_race)
	_garage_btn = _nav_button(navbox, "menu.garage", _on_garage)
	_pursuit_btn = _nav_button(navbox, "menu.pursuit", _on_pursuit)
	_records_btn = _nav_button(navbox, "menu.records", _on_records)
	# Experimental LAN online: only with NetConfig.ENABLED or --experimental-online (see docs/design/ONLINE_LAN.md).
	if NetConfig.is_enabled():
		_online_btn = _nav_button(navbox, "net.menu_button", _on_online)
	_settings_btn = _nav_button(navbox, "menu.settings", _on_settings)
	_quit_btn = _nav_button(navbox, "menu.quit", _on_quit)
	_quit_btn.visible = not (OS.has_feature("ios") or OS.has_feature("android"))

	# Bottom left: district progress (desktop; phones show it on the career screen).
	var dist := VBoxContainer.new()
	dist.name = "Districts"
	dist.visible = not MSTheme.phone
	dist.add_theme_constant_override("separation", 6)
	dist.anchor_top = 1.0
	dist.anchor_bottom = 1.0
	dist.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dist.offset_left = ex
	dist.offset_bottom = -eyb
	dist.custom_minimum_size = Vector2(420.0, 0.0)
	dist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fg.add_child(dist)
	_intro_items.append(dist)
	_districts_title = MSTheme.make_label("", "tracked", 14, MSTheme.STEEL)
	dist.add_child(_districts_title)
	for d: int in CAREER_SCREEN.DISTRICT_COUNT:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nm: Label = MSTheme.make_label("", "bold", 17, MSTheme.PEARL)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cnt: Label = MSTheme.make_label("", "digits", 15, MSTheme.TITANIUM)
		head.add_child(nm)
		head.add_child(cnt)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0.0, 4.0)
		bar.max_value = 1.0
		bar.step = 0.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(head)
		row.add_child(bar)
		dist.add_child(row)
		_district_rows.append([d, nm, cnt, bar])

	# Bottom right: featured event card with PLAY.
	var card := PanelContainer.new()
	card.name = "Featured"
	var card_sb: StyleBoxFlat = MSTheme.box(MSTheme.tint(MSTheme.GRAPHITE, 0.86), MSTheme.BORDER)
	card_sb.border_width_top = 3
	card_sb.border_color = MSTheme.tint(MSTheme.TITANIUM, 0.16)
	card_sb.content_margin_left = MSTheme.px(28)
	card_sb.content_margin_right = MSTheme.px(28)
	card_sb.content_margin_top = MSTheme.px(22)
	card_sb.content_margin_bottom = MSTheme.px(24)
	card.add_theme_stylebox_override("panel", card_sb)
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_right = -exr
	card.offset_bottom = -eyb
	card.custom_minimum_size = Vector2(MSTheme.px(CARD_W) if not MSTheme.phone else 700.0, 0.0)
	_fg.add_child(card)
	_intro_items.append(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MSTheme.px(8))
	card.add_child(col)
	_f_caption = MSTheme.make_label("", "tracked", MSTheme.px(14), MSTheme.RED)
	col.add_child(_f_caption)
	_f_name = MSTheme.make_label("", "display", MSTheme.px(46), MSTheme.PEARL)
	_f_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_f_name.clip_text = true
	col.add_child(_f_name)
	_f_meta = MSTheme.make_label("", "tracked", MSTheme.px(15), MSTheme.TITANIUM)
	col.add_child(_f_meta)
	var rew := HBoxContainer.new()
	rew.add_theme_constant_override("separation", MSTheme.px(18))
	col.add_child(rew)
	_f_stars = STAR_PIPS.new(float(MSTheme.px(20))) as Control
	_f_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rew.add_child(_f_stars)
	_f_reward = MSTheme.make_label("", "digits", MSTheme.px(18), MSTheme.PEARL)
	_f_reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rew.add_child(_f_reward)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, MSTheme.px(6))
	col.add_child(gap)
	_race_btn = Button.new()
	_race_btn.name = "Play"
	_race_btn.theme_type_variation = &"PrimaryButton"
	_race_btn.custom_minimum_size = Vector2(0.0, maxf(MSTheme.px(PLAY_H), MSTheme.button_h()))
	_race_btn.add_theme_font_override("font", MSTheme.font("slant"))
	_race_btn.add_theme_font_size_override("font_size", MSTheme.px(44))
	_race_btn.pressed.connect(func() -> void: UiSounds.click())
	_race_btn.pressed.connect(_on_play)
	col.add_child(_race_btn)
	_text_nodes.append([_race_btn, "menu.race"])

	# Bottom centre: car identity and the orbit hint.
	var plate := VBoxContainer.new()
	plate.name = "CarPlate"
	plate.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_theme_constant_override("separation", 2)
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.anchor_top = 1.0
	plate.anchor_bottom = 1.0
	plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	plate.offset_bottom = -eyb
	plate.offset_left = MSTheme.px(40) if not MSTheme.phone else -160.0
	plate.offset_right = plate.offset_left
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fg.add_child(plate)
	_intro_items.append(plate)
	_car_class = MSTheme.make_label("", "tracked", MSTheme.px(13), MSTheme.RED)
	_car_class.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(_car_class)
	_car_name = MSTheme.make_label("", "slant", MSTheme.px(40), MSTheme.PEARL)
	_car_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(_car_name)
	_hint = MSTheme.make_label("", "tracked", MSTheme.px(12), MSTheme.STEEL)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = stage != null
	plate.add_child(_hint)

	_version = MSTheme.make_label("", "tracked", 12, MSTheme.tint(MSTheme.STEEL, 0.7))
	_version.name = "Version"
	_version.anchor_left = 1.0
	_version.anchor_right = 1.0
	_version.anchor_top = 1.0
	_version.anchor_bottom = 1.0
	_version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_version.offset_right = -exr
	_version.offset_bottom = -(ins.w + 18.0)
	_version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fg.add_child(_version)

	_toast = MSTheme.make_label("", "bold", MSTheme.px(22), MSTheme.PEARL, true)
	_toast.name = "Toast"
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = ey + MSTheme.button_h() * 1.6
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fg.add_child(_toast)

	# Focus: the nav column and PLAY reach each other with left/right.
	for b: Button in _nav_btns:
		b.focus_neighbor_right = _race_btn.get_path()
	_race_btn.focus_neighbor_left = _career_btn.get_path()
	_race_btn.focus_neighbor_top = _profile_btn.get_path()
	_profile_btn.focus_neighbor_bottom = _race_btn.get_path()


func _stat_box(parent: Container, cap_key: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cap: Label = MSTheme.make_label("", "tracked", MSTheme.px(12), MSTheme.STEEL)
	box.add_child(cap)
	_text_nodes.append([cap, cap_key])
	parent.add_child(box)
	return box


## Navigation entry: big Anton capitals on no plate; hover lifts a graphite plate, focus adds the red edge.
func _nav_button(parent: Container, key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.name = key.get_slice(".", 1).capitalize().replace(" ", "")
	b.custom_minimum_size = Vector2(MSTheme.px(NAV_W) if not MSTheme.phone else 560.0, maxf(NAV_H_PX, MSTheme.button_h()))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", MSTheme.font("display"))
	b.add_theme_font_size_override("font_size", MSTheme.px(NAV_PX))
	var clear: StyleBoxFlat = MSTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	clear.content_margin_left = MSTheme.px(18)
	var hover: StyleBoxFlat = MSTheme.edged(MSTheme.tint(MSTheme.GRAPHITE_3, 0.8), MSTheme.tint(MSTheme.TITANIUM, 0.6), 3)
	hover.content_margin_left = MSTheme.px(18)
	var focus: StyleBoxFlat = MSTheme.edged(MSTheme.tint(MSTheme.GRAPHITE_2, 0.85), MSTheme.RED, 4)
	focus.content_margin_left = MSTheme.px(18)
	focus.draw_center = true
	b.add_theme_stylebox_override("normal", clear)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", focus)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", MSTheme.tint(MSTheme.PEARL, 0.86))
	b.add_theme_color_override("font_hover_color", MSTheme.PEARL)
	b.add_theme_color_override("font_focus_color", MSTheme.PEARL)
	b.pressed.connect(func() -> void: UiSounds.click())
	b.pressed.connect(handler)
	parent.add_child(b)
	_nav_btns.append(b)
	_intro_items.append(b)
	_text_nodes.append([b, key])
	return b


## Elements fade in and rise, staggered. Runs one frame late so anchored panels have their final size and position.
func _play_intro() -> void:
	for c: Control in _intro_items:
		c.modulate.a = 0.0
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	for i: int in _intro_items.size():
		var c: Control = _intro_items[i]
		if not is_instance_valid(c):
			continue
		var tw: Tween = create_tween()
		tw.tween_interval(INTRO_STAGGER_S * float(i))
		tw.tween_property(c, "modulate:a", 1.0, INTRO_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if c.get_parent() is Container:
			continue  # a container child cannot move on its own
		var y0: float = c.position.y
		c.position.y = y0 + INTRO_RISE_PX
		tw.parallel().tween_property(c, "position:y", y0, INTRO_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Replaces the showroom / backdrop with a 3D scene rendered through a SubViewport behind the UI.
func set_backdrop(node: Node) -> void:
	for c: Node in _holder.get_children():
		c.queue_free()
	if node == null:
		_backdrop.visible = _stage_box == null  # no shader pass under the opaque showroom
		if _stage_box != null:
			_stage_box.visible = true
		return
	_backdrop.visible = false
	if _stage_box != null:
		_stage_box.visible = false
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


# --- data ----------------------------------------------------------------------------------------

## The next career event to play: the first unlocked ladder event without three stars; else the first unlocked open
## event without three stars; else the last unlocked event. "" only with an empty catalog.
static func featured_event_id() -> String:
	var last: String = ""
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		if not GameState.is_event_unlocked(id):
			continue
		last = id
		if not EventCatalog.is_open(id) and GameState.event_stars(id) < GameState.MAX_STARS:
			return id
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		if EventCatalog.is_open(id) and GameState.event_stars(id) < GameState.MAX_STARS:
			return id
	return last


## Place of an event for its caption (the career screen groups pursuit events apart; the place stays geographic).
static func place_of(id: String) -> String:
	return str(EventCatalog.find(id).get("place", "arden"))


## {district index (career screen order): [stars earned, stars possible]} over every event.
static func district_progress() -> Dictionary:
	var out: Dictionary = {}
	for d: int in CAREER_SCREEN.DISTRICT_COUNT:
		out[d] = [0, 0]
	for i: int in EventCatalog.count():
		var id: String = EventCatalog.id_at(i)
		var d: int = CAREER_SCREEN.district_of(id)
		out[d][0] += GameState.event_stars(id)
		out[d][1] += GameState.MAX_STARS
	return out


## [rep of the previous unlock, rep of the next unlock, car id of the next unlock]; next is -1 when all are open.
static func rep_window(rep: int) -> Array:
	var prev: int = 0
	var next: int = -1
	var next_id: String = ""
	for id: String in CarCatalog.available_ids():
		var need: int = CarCatalog.rep_needed(id)
		if need <= rep:
			prev = maxi(prev, need)
		elif next < 0 or need < next:
			next = need
			next_id = id
	return [prev, next, next_id]


static func _car_display_name(id: String) -> String:
	var path: String = CarCatalog.spec_path(id)
	if ResourceLoader.exists(path):
		var spec: CarSpec = load(path) as CarSpec
		if spec != null:
			return spec.display_name
	return id


func _event_meta(id: String) -> String:
	var ev: Dictionary = EventCatalog.find(id)
	var parts: Array[String] = []
	parts.append(I18n.t("place." + place_of(id)))
	parts.append(I18n.t("tod." + str(ev.get("tod", "night"))))
	var mode: String = EventCatalog.mode_of(id)
	if bool(ev.get("pursuit", false)):
		parts.append(I18n.t("menu.mode_pursuit"))
	elif mode == RaceConfig.MODE_DRIFT:
		parts.append(I18n.t("mode.drift"))
	elif mode == RaceConfig.MODE_ELIMINATION:
		parts.append(I18n.t("mode.elimination"))
	elif EventCatalog.is_time_event(id):
		parts.append(I18n.t("menu.mode_time_trial"))
	if mode != RaceConfig.MODE_DRIFT:
		var laps: int = int(ev.get("laps", 1))
		parts.append(I18n.t("menu.one_lap") if laps == 1 else "%d %s" % [laps, I18n.t("event.laps")])
	var rivals: int = (ev.get("skills", []) as Array).size()
	if rivals > 0:
		parts.append("%d %s" % [rivals, I18n.t("event.rivals")])
	return "  ·  ".join(parts)


func _money(v: int) -> String:
	return I18n.t("garage.money").replace("%d", RaceHUD.group_int(v))


func _refresh_text() -> void:
	for pair: Array in _text_nodes:
		var n: Object = pair[0]
		if n is Button:
			(n as Button).text = I18n.t(pair[1])
		elif n is Label:
			(n as Label).text = I18n.t(pair[1])
	_hint.text = I18n.t("menu.drag_hint")
	_districts_title.text = I18n.t("menu.districts")
	_version.text = I18n.t("menu.version") % str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_refresh_stats()


func _refresh_stats() -> void:
	var rep: int = GameState.get_rep()
	_rep_val.text = RaceHUD.group_int(rep)
	var w: Array = rep_window(rep)
	if int(w[1]) < 0:
		_rep_next.text = I18n.t("menu.all_unlocked")
		_rep_bar.value = 1.0
	else:
		_rep_next.text = I18n.t("menu.next_unlock") % RaceHUD.group_int(int(w[1]))
		_rep_bar.value = clampf(float(rep - int(w[0])) / float(maxi(int(w[1]) - int(w[0]), 1)), 0.0, 1.0)
	_cash_val.text = _money(GameState.get_cash())
	_stars_val.text = "%d / %d" % [GameState.total_stars(), EventCatalog.count() * GameState.MAX_STARS]
	var prog: Dictionary = district_progress()
	var earned: int = 0
	var possible: int = 0
	for row: Array in _district_rows:
		var p: Array = prog.get(row[0], [0, 0])
		(row[1] as Label).text = I18n.t(CAREER_SCREEN.DISTRICT_KEYS[int(row[0])])
		(row[2] as Label).text = "%d / %d" % [int(p[0]), int(p[1])]
		(row[3] as ProgressBar).value = float(p[0]) / float(maxi(int(p[1]), 1))
		earned += int(p[0])
		possible += int(p[1])
	_districts_title.text = I18n.t("menu.districts") + "  ·  " + (I18n.t("menu.career_pct") % roundi(100.0 * float(earned) / float(maxi(possible, 1))))
	_featured_id = featured_event_id()
	var has_event: bool = _featured_id != ""
	_race_btn.disabled = not has_event
	if has_event:
		_f_caption.text = I18n.t("menu.featured")
		_f_name.text = I18n.t(EventCatalog.name_key(_featured_id))
		_f_meta.text = _event_meta(_featured_id)
		_f_stars.call("set_earned", GameState.event_stars(_featured_id))
		var rw: Dictionary = EventCatalog.win_rewards(_featured_id)
		_f_reward.text = "+%s   +%s %s" % [_money(int(rw["cash"])), RaceHUD.group_int(int(rw["rep"])), I18n.t("results.reward_rep")]
	var car_id: String = CarCatalog.race_car_id()
	_car_name.text = _car_display_name(car_id)
	_car_class.text = GarageText.t("garage.class_" + CarCatalog.class_id(car_id))
	if stage != null and str(stage.get("car_id")) != car_id:
		stage.call("show_car", car_id)
	if _profile_card != null:
		_fill_profile()


func _on_settings_changed(section: String) -> void:
	if section == Settings.SECTION_GENERAL:
		_refresh_text()


# --- profile card --------------------------------------------------------------------------------

## Real numbers only: rep, cash, stars, cars owned, events finished, events with three stars.
func open_profile() -> void:
	if _profile_card != null:
		return
	var shade := ColorRect.new()
	shade.name = "Profile"
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_profile_card = shade
	var panel := PanelContainer.new()
	var sb: StyleBoxFlat = MSTheme.box(MSTheme.GRAPHITE_2, MSTheme.tint(MSTheme.TITANIUM, 0.2))
	sb.border_width_top = 3
	sb.border_color = MSTheme.RED
	sb.content_margin_left = MSTheme.px(40)
	sb.content_margin_right = MSTheme.px(40)
	sb.content_margin_top = MSTheme.px(32)
	sb.content_margin_bottom = MSTheme.px(32)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(MSTheme.px(640), 0.0)
	shade.add_child(panel)
	var col := VBoxContainer.new()
	col.name = "Rows"
	col.add_theme_constant_override("separation", MSTheme.px(14))
	panel.add_child(col)
	var title: Label = MSTheme.make_label(I18n.t("menu.profile"), "display", MSTheme.px(48), MSTheme.PEARL)
	col.add_child(title)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", MSTheme.px(48))
	grid.add_theme_constant_override("v_separation", MSTheme.px(12))
	col.add_child(grid)
	var close := Button.new()
	close.name = "Close"
	close.text = I18n.t("menu.close")
	close.custom_minimum_size = Vector2(0.0, MSTheme.button_h())
	close.pressed.connect(_close_profile)
	col.add_child(close)
	var rec := Button.new()
	rec.name = "OpenRecords"
	rec.text = I18n.t("menu.records")
	rec.custom_minimum_size = Vector2(0.0, MSTheme.button_h())
	rec.pressed.connect(_on_records)
	col.add_child(rec)
	close.focus_neighbor_top = rec.get_path()
	close.focus_neighbor_bottom = rec.get_path()
	rec.focus_neighbor_top = close.get_path()
	rec.focus_neighbor_bottom = close.get_path()
	for b: Button in [close, rec]:
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()
	_set_background_focus(false)
	_fill_profile()
	close.grab_focus()


## While the profile card is open, nothing behind it can take keyboard or gamepad focus.
func _set_background_focus(on: bool) -> void:
	var btns: Array[Button] = _nav_btns.duplicate()
	btns.append_array([_race_btn, _profile_btn])
	for b: Button in btns:
		b.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE


func _fill_profile() -> void:
	var grid: GridContainer = _profile_card.find_child("Grid", true, false) as GridContainer
	for c: Node in grid.get_children():
		c.queue_free()
	var owned: int = 0
	var cars: Array[String] = CarCatalog.available_ids()
	for id: String in cars:
		if GameState.has_car(id):
			owned += 1
	var finished: int = 0
	var perfect: int = 0
	for i: int in EventCatalog.count():
		var s: int = GameState.event_stars(EventCatalog.id_at(i))
		finished += 1 if s > 0 else 0
		perfect += 1 if s >= GameState.MAX_STARS else 0
	var rows: Array = [
		["results.reward_rep", RaceHUD.group_int(GameState.get_rep())],
		["results.reward_cash", _money(GameState.get_cash())],
		["results.reward_stars", "%d / %d" % [GameState.total_stars(), EventCatalog.count() * GameState.MAX_STARS]],
		["menu.cars_owned", "%d / %d" % [owned, cars.size()]],
		["menu.events_done", "%d / %d" % [finished, EventCatalog.count()]],
		["menu.events_perfect", "%d" % perfect],
	]
	for r: Array in rows:
		grid.add_child(MSTheme.make_label(I18n.t(r[0]), "tracked", MSTheme.px(16), MSTheme.STEEL))
		grid.add_child(MSTheme.make_label(str(r[1]), "digits", MSTheme.px(26), MSTheme.PEARL))


func _close_profile() -> void:
	if _profile_card != null:
		_profile_card.queue_free()
		_profile_card = null
		_set_background_focus(true)
		_profile_btn.grab_focus()


# --- actions -------------------------------------------------------------------------------------

## PLAY: the featured event's RaceConfig straight to the race scene (same hand-off as the career screen's START).
func _on_play() -> void:
	if _featured_id == "" or not GameState.is_event_unlocked(_featured_id):
		_open(EVENT_SELECT_SCENE)
		return
	nav.call(LoadingScreen.SCENE, LoadingScreen.params_for(RACE_SCENE, {RaceScene.CONFIG_PARAM: EventCatalog.config_for(_featured_id)}))


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


func _on_career() -> void:
	_open(EVENT_SELECT_SCENE)


func _on_garage() -> void:
	_open(GARAGE_SCENE)


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
