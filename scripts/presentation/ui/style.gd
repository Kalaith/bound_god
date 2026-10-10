extends RefCounted
## One palette and a few builders so every screen reads the same. Sizes are
## authored at 1080p; the canvas_items stretch scales them for smaller windows.
## The look follows docs/design/art_direction.md: warm ink-wash panels ruled with a thin
## line of aged gold, cream text, and jade kept for the sacred.
## Type (docs/design/font_direction.md): a woodblock-flavoured Mincho serif for titles,
## shrine names and headings; a clean humanist sans for body text (the project
## theme default, assets/ui_theme.tres) and, in bold, for numbers and counters.
## Both are OFL, subset to Latin in assets/fonts.

const DISPLAY: Font = preload("res://assets/fonts/ShipporiMinchoB1-Bold.ttf")
const BODY: Font = preload("res://assets/fonts/ZenKakuGothicNew-Medium.ttf")
const UTILITY: Font = preload("res://assets/fonts/ZenKakuGothicNew-Bold.ttf")

const INK := Color("1a1714")
const PANEL := Color(0.11, 0.1, 0.085, 0.86)
const PANEL_SOLID := Color("1e1b17")
const BORDER := Color("a08a62")
const LEAF := Color("bccb98")
const GOLD := Color("e2bf7c")
const WHITE := Color("f2ebdc")
const MUTED := Color("b8ad99")
const WARN := Color("eda57c")
const BAD := Color("e07a6a")
const GOOD := Color("a9d39a")
const FAITH := Color("a9e2d2")


static func label(text: String, size: int = 20, color: Color = WHITE) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_color_override("font_shadow_color", Color(INK, 0.45))
	result.add_theme_constant_override("shadow_offset_x", 1)
	result.add_theme_constant_override("shadow_offset_y", 1)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


## A title, shrine name or section heading, set in the display serif.
static func heading(text: String, size: int = 30, color: Color = GOLD) -> Label:
	var result: Label = label(text, size, color)
	result.add_theme_font_override("font", DISPLAY)
	return result


## Numbers, counters and key labels: the bold sans, steady at small sizes.
static func utility(text: String, size: int = 16, color: Color = WHITE) -> Label:
	var result: Label = label(text, size, color)
	result.add_theme_font_override("font", UTILITY)
	return result


## A heading inside rich text: the theme sets bold in the display serif, a
## step larger than the body so it holds its own beside the sans.
static func rich_heading(text: String, color: Color = GOLD, size: int = 22) -> String:
	return "[font_size=%d][b][color=#%s]%s[/color][/b][/font_size]" % [size, color.to_html(false), text]


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
		box.bg_color = Color("4a3a2a") if primary else Color("2a2520")
		if state == "hover":
			box.bg_color = box.bg_color.lightened(0.06)
		if state == "pressed":
			box.bg_color = Color("5c4630")
		if state == "disabled":
			box.bg_color = Color("1e1b18")
		box.border_color = GOLD if state in ["hover", "focus"] else Color(BORDER, 0.7)
		box.set_border_width_all(2 if primary else 1)
		box.set_corner_radius_all(4)
		box.content_margin_left = 16
		box.content_margin_right = 16
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		result.add_theme_stylebox_override(state, box)
	return result


static func panel_box(alpha: float = 0.9, radius: int = 12, margin: int = 18) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(PANEL, alpha)
	box.border_color = Color(BORDER, 0.55)
	box.set_border_width_all(1)
	# Squarer corners than a modern card: closer to a mounted print.
	box.set_corner_radius_all(mini(radius, 6))
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
	back.bg_color = Color(INK, 0.55)
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
