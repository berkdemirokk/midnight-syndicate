extends Node
## Creates every input action in code so project.godot never needs a hand-edited input map.

const KEYS: Dictionary = {
	"accelerate": [KEY_W, KEY_UP],
	"brake": [KEY_S, KEY_DOWN],
	"steer_left": [KEY_A, KEY_LEFT],
	"steer_right": [KEY_D, KEY_RIGHT],
	"handbrake": [KEY_SPACE],
	"nitro": [KEY_SHIFT],
	"pause": [KEY_ESCAPE],
	"reset_car": [KEY_R],
	"camera_toggle": [KEY_C],
}

const PAD_BUTTONS: Dictionary = {
	"handbrake": JOY_BUTTON_A,
	"nitro": JOY_BUTTON_X,
	"pause": JOY_BUTTON_START,
	"reset_car": JOY_BUTTON_BACK,
	"camera_toggle": JOY_BUTTON_Y,
}

# action -> [axis, sign]
const PAD_AXES: Dictionary = {
	"accelerate": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"brake": [JOY_AXIS_TRIGGER_LEFT, 1.0],
	"steer_left": [JOY_AXIS_LEFT_X, -1.0],
	"steer_right": [JOY_AXIS_LEFT_X, 1.0],
}


func _enter_tree() -> void:
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key: int in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action: String in PAD_BUTTONS:
		var ev := InputEventJoypadButton.new()
		ev.button_index = PAD_BUTTONS[action]
		InputMap.action_add_event(action, ev)
	for action: String in PAD_AXES:
		var ev := InputEventJoypadMotion.new()
		ev.axis = PAD_AXES[action][0]
		ev.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, ev)
