extends RefCounted
## Physical keyboard slots; gamepad and mouse events and reserved navigation stay intact.
## Fixed, not listed: Esc (settings), Tab (overlook), Shift (sprint), mouse buttons
## (break/place), mouse wheel and 1-9 (hotbar). Every listed action needs a default
## key in project.godot, or saved bindings can never validate.
const ACTIONS: Dictionary = {
	"move_left": "Move left", "move_right": "Move right",
	"move_forward": "Move forward", "move_back": "Move back",
	"jump": "Jump", "interact": "Use / shrine", "inspect": "Inspect person", "inventory": "Blocks and hotbar",
	"rotate_block": "Rotate block", "design_tool": "Design tool",
	"zoom_in": "Zoom in", "zoom_out": "Zoom out",
	"toggle_chronicle": "Chronicle", "toggle_settlement": "Settlement",
	"speed_pause": "Pause time", "speed_up": "Faster time", "speed_down": "Slower time",
	"quick_save": "Quick save", "toggle_fullscreen": "Fullscreen", "dismiss_prompt": "Dismiss prompt", "toggle_qi": "Show qi", "toggle_tree": "The sacred tree",
}


static func defaults() -> Dictionary:
	var result: Dictionary = {}
	for action in ACTIONS:
		var codes: Array = []
		for event in ProjectSettings.get_setting("input/" + action).events:
			if event is InputEventKey:
				codes.append(int(event.physical_keycode))
		while codes.size() < 2:
			codes.append(0)
		result[action] = codes
	return result


static func allowed(code: int) -> bool:
	if code <= 0 or code in [KEY_ESCAPE, KEY_TAB, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return false
	return OS.find_keycode_from_string(OS.get_keycode_string(code)) == code


## Bindings saved before an action existed are still valid: the missing
## actions take their defaults when normalized.
static func valid(mapping: Variant) -> bool:
	if not mapping is Dictionary or mapping.size() > ACTIONS.size():
		return false
	var used: Array[int] = []
	for action in mapping:
		if not ACTIONS.has(action):
			return false
	for action in ACTIONS:
		if not mapping.has(action):
			continue
		var slots: Variant = mapping.get(action)
		if not slots is Array or slots.size() != 2:
			return false
		for slot in range(2):
			var code: Variant = slots[slot]
			if not (code is int or code is float) or not is_finite(float(code)) or float(code) != floorf(float(code)):
				return false
			if code == 0 and slot == 1:
				continue
			if code > 0x1ffffff or not allowed(int(code)) or used.has(int(code)):
				return false
			used.append(int(code))
	return true


static func change_error(mapping: Dictionary, action: String, slot: int, code: int) -> String:
	if not ACTIONS.has(action) or slot < 0 or slot > 1:
		return "Unknown binding."
	if code == 0 and slot == 0:
		return "Keep a primary key for every action."
	if code != 0 and not allowed(code):
		return "Choose a single key. Esc and Tab are reserved for navigation."
	if code != 0:
		for other in ACTIONS:
			for other_slot in range(2):
				if other == action and other_slot == slot:
					continue
				if int(mapping[other][other_slot]) == code:
					return "%s is already assigned to %s. Choose another key." % [key_name(code), ACTIONS[other]]
	return ""


static func normalized(mapping: Dictionary) -> Dictionary:
	# JSON numbers arrive as floats; keep runtime slots consistently integral.
	var result: Dictionary = {}
	var used: Array[int] = []
	for action in ACTIONS:
		if mapping.has(action):
			result[action] = [int(mapping[action][0]), int(mapping[action][1])]
			used.append_array(result[action])
	# An action newer than the saved bindings gets its default key, or the
	# first free one when the player already uses that key for something else.
	var defaults_now: Dictionary = defaults()
	for action in ACTIONS:
		if result.has(action):
			continue
		var code: int = int(defaults_now[action][0])
		for spare in [code, KEY_U, KEY_O, KEY_Y, KEY_H, KEY_G, KEY_N, KEY_M]:
			if not used.has(spare):
				code = spare
				break
		result[action] = [code, 0]
		used.append(code)
	return result


static func apply(mapping: Dictionary) -> void:
	for action in ACTIONS:
		Input.action_release(action)
		var other_events: Array[InputEvent] = []
		for event in InputMap.action_get_events(action):
			if not event is InputEventKey:
				other_events.append(event)
		InputMap.action_erase_events(action)
		for code in mapping[action]:
			if code != 0:
				var event := InputEventKey.new()
				event.physical_keycode = int(code)
				InputMap.action_add_event(action, event)
		for event in other_events:
			InputMap.action_add_event(action, event)


static func key_name(code: int) -> String:
	return OS.get_keycode_string(code) if code != 0 else "Unassigned"


static func hint(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return key_name(event.physical_keycode)
	return ""
