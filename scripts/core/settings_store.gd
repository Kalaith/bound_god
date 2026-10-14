extends "res://addons/hatchery/settings/settings_store.gd"
## The Bound God's preferences: which settings exist, which actions rebind,
## and how they reach the engine. Storage, validation, backups and binding
## rules come from the shared toolkit store. Preferences never share a file
## or schema with earned progression.
const KeyBindings = preload("res://addons/hatchery/input/key_bindings.gd")
const PadBindings = preload("res://addons/hatchery/input/pad_bindings.gd")
const Levels = preload("res://addons/hatchery/audio/levels.gd")
const Display = preload("res://addons/hatchery/settings/display.gd")

## A saved `values` dictionary missing a newer key defaults it in on load, so a
## single added setting cannot invalidate every existing preferences file.
## Numbers are fractions 0..1 (volumes, look sensitivity); graphics toggles let
## weaker GPUs drop Forward+ effects.
const CURRENT_SCHEMA: int = 1
const DEFAULTS: Dictionary = {
	"master": 1.0, "music": 1.0, "effects": 1.0, "muted": false,
	"look_sensitivity": 0.5, "invert_look": false,
	"fullscreen": false, "reduce_motion": false,
	"ssao": true, "glow": true, "shadows": true, "ink": true,
	"show_guide": true,
	"ui_scale": 0.23, "colour_safe": false, "high_contrast": false, "captions": false, "pseudo_language": false,
}
## Physical keyboard slots; gamepad and mouse events and reserved navigation stay intact.
## Fixed, not listed: Esc (settings), Tab (overlook), Shift (sprint), mouse buttons
## (break/place), mouse wheel and 1-9 (hotbar). Every listed action needs a default
## key in project.godot, or saved bindings can never validate.
const KEY_ACTIONS: Dictionary = {
	"move_left": "Move left", "move_right": "Move right",
	"move_forward": "Move forward", "move_back": "Move back",
	"jump": "Jump", "interact": "Use / shrine", "inspect": "Inspect person", "inventory": "Blocks and hotbar",
	"rotate_block": "Rotate block", "design_tool": "Design tool",
	"zoom_in": "Zoom in", "zoom_out": "Zoom out",
	"toggle_chronicle": "Chronicle", "toggle_settlement": "Settlement",
	"speed_pause": "Pause time", "speed_up": "Faster time", "speed_down": "Slower time",
	"quick_save": "Quick save", "toggle_fullscreen": "Fullscreen", "dismiss_prompt": "Dismiss prompt", "toggle_qi": "Show qi", "toggle_tree": "The sacred tree",
}
## One gamepad button per action; sticks, triggers and every keyboard slot stay intact.
## Fixed, not listed: Start (settings), B (back/cancel in menus), triggers (break/place).
## Every listed action needs a default button in project.godot.
const PAD_ACTIONS: Dictionary = {
	"jump": "Jump", "sprint": "Sprint", "interact": "Interact / shrine",
	"inspect": "Inspect person", "rotate_block": "Rotate block", "overlook": "Overlook",
	"design_tool": "Design tool", "toggle_chronicle": "Chronicle",
	"hotbar_prev": "Previous block", "hotbar_next": "Next block",
	"zoom_in": "Zoom in", "zoom_out": "Zoom out",
}
const BUSES: Dictionary = {"Master": "master", "Music": "music", "Effects": "effects"}


func _init(path: String = "user://settings.json") -> void:
	super(DEFAULTS, path, CURRENT_SCHEMA)
	keys = KeyBindings.new(KEY_ACTIONS)
	pad = PadBindings.new(PAD_ACTIONS)
	_reset_bindings()


## Push every stored preference into the engine: bindings, window mode, the
## interface and the buses. Graphics toggles are read by the world environment.
func apply_all(_tree: SceneTree) -> void:
	apply_bindings()
	Display.set_fullscreen(bool(values.fullscreen))
	# Accessibility and language (M24).
	var Text = load("res://scripts/core/text.gd")
	Text.pseudo = bool(values.pseudo_language)
	var StyleScript = load("res://scripts/presentation/ui/style.gd")
	StyleScript.set_palette(bool(values.colour_safe), bool(values.high_contrast))
	StyleScript.reduce_motion = bool(values.reduce_motion)
	Display.set_ui_scale(_tree, ui_scale())
	Levels.apply_buses(values, BUSES)


## The UI scale: 85 % to 150 %, from the 0..1 setting.
func ui_scale() -> float:
	return Display.scale_from_fraction(float(values.ui_scale))
