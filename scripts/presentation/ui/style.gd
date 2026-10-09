extends RefCounted
## One palette and a few builders so every screen reads the same. Sizes are
## authored at 1080p; the canvas_items stretch scales them for smaller windows.

const INK := Color("0f1410")
const PANEL := Color(0.07, 0.09, 0.08, 0.90)
const PANEL_SOLID := Color("141b16")
const BORDER := Color("5f7d5a")
const LEAF := Color("a6d18f")
const GOLD := Color("e6c27a")
const WHITE := Color("f1efe4")
const MUTED := Color("a8b3a2")
const WARN := Color("f0a07a")
const BAD := Color("e57373")
const GOOD := Color("8fd49a")
const FAITH := Color("d9c8ff")


static func label(text: String, size: int = 20, color: Color = WHITE) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	result.add_theme_constant_override("shadow_offset_x", 1)
	result.add_theme_constant_override("shadow_offset_y", 1)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func wrapped(text: String, size: int = 18, color: Color = WHITE) -> Label:
	var result: Label = label(text, size, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


static func button(text: String, primary: bool = false, size: int = 21) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 50
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", WHITE)
	result.add_theme_color_override("font_disabled_color", Color(MUTED, 0.6))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("2f4a2e") if primary else Color("1c261d")
		if state == "pressed":
			box.bg_color = Color("44683f")
		if state == "disabled":
			box.bg_color = Color("161c17")
		box.border_color = LEAF if state in ["hover", "focus"] else BORDER
		box.set_border_width_all(2 if primary else 1)
		box.set_corner_radius_all(8)
		box.content_margin_left = 16
		box.content_margin_right = 16
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		result.add_theme_stylebox_override(state, box)
	return result


static func panel_box(alpha: float = 0.9, radius: int = 12, margin: int = 18) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(PANEL, alpha)
	box.border_color = Color(BORDER, 0.8)
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin - 4
	box.content_margin_bottom = margin - 4
	return box


static func panel(alpha: float = 0.9) -> PanelContainer:
	var result := PanelContainer.new()
	result.add_theme_stylebox_override("panel", panel_box(alpha))
	return result


static func meter(value: float, maximum: float = 100.0, width: float = 160.0, color: Color = LEAF) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.45)
	back.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


## Need/mood colour: red when low, gold in the middle, green when content.
static func level_color(value: float) -> Color:
	if value < 25.0:
		return BAD
	if value < 50.0:
		return WARN
	if value < 70.0:
		return GOLD
	return GOOD
