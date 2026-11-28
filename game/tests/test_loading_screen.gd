extends "res://tests/test_case.gd"
## Loading card: params carry the target and the race params, every tip exists in TR and EN, the card names the
## place and the event of its race, and the progress stays between 0 and 1.

const RACE: String = "res://race/race_scene.tscn"
const EVENT_ID: String = "maslak_sprint"


func test_params_round_trip_and_tips_exist_in_both_languages() -> void:
	var cfg: RaceConfig = EventCatalog.config_for(EVENT_ID)
	var p: Dictionary = LoadingScreen.params_for(RACE, {RaceScene.CONFIG_PARAM: cfg}, 2)
	check(p[LoadingScreen.TARGET_KEY] == RACE, "the card carries the race scene as its target")
	check(((p[LoadingScreen.NEXT_KEY] as Dictionary)[RaceScene.CONFIG_PARAM] as RaceConfig).event_id == EVENT_ID, "the race config is kept")
	check(int(p[LoadingScreen.TIP_KEY]) == 2, "the tip index is kept")
	var keys: Array[String] = LoadingScreen.tip_keys()
	check(keys.size() == LoadingScreen.TIP_COUNT, "%d tip keys" % keys.size())
	for k: String in keys:
		check(I18n.has_key(k), "tip key %s exists" % k)
		var entry: Dictionary = I18n.DICT.get(k, {})
		check(str(entry.get("tr", "")) != "" and str(entry.get("en", "")) != "", "%s has TR and EN text" % k)


func test_card_names_the_place_and_the_event() -> void:
	var cfg: RaceConfig = EventCatalog.config_for(EVENT_ID)
	var card := LoadingScreen.new()
	card.configure("", {RaceScene.CONFIG_PARAM: cfg}, 0)
	add(card)
	await frames(1)
	check((card.get("_track") as Label).text == I18n.t("place.maslak"), "the card shows the track name")
	check((card.get("_event") as Label).text == I18n.t(EventCatalog.name_key(EVENT_ID)), "the card shows the event name")
	check((card.get("_tip_label") as Label).text == I18n.t("menu.tip_1"), "the card shows the chosen tip")
	await cleanup([card as Node])


func test_progress_is_clamped_and_shown_as_a_percentage() -> void:
	var card: LoadingScreen = add(LoadingScreen.new()) as LoadingScreen
	card.configure("", {}, 0)
	await frames(1)
	card.set_progress(0.4)
	check((card.get("_pct") as Label).text == "40%", "40 percent shown")
	card.set_progress(1.7)
	check(is_equal_approx(float(card.get("_progress")), 1.0), "progress above 1 is clamped")
	card.set_progress(-0.3)
	check(is_equal_approx(float(card.get("_progress")), 0.0) and (card.get("_pct") as Label).text == "0%", "progress below 0 is clamped")
	await cleanup([card as Node])
