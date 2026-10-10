extends Control
## A small modal with a title, a line of explanation and a few choices, for
## things used in the world that offer more than one action (resting in a bed).
signal closed
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")

var _title: Label
var _hint: Label
var _choices: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = Style.panel(0.95)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -200
	panel.offset_bottom = 200
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	_title = Style.heading("", 30, Style.GOLD)
	column.add_child(_title)
	_hint = Style.wrapped("", 19, Style.MUTED)
	column.add_child(_hint)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	column.add_child(_choices)
	hide()


## choices: Array of [label text, Callable]. A Close choice is always added.
func open(title: String, hint: String, choices: Array) -> void:
	_title.text = title
	_hint.text = hint
	for child in _choices.get_children():
		child.queue_free()
	for choice in choices:
		var button: Button = Style.button(str(choice[0]))
		var action: Callable = choice[1]
		button.pressed.connect(func() -> void:
			closed.emit()
			action.call())
		_choices.add_child(button)
	var close: Button = Style.button(Text.label("design_close"))
	close.pressed.connect(func() -> void: closed.emit())
	_choices.add_child(close)
	show()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("toggle_settings") or event.is_action_pressed("interact")):
		closed.emit()
		get_viewport().set_input_as_handled()
