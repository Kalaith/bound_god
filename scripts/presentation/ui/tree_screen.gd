extends Control
## The tree screen (T): what the sacred tree has become. Its maturity and
## phase, every insight with the trials it came from, what it can do now,
## the fruit on its boughs, the scars on its bark and the spots the god has
## nurtured. Read-only.
signal closed
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const Data = preload("res://scripts/core/data.gd")

var sim: RefCounted
var _body: RichTextLabel
var _refresh_left: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = Style.panel(0.95)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -520
	panel.offset_right = 520
	panel.offset_top = -400
	panel.offset_bottom = 400
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title: Label = Style.heading(Text.label("tree_title"), 34, Style.FAITH)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button = Style.button(Text.label("tree_close"))
	close.pressed.connect(func() -> void: closed.emit())
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 21)
	_body.add_theme_color_override("default_color", Style.WHITE)
	scroll.add_child(_body)
	hide()


func open() -> void:
	_refresh_left = 0.0
	show()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("toggle_settings") or event.is_action_pressed("toggle_tree")):
		closed.emit()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or sim == null or sim.tree_growth == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.5
	_body.text = text(sim)


static func text(sim: RefCounted) -> String:
	var growth: RefCounted = sim.tree_growth
	var lines: Array[String] = []
	var phases: Array = Data.tree_growth().maturity.phases
	lines.append(Style.rich_heading(Text.format("tree_phase", {"phase": Text.label("phase_" + growth.phase_id()), "maturity": "%.1f" % float(growth.maturity)})))
	if int(growth.phase) + 1 < phases.size():
		var next: Dictionary = phases[int(growth.phase) + 1]
		lines.append("[color=#%s]%s[/color]" % [Style.MUTED.to_html(false), Text.format("tree_next_phase", {"phase": Text.label("phase_" + str(next.id)), "at": roundi(float(next.at))})])
	lines.append("")
	lines.append(Style.rich_heading(Text.label("tree_insights")))
	if growth.insights.is_empty():
		lines.append(Text.label("tree_no_insights"))
	var kinds: Array = growth.insights.keys()
	kinds.sort()
	for kind in kinds:
		lines.append(Text.format("tree_insight_line", {"kind": Text.label("insight_" + str(kind)).capitalize(), "amount": "%.1f" % float(growth.insights[kind]),
			"count": int(growth.witnessed.get(kind, 0))}))
		for record in growth.history:
			if str(record.kind) == str(kind):
				lines.append("    " + Text.format("tree_insight_source", {"day": int(record.day), "name": record.name,
					"outcome": Text.label("cult_outcome_" + str(record.outcome)), "gain": "%.1f" % float(record.gain)}))
	lines.append("")
	lines.append(Style.rich_heading(Text.label("tree_unlocks")))
	if growth.unlocks.is_empty():
		lines.append(Text.label("tree_no_unlocks"))
	for id in growth.unlocks:
		lines.append("[color=#%s]%s[/color]" % [Style.FAITH.to_html(false), Text.label("unlock_" + str(id)).capitalize()])
	lines.append("")
	lines.append(Text.format("tree_fruit", {"count": int(growth.fruit)}))
	lines.append(Text.format("tree_scars", {"count": growth.scars.size()}))
	lines.append(Text.format("tree_nurtured", {"count": growth.nurtured.size()}))
	return "\n".join(lines)
