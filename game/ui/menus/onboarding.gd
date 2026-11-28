class_name OnboardingScreen
extends Control
## First launch only (main menu sends a player here while GameState.is_onboarded() is false). Two steps:
## 1. language, preselected from the OS locale (Turkish phone: TR); 2. the touch controls, drawn by the real
## touch layout, then START goes straight into the first career race (Ortakoy Night) with the in-race hints.
## store: the GameState to write to (null = the autoload). Tests pass a temporary profile.

const RACE_SCENE: String = "res://race/race_scene.tscn"
const TOUCH_SCENE: String = "res://vehicles/touch/touch_controls.tscn"
const FIRST_EVENT: String = "ortakoy_night"
const STEP_LANGUAGE: int = 0
const STEP_CONTROLS: int = 1
const EDGE_PX: float = 96.0
const EDGE_Y_PX: float = 56.0
const TITLE_PX: int = 40
const BODY_PX: int = 24
const BODY_W: float = 720.0
const LANG_BTN_W: float = 300.0
const LANG_KEYS: Dictionary = {"tr": "settings.lang_tr", "en": "settings.lang_en"}

var store: Node = null
var nav: Callable = Router.goto  ## scene change; tests swap in a recorder so the runner scene stays
var step: int = STEP_LANGUAGE

var _backdrop: MenuBackdrop
var _col: VBoxContainer
var _logo: Control
var _title: Label
var _body: Label
var _lang_row: HBoxContainer
var _lang_btns: Dictionary = {}  ## language code -> Button
var _next_btn: Button
var _touch: Node = null


## The language the first screen starts on: Turkish when the device is set to Turkish, English otherwise.
static func default_language() -> String:
	return "tr" if OS.get_locale_language() == "tr" else "en"


func _ready() -> void:
	theme = MSTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop = MenuBackdrop.new(0.6)
	add_child(_backdrop)
	var ins: Vector4 = MSTheme.safe_insets()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(ins.x + EDGE_PX))
	margin.add_theme_constant_override("margin_top", int(ins.y + EDGE_Y_PX))
	margin.add_theme_constant_override("margin_right", int(ins.z + EDGE_PX))
	margin.add_theme_constant_override("margin_bottom", int(ins.w + EDGE_Y_PX))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	# Content sits in the top part of the screen: the touch pad (step 2) takes the lower part.
	_col = VBoxContainer.new()
	_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_col.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 3))
	margin.add_child(_col)
	_logo = Logotype.new(MSTheme.k() * 0.6, true)
	_col.add_child(_logo)
	_title = MSTheme.make_label("", "display", MSTheme.px(TITLE_PX), MSTheme.TEXT)
	_col.add_child(_title)
	_body = MSTheme.make_label("", "body", MSTheme.px(BODY_PX), MSTheme.MUTED)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(BODY_W * MSTheme.k(), 0.0)
	_col.add_child(_body)
	_lang_row = HBoxContainer.new()
	_lang_row.add_theme_constant_override("separation", int(MSTheme.GRID_PX * 2))
	_col.add_child(_lang_row)
	for code: String in Settings.LANGUAGES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(LANG_BTN_W, MSTheme.button_h())
		b.text = I18n.t(LANG_KEYS[code])
		b.pressed.connect(func() -> void: UiSounds.click())
		b.pressed.connect(_on_language.bind(code))
		_lang_row.add_child(b)
		_lang_btns[code] = b
	_next_btn = Button.new()
	_next_btn.custom_minimum_size = Vector2(MSTheme.BUTTON_MIN_W, MSTheme.button_h())
	_next_btn.theme_type_variation = &"PrimaryButton"
	_next_btn.pressed.connect(func() -> void: UiSounds.click())
	_next_btn.pressed.connect(_on_next)
	_col.add_child(_next_btn)
	Settings.set_language(default_language())
	Settings.changed.connect(_on_settings_changed)
	set_step(STEP_LANGUAGE)
	_next_btn.grab_focus()


func _exit_tree() -> void:
	if is_instance_valid(_touch):
		_touch.queue_free()


## Shows one step. Public so captures can open the second screen directly.
func set_step(s: int) -> void:
	step = s
	_lang_row.visible = step == STEP_LANGUAGE
	# Step 2 draws the real touch pads over the upper and middle screen: the text moves to the free bottom band.
	_logo.visible = step == STEP_LANGUAGE
	_col.size_flags_vertical = Control.SIZE_SHRINK_END if step == STEP_CONTROLS else Control.SIZE_FILL
	_col.add_theme_constant_override("separation", int(MSTheme.GRID_PX * (1.5 if step == STEP_CONTROLS else 3.0)))
	if step == STEP_CONTROLS:
		_show_touch_layout()
	elif is_instance_valid(_touch):
		_touch.queue_free()
		_touch = null
	_refresh_text()


func _show_touch_layout() -> void:
	if is_instance_valid(_touch):
		return
	var t: Node = (load(TOUCH_SCENE) as PackedScene).instantiate()
	t.set("force_visible", true)  # the real layout, also on a desktop preview
	add_child(t)
	_touch = t


func _on_language(code: String) -> void:
	Settings.set_language(code)  # the whole screen refreshes through Settings.changed


func _on_settings_changed(section: String) -> void:
	if section == Settings.SECTION_GENERAL:
		_refresh_text()


func _on_next() -> void:
	if step == STEP_LANGUAGE:
		set_step(STEP_CONTROLS)
	else:
		_start_first_race()


## Marks onboarding done (saved) and goes straight to the first race.
func _start_first_race() -> void:
	var gs: Node = store if store != null else GameState
	gs.set_onboarded()
	nav.call(LoadingScreen.SCENE, LoadingScreen.params_for(RACE_SCENE, {RaceScene.CONFIG_PARAM: EventCatalog.config_for(FIRST_EVENT)}))


func _refresh_text() -> void:
	# One primary per screen: CONTINUE. The chosen language is marked in red text instead.
	for code: String in _lang_btns:
		var b: Button = _lang_btns[code]
		b.add_theme_color_override("font_color", MSTheme.RED if code == Settings.language else MSTheme.TEXT)
	if step == STEP_LANGUAGE:
		_title.text = I18n.t("onboard.title")
		_body.text = I18n.t("onboard.lang_body")
		_next_btn.text = I18n.t("onboard.continue")
	else:
		_title.text = I18n.t("onboard.controls_title")
		_body.text = I18n.t("onboard.controls_body")
		_next_btn.text = I18n.t("onboard.start")
