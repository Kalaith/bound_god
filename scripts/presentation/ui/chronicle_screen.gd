extends Control
## The chronicle: the valley's history with causes, newest first, filtered
## by place. Only what someone could have told the god appears.
signal closed
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const ChronicleText = preload("res://scripts/presentation/ui/chronicle_text.gd")
const ChronicleExport = preload("res://scripts/presentation/ui/chronicle_export.gd")
const SagaText = preload("res://scripts/presentation/ui/saga_text.gd")

var sim: RefCounted
## The campaign: its ages head the chronicle, and it is what is exported (M23).
var campaign: RefCounted = null
var slot: String = "world"
var _places: OptionButton
var _notice: Label
var _body: RichTextLabel
var _count: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.03, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel: PanelContainer = Style.panel(0.97)
	panel.anchor_left = 0.12
	panel.anchor_right = 0.88
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title: Label = Style.heading(Text.label("chronicle_title"), 34, Style.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_places = OptionButton.new()
	_places.add_theme_font_size_override("font_size", 20)
	_places.item_selected.connect(func(_index: int) -> void: _count = -1)
	header.add_child(_places)
	var export: Button = Style.button(Text.label("chronicle_export"))
	export.pressed.connect(_export)
	header.add_child(export)
	var close: Button = Style.button(Text.label("design_close"))
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)
	_notice = Style.wrapped("", 16, Style.MUTED)
	column.add_child(_notice)
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
	hide()


func open() -> void:
	_places.clear()
	_places.add_item(Text.label("chronicle_everywhere"))
	for id in sim.settlements.ids():
		_places.add_item(sim.settlements.entries[id].name)
	_count = -1
	show()


func _process(_delta: float) -> void:
	if not visible or sim == null or sim.chronicle.entries.size() == _count:
		return
	_count = sim.chronicle.entries.size()
	var place: String = "" if _places.selected <= 0 else _places.get_item_text(_places.selected)
	var lines: Array[String] = []
	var ages: Array = campaign.ages if campaign != null else []
	var age_index: int = ages.size() - 1
	for i in range(sim.chronicle.entries.size() - 1, -1, -1):
		var entry: Dictionary = sim.chronicle.entries[i]
		if not entry.known or (not place.is_empty() and entry.place != place):
			continue
		# Newest first: an age's heading follows the oldest of its entries.
		while age_index >= 0 and int(entry.tick) < int(ages[age_index].tick):
			lines.append(Style.rich_heading(SagaText._sentence(SagaText.age_name(ages[age_index]))))
			age_index -= 1
		lines.append(ChronicleText.line(entry))
		if lines.size() >= 300:
			break
	_body.text = "\n".join(lines) if not lines.is_empty() else Text.label("chronicle_empty")


func _export() -> void:
	if campaign == null:
		return
	var path: String = ChronicleExport.write(campaign, slot)
	_notice.text = Text.format("chronicle_exported", {"path": path}) if not path.is_empty() else Text.label("chronicle_export_failed")


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("toggle_settings") or event.is_action_pressed("toggle_chronicle")):
		closed.emit()
		get_viewport().set_input_as_handled()
