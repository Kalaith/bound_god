extends Control
## The blocks screen: every block the god can place, what it costs and how
## much of that the god holds, and the hotbar to fill. Choose a slot, then a
## block to put in it. The hotbar holds only what the player puts there, in
## the order they choose; it starts empty.
signal closed
signal hotbar_changed(slots: Array, selected: int)
const Style = preload("res://scripts/presentation/ui/style.gd")
const Text = preload("res://scripts/core/text.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Balance = preload("res://scripts/core/balance.gd")

## Block families, so related blocks sit together in the grid, each under
## its heading label.
const FAMILIES: Array = [
	["inventory_family_walls", ["planks", "log", "thatch", "cobble", "cut_stone", "glass", "fence", "roof_tiles", "lacquered_pillar", "paper_screen"]],
	["inventory_family_furniture", ["storage_chest", "bed", "door", "workbench", "hearth", "altar", "table", "bench", "planter", "lantern",
		"granary_bin", "farmland"]],
	["inventory_family_sect", ["meditation_mat", "formation_stone", "scripture_shelf", "lectern", "incense_burner", "medicine_cabinet",
		"memorial_tablet", "bronze_bell", "tribulation_array", "thunder_spire", "spirit_jade", "precept_stele", "sect_banner"]],
	["inventory_family_ground", ["berry_bush", "sapling", "dirt", "grass", "stone", "sand", "gravel"]],
]

var sim: RefCounted
var selected: int = 0
var _atlas: Texture2D
var _slots: Array = []
var _blocks: Dictionary = {}
var _notice: Label


func _ready() -> void:
	_atlas = load("res://assets/blocks_atlas.png")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel: PanelContainer = Style.panel(0.95)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -690
	panel.offset_right = 690
	panel.offset_top = -420
	panel.offset_bottom = 420
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	column.add_child(Style.heading(Text.label("inventory_title"), 30, Style.GOLD))
	column.add_child(Style.wrapped(Text.label("inventory_hint"), 18, Style.MUTED))
	# The families scroll; the hotbar and its buttons stay in view below.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var families := VBoxContainer.new()
	families.add_theme_constant_override("separation", 8)
	families.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(families)
	for family in FAMILIES:
		families.add_child(Style.label(Text.label(str(family[0])), 19, Style.MUTED))
		var grid := GridContainer.new()
		grid.columns = 7
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		families.add_child(grid)
		for name in family[1]:
			var block: int = Registry.id(name)
			var button: Button = _block_button(block)
			button.pressed.connect(func() -> void: _put(block))
			grid.add_child(button)
			_blocks[block] = button
	column.add_child(Style.label(Text.label("inventory_hotbar"), 20, Style.MUTED))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	column.add_child(bar)
	for slot in range(Balance.integer("avatar.hotbar_slots")):
		var button := Button.new()
		button.custom_minimum_size = Vector2(84, 84)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.text = str(slot + 1)
		button.add_theme_font_size_override("font_size", 15)
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				selected = slot
				_clear())
		button.pressed.connect(func() -> void: selected = slot)
		bar.add_child(button)
		_slots.append(button)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var left: Button = Style.button(Text.label("inventory_move_left"), false, 19)
	left.pressed.connect(func() -> void: _move(-1))
	actions.add_child(left)
	var right: Button = Style.button(Text.label("inventory_move_right"), false, 19)
	right.pressed.connect(func() -> void: _move(1))
	actions.add_child(right)
	var clear: Button = Style.button(Text.label("inventory_clear"), false, 19)
	clear.pressed.connect(_clear)
	actions.add_child(clear)
	var close: Button = Style.button(Text.label("design_close"), true, 19)
	close.pressed.connect(func() -> void: closed.emit())
	actions.add_child(close)
	_notice = Style.wrapped("", 18)
	column.add_child(_notice)
	hide()


func _block_button(block: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(184, 72)
	button.icon = _icon(block)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 52)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 15)
	return button


func _icon(block: int) -> Texture2D:
	var region := AtlasTexture.new()
	region.atlas = _atlas
	var tile: Vector2i = Registry.tiles[block][0]
	var size: float = float(_atlas.get_width()) / Registry.atlas_size.x
	region.region = Rect2(tile.x * size, tile.y * size, size, size)
	return region


func open(slot: int) -> void:
	selected = slot
	_notice.text = ""
	show()


func _slots_now() -> Array:
	return sim.god.hotbar.duplicate()


## Puts a block in the chosen slot; if it was already in another slot it
## moves from there, so each block appears once.
func _put(block: int) -> void:
	var slots: Array = _slots_now()
	var was: int = slots.find(block)
	if was >= 0:
		slots[was] = slots[selected]
	slots[selected] = block
	_notice.text = Text.format("inventory_put", {"block": Text.label("block_" + Registry.block_name(block)), "slot": selected + 1})
	# Fill onward: the next empty slot is chosen for the next block.
	for step in range(1, slots.size()):
		var next: int = (selected + step) % slots.size()
		if int(slots[next]) == 0:
			selected = next
			break
	hotbar_changed.emit(slots, selected)


func _move(direction: int) -> void:
	var slots: Array = _slots_now()
	var other: int = posmod(selected + direction, slots.size())
	var held: int = slots[other]
	slots[other] = slots[selected]
	slots[selected] = held
	selected = other
	hotbar_changed.emit(slots, selected)


func _clear() -> void:
	var slots: Array = _slots_now()
	slots[selected] = 0
	hotbar_changed.emit(slots, selected)


func _process(_delta: float) -> void:
	if not visible or sim == null:
		return
	for block in _blocks:
		var button: Button = _blocks[block]
		var resource: String = Registry.resource(block)
		var held: int = sim.god.stock(resource)
		button.text = "%s\n%s %d" % [Text.label("block_" + Registry.block_name(block)), Text.label("resource_" + resource), held]
		button.modulate = Color.WHITE if held > 0 else Color(1, 1, 1, 0.55)
	var slots: Array = sim.god.hotbar
	for slot in range(_slots.size()):
		var button: Button = _slots[slot]
		var block: int = int(slots[slot])
		if button.get_meta("block", -1) != block:
			button.icon = _icon(block) if block != 0 else null
			button.set_meta("block", block)
		var style: StyleBoxFlat = Style.panel_box(0.7, 8, 6)
		if slot == selected:
			style.border_color = Style.GOLD
			style.set_border_width_all(3)
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, style)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("toggle_settings") or event.is_action_pressed("inventory")):
		closed.emit()
		get_viewport().set_input_as_handled()
