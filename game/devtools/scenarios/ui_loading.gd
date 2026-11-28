extends "res://devtools/capture_scenario.gd"
## Loading card between the menu and a race, at desktop and iPhone-landscape sizes, at a fixed progress.

const LOADING_SCENE: String = "res://ui/menus/loading_screen.tscn"
const EVENT_ID: String = "maslak_sprint"
const PROGRESS: float = 0.62
const SETTLE_FRAMES: int = 30
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2532
const PHONE_H: int = 1170


func run() -> void:
	var cfg: RaceConfig = EventCatalog.config_for(EVENT_ID)
	cap.set_size(DESKTOP_W, DESKTOP_H)
	await _show(cfg)
	await cap.shot("loading_%dx%d" % [DESKTOP_W, DESKTOP_H])
	MSTheme.set_phone(true)  # the phone layout is chosen at build time
	cap.set_size(PHONE_W, PHONE_H)
	await _show(cfg)
	await cap.shot("loading_iphone_%dx%d" % [PHONE_W, PHONE_H])
	MSTheme.set_phone(false)


## Routes to the card with no target, so nothing loads: the progress is the fixed value for the shot.
func _show(cfg: RaceConfig) -> void:
	await Router.goto(LoadingScreen.SCENE, LoadingScreen.params_for("", {RaceScene.CONFIG_PARAM: cfg}, 1))
	await cap.wait_frames(SETTLE_FRAMES)
	var card: LoadingScreen = tree.current_scene as LoadingScreen
	if card == null:
		cap.fail("loading card is not the current scene")
		return
	card.set_progress(PROGRESS)
	await cap.wait_frames(2)
