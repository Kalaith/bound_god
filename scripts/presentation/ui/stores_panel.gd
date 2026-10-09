extends Control
## Moving materials between the god's divine stock and a settlement's stores.
## Opened with Interact beside the stores; giving supplies people, it never
## tells them what to build.
signal closed
signal transfer(settlement_id: int, resource: String, amount: int)
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")

const RESOURCES: Array[String] = ["wood", "stone", "thatch", "berries", "ore"]
const STEP: int = 10

var sim: RefCounted
var settlement_id: int = -1
var _title: Label
var _rows: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = Style.panel(0.95)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -360
	panel.offset_right = 360
	panel.offset_top = -260
	panel.offset_bottom = 260
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	_title = Style.label("", 30, Style.GOLD)
	column.add_child(_title)
	column.add_child(Style.wrapped(Text.label("stores_hint"), 19, Style.MUTED))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for header in ["stores_resource", "stores_in_stores", "stores_yours", "", ""]:
		grid.add_child(Style.label(Text.label(header) if not header.is_empty() else "", 18, Style.MUTED))
	for resource in RESOURCES:
		grid.add_child(Style.label(Text.label("resource_" + resource), 22))
		var here := Style.label("", 22)
		var mine := Style.label("", 22)
		grid.add_child(here)
		grid.add_child(mine)
		var give: Button = Style.button(Text.format("stores_give", {"amount": STEP}), false, 19)
		give.pressed.connect(func() -> void: transfer.emit(settlement_id, resource, STEP))
		grid.add_child(give)
		var take: Button = Style.button(Text.format("stores_take", {"amount": STEP}), false, 19)
		take.pressed.connect(func() -> void: transfer.emit(settlement_id, resource, -STEP))
		grid.add_child(take)
		_rows[resource] = [here, mine, give, take]
	var close: Button = Style.button(Text.label("design_close"))
	close.pressed.connect(func() -> void: closed.emit())
	column.add_child(close)
	hide()


func open(id: int) -> void:
	settlement_id = id
	show()


func _process(_delta: float) -> void:
	if not visible or sim == null:
		return
	var settlement: Dictionary = sim.settlements.get_settlement(settlement_id)
	_title.text = Text.format("stores_title", {"place": settlement.get("name", ""), "total": sim.settlements.total(settlement_id), "capacity": sim.settlements.capacity(sim, settlement_id)})
	for resource in RESOURCES:
		var row: Array = _rows[resource]
		row[0].text = str(sim.settlements.amount(settlement_id, resource))
		row[1].text = str(sim.god.stock(resource))
		row[2].disabled = sim.god.stock(resource) <= 0
		row[3].disabled = sim.settlements.amount(settlement_id, resource) <= 0


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("toggle_settings") or event.is_action_pressed("interact")):
		closed.emit()
		get_viewport().set_input_as_handled()
