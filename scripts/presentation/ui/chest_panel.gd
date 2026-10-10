extends Control
## One storage chest, opened by using it: what it holds beside the god's
## divine stock, with give and take. Goods in a chest inside a settlement are
## the settlement's to use; giving supplies people, it never tells them what
## to build.
signal closed
signal transfer(chest: Vector3i, resource: String, amount: int)
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")

const RESOURCES: Array[String] = ["wood", "stone", "thatch", "berries", "ore", "grain", "seed", "meal", "tree_seed"]
const STEPS: Array[int] = [1, 10]

var sim: RefCounted
var chest := Vector3i(-1, -1, -1)
var _title: Label
var _owner: Label
var _notice: Label
var _rows: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = Style.panel(0.95)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -440
	panel.offset_right = 440
	panel.offset_top = -340
	panel.offset_bottom = 340
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	_title = Style.heading("", 30, Style.GOLD)
	column.add_child(_title)
	_owner = Style.wrapped("", 19)
	column.add_child(_owner)
	column.add_child(Style.wrapped(Text.label("chest_hint"), 18, Style.MUTED))
	var grid := GridContainer.new()
	grid.columns = 3 + STEPS.size() * 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for header in ["stores_resource", "chest_in_chest", "stores_yours"]:
		grid.add_child(Style.label(Text.label(header), 18, Style.MUTED))
	for _i in range(STEPS.size() * 2):
		grid.add_child(Control.new())
	for resource in RESOURCES:
		grid.add_child(Style.label(Text.label("resource_" + resource), 22))
		var here := Style.utility("", 22)
		var mine := Style.utility("", 22)
		grid.add_child(here)
		grid.add_child(mine)
		var buttons: Array = []
		for step in STEPS:
			var give: Button = Style.button(Text.format("stores_give", {"amount": step}), false, 18)
			give.pressed.connect(func() -> void: transfer.emit(chest, resource, step))
			grid.add_child(give)
			buttons.append([give, step])
		for step in STEPS:
			var take: Button = Style.button(Text.format("stores_take", {"amount": step}), false, 18)
			take.pressed.connect(func() -> void: transfer.emit(chest, resource, -step))
			grid.add_child(take)
			buttons.append([take, -step])
		_rows[resource] = [here, mine, buttons]
	_notice = Style.wrapped("", 19)
	column.add_child(_notice)
	var close: Button = Style.button(Text.label("design_close"))
	close.pressed.connect(func() -> void: closed.emit())
	column.add_child(close)
	hide()


func open(cell: Vector3i) -> void:
	chest = cell
	_notice.text = ""
	show()


## The outcome of the last give or take, kept in view.
func notice(text: String, bad: bool) -> void:
	_notice.text = text
	_notice.add_theme_color_override("font_color", Style.WARN if bad else Style.WHITE)


func _process(_delta: float) -> void:
	if not visible or sim == null:
		return
	if not sim.settlements.chests.has(chest):
		closed.emit()
		return
	var capacity: int = sim.settlements.container_capacity(chest)
	_title.text = Text.format("bin_title" if sim.settlements.bins.has(chest) else "chest_title", {"total": sim.settlements.chest_total(chest), "capacity": capacity})
	var owner: int = sim.settlements.chest_owner(chest)
	if owner >= 0:
		_owner.text = Text.format("chest_owner", {"place": sim.settlements.get_settlement(owner).name})
		_owner.add_theme_color_override("font_color", Style.WHITE)
	else:
		_owner.text = Text.label("chest_no_owner")
		_owner.add_theme_color_override("font_color", Style.WARN)
	var contents: Dictionary = sim.settlements.chest_contents(chest)
	for resource in RESOURCES:
		var room: int = sim.settlements.chest_room(chest, resource)
		var row: Array = _rows[resource]
		var held: int = int(contents.get(resource, 0))
		row[0].text = str(held)
		row[1].text = str(sim.god.stock(resource))
		for pair in row[2]:
			var amount: int = pair[1]
			pair[0].disabled = (sim.god.stock(resource) <= 0 or room <= 0) if amount > 0 else held <= 0


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("toggle_settings") or event.is_action_pressed("interact")):
		closed.emit()
		get_viewport().set_input_as_handled()
