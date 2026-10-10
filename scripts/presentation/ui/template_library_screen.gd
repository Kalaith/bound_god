extends Control
signal closed
signal capture_requested
signal offer_requested(design: RefCounted)
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const FunctionRules = preload("res://scripts/building/function_rules.gd")
const Library = preload("res://scripts/building/template_library.gd")
const Preview = preload("res://scripts/presentation/ui/template_preview.gd")

var library := Library.new()
var selected: RefCounted
var draft: bool = false
var _panel: PanelContainer
var _list: ItemList
var _name: LineEdit
var _details: Label
var _help_button: Button
## Showing what makes each function instead of the selected design.
var _help: bool = false
var _notice: Label
var _preview: Control
var _save: Button
var _export: Button
var _offer: Button
## Ids already offered at a shrine, pushed in by main when the screen opens.
var offered: Dictionary = {}
var _dialog: FileDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.03, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = Style.panel(0.98)
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_panel.add_child(column)
	column.add_child(Style.label(Text.label("design_library"), 36, Style.GOLD))
	column.add_child(Style.wrapped(Text.label("design_private"), 21, Style.MUTED))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 340
	_list.add_theme_font_size_override("font_size", 23)
	_list.item_selected.connect(_select)
	row.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_name = LineEdit.new()
	_name.placeholder_text = Text.label("design_name")
	_name.max_length = 64
	_name.add_theme_font_size_override("font_size", 27)
	right.add_child(_name)
	_preview = Preview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_preview)
	_details = Style.wrapped("", 22)
	_details.custom_minimum_size.y = 130
	right.add_child(_details)
	_notice = Style.wrapped("", 21, Style.WARN)
	_notice.custom_minimum_size.y = 56
	column.add_child(_notice)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	_button(actions, "design_capture", func() -> void: capture_requested.emit())
	_save = _button(actions, "design_save", _save_draft)
	_button(actions, "design_import", _import_dialog)
	_export = _button(actions, "design_export", _export_dialog)
	_offer = _button(actions, "design_offer", func() -> void:
		if selected != null and not draft:
			offer_requested.emit(selected))
	_help_button = _button(actions, "design_functions", func() -> void:
		_help = not _help
		_refresh())
	_button(actions, "design_close", func() -> void: closed.emit())
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray([Text.label("design_filter")])
	_dialog.file_selected.connect(_file_selected)
	add_child(_dialog)
	_panel.anchor_left = 0.13
	_panel.anchor_right = 0.87
	_panel.anchor_top = 0.08
	_panel.anchor_bottom = 0.92
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = 0
	_panel.offset_bottom = 0
	hide()


func _button(parent: Node, key: String, action: Callable) -> Button:
	var button: Button = Style.button(Text.label(key))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func open(value: RefCounted = null) -> void:
	library.scan()
	_list.clear()
	for design in library.designs:
		_list.add_item(design.name)
	_notice.text = ""
	if not library.errors.is_empty():
		var lines: Array[String] = []
		for error in library.errors:
			var key: String = error.get_slice(": ", 1) if error.contains(": ") else error
			lines.append(Text.label(key))
		_notice.text = "\n".join(lines)
	selected = value
	draft = value != null
	_help = false
	if value == null and not library.designs.is_empty():
		selected = library.designs[0]
		_list.select(0)
	_refresh()
	show()
	if draft:
		_name.grab_focus()
		_name.select_all()
	else:
		_list.grab_focus()


func _select(index: int) -> void:
	selected = library.designs[index]
	draft = false
	_help = false
	_refresh()


## What makes each function, read from the rules' own order, and lanterns.
static func reference() -> String:
	var lines: Array[String] = []
	for function in FunctionRules.FUNCTIONS:
		lines.append(Text.label("function_help_" + function))
	lines.append(Text.label("function_help_lantern"))
	return "
".join(lines)


func _refresh() -> void:
	_help_button.text = Text.label("design_back" if _help else "design_functions")
	_preview.visible = not _help
	if _help:
		_details.text = reference()
		return
	_save.disabled = not draft
	_export.disabled = selected == null or draft
	_offer.disabled = selected == null or draft or offered.has(selected.id)
	_offer.text = Text.label("design_offered" if selected != null and offered.has(selected.id) else "design_offer")
	_name.editable = draft
	_name.text = selected.name if selected != null else ""
	_preview.show_design(selected)
	if selected == null:
		_details.text = Text.label("design_empty_library")
		return
	var functions: Array[String] = []
	for function in selected.functions:
		functions.append(Text.label("function_" + function))
	if functions.is_empty():
		functions.append(Text.label("function_unrecognised"))
	var capacities: Array[String] = []
	for key in selected.capacity:
		capacities.append("%d %s" % [selected.capacity[key], Text.label("capacity_" + key)])
	var bill: Array[String] = []
	for resource in selected.bill:
		bill.append("%d %s" % [selected.bill[resource], Text.label("resource_" + resource)])
	_details.text = Text.format("design_details", {"functions": ", ".join(functions), "capacity": ", ".join(capacities),
		"size": "%d × %d × %d" % [selected.size.x, selected.size.y, selected.size.z], "bill": ", ".join(bill)})


func _save_draft() -> void:
	if selected == null or not draft:
		return
	selected.name = _name.text.strip_edges()
	var problem: String = library.save(selected)
	if not problem.is_empty():
		_notice.text = Text.label(problem)
		return
	open()
	_notice.text = Text.label("design_saved")


func _import_dialog() -> void:
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.title = Text.label("design_import")
	_dialog.popup_centered_ratio(0.7)


func _export_dialog() -> void:
	if selected == null:
		return
	_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_dialog.title = Text.label("design_export")
	_dialog.current_file = selected.id + ".json"
	_dialog.popup_centered_ratio(0.7)


func _file_selected(path: String) -> void:
	if _dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE:
		var result: Array = library.import_file(path)
		if result[0] == null:
			_notice.text = Text.label(result[1])
		else:
			open()
			_notice.text = Text.label("design_imported")
	else:
		var problem: String = Library.write_file(path, selected)
		_notice.text = Text.label("design_exported" if problem.is_empty() else problem)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("toggle_settings"):
		closed.emit()
		get_viewport().set_input_as_handled()
