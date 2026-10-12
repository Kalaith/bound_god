extends Control
## A page of the saga (M23): a title, a body of lines and a row of buttons.
## The Saga screen and the epilogue are both pages; the main scene fills
## them and listens for which button was pressed.
signal chosen(id: String)
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")

var _title: Label
var _body: RichTextLabel
var _buttons: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.03, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel: PanelContainer = Style.panel(0.97)
	panel.anchor_left = 0.16
	panel.anchor_right = 0.84
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	_title = Style.heading("", 34, Style.GOLD)
	column.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 20)
	scroll.add_child(_body)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	column.add_child(_buttons)
	hide()


## Shows the page: `buttons` are [id, label key] pairs, the first focused.
func open(title: String, lines: Array, buttons: Array) -> void:
	_title.text = title
	_body.text = "\n".join(lines)
	for child in _buttons.get_children():
		child.queue_free()
	for i in range(buttons.size()):
		var id: String = str(buttons[i][0])
		var button: Button = Style.button(Text.label(str(buttons[i][1])), i == 0)
		button.pressed.connect(func() -> void: chosen.emit(id))
		_buttons.add_child(button)
		if i == 0:
			button.grab_focus.call_deferred()
	show()
