class_name PursuitHud
extends CanvasLayer
## Pursuit HUD: heat pips, the goal line (escape, or the survive timer), bust and escape gauges, a radar of the police
## cars, and the BUSTED / ESCAPED banner. Plain labels and drawing built in code, no art. The radar sits on the left,
## under the position list; the gauges sit under the heat line. Hidden until the chase starts (heat above 0).

const RADAR_RANGE_M: float = 120.0  ## police beyond this range are drawn on the rim
const RADAR_RADIUS_PX: float = 96.0
const RADAR_POS: Vector2 = Vector2(30.0, 330.0)  ## top-left of the radar box, screen pixels at 1920x1080
const BAR_W_PX: float = 170.0
const BAR_H_PX: float = 10.0
const PIP_SPACING_PX: float = 22.0
const BUST_COLOUR: Color = Color("#FF3B3B")
const ESCAPE_COLOUR: Color = Color("#2AE6FF")
const PIP_COLOUR: Color = Color("#FFC233")
const POLICE_COLOUR: Color = Color("#4A8DFF")

var _heat: Label
var _goal: Label
var _banner: Label
var _panel: Control
var _heat_now: int = 0
var _heat_max: int = 5
var _bust: float = 0.0
var _escape: float = 0.0
var _dots: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	layer = 4
	_heat = Label.new()
	# Top centre, under the track name: the top-left corner holds the race position list.
	_heat.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_heat.offset_top = 92.0
	_heat.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_heat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heat.add_theme_font_size_override("font_size", 28)
	add_child(_heat)
	_goal = Label.new()
	_goal.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_goal.offset_top = 124.0
	_goal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal.add_theme_font_size_override("font_size", 18)
	add_child(_goal)
	_panel = Control.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_panel)
	add_child(_panel)
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 64)
	add_child(_banner)


func set_heat(heat: int, max_heat: int) -> void:
	_heat.text = "" if heat <= 0 else I18n.t("pursuit.heat") % [heat, max_heat]
	_heat_now = heat
	_heat_max = max_heat
	_goal.visible = heat > 0
	_panel.visible = heat > 0
	_panel.queue_redraw()


func set_goal(text: String) -> void:
	_goal.text = text


func set_banner(text: String) -> void:
	_banner.text = text


## bust and escape are 0..1 fills; dots are police positions in the player's frame (x right, y ahead, metres).
func set_gauges(bust: float, escape: float, dots: PackedVector2Array) -> void:
	_bust = clampf(bust, 0.0, 1.0)
	_escape = clampf(escape, 0.0, 1.0)
	_dots = dots
	_panel.queue_redraw()


func _draw_panel() -> void:
	if _heat_now <= 0:
		return
	var sz: Vector2 = _panel.size
	var cx: float = sz.x * 0.5
	for i: int in _heat_max:
		var pip := Vector2(cx + (float(i) - float(_heat_max - 1) * 0.5) * PIP_SPACING_PX, 186.0)
		_panel.draw_circle(pip, 7.0, PIP_COLOUR if i < _heat_now else Color(1.0, 1.0, 1.0, 0.18))
	_bar(Vector2(cx - 12.0 - BAR_W_PX, 164.0), _bust, BUST_COLOUR)
	_bar(Vector2(cx + 12.0, 164.0), _escape, ESCAPE_COLOUR)
	var centre: Vector2 = RADAR_POS + Vector2(RADAR_RADIUS_PX, RADAR_RADIUS_PX)
	_panel.draw_circle(centre, RADAR_RADIUS_PX, Color(0.0, 0.0, 0.0, 0.45))
	_panel.draw_arc(centre, RADAR_RADIUS_PX, 0.0, TAU, 48, Color(0.6, 0.9, 1.0, 0.5), 2.0)
	var k: float = RADAR_RADIUS_PX / RADAR_RANGE_M
	for d: Vector2 in _dots:
		var p: Vector2 = centre + Vector2(d.x, -d.y) * k  # d.y is ahead: negative (behind) is down the screen
		var off: Vector2 = p - centre
		if off.length() > RADAR_RADIUS_PX:
			p = centre + off.normalized() * RADAR_RADIUS_PX
		_panel.draw_circle(p, 6.0, POLICE_COLOUR)
	_panel.draw_colored_polygon(PackedVector2Array([centre + Vector2(0.0, -10.0), centre + Vector2(-7.0, 7.0), centre + Vector2(7.0, 7.0)]), Color.WHITE)


func _bar(pos: Vector2, ratio: float, colour: Color) -> void:
	_panel.draw_rect(Rect2(pos, Vector2(BAR_W_PX, BAR_H_PX)), Color(0.0, 0.0, 0.0, 0.5))
	if ratio > 0.0:
		_panel.draw_rect(Rect2(pos, Vector2(BAR_W_PX * ratio, BAR_H_PX)), colour)
