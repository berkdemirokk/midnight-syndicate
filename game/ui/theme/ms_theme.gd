class_name MSTheme
extends RefCounted
## Shared look for every menu and the race HUD. Tokens and rules: docs/design/UI_STYLE.md.
## Fonts are Godot's built-in font wrapped in FontVariation; shapes are StyleBoxFlat and drawn textures.

const BG: Color = Color(0.039, 0.051, 0.078)
const PANEL_BG: Color = Color(0.067, 0.094, 0.153, 0.82)
const CYAN: Color = Color(0.098, 0.902, 1.0)
const MAGENTA: Color = Color(1.0, 0.169, 0.839)
const AMBER: Color = Color(1.0, 0.761, 0.239)
const DANGER: Color = Color(1.0, 0.231, 0.188)
const GOOD: Color = Color(0.263, 1.0, 0.478)  ## ahead / positive (HUD lap delta); DANGER is behind
const TEXT: Color = Color(0.949, 0.961, 0.98)
const MUTED: Color = Color(0.541, 0.580, 0.651)
const BORDER: Color = Color(0.098, 0.902, 1.0, 0.45)
const OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.6)
const DISABLED_BG: Color = Color(0.1, 0.1, 0.12, 0.6)

const GRID_PX: int = 8
const SKEW_RATIO: float = 0.2126  ## tan(12 deg): horizontal shift per px of height
const EMBOLDEN: float = 0.6
const TRACKING_PX: int = 2
const HUD_OUTLINE_PX: int = 4
const ICON_PX: int = 20
const CHECK_PX: int = 28  ## checkbox square, larger than the slider grabber so on/off reads at a glance
const BUTTON_MIN_W: float = 360.0
const BUTTON_MIN_H: float = 64.0
const BUTTON_PAD_X: float = 24.0
const BUTTON_PAD_Y: float = 12.0
const FOCUS_PX: int = 2
const SIZE_BODY: int = 24
const SIZE_BUTTON: int = 28
const SIZE_SMALL: int = 18
const SIZE_HEAD: int = 40
const SAFE_MARGIN_PX: float = 24.0

## Touch phones get larger type and 44 pt touch targets. At the 1080 px base height an iPhone landscape screen is
## about 0.36 pt per px, so 44 pt is 124 px and 11 pt text is 30 px. Desktop keeps the base sizes (boost 1.0).
const PHONE_BOOST: float = 1.5
const PHONE_BUTTON_H: float = 124.0  ## 44.6 pt on a 393 pt tall iPhone screen
const PRIMARY_FILL: Color = Color(0.098, 0.902, 1.0, 0.94)
const PLATE_BG: Color = Color(0.027, 0.039, 0.071, 0.66)  ## backing plate under HUD clusters, readable on bright signage

static var phone: bool = OS.has_feature("mobile")
static var _theme: Theme = null
static var _fonts: Dictionary = {}
static var _textures: Dictionary = {}


## Switches phone layout on or off (tests and captures use it to preview the iPhone build on desktop).
static func set_phone(on: bool) -> void:
	if phone != on:
		phone = on
		_theme = null


static func k() -> float:
	return PHONE_BOOST if phone else 1.0


## Pixel size scaled for the current device class.
static func px(v: float) -> int:
	return roundi(v * k())


static func button_h() -> float:
	return PHONE_BUTTON_H if phone else BUTTON_MIN_H


static func tint(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## kind: "body", "bold", "digits" (bold, tabular figures), "slant" (bold, leaning right), "tracked" (bold, spaced).
static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind] as Font
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	match kind:
		"bold":
			f.variation_embolden = EMBOLDEN
		"digits":
			f.variation_embolden = EMBOLDEN
			f.opentype_features = {"tnum": 1}
		"slant":
			f.variation_embolden = EMBOLDEN
			f.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-SKEW_RATIO, 1.0), Vector2.ZERO)
		"tracked":
			f.variation_embolden = EMBOLDEN
			f.spacing_glyph = TRACKING_PX
	_fonts[kind] = f
	return f


## Slanted panel box: flat fill, 1 px border, parallelogram skew.
static func box(bg: Color, border: Color, border_px: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_px)
	sb.skew = Vector2(-SKEW_RATIO * 0.5, 0.0)
	sb.content_margin_left = BUTTON_PAD_X * (1.0 + (k() - 1.0) * 0.5)
	sb.content_margin_right = sb.content_margin_left
	sb.content_margin_top = BUTTON_PAD_Y
	sb.content_margin_bottom = BUTTON_PAD_Y
	return sb


## Unslanted card (settings, wide tables inside scroll areas, where a slanted edge would be clipped).
static func card(bg: Color, border: Color, border_px: int = 1) -> StyleBoxFlat:
	var sb: StyleBoxFlat = box(bg, border, border_px)
	sb.skew = Vector2.ZERO
	return sb


static func make_label(text: String, kind: String, px: int, color: Color = TEXT, outlined: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", HUD_OUTLINE_PX if outlined else 0)
	return l


static func disc_texture(px: int, col: Color) -> ImageTexture:
	var key: String = "disc_%d_%s" % [px, col.to_html()]
	if _textures.has(key):
		return _textures[key] as ImageTexture
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c: float = px * 0.5
	for y: int in px:
		for x: int in px:
			if Vector2(x + 0.5 - c, y + 0.5 - c).length() <= c:
				img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## Square checkbox texture: filled when on, outlined when off.
static func check_texture(px: int, filled: bool) -> ImageTexture:
	var key: String = "check_%d_%s" % [px, str(filled)]
	if _textures.has(key):
		return _textures[key] as ImageTexture
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in px:
		for x: int in px:
			var edge: bool = x < FOCUS_PX or y < FOCUS_PX or x >= px - FOCUS_PX or y >= px - FOCUS_PX
			if filled or edge:
				img.set_pixel(x, y, CYAN)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## Safe-area insets in window pixels as (left, top, right, bottom). Zero when the platform reports none.
static func safe_insets() -> Vector4:
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var screen: Vector2i = DisplayServer.screen_get_size()
	if safe.size.x <= 0 or safe.size.y <= 0 or screen.x <= 0 or screen.y <= 0:
		return Vector4.ZERO
	return Vector4(
		maxf(float(safe.position.x), 0.0),
		maxf(float(safe.position.y), 0.0),
		maxf(float(screen.x - safe.end.x), 0.0),
		maxf(float(screen.y - safe.end.y), 0.0))


static func build() -> Theme:
	if _theme != null:
		return _theme
	var th := Theme.new()
	th.default_font = font("body")
	th.default_font_size = px(SIZE_BODY)
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_outline_color", "Label", OUTLINE)
	th.set_constant("outline_size", "Label", 0)

	var b_normal: StyleBoxFlat = box(PANEL_BG, BORDER)
	var b_hover: StyleBoxFlat = box(tint(CYAN, 0.16), CYAN)
	b_hover.border_width_left = 6
	var b_pressed: StyleBoxFlat = box(tint(CYAN, 0.32), CYAN)
	b_pressed.border_width_left = 6
	var b_disabled: StyleBoxFlat = box(DISABLED_BG, tint(MUTED, 0.3))
	var b_focus := StyleBoxFlat.new()
	b_focus.draw_center = false
	b_focus.set_border_width_all(FOCUS_PX)
	b_focus.border_color = MAGENTA
	b_focus.skew = Vector2(-SKEW_RATIO * 0.5, 0.0)
	th.set_stylebox("normal", "Button", b_normal)
	th.set_stylebox("hover", "Button", b_hover)
	th.set_stylebox("pressed", "Button", b_pressed)
	th.set_stylebox("disabled", "Button", b_disabled)
	th.set_stylebox("focus", "Button", b_focus)
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", CYAN)
	th.set_color("font_pressed_color", "Button", TEXT)
	th.set_color("font_focus_color", "Button", TEXT)
	th.set_color("font_disabled_color", "Button", MUTED)
	th.set_font("font", "Button", font("bold"))
	th.set_font_size("font_size", "Button", px(SIZE_BUTTON))

	# Primary call to action: solid cyan, dark label. One per screen (RACE, START, NEXT EVENT).
	th.set_type_variation("PrimaryButton", "Button")
	th.set_stylebox("normal", "PrimaryButton", box(PRIMARY_FILL, CYAN))
	th.set_stylebox("hover", "PrimaryButton", box(Color(0.45, 0.95, 1.0, 1.0), TEXT))
	th.set_stylebox("pressed", "PrimaryButton", box(Color(0.06, 0.62, 0.72, 1.0), CYAN))
	th.set_stylebox("disabled", "PrimaryButton", b_disabled)
	th.set_color("font_color", "PrimaryButton", BG)
	th.set_color("font_hover_color", "PrimaryButton", BG)
	th.set_color("font_pressed_color", "PrimaryButton", TEXT)
	th.set_color("font_focus_color", "PrimaryButton", BG)
	th.set_color("font_disabled_color", "PrimaryButton", MUTED)

	th.set_stylebox("panel", "PanelContainer", box(PANEL_BG, BORDER))
	th.set_stylebox("panel", "Panel", box(PANEL_BG, BORDER))

	th.set_stylebox("normal", "OptionButton", b_normal)
	th.set_stylebox("hover", "OptionButton", b_hover)
	th.set_stylebox("pressed", "OptionButton", b_pressed)
	th.set_stylebox("focus", "OptionButton", b_focus)
	th.set_stylebox("disabled", "OptionButton", b_disabled)
	th.set_color("font_color", "OptionButton", TEXT)
	th.set_color("font_hover_color", "OptionButton", CYAN)
	th.set_color("font_focus_color", "OptionButton", TEXT)
	th.set_font("font", "OptionButton", font("bold"))
	th.set_font_size("font_size", "OptionButton", px(SIZE_BUTTON))
	th.set_stylebox("panel", "PopupMenu", box(BG, CYAN))
	th.set_stylebox("hover", "PopupMenu", b_hover)
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", CYAN)
	th.set_font("font", "PopupMenu", font("body"))
	th.set_font_size("font_size", "PopupMenu", px(SIZE_BODY))

	var slider_bg: StyleBoxFlat = box(Color(1, 1, 1, 0.08), tint(MUTED, 0.0), 0)
	slider_bg.content_margin_top = 5.0
	slider_bg.content_margin_bottom = 5.0
	slider_bg.content_margin_left = 0.0
	slider_bg.content_margin_right = 0.0
	var slider_fill: StyleBoxFlat = box(tint(CYAN, 0.9), tint(CYAN, 0.0), 0)
	slider_fill.content_margin_top = 5.0
	slider_fill.content_margin_bottom = 5.0
	slider_fill.content_margin_left = 0.0
	slider_fill.content_margin_right = 0.0
	th.set_stylebox("slider", "HSlider", slider_bg)
	th.set_stylebox("grabber_area", "HSlider", slider_fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	th.set_icon("grabber", "HSlider", disc_texture(px(ICON_PX + 8), CYAN))
	th.set_icon("grabber_highlight", "HSlider", disc_texture(px(ICON_PX + 8), TEXT))
	th.set_constant("grabber_offset", "HSlider", 0)

	th.set_icon("checked", "CheckButton", check_texture(px(CHECK_PX + 8), true))
	th.set_icon("unchecked", "CheckButton", check_texture(px(CHECK_PX + 8), false))
	th.set_icon("checked", "CheckBox", check_texture(px(CHECK_PX + 8), true))
	th.set_icon("unchecked", "CheckBox", check_texture(px(CHECK_PX + 8), false))
	th.set_color("font_color", "CheckButton", TEXT)
	th.set_color("font_hover_color", "CheckButton", CYAN)
	th.set_color("font_focus_color", "CheckButton", TEXT)
	th.set_font("font", "CheckButton", font("bold"))
	th.set_font_size("font_size", "CheckButton", px(SIZE_BUTTON))
	var none: StyleBoxFlat = box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	none.content_margin_left = 0.0
	none.content_margin_right = 0.0
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		th.set_stylebox(state, "CheckButton", none)
	th.set_stylebox("focus", "CheckButton", b_focus)

	th.set_stylebox("background", "ProgressBar", slider_bg)
	th.set_stylebox("fill", "ProgressBar", slider_fill)

	th.set_constant("separation", "VBoxContainer", GRID_PX * 2)
	th.set_constant("separation", "HBoxContainer", GRID_PX * 2)
	th.set_constant("h_separation", "GridContainer", GRID_PX * 2)
	th.set_constant("v_separation", "GridContainer", GRID_PX)
	_theme = th
	return th
