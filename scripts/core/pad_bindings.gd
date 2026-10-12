extends RefCounted
## One gamepad button per action; sticks, triggers and every keyboard slot stay intact.
## Fixed, not listed: Start (settings), B (back/cancel in menus), triggers (break/place).
## Every listed action needs a default button in project.godot.
const ACTIONS: Dictionary = {
	"jump": "Jump", "sprint": "Sprint", "interact": "Interact / shrine",
	"inspect": "Inspect person", "rotate_block": "Rotate block", "overlook": "Overlook",
	"design_tool": "Design tool", "toggle_chronicle": "Chronicle",
	"hotbar_prev": "Previous block", "hotbar_next": "Next block",
	"zoom_in": "Zoom in", "zoom_out": "Zoom out",
}
const NAMES: Array[String] = [
	"A / Cross", "B / Circle", "X / Square", "Y / Triangle", "Back / Select", "Guide",
	"Start", "Left stick press", "Right stick press", "Left bumper", "Right bumper",
	"D-pad up", "D-pad down", "D-pad left", "D-pad right", "Misc button",
	"Paddle 1", "Paddle 2", "Paddle 3", "Paddle 4", "Touchpad",
]


static func defaults() -> Dictionary:
	var result: Dictionary = {}
	for action in ACTIONS:
		for event in ProjectSettings.get_setting("input/" + action).events:
			if event is InputEventJoypadButton:
				result[action] = int(event.button_index)
				break
	return result


static func allowed(button: int) -> bool:
	return button >= 0 and button < NAMES.size()


static func valid(mapping: Variant) -> bool:
	if not mapping is Dictionary or mapping.size() != ACTIONS.size():
		return false
	var used: Array[int] = []
	for action in ACTIONS:
		var button: Variant = mapping.get(action)
		if not (button is int or button is float) or not is_finite(float(button)) or float(button) != floorf(float(button)):
			return false
		if not allowed(int(button)) or used.has(int(button)):
			return false
		used.append(int(button))
	return true


static func change_error(mapping: Dictionary, action: String, button: int) -> String:
	if not ACTIONS.has(action):
		return "bind_unknown"
	if not allowed(button):
		return "bind_button_fixed"
	for other in ACTIONS:
		if other != action and int(mapping[other]) == button:
			return "bind_button_taken|%s|%s" % [button_name(button), other]
	return ""


static func normalized(mapping: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for action in ACTIONS:
		result[action] = int(mapping[action])
	return result


static func apply(mapping: Dictionary) -> void:
	for action in ACTIONS:
		Input.action_release(action)
		var other_events: Array[InputEvent] = []
		for event in InputMap.action_get_events(action):
			if not event is InputEventJoypadButton:
				other_events.append(event)
		InputMap.action_erase_events(action)
		for event in other_events:
			InputMap.action_add_event(action, event)
		var pad := InputEventJoypadButton.new()
		pad.button_index = int(mapping[action])
		InputMap.action_add_event(action, pad)


static func button_name(button: int) -> String:
	return NAMES[button] if allowed(button) else "Button %d" % button
