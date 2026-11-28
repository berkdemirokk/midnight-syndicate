extends "res://tests/test_case.gd"
## HUD pass 3: elimination countdown maths, and the English strings the top-right rows and countdown show.

const EPS: float = 0.0001


func test_elim_eta_counts_to_next_line() -> void:
	# Lap 1000 m, nobody out yet: the trailing car at 950 m reaches the line in 50 m / 20 m/s = 2.5 s.
	check(absf(RaceHUD.elim_eta_s(950.0, 1000.0, 0, 20.0) - 2.5) < EPS, "trailing car 50 m short of the line at 20 m/s")
	# One car out: the next check is the second line, 2000 m.
	check(absf(RaceHUD.elim_eta_s(1500.0, 1000.0, 1, 10.0) - 50.0) < EPS, "second line counts after one car is out")


func test_elim_eta_clamps_and_floors_speed() -> void:
	check(RaceHUD.elim_eta_s(1000.0, 1000.0, 0, 20.0) == 0.0, "a car already across the line gives zero")
	check(RaceHUD.elim_eta_s(1200.0, 1000.0, 0, 20.0) == 0.0, "past the line never goes negative")
	# A stopped car is floored at GAP_MIN_MS so the countdown stays finite.
	check(absf(RaceHUD.elim_eta_s(0.0, 1000.0, 0, 0.0) - 1000.0 / RaceHUD.GAP_MIN_MS) < EPS, "stopped car uses the speed floor")


func test_elim_countdown_english_text() -> void:
	var saved: String = Settings.language
	Settings.language = "en"
	check(I18n.t("hud.best") == "BEST", "top-right best row is BEST in English")
	check((I18n.t("hud.elim_in") % 7) == "LAST OUT IN 7 s", "countdown reads LAST OUT IN 7 s in English")
	Settings.language = "tr"
	check((I18n.t("hud.elim_in") % 7) == "SON ELEME 7 sn", "countdown reads SON ELEME 7 sn in Turkish")
	Settings.language = saved
