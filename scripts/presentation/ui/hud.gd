extends Control
## The small HUD: time and speed, the shrine the god stands at with its
## Favour and the god's renown, the divine stock, the crosshair, the block
## hotbar, a message line and the last three prayers. Main pushes a plain
## state dictionary each frame; the HUD never reads the simulation itself.
const Style = preload("res://scripts/presentation/ui/style.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Text = preload("res://scripts/core/text.gd")

var _clock: Label
var _shrine: Label
var _stock: Label
var _message: Label
var _hint: Label
var _guide: Label
var _prayers: VBoxContainer
var _slots: Array = []
var _slot_labels: Array = []
var _slot_counts: Array = []
var _hotbar: HBoxContainer
var _prompt: Label
var _selected_name: Label
var _message_time: float = 0.0
var _atlas: Texture2D
var _crosshair: Control
var _prayer_keys: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atlas = load("res://assets/blocks_atlas.png")
	var top_left := Style.panel(0.72)
	top_left.position = Vector2(20, 18)
	add_child(top_left)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 4)
	top_left.add_child(left_box)
	_clock = Style.label("", 24)
	left_box.add_child(_clock)
	_stock = Style.label("", 18, Style.MUTED)
	left_box.add_child(_stock)
	_guide = Style.wrapped("", 19, Style.FAITH)
	_guide.custom_minimum_size.x = 520
	left_box.add_child(_guide)
	var top_center := Style.panel(0.72)
	top_center.name = "ShrinePanel"
	add_child(top_center)
	_shrine = Style.label("", 22, Style.FAITH)
	_shrine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_center.add_child(_shrine)
	_prayers = VBoxContainer.new()
	_prayers.add_theme_constant_override("separation", 6)
	add_child(_prayers)
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	add_child(_crosshair)
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 6)
	add_child(_hotbar)
	for slot in range(9):
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(76, 82)
		box.add_theme_stylebox_override("panel", Style.panel_box(0.7, 8, 6))
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 0)
		box.add_child(column)
		var key := Style.label(str(slot + 1), 13, Style.MUTED)
		column.add_child(key)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(icon)
		var count := Style.label("", 15)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(count)
		_hotbar.add_child(box)
		_slots.append(box)
		_slot_labels.append(icon)
		_slot_counts.append(count)
	_prompt = Style.label("", 20, Style.GOLD)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(_prompt)
	_selected_name = Style.label("", 20, Style.GOLD)
	_selected_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_selected_name)
	_message = Style.label("", 21)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_message)
	_hint = Style.wrapped("", 16, Style.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_hint)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var view: Vector2 = size
	_crosshair.position = view * 0.5 - Vector2(12, 12)
	_crosshair.size = Vector2(24, 24)
	_prompt.position = Vector2(view.x * 0.5 - 300, view.y * 0.5 + 22)
	_prompt.size = Vector2(600, 30)
	_hotbar.position = Vector2((view.x - 9 * 82) * 0.5, view.y - 104)
	_selected_name.position = Vector2(view.x * 0.5 - 300, view.y - 140)
	_selected_name.size = Vector2(600, 30)
	_message.position = Vector2(view.x * 0.5 - 500, view.y - 182)
	_message.size = Vector2(1000, 32)
	# Bottom-left, clear of the centred hotbar even at 1280x720.
	_hint.position = Vector2(20, view.y - 66)
	_hint.size = Vector2(minf(520.0, (view.x - 9 * 82) * 0.5 - 40.0), 48)
	var shrine_panel: Control = get_node("ShrinePanel")
	shrine_panel.position = Vector2(view.x * 0.5 - shrine_panel.size.x * 0.5, 18)
	_prayers.position = Vector2(view.x - 520, 18)
	_prayers.size = Vector2(500, 0)


func _draw_crosshair() -> void:
	var center := Vector2(12, 12)
	var color := Color(1, 1, 1, 0.85)
	_crosshair.draw_line(center - Vector2(9, 0), center - Vector2(3, 0), color, 2.0)
	_crosshair.draw_line(center + Vector2(3, 0), center + Vector2(9, 0), color, 2.0)
	_crosshair.draw_line(center - Vector2(0, 9), center - Vector2(0, 3), color, 2.0)
	_crosshair.draw_line(center + Vector2(0, 3), center + Vector2(0, 9), color, 2.0)


func flash(text: String, bad: bool = false) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", Style.WARN if bad else Style.WHITE)
	_message_time = 2.6


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time / 0.6, 0.0, 1.0)


func _icon(block: int) -> Texture2D:
	var region := AtlasTexture.new()
	region.atlas = _atlas
	var tile: Vector2i = Registry.tiles[block][0]
	region.region = Rect2(tile.x * 16, tile.y * 16, 16, 16)
	return region


## state: clock, stock (resource -> int), hotbar (Array[int]), selected,
## shrine (String), prayers (Array[String]), hint (String), crosshair (bool)
func refresh(state: Dictionary) -> void:
	_clock.text = state.get("clock", "")
	var stock: Dictionary = state.get("stock", {})
	var parts: Array = []
	for resource in ["wood", "stone", "thatch", "berries", "ore", "soil"]:
		if int(stock.get(resource, 0)) > 0:
			parts.append("%s %d" % [Text.label("resource_" + resource), int(stock[resource])])
	_stock.text = Text.label("hud_stock") + "  " + ("   ".join(parts) if not parts.is_empty() else Text.label("hud_stock_empty"))
	_shrine.text = state.get("shrine", "")
	get_node("ShrinePanel").visible = not _shrine.text.is_empty()
	_crosshair.visible = state.get("crosshair", true)
	_hint.text = state.get("hint", "")
	_prompt.text = state.get("prompt", "")
	_guide.text = state.get("guide", "")
	_guide.visible = not _guide.text.is_empty()
	var hotbar: Array = state.get("hotbar", [])
	var selected: int = int(state.get("selected", 0))
	for slot in range(_slots.size()):
		var box: PanelContainer = _slots[slot]
		var block: int = int(hotbar[slot]) if slot < hotbar.size() else 0
		var icon: TextureRect = _slot_labels[slot]
		if icon.get_meta("block", -1) != block:
			icon.texture = _icon(block) if block != 0 else null
			icon.set_meta("block", block)
		_slot_counts[slot].text = str(int(stock.get(Registry.resource(block), 0))) if block != 0 else ""
		var style: StyleBoxFlat = Style.panel_box(0.7 if block != 0 else 0.4, 8, 6)
		if slot == selected:
			style.border_color = Style.GOLD
			style.set_border_width_all(3)
		box.add_theme_stylebox_override("panel", style)
	var chosen: int = int(hotbar[selected]) if selected < hotbar.size() else 0
	if chosen != 0:
		_selected_name.text = "%s  ·  %s" % [Text.label("block_" + Registry.block_name(chosen)), Text.label("resource_" + Registry.resource(chosen))]
	else:
		_selected_name.text = Text.label("hotbar_slot_empty")
	_set_prayers(state.get("prayers", []))
	_hotbar.visible = state.get("hotbar_visible", true)
	_selected_name.visible = _hotbar.visible


func _set_prayers(lines: Array) -> void:
	if lines == _prayer_keys:
		return
	_prayer_keys = lines.duplicate()
	for child in _prayers.get_children():
		child.queue_free()
	for line in lines:
		var card := Style.panel(0.72)
		var text := Style.wrapped(str(line), 17, Style.FAITH)
		text.custom_minimum_size.x = 460
		card.add_child(text)
		_prayers.add_child(card)
