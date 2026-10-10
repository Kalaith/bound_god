extends Control
## Settings over the title or the valley: sound, display, graphics, keys and
## pad buttons. It edits the SettingsStore directly and saves on every change;
## the world keeps running behind it (it never pauses the simulation).
signal close_requested
signal title_requested
signal changed

const Style = preload("res://scripts/presentation/ui/style.gd")
const Keys = preload("res://scripts/core/key_bindings.gd")
const Pad = preload("res://scripts/core/pad_bindings.gd")

var store: RefCounted
var show_title_button: bool = false
var panel: PanelContainer
var tabs: TabContainer
var notice: Label
var sliders: Dictionary = {}
var toggles: Dictionary = {}
var key_buttons: Dictionary = {}
var pad_buttons: Dictionary = {}
var capture_action: String = ""
var capture_slot: int = 0
var capture_pad: bool = false
var close_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.02, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	panel = Style.panel(0.97)
	add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	body.add_child(Style.label("Settings", 34))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 18)
	tabs.tab_changed.connect(func(_index: int) -> void: cancel_capture())
	body.add_child(tabs)
	_build_general()
	_build_keys()
	notice = Style.wrapped("", 16, Style.GOLD)
	notice.custom_minimum_size.y = 26
	body.add_child(notice)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	body.add_child(actions)
	close_button = Style.button("Back   ·   Esc", true)
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(func() -> void:
		cancel_capture()
		close_requested.emit())
	actions.add_child(close_button)
	if show_title_button:
		var title := Style.button("Save and return to title")
		title.pressed.connect(func() -> void: title_requested.emit())
		actions.add_child(title)
	resized.connect(_layout)
	_layout()
	refresh()


func _build_general() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Sound, display, graphics"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	rows.add_child(Style.label("Sound", 20, Style.LEAF))
	for entry in [["master", "Master volume"], ["music", "Music"], ["effects", "Effects"], ["look_sensitivity", "Look sensitivity"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var name_label: Label = Style.label(entry[1], 18)
		name_label.custom_minimum_size.x = 200
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.custom_minimum_size = Vector2(240, 40)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = entry[0]
		slider.value_changed.connect(func(value: float) -> void: _set_value(key, value / 100.0))
		row.add_child(slider)
		sliders[key] = slider
		rows.add_child(row)
	for entry in [["muted", "Mute all sound"], ["invert_look", "Invert vertical look"], ["fullscreen", "Fullscreen   ·   F11"],
			["reduce_motion", "Reduce motion"], ["show_guide", "Show first-steps guide"], ["ssao", "Ambient occlusion (SSAO)"], ["glow", "Glow"], ["shadows", "Sun shadows"], ["ink", "Ink outlines and paper"]]:
		if entry[0] == "ssao":
			rows.add_child(Style.label("Graphics", 20, Style.LEAF))
		var toggle := CheckButton.new()
		toggle.text = entry[1]
		toggle.add_theme_font_size_override("font_size", 18)
		toggle.custom_minimum_size.y = 44
		var key: String = entry[0]
		toggle.toggled.connect(func(value: bool) -> void: _set_value(key, value))
		rows.add_child(toggle)
		toggles[key] = toggle


func _build_keys() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Keys and pad"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("separation", 8)
	scroll.add_child(holder)
	holder.add_child(Style.wrapped("Click a binding, then press a key. Esc, Tab, Shift, mouse buttons and 1-9 stay fixed.", 16, Style.MUTED))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	holder.add_child(grid)
	for action in Keys.ACTIONS:
		var name_label: Label = Style.label(Keys.ACTIONS[action], 17)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		var pair: Array = []
		for slot in range(2):
			var button: Button = Style.button("", false, 16)
			button.custom_minimum_size = Vector2(150, 40)
			button.pressed.connect(_begin_capture.bind(action, slot, false))
			grid.add_child(button)
			pair.append(button)
		key_buttons[action] = pair
	holder.add_child(Style.label("Gamepad buttons", 20, Style.LEAF))
	var pad_grid := GridContainer.new()
	pad_grid.columns = 2
	pad_grid.add_theme_constant_override("h_separation", 10)
	holder.add_child(pad_grid)
	for action in Pad.ACTIONS:
		var name_label: Label = Style.label(Pad.ACTIONS[action], 17)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad_grid.add_child(name_label)
		var button: Button = Style.button("", false, 16)
		button.custom_minimum_size = Vector2(220, 40)
		button.pressed.connect(_begin_capture.bind(action, 0, true))
		pad_grid.add_child(button)
		pad_buttons[action] = button
	var resets := HBoxContainer.new()
	resets.add_theme_constant_override("separation", 10)
	holder.add_child(resets)
	var reset_keys: Button = Style.button("Restore default keys", false, 16)
	reset_keys.pressed.connect(func() -> void:
		store.reset_keys()
		_save())
	resets.add_child(reset_keys)
	var reset_pad: Button = Style.button("Restore default buttons", false, 16)
	reset_pad.pressed.connect(func() -> void:
		store.reset_pad()
		_save())
	resets.add_child(reset_pad)


func refresh() -> void:
	if store == null or panel == null:
		return
	for key in sliders:
		sliders[key].set_value_no_signal(float(store.values[key]) * 100.0)
	for key in toggles:
		toggles[key].set_pressed_no_signal(bool(store.values[key]))
	for action in key_buttons:
		for slot in range(2):
			var waiting: bool = capture_action == action and capture_slot == slot and not capture_pad
			key_buttons[action][slot].text = "Press a key…" if waiting else Keys.key_name(int(store.key_bindings[action][slot]))
	for action in pad_buttons:
		var waiting: bool = capture_action == action and capture_pad
		pad_buttons[action].text = "Press a button…" if waiting else Pad.button_name(int(store.pad_bindings[action]))


func _set_value(key: String, value: Variant) -> void:
	store.values[key] = value
	store.apply_all(get_tree())
	_save()


func _save() -> void:
	if not store.save_settings():
		notice.text = store.last_error
	refresh()
	changed.emit()


func _begin_capture(action: String, slot: int, pad: bool) -> void:
	capture_action = action
	capture_slot = slot
	capture_pad = pad
	notice.text = "Press a %s for %s. Esc cancels." % ["gamepad button" if pad else "key", (Pad.ACTIONS if pad else Keys.ACTIONS)[action]]
	refresh()


func cancel_capture() -> void:
	capture_action = ""
	if notice != null:
		notice.text = ""
	refresh()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if capture_action.is_empty():
		if event.is_action_pressed("toggle_settings") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
			close_requested.emit()
			get_viewport().set_input_as_handled()
		return
	if capture_pad and event is InputEventJoypadButton and event.pressed:
		notice.text = store.rebind_pad(capture_action, event.button_index)
		capture_action = ""
		_save()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_ESCAPE:
			cancel_capture()
			return
		if capture_pad:
			return
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		var error: String = store.rebind(capture_action, capture_slot, code)
		capture_action = ""
		_save()
		notice.text = error


func _layout() -> void:
	if panel == null:
		return
	panel.size = Vector2(minf(820, size.x - 32), minf(860, size.y - 32))
	panel.position = (size - panel.size) * 0.5
