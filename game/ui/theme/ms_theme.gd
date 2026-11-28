class_name MSTheme
extends RefCounted
## STREET EMPIRE look for every menu and the race HUD. Tokens and rules: docs/design/UI_STYLE.md and
## docs/brand/BRAND_GUIDELINES.md. Fonts are OFL files in assets/branding/fonts (Anton display, Manrope UI) wrapped in
## FontVariation; shapes are StyleBoxFlat with chamfered corners and drawn textures.
## The class keeps its old name and constant names so every screen restyles through this one file. The old colour
## names are aliases of the brand tokens: CYAN is the accent (racing red), MAGENTA the focus ring (pearl).

# Brand tokens (docs/brand/BRAND_GUIDELINES.md).
const GRAPHITE: Color = Color(0.063, 0.071, 0.086)  ## #101216 base
const GRAPHITE_2: Color = Color(0.094, 0.106, 0.129)  ## #181B21 raised surface
const GRAPHITE_3: Color = Color(0.141, 0.153, 0.180)  ## #24272E hover surface, tracks
const RED: Color = Color(0.941, 0.267, 0.196)  ## #F04432 racing red: primary action, accent, progress
const RED_DEEP: Color = Color(0.722, 0.165, 0.110)  ## #B82A1C pressed red
const TITANIUM: Color = Color(0.769, 0.784, 0.808)  ## #C4C8CE secondary text, hairlines, inactive icons
const PEARL: Color = Color(0.957, 0.957, 0.957)  ## #F4F4F4 primary text, focus ring
const STEEL: Color = Color(0.557, 0.580, 0.616)  ## #8E949D captions (5.9:1 on graphite)
const GOLD: Color = Color(0.914, 0.722, 0.337)  ## #E9B856 currency, stars (sparingly)
const GO: Color = Color(0.333, 0.780, 0.557)  ## #55C78E owned, gained, personal best

# Old names, kept so every screen picks up the brand without a rewrite.
const BG: Color = GRAPHITE
const PANEL_BG: Color = Color(0.094, 0.106, 0.129, 0.90)
const CYAN: Color = RED
const MAGENTA: Color = PEARL
const AMBER: Color = GOLD
const DANGER: Color = Color(1.0, 0.329, 0.251)  ## #FF5440 redline, wrong way, busted
const TEXT: Color = PEARL
const MUTED: Color = STEEL
const BORDER: Color = Color(0.769, 0.784, 0.808, 0.16)
const OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.55)
const DISABLED_BG: Color = Color(0.094, 0.106, 0.129, 0.55)

const GRID_PX: int = 8
const SKEW_RATIO: float = 0.1405  ## tan(8 deg): italic lean of display type and painted boards
const CHAMFER_PX: int = 10  ## cut corner on buttons and panels (top-right and bottom-left)
const EMBOLDEN: float = 0.0
const TRACKING_PX: int = 2
const HUD_OUTLINE_PX: int = 3
const ICON_PX: int = 20
const CHECK_PX: int = 28  ## checkbox square, larger than the slider grabber so on/off reads at a glance
const BUTTON_MIN_W: float = 360.0
const BUTTON_MIN_H: float = 64.0
const BUTTON_PAD_X: float = 28.0
const BUTTON_PAD_Y: float = 12.0
const FOCUS_PX: int = 2
const SIZE_BODY: int = 22
const SIZE_BUTTON: int = 24
const SIZE_SMALL: int = 16
const SIZE_HEAD: int = 44
const SAFE_MARGIN_PX: float = 24.0

## Touch phones get larger type and 44 pt touch targets. At the 1080 px base height an iPhone landscape screen is
## about 0.36 pt per px, so 44 pt is 124 px and 11 pt text is 30 px. Desktop keeps the base sizes (boost 1.0).
const PHONE_BOOST: float = 1.5
const PHONE_BUTTON_H: float = 124.0  ## 44.6 pt on a 393 pt tall iPhone screen
const PRIMARY_FILL: Color = RED
const PLATE_BG: Color = Color(0.039, 0.043, 0.051, 0.74)  ## backing plate under HUD clusters, readable on bright signage

const FONT_DIR: String = "res://assets/branding/fonts/"
const FONT_FILES: Dictionary = {
	"display": "Anton-Regular.ttf",
	"ui_medium": "Manrope-Medium.ttf",
	"ui_bold": "Manrope-Bold.ttf",
	"ui_heavy": "Manrope-ExtraBold.ttf",
}

static var phone: bool = OS.has_feature("mobile")
static var _theme: Theme = null
static var _fonts: Dictionary = {}
static var _files: Dictionary = {}
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


## One shipped font file, or Godot's fallback font when the file is missing (a stripped test checkout).
static func _file(id: String) -> Font:
	if _files.has(id):
		return _files[id] as Font
	var path: String = FONT_DIR + str(FONT_FILES[id])
	var f: Font = load(path) as Font if ResourceLoader.exists(path) else null
	if f == null:
		f = ThemeDB.fallback_font
	_files[id] = f
	return f


## kind:
##   "body"    Manrope Medium, running text
##   "bold"    Manrope ExtraBold, buttons and titles in the UI face
##   "digits"  Manrope ExtraBold with tabular figures (times, money, counters)
##   "tracked" Manrope Bold, spaced: captions and labels in capitals
##   "display" Anton, upright: headlines, big numbers (speed, position)
##   "slant"   Anton leaning 8 degrees: wordmark, hero titles
static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind] as Font
	var f := FontVariation.new()
	match kind:
		"bold":
			f.base_font = _file("ui_heavy")
		"digits":
			f.base_font = _file("ui_heavy")
			f.opentype_features = {"tnum": 1}
		"tracked":
			f.base_font = _file("ui_bold")
			f.spacing_glyph = TRACKING_PX
		"display":
			f.base_font = _file("display")
			f.spacing_glyph = 1
		"slant":
			f.base_font = _file("display")
			f.spacing_glyph = 1
			f.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-SKEW_RATIO, 1.0), Vector2.ZERO)
		_:
			f.base_font = _file("ui_medium")
	_fonts[kind] = f
	return f


## Panel box: flat fill, hairline border, top-right and bottom-left corners cut at 45 degrees (corner_detail 1 draws
## a radius as one straight segment). The old parallelogram skew is gone; the name stays for the callers.
static func box(bg: Color, border: Color, border_px: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_px)
	sb.corner_detail = 1
	sb.corner_radius_top_right = CHAMFER_PX
	sb.corner_radius_bottom_left = CHAMFER_PX
	sb.anti_aliasing = true
	sb.content_margin_left = BUTTON_PAD_X * (1.0 + (k() - 1.0) * 0.5)
	sb.content_margin_right = sb.content_margin_left
	sb.content_margin_top = BUTTON_PAD_Y
	sb.content_margin_bottom = BUTTON_PAD_Y
	return sb


## Square-cornered card (settings rows, wide tables inside scroll areas).
static func card(bg: Color, border: Color, border_px: int = 1) -> StyleBoxFlat:
	var sb: StyleBoxFlat = box(bg, border, border_px)
	sb.corner_radius_top_right = 2
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_top_left = 2
	sb.corner_radius_bottom_right = 2
	sb.corner_detail = 3
	return sb


## Accent edge: a box with a thick left border in `edge` (selected rows, the active tab, the featured card).
static func edged(bg: Color, edge: Color, edge_px: int = 4) -> StyleBoxFlat:
	var sb: StyleBoxFlat = box(bg, Color(edge.r, edge.g, edge.b, 0.0), 0)
	sb.border_color = edge
	sb.border_width_left = edge_px
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
			var d: float = Vector2(x + 0.5 - c, y + 0.5 - c).length()
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * clampf(c - d, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex


## Square checkbox texture: filled red with a pearl tick when on, a titanium outline when off.
static func check_texture(px: int, filled: bool) -> ImageTexture:
	var key: String = "check_%d_%s" % [px, str(filled)]
	if _textures.has(key):
		return _textures[key] as ImageTexture
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in px:
		for x: int in px:
			var edge: bool = x < FOCUS_PX or y < FOCUS_PX or x >= px - FOCUS_PX or y >= px - FOCUS_PX
			if filled:
				img.set_pixel(x, y, RED)
			elif edge:
				img.set_pixel(x, y, tint(TITANIUM, 0.7))
	if filled:
		# tick: short stroke down-right, long stroke up-right
		var s: float = float(px)
		for i: int in 200:
			var t: float = float(i) / 199.0
			var p: Vector2 = Vector2(0.24, 0.52).lerp(Vector2(0.42, 0.70), t / 0.35) if t < 0.35 else Vector2(0.42, 0.70).lerp(Vector2(0.78, 0.30), (t - 0.35) / 0.65)
			for oy: int in range(-1, 2):
				for ox: int in range(-1, 2):
					var q := Vector2i(int(p.x * s) + ox, int(p.y * s) + oy)
					if q.x >= 0 and q.y >= 0 and q.x < px and q.y < px:
						img.set_pixel(q.x, q.y, PEARL)
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

	# Secondary buttons: graphite plate, hairline; hover lifts the surface and draws a red left edge.
	var b_normal: StyleBoxFlat = box(PANEL_BG, BORDER)
	var b_hover: StyleBoxFlat = box(GRAPHITE_3, tint(TITANIUM, 0.35))
	b_hover.border_width_left = 4
	b_hover.border_color = tint(TITANIUM, 0.35)
	var b_pressed: StyleBoxFlat = box(GRAPHITE_2, RED)
	b_pressed.border_width_left = 4
	var b_disabled: StyleBoxFlat = box(DISABLED_BG, tint(STEEL, 0.18))
	var b_focus := StyleBoxFlat.new()
	b_focus.draw_center = false
	b_focus.set_border_width_all(FOCUS_PX)
	b_focus.border_color = PEARL
	b_focus.corner_detail = 1
	b_focus.corner_radius_top_right = CHAMFER_PX
	b_focus.corner_radius_bottom_left = CHAMFER_PX
	b_focus.expand_margin_left = 3.0
	b_focus.expand_margin_right = 3.0
	b_focus.expand_margin_top = 3.0
	b_focus.expand_margin_bottom = 3.0
	th.set_stylebox("normal", "Button", b_normal)
	th.set_stylebox("hover", "Button", b_hover)
	th.set_stylebox("pressed", "Button", b_pressed)
	th.set_stylebox("disabled", "Button", b_disabled)
	th.set_stylebox("focus", "Button", b_focus)
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", PEARL)
	th.set_color("font_pressed_color", "Button", PEARL)
	th.set_color("font_focus_color", "Button", PEARL)
	th.set_color("font_hover_pressed_color", "Button", PEARL)
	th.set_color("font_disabled_color", "Button", tint(STEEL, 0.7))
	th.set_font("font", "Button", font("bold"))
	th.set_font_size("font_size", "Button", px(SIZE_BUTTON))

	# Primary call to action: solid racing red, pearl label. One per screen (PLAY, START, NEXT EVENT).
	th.set_type_variation("PrimaryButton", "Button")
	th.set_stylebox("normal", "PrimaryButton", box(RED, RED, 0))
	th.set_stylebox("hover", "PrimaryButton", box(Color(1.0, 0.36, 0.29), Color(1.0, 0.36, 0.29), 0))
	th.set_stylebox("pressed", "PrimaryButton", box(RED_DEEP, RED_DEEP, 0))
	th.set_stylebox("disabled", "PrimaryButton", b_disabled)
	th.set_color("font_color", "PrimaryButton", PEARL)
	th.set_color("font_hover_color", "PrimaryButton", PEARL)
	th.set_color("font_pressed_color", "PrimaryButton", PEARL)
	th.set_color("font_focus_color", "PrimaryButton", PEARL)
	th.set_color("font_hover_pressed_color", "PrimaryButton", PEARL)
	th.set_color("font_disabled_color", "PrimaryButton", tint(STEEL, 0.7))

	# Quiet text button (BACK, links): no plate until hovered.
	th.set_type_variation("GhostButton", "Button")
	var ghost: StyleBoxFlat = box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	th.set_stylebox("normal", "GhostButton", ghost)
	th.set_stylebox("hover", "GhostButton", box(tint(PEARL, 0.06), Color(0, 0, 0, 0), 0))
	th.set_stylebox("pressed", "GhostButton", box(tint(PEARL, 0.10), Color(0, 0, 0, 0), 0))
	th.set_stylebox("disabled", "GhostButton", ghost)
	th.set_color("font_color", "GhostButton", TITANIUM)
	th.set_color("font_hover_color", "GhostButton", PEARL)
	th.set_color("font_focus_color", "GhostButton", PEARL)

	th.set_stylebox("panel", "PanelContainer", box(PANEL_BG, BORDER))
	th.set_stylebox("panel", "Panel", box(PANEL_BG, BORDER))

	th.set_stylebox("normal", "OptionButton", b_normal)
	th.set_stylebox("hover", "OptionButton", b_hover)
	th.set_stylebox("pressed", "OptionButton", b_pressed)
	th.set_stylebox("focus", "OptionButton", b_focus)
	th.set_stylebox("disabled", "OptionButton", b_disabled)
	th.set_color("font_color", "OptionButton", TEXT)
	th.set_color("font_hover_color", "OptionButton", PEARL)
	th.set_color("font_focus_color", "OptionButton", TEXT)
	th.set_font("font", "OptionButton", font("bold"))
	th.set_font_size("font_size", "OptionButton", px(SIZE_BUTTON))
	th.set_stylebox("panel", "PopupMenu", card(GRAPHITE_2, tint(TITANIUM, 0.25)))
	th.set_stylebox("hover", "PopupMenu", card(GRAPHITE_3, Color(0, 0, 0, 0), 0))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", PEARL)
	th.set_font("font", "PopupMenu", font("body"))
	th.set_font_size("font_size", "PopupMenu", px(SIZE_BODY))

	var slider_bg: StyleBoxFlat = card(tint(TITANIUM, 0.14), Color(0, 0, 0, 0), 0)
	slider_bg.content_margin_top = 3.0
	slider_bg.content_margin_bottom = 3.0
	slider_bg.content_margin_left = 0.0
	slider_bg.content_margin_right = 0.0
	var slider_fill: StyleBoxFlat = card(RED, Color(0, 0, 0, 0), 0)
	slider_fill.content_margin_top = 3.0
	slider_fill.content_margin_bottom = 3.0
	slider_fill.content_margin_left = 0.0
	slider_fill.content_margin_right = 0.0
	th.set_stylebox("slider", "HSlider", slider_bg)
	th.set_stylebox("grabber_area", "HSlider", slider_fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	th.set_icon("grabber", "HSlider", disc_texture(px(ICON_PX + 8), PEARL))
	th.set_icon("grabber_highlight", "HSlider", disc_texture(px(ICON_PX + 10), PEARL))
	th.set_constant("grabber_offset", "HSlider", 0)

	th.set_icon("checked", "CheckButton", check_texture(px(CHECK_PX + 8), true))
	th.set_icon("unchecked", "CheckButton", check_texture(px(CHECK_PX + 8), false))
	th.set_icon("checked", "CheckBox", check_texture(px(CHECK_PX + 8), true))
	th.set_icon("unchecked", "CheckBox", check_texture(px(CHECK_PX + 8), false))
	th.set_color("font_color", "CheckButton", TEXT)
	th.set_color("font_hover_color", "CheckButton", PEARL)
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

	# Slim scroll bars: 6 px wide (12 on a phone, still draggable), no padding from box().
	var bar_w: float = 3.0 * k()
	for sb_name: String in ["VScrollBar", "HScrollBar"]:
		var styles: Dictionary = {
			"scroll": tint(TITANIUM, 0.06), "grabber": tint(TITANIUM, 0.35),
			"grabber_highlight": tint(PEARL, 0.6), "grabber_pressed": RED,
		}
		for key: String in styles:
			var sb: StyleBoxFlat = card(styles[key], Color(0, 0, 0, 0), 0)
			sb.content_margin_left = bar_w
			sb.content_margin_right = bar_w
			sb.content_margin_top = bar_w
			sb.content_margin_bottom = bar_w
			th.set_stylebox(key, sb_name, sb)

	th.set_constant("separation", "VBoxContainer", GRID_PX * 2)
	th.set_constant("separation", "HBoxContainer", GRID_PX * 2)
	th.set_constant("h_separation", "GridContainer", GRID_PX * 2)
	th.set_constant("v_separation", "GridContainer", GRID_PX)
	_theme = th
	return th
