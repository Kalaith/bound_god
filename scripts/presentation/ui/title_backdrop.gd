extends RefCounted
## Painted title art stays separate from live text and interactive controls.
const IMAGE: Texture2D = preload("res://assets/art/ui/title_screen.png")


static func mount(host: Control, menu_on_right: bool = false) -> Control:
	var layer := Control.new()
	layer.name = "TitleBackdrop"
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(layer)
	var image := TextureRect.new()
	image.texture = IMAGE
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(image)
	# Only the menu side is shaded; the illustration keeps its light and colour.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.38, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.025, 0.03, 0.045, 0.78), Color(0.025, 0.03, 0.045, 0.60),
		Color(0.025, 0.03, 0.045, 0.10), Color(0.025, 0.03, 0.045, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(1, 0) if menu_on_right else Vector2.ZERO
	texture.fill_to = Vector2.ZERO if menu_on_right else Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)
	return layer
