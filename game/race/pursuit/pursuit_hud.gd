class_name PursuitHud
extends CanvasLayer
## Heat readout and the BUSTED / ESCAPED banner for PursuitMode. Plain labels built in code, no art.

var _heat: Label
var _banner: Label


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
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 64)
	add_child(_banner)


func set_heat(heat: int, max_heat: int) -> void:
	_heat.text = "" if heat <= 0 else I18n.t("pursuit.heat") % [heat, max_heat]


func set_banner(text: String) -> void:
	_banner.text = text
