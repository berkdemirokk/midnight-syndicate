class_name HudText
extends RefCounted
## One shaped line of text painted from a parent CanvasItem's _draw (no Label node).
## Why: Godot only batches glyph quads that share one atlas texture and are adjacent in draw order. A Label with an
## outline draws outline then fill, so a column of outlined Labels costs two draw calls each. HudText.paint draws every
## outline first, then every fill, with items sorted by pixel size, so a whole screen costs two draws per distinct size
## (one per size when nothing is outlined). Fonts of one size share an atlas (digits, tracked and bold batch together).

var text: String = ""
var size_px: int = 18
var color: Color = MSTheme.TEXT
var outlined: bool = false
var visible: bool = true
var pos: Vector2 = Vector2.ZERO  ## top-left of the line box, in the painting item's local space
var modulate: Color = Color.WHITE
var scale: float = 1.0  ## about pivot
var pivot: Vector2 = Vector2.ZERO

var _line: TextLine = TextLine.new()
var _font: Font


func _init(kind: String = "digits", px: int = 18, col: Color = MSTheme.TEXT, outline: bool = false) -> void:
	_font = MSTheme.font(kind)
	size_px = px
	color = col
	outlined = outline


## Returns true when the text changed (and the line was reshaped).
func set_text(t: String) -> bool:
	if t == text and _line.get_size().x > 0.0:
		return false
	text = t
	_line.clear()
	_line.add_string(t, _font, size_px)
	return true


func width() -> float:
	return _line.get_size().x


func height() -> float:
	return _font.get_height(size_px)


## Paints all items: outlines first, then fills. Items must already be sorted by size_px.
static func paint(ci: CanvasItem, items: Array[HudText]) -> void:
	var rid: RID = ci.get_canvas_item()
	for item: HudText in items:
		if item.visible and item.outlined and item.text != "":
			item._draw_pass(ci, rid, true)
	for item: HudText in items:
		if item.visible and item.text != "":
			item._draw_pass(ci, rid, false)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_pass(ci: CanvasItem, rid: RID, outline: bool) -> void:
	if scale != 1.0:
		ci.draw_set_transform_matrix(Transform2D(0.0, Vector2(scale, scale), 0.0, pivot - pivot * scale))
	else:
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if outline:
		_line.draw_outline(rid, pos, MSTheme.HUD_OUTLINE_PX, MSTheme.OUTLINE * modulate)
	else:
		_line.draw(rid, pos, color * modulate)
