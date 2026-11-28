extends "res://devtools/capture_scenario.gd"
## First-launch onboarding: both steps (language, touch controls), both languages, desktop and iPhone-landscape sizes.
## Settings autosave is off in captures, so the language choice never reaches the player's settings file.

const SCENE: String = "res://ui/menus/onboarding.tscn"
const SETTLE_FRAMES: int = 40
const DESKTOP_W: int = 1920
const DESKTOP_H: int = 1080
const PHONE_W: int = 2532
const PHONE_H: int = 1170


func run() -> void:
	for phone: bool in [false, true]:
		MSTheme.set_phone(phone)
		var w: int = PHONE_W if phone else DESKTOP_W
		var h: int = PHONE_H if phone else DESKTOP_H
		var tag: String = "iphone_%dx%d" % [w, h] if phone else "desktop_%dx%d" % [w, h]
		for lang: String in ["tr", "en"]:
			for s: int in [OnboardingScreen.STEP_LANGUAGE, OnboardingScreen.STEP_CONTROLS]:
				cap.set_size(w, h)
				var node: Node = await cap.load_scene(SCENE)
				var screen: OnboardingScreen = node as OnboardingScreen
				Settings.set_language(lang)
				screen.set_step(s)
				await cap.wait_frames(SETTLE_FRAMES)
				await cap.shot("%s_%s_step%d" % [tag, lang, s + 1])
	MSTheme.set_phone(false)
