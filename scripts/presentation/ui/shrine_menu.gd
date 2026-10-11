extends Control
## The shrine menu, opened with Interact at an altar or the sacred tree:
## every shrine the god knows with its state and a transfer, the miracles it
## can work here with their Favour cost, and ways to the design library and
## the stores. Nothing here commands anyone.
signal closed
signal command(value: Dictionary)
signal open_library
signal open_stores(settlement_id: int)
signal open_requests
signal rest_requested(days: float)
signal meditate_requested(years: float)
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const Data = preload("res://scripts/core/data.gd")
const Miracles = preload("res://scripts/sim/miracles.gd")
const Balance = preload("res://scripts/core/balance.gd")

var sim: RefCounted
var avatar_cell := Vector3i.ZERO
var _title: Label
var _status: Label
var _notice: Label
var _shrines: VBoxContainer
var _miracles: VBoxContainer
var _refresh_left: float = 0.0
var _key: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = Style.panel(0.95)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -620
	panel.offset_right = 620
	panel.offset_top = -400
	panel.offset_bottom = 400
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	_title = Style.heading("", 34, Style.FAITH)
	column.add_child(_title)
	_status = Style.wrapped("", 20, Style.MUTED)
	column.add_child(_status)
	_notice = Style.wrapped("", 20)
	column.add_child(_notice)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	left.add_child(Style.heading(Text.label("shrine_menu_shrines"), 24, Style.GOLD))
	_shrines = VBoxContainer.new()
	_shrines.add_theme_constant_override("separation", 8)
	left.add_child(_shrines)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(Style.heading(Text.label("shrine_menu_miracles"), 24, Style.GOLD))
	_miracles = VBoxContainer.new()
	_miracles.add_theme_constant_override("separation", 8)
	right.add_child(_miracles)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	_add_button(actions, "shrine_menu_designs", func() -> void: open_library.emit())
	_add_button(actions, "shrine_menu_stores", func() -> void:
		var shrine: Dictionary = sim.faith.current(sim)
		open_stores.emit(int(shrine.get("settlement_id", -1))))
	_add_button(actions, "shrine_menu_requests", func() -> void: open_requests.emit())
	for days in [1.0, 5.0, 10.0]:
		var label: String = Text.format("shrine_menu_rest", {"days": int(days)})
		var button: Button = Style.button(label)
		button.pressed.connect(func() -> void: rest_requested.emit(days))
		actions.add_child(button)
	_add_button(actions, "design_close", func() -> void: closed.emit())
	var meditate := HBoxContainer.new()
	meditate.add_theme_constant_override("separation", 12)
	column.add_child(meditate)
	for years in [1.0, 5.0, 10.0, 50.0]:
		var button: Button = Style.button(Text.format("shrine_menu_meditate", {"years": int(years)}))
		button.pressed.connect(func() -> void: meditate_requested.emit(years))
		meditate.add_child(button)
	hide()


func _add_button(parent: Node, key: String, action: Callable) -> Button:
	var button: Button = Style.button(Text.label(key))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func open() -> void:
	_refresh_left = 0.0
	_key = ""
	_notice.text = ""
	show()


## The outcome of the last thing tried here, kept in view under the menu's title.
func notice(text: String, bad: bool = false) -> void:
	_notice.text = text
	_notice.add_theme_color_override("font_color", Style.WARN if bad else Style.WHITE)


func _process(delta: float) -> void:
	if not visible or sim == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.5
	var shrine: Dictionary = sim.faith.current(sim)
	_title.text = str(shrine.get("name", Text.label("shrine_none")))
	_status.text = Text.format("shrine_menu_status", {"favour": roundi(float(shrine.get("favour", 0.0))), "support": "%.1f" % float(shrine.get("support", 0.0)),
		"condition": roundi(float(shrine.get("condition", 0.0))), "renown": sim.god.renown, "state": Text.label("shrine_state_" + str(shrine.get("state", "fallen")))})
	var key: String = "%d|%d|%s|%d" % [sim.god.active_shrine_id, sim.god.renown, avatar_cell, ceili(float(Miracles.transfer_wait(sim)) / sim.calendar.ticks_per_hour())]
	for id in sim.faith.ids():
		key += "|%s:%d" % [sim.faith.shrines[id].state, int(sim.faith.shrines[id].favour)]
	if key != _key:
		_key = key
		_rebuild_shrines()
		_rebuild_miracles()


func _rebuild_shrines() -> void:
	for child in _shrines.get_children():
		child.queue_free()
	for id in sim.faith.ids():
		var shrine: Dictionary = sim.faith.shrines[id]
		var line := HBoxContainer.new()
		var label: Label = Style.label("%s · %s" % [shrine.name, Text.label("shrine_state_" + str(shrine.state))], 20)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		if id != sim.god.active_shrine_id:
			var go: Button = Style.button(Text.format("shrine_menu_transfer_cost", {"cost": roundi(Balance.number("shrines.transfer_cost"))}), false, 18)
			var refusal: String = Miracles.transfer_refusal(sim, id)
			go.disabled = not refusal.is_empty()
			# Why the god cannot go yet is said beside the shrine, not hidden in a tooltip.
			if refusal == "transfer_cooldown":
				label.text += " · " + Text.format("transfer_cooldown_hours", {"hours": ceili(float(Miracles.transfer_wait(sim)) / sim.calendar.ticks_per_hour())})
			elif not refusal.is_empty() and refusal != "transfer_inactive":
				label.text += " · " + Text.label(refusal)
			go.pressed.connect(func() -> void: command.emit({"type": "transfer_shrine", "shrine": id}))
			line.add_child(go)
		_shrines.add_child(line)


func _rebuild_miracles() -> void:
	for child in _miracles.get_children():
		child.queue_free()
	for definition in Data.miracles():
		# Worked on one person, from the inspector.
		if definition.effect in ["whisper", "bless_cultivation"]:
			continue
		var line := HBoxContainer.new()
		var cost: float = float(Miracles.cost_of(sim, definition)[0])
		var label: Label = Style.label("%s · %d" % [Text.label("miracle_" + definition.id), roundi(cost)], 20)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		var problem: String = Miracles.problem(sim, definition.id, avatar_cell)
		var cast: Button = Style.button(Text.label("shrine_menu_cast"), false, 18)
		cast.disabled = not problem.is_empty()
		cast.tooltip_text = Text.label(problem) if not problem.is_empty() else ""
		cast.pressed.connect(func() -> void: command.emit({"type": "cast_miracle", "miracle": definition.id, "cell": avatar_cell}))
		line.add_child(cast)
		_miracles.add_child(line)
	var hint: Label = Style.wrapped(Text.label("shrine_menu_whisper_hint"), 18, Style.MUTED)
	_miracles.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("toggle_settings") or event.is_action_pressed("interact")):
		closed.emit()
		get_viewport().set_input_as_handled()
