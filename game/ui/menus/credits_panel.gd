class_name CreditsPanel
extends ScrollContainer
## Scrollable panel with the whole third-party credits file (CC BY 4.0 credit lines and CC0 notices).
## The file is the one shipped with the game, so every licence line shown here is the one the build carries.

const CREDITS_PATH: String = "res://ui/credits_third_party.txt"
const PANEL_PX: float = 440.0  ## base px; MSTheme.px() scales it on the phone layout
const TEXT_PX: int = 16

var _label: Label


static func credits_text() -> String:
	if not FileAccess.file_exists(CREDITS_PATH):
		return ""
	return FileAccess.get_file_as_string(CREDITS_PATH).strip_edges()


## The text the panel shows (empty if the file is missing).
func shown_text() -> String:
	return _label.text if _label != null else ""


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, MSTheme.px(PANEL_PX))
	_label = MSTheme.make_label(credits_text(), "bold", MSTheme.px(TEXT_PX), MSTheme.TEXT)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_label)
