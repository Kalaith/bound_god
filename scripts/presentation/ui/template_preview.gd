extends Control
## A small isometric drawing of the captured blocks, with no scene or physics.
const Registry = preload("res://scripts/world/block_registry.gd")
var design: RefCounted


func show_design(value: RefCounted) -> void:
	design = value
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(450, 320)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if design == null:
		return
	var scale: float = minf(size.x / (design.size.x + design.size.z + 2), size.y / (design.size.y * 2 + design.size.x + design.size.z + 2))
	var center := Vector2(size.x * 0.5, size.y * 0.55 + design.size.y * scale * 0.5)
	for y in range(design.size.y):
		for z in range(design.size.z):
			for x in range(design.size.x):
				var block: int = design.block_at(Vector3i(x, y, z))
				if block == 0:
					continue
				var offset := Vector2(x - z - (design.size.x - design.size.z) * 0.5, (x + z - (design.size.x + design.size.z) * 0.5) * 0.5 - y)
				var top: Vector2 = center + offset * scale
				var left: Vector2 = top + Vector2(-scale, scale * 0.5)
				var right: Vector2 = top + Vector2(scale, scale * 0.5)
				var front: Vector2 = top + Vector2(0, scale)
				var down := Vector2(0, scale)
				var color := Color("b28d60")
				match Registry.resource(block):
					"stone": color = Color("a6adb1")
					"thatch": color = Color("d7bf75")
					"soil": color = Color("8eaa6c")
				if not Registry.component(block).is_empty():
					color = Color("b1a2d3")
				draw_colored_polygon(PackedVector2Array([left, front, front + down, left + down]), color.darkened(0.25))
				draw_colored_polygon(PackedVector2Array([front, right, right + down, front + down]), color.darkened(0.4))
				draw_colored_polygon(PackedVector2Array([top, right, front, left]), color)
