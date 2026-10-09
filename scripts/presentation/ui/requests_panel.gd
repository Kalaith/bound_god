extends Control
## Divine requests: what the god can ask of its believers at this shrine,
## and what has become of earlier requests. Asking is not commanding; each
## believer decides whether to take a request.
signal closed
signal command(value: Dictionary)
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")

const BOON: float = 10.0

var sim: RefCounted
var _offers: VBoxContainer
var _history: RichTextLabel
var _key: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = Style.panel(0.95)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -600
	panel.offset_right = 600
	panel.offset_top = -380
	panel.offset_bottom = 380
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	column.add_child(Style.label(Text.label("requests_title"), 34, Style.FAITH))
	column.add_child(Style.wrapped(Text.format("requests_hint", {"boon": int(BOON)}), 19, Style.MUTED))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	_offers = VBoxContainer.new()
	_offers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_offers.add_theme_constant_override("separation", 8)
	row.add_child(_offers)
	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history.add_theme_font_size_override("normal_font_size", 19)
	row.add_child(_history)
	var close: Button = Style.button(Text.label("design_close"))
	close.pressed.connect(func() -> void: closed.emit())
	column.add_child(close)
	hide()


func open() -> void:
	_key = ""
	show()


## Places the god has heard of through its believers.
func _known_settlements() -> Array:
	var result: Array = []
	for agent in sim.agents:
		if not agent.is_present() or not agent.faith.knows:
			continue
		for key in agent.beliefs.places:
			var place: Dictionary = agent.beliefs.places[key]
			if place.kind == "settlement" and not result.has(int(place.id)):
				result.append(int(place.id))
	result.sort()
	return result


func _process(_delta: float) -> void:
	if not visible or sim == null:
		return
	var key: String = "%d|%d|%d" % [sim.god.active_shrine_id, sim.requests.next_id, int(sim.faith.current(sim).get("favour", 0.0))]
	for id in sim.requests.ids():
		key += sim.requests.requests[id].state
	if key == _key:
		return
	_key = key
	for child in _offers.get_children():
		child.queue_free()
	var here: int = int(sim.faith.current(sim).get("settlement_id", -1))
	for id in _known_settlements():
		if id != here:
			var name: String = sim.settlements.get_settlement(id).name
			_offer(Text.format("request_offer_carry", {"place": name}), {"kind": "carry_name", "target": id})
			if not sim.faith.settlement_has_shrine(sim, id):
				_offer(Text.format("request_offer_raise", {"place": name}), {"kind": "raise_shrine", "target": id})
	for id in sim.faith.ids():
		if sim.faith.shrines[id].state == "fallen":
			_offer(Text.format("request_offer_restore", {"shrine": sim.faith.shrines[id].name}), {"kind": "restore_shrine", "target": id})
	for resource in ["wood", "stone", "thatch", "berries"]:
		_offer(Text.format("request_offer_bring", {"resource": Text.label("resource_" + resource).to_lower()}), {"kind": "bring", "resource": resource, "amount": 10})
	var lines: Array[String] = ["[color=#%s]%s[/color]" % [Style.GOLD.to_html(false), Text.label("requests_history")]]
	for id in sim.requests.ids():
		var request: Dictionary = sim.requests.requests[id]
		var takers: Array[String] = []
		for agent_id in request.takers:
			takers.append(sim.agents[agent_id].given_name)
		lines.append("%s · %s%s" % [sim.requests._describe(sim, request), Text.label("request_state_" + str(request.state)),
			(" · " + ", ".join(takers)) if not takers.is_empty() else ""])
	_history.text = "\n".join(lines)


func _offer(text: String, base: Dictionary) -> void:
	var button: Button = Style.button(text, false, 19)
	var payload: Dictionary = base.duplicate()
	payload["type"] = "post_request"
	payload["boon"] = BOON
	button.pressed.connect(func() -> void: command.emit(payload))
	_offers.add_child(button)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("toggle_settings"):
		closed.emit()
		get_viewport().set_input_as_handled()
