extends Control
## Title: new world (seed), continue, load, settings, quit. Data validation
## runs here first; broken data is shown and the valley never rises from it.
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const Validation = preload("res://scripts/core/validation.gd")
const Session = preload("res://scripts/presentation/session.gd")
const Capture = preload("res://scripts/presentation/capture.gd")
const SaveStore = preload("res://scripts/core/save_store.gd")
const SettingsStore = preload("res://scripts/core/settings_store.gd")
const SettingsScreen = preload("res://scripts/presentation/ui/settings_screen.gd")

const MAIN_SCENE: String = "res://scenes/main.tscn"

var seed_input: LineEdit
## New-world options (M23): neighbouring regions, outlaws, pace.
var _neighbours: OptionButton
var _outlaws: OptionButton
var _pace: OptionButton
var continue_button: Button
var new_button: Button
var notice: Label
var errors: Array[String] = []
var settings := SettingsStore.new()
var settings_screen: Control
var _menu: VBoxContainer
var _heading: Label
var _tagline: Label
var _version_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings.load_settings()
	settings.apply_all(get_tree())
	errors = Validation.run()
	Session.data_errors = errors
	_build()
	resized.connect(_layout)
	_layout()
	var request: Dictionary = Capture.request()
	if not request.is_empty():
		_start_capture(request)
	elif errors.is_empty():
		new_button.grab_focus()


func _build() -> void:
	_heading = Style.heading(Text.label("game_title"), 84, Style.WHITE)
	add_child(_heading)
	_tagline = Style.wrapped(Text.label("game_tagline"), 24, Style.LEAF)
	add_child(_tagline)
	_version_label = Style.label(Text.format("title_version", {
		"version": str(ProjectSettings.get_setting("application/config/version"))}), 16, Style.MUTED)
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_version_label)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 14)
	add_child(_menu)
	if not errors.is_empty():
		_menu.add_child(Style.wrapped(Text.label("title_data_error"), 22, Style.BAD))
		for error in errors.slice(0, 12):
			_menu.add_child(Style.wrapped("• " + error, 16, Style.WARN))
		for error in errors:
			push_error(error)
		var quit: Button = Style.button(Text.label("title_quit"))
		quit.pressed.connect(func() -> void: get_tree().quit(1))
		_menu.add_child(quit)
		return
	continue_button = Style.button(Text.label("title_continue"), true)
	continue_button.pressed.connect(_continue)
	continue_button.disabled = not SaveStore.exists(Session.slot)
	_menu.add_child(continue_button)
	_menu.add_child(Style.label(Text.label("title_seed"), 16, Style.GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_menu.add_child(row)
	seed_input = LineEdit.new()
	seed_input.text = str(randi_range(1, 99999))
	seed_input.placeholder_text = Text.label("title_seed_hint")
	seed_input.custom_minimum_size = Vector2(0, 50)
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_input.add_theme_font_size_override("font_size", 20)
	seed_input.text_submitted.connect(func(_text: String) -> void: _new_world())
	row.add_child(seed_input)
	new_button = Style.button(Text.label("title_new_world"), continue_button.disabled)
	new_button.pressed.connect(_new_world)
	row.add_child(new_button)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 10)
	_menu.add_child(options)
	_neighbours = _choice(options, ["title_neighbours_0", "title_neighbours_1", "title_neighbours_2"], 2)
	_outlaws = _choice(options, ["title_outlaws_on", "title_outlaws_off"], 0)
	_pace = _choice(options, ["title_pace_gentle", "title_pace_usual", "title_pace_harsh"], 1)
	var settings_button: Button = Style.button(Text.label("title_settings"))
	settings_button.pressed.connect(_open_settings)
	_menu.add_child(settings_button)
	var quit_button: Button = Style.button(Text.label("title_quit"))
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	_menu.add_child(quit_button)
	notice = Style.wrapped("", 16, Style.MUTED)
	_menu.add_child(notice)


## A drop-down of label keys with one chosen.
func _choice(parent: Container, keys: Array, chosen: int) -> OptionButton:
	var button := OptionButton.new()
	for key in keys:
		button.add_item(Text.label(str(key)))
	button.select(chosen)
	button.add_theme_font_size_override("font_size", 18)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button


func _new_world() -> void:
	var text: String = seed_input.text.strip_edges()
	Session.mode = "new"
	Session.options = {"neighbours": _neighbours.selected, "outlaws": _outlaws.selected == 0, "pace": [0.8, 1.0, 1.2][_pace.selected]}
	Session.seed = int(text) if text.is_valid_int() else abs(text.hash()) % 1000000 + 1
	Session.seed = maxi(Session.seed, 1)
	get_tree().change_scene_to_file(MAIN_SCENE)


func _continue() -> void:
	if not SaveStore.exists(Session.slot):
		notice.text = Text.label("title_no_save")
		return
	Session.mode = "load"
	get_tree().change_scene_to_file(MAIN_SCENE)


func _open_settings() -> void:
	if is_instance_valid(settings_screen):
		settings_screen.show()
		return
	settings_screen = SettingsScreen.new()
	settings_screen.store = settings
	add_child(settings_screen)
	settings_screen.close_requested.connect(func() -> void:
		settings_screen.hide()
		new_button.grab_focus())


func _start_capture(request: Dictionary) -> void:
	if str(request.scenario) == "title":
		var shot: Node = Capture.new()
		shot.configure(request)
		add_child(shot)
		shot.shoot_after()
		return
	Session.mode = "new"
	Session.seed = int(request.get("seed", 7))
	get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)


func _layout() -> void:
	if not is_instance_valid(_menu):
		return
	_heading.position = Vector2(size.x * 0.07, size.y * 0.16)
	_tagline.position = Vector2(size.x * 0.07 + 6, size.y * 0.16 + 112)
	_tagline.size = Vector2(size.x * 0.42, 70)
	_version_label.size = Vector2(200, 24)
	_version_label.position = Vector2(size.x - 224, maxf(8, size.y - 32))
	var width: float = minf(520, size.x * 0.36)
	_menu.size = Vector2(width, 0)
	_menu.position = Vector2(size.x * 0.07, size.y * 0.42)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Style.INK)
	# Dusk sky bands above a valley line.
	for band in range(12):
		var t: float = band / 12.0
		var color: Color = Color("1d3a3a").lerp(Color("c98f4f"), pow(t, 1.6))
		draw_rect(Rect2(0, size.y * t * 0.62, size.x, size.y * 0.062 + 1), Color(color, 0.85))
	var ridge := PackedVector2Array([Vector2(0, size.y * 0.66)])
	for step in range(25):
		var x: float = size.x * step / 24.0
		ridge.append(Vector2(x, size.y * (0.58 + 0.05 * sin(step * 0.9) + 0.03 * sin(step * 2.3))))
	ridge.append(Vector2(size.x, size.y))
	ridge.append(Vector2(0, size.y))
	draw_colored_polygon(ridge, Color("142019"))
	# The sacred tree: trunk and a glowing crown, with a small light at its foot.
	var foot := Vector2(size.x * 0.72, size.y * 0.74)
	var scale: float = size.y / 1080.0
	draw_rect(Rect2(foot + Vector2(-14, -230) * scale, Vector2(28, 230) * scale), Color("3b2a1f"))
	for ring in range(5):
		var radius: float = (150.0 - ring * 22.0) * scale
		draw_circle(foot + Vector2(0, -280) * scale, radius, Color(Style.LEAF, 0.10 + ring * 0.06))
	draw_circle(foot + Vector2(0, -8) * scale, 10 * scale, Color(Style.FAITH, 0.9))
	draw_arc(foot + Vector2(0, -8) * scale, 26 * scale, 0, TAU, 48, Color(Style.FAITH, 0.35), 2.0, true)
	draw_rect(Rect2(0, size.y * 0.74, size.x, size.y * 0.26), Color("0d1410"))
