extends "res://tests/test_case.gd"
## UX regression: results footer buttons grow to fit their Turkish labels (the longest, SONRAKİ ETKİNLİK, was
## spilling past its frame), and the results screen still builds with every footer button present.

const RESULTS: String = "res://ui/menus/results_screen.tscn"

var _saved_language: String = "en"


func test_results_footer_fits_turkish_labels() -> void:
	_saved_language = Settings.language
	Settings.autosave = false
	Settings.set_language("tr")
	var screen: ResultsScreen = add(load(RESULTS).instantiate()) as ResultsScreen
	await frames(2)
	var buttons: Array = screen.get("_buttons")
	check(buttons.size() >= 5, "results footer has %d buttons, expected 5" % buttons.size())
	for b: Button in buttons:
		var text_w: float = b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
		check(b.custom_minimum_size.x >= text_w, "button '%s' is %.0f px wide, its label needs %.0f" % [b.text, b.custom_minimum_size.x, text_w])
	await cleanup([screen])
	Settings.set_language(_saved_language)
	Settings.autosave = true
