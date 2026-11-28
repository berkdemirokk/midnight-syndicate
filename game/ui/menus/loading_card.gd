extends Control
## STREET EMPIRE loading card: graphite studio, the wordmark, LOADING and a red rule. Router shows it inside its fade
## (scene loads are synchronous, so the card is what the player sees while the next scene loads). Static by design:
## nothing animates while the main thread is blocked. Captured by devtools/scenarios/ui_loading.gd.

const RULE_W: float = 220.0


func _init() -> void:
	name = "LoadingCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var back := MenuBackdrop.new(0.0, 0.9)
	add_child(back)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.add_theme_constant_override("separation", 28)
	add_child(col)
	var logo := Logotype.new(0.9 if not MSTheme.phone else 1.0, false)
	logo.name = "Logo"
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(logo)
	var bar := ColorRect.new()
	bar.color = MSTheme.RED
	bar.custom_minimum_size = Vector2(RULE_W, 3.0)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bar)
	var cap: Label = MSTheme.make_label(I18n.t("common.loading"), "tracked", MSTheme.px(14), MSTheme.STEEL)
	cap.name = "Caption"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
