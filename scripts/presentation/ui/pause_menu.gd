extends Control
## Esc in the valley: return, settings, save, or back to the title. The
## world keeps going behind it; the god does not stop time by looking away.
signal resume
signal save
signal settings
signal title
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.03, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel: PanelContainer = Style.panel(0.96)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -230
	panel.offset_bottom = 230
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.add_child(Style.heading(Text.label("game_title"), 34, Style.GOLD))
	for entry in [["pause_resume", resume], ["pause_save", save], ["title_settings", settings], ["pause_title", title]]:
		var button: Button = Style.button(Text.label(entry[0]), entry[0] == "pause_resume")
		var target: Signal = entry[1]
		button.pressed.connect(func() -> void: target.emit())
		column.add_child(button)
	hide()


func open() -> void:
	show()
	get_child(1).get_child(0).get_child(1).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("toggle_settings"):
		resume.emit()
		get_viewport().set_input_as_handled()
