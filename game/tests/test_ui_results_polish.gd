extends "res://tests/test_case.gd"
## Results screen polish: car paint chips per row, the NEW BEST tag and the entrance fade. Pure checks on the
## screen's state; the pixels are checked with the ui_results_cash capture.

const RESULTS: String = "res://ui/menus/results_screen.tscn"


func _rows() -> Array[Dictionary]:
	return [
		{"name": "A", "position": 1, "total_time": 70.0, "best_lap": 20.0, "paint": "#e0a030"},
		{"name": "B", "position": 2, "total_time": 71.0, "best_lap": 21.0, "paint": Color(0.2, 0.4, 0.6), "is_player": true},
		{"name": "C", "position": 3, "total_time": 72.0, "best_lap": 22.0}]


func test_paint_of_reads_hex_colour_and_falls_back() -> void:
	check(ResultsScreen._paint_of({"paint": "#e0a030"}).is_equal_approx(Color.from_string("#e0a030", Color.BLACK)), "hex paint parsed")
	check(ResultsScreen._paint_of({"paint": Color(0.2, 0.4, 0.6)}) == Color(0.2, 0.4, 0.6), "Color paint passes through")
	check(ResultsScreen._paint_of({}) == MSTheme.MUTED, "missing paint uses the muted chip colour")


func test_rows_carry_paint_and_new_best_tag() -> void:
	var screen: ResultsScreen = (load(RESULTS) as PackedScene).instantiate() as ResultsScreen
	add(screen)
	await frames(2)
	screen.show_results(_rows(), {"cash": 10, "rep": 1, "stars": 1, "new_best": true})
	var paint: Array[Color] = screen.get("_row_paint")
	check(paint.size() == 3 and screen.get_row_count() == 3, "one paint chip per result row (%d)" % paint.size())
	check((screen.get("_best_tag") as HudText).text == I18n.t("results.new_best"), "NEW BEST shown on a new best")
	screen.show_results(_rows(), {"cash": 10, "rep": 1, "stars": 1})
	check((screen.get("_best_tag") as HudText).text == "", "no NEW BEST tag without a new best")
	cleanup([screen])
	await frames(2)


func test_fade_restarts_and_footer_buttons_are_tall() -> void:
	var screen: ResultsScreen = (load(RESULTS) as PackedScene).instantiate() as ResultsScreen
	add(screen)
	await frames(2)
	screen.show_results(_rows(), {"cash": 10, "rep": 1})
	var board: Control = screen.get("_board")
	check(board.modulate.a == 0.0, "board starts transparent for the entrance fade")
	var first: Tween = screen.get("_fade_tw")
	screen.show_results(_rows(), {"cash": 10, "rep": 1})
	check(first == null or not first.is_valid(), "a second show_results kills the previous fade tween")
	await frames(40)
	check(board.modulate.a == 1.0, "board ends fully opaque after the fade")
	var tall: bool = true
	for b: Button in screen.get("_buttons"):
		tall = tall and b.custom_minimum_size.y >= 88.0
	check(tall, "every results button is at least 88 px tall")
	cleanup([screen])
	await frames(2)
