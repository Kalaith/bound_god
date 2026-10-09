extends Node3D
signal captured(design: RefCounted)
signal message(text: String, bad: bool)
const Capture = preload("res://scripts/building/template_capture.gd")
const Data = preload("res://scripts/core/data.gd")
const Text = preload("res://scripts/core/text.gd")

var sim: RefCounted
var builder: Node3D
var active: bool = false
var first_set: bool = false
var first := Vector3i.ZERO
var second := Vector3i.ZERO
var outline := MeshInstance3D.new()
var material := StandardMaterial3D.new()


func _ready() -> void:
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	outline.mesh = builder._box_lines()
	outline.material_override = material
	add_child(outline)
	outline.hide()


func begin() -> void:
	active = true
	first_set = false
	builder.enabled = false


func finish() -> void:
	active = false
	builder.enabled = true
	outline.hide()


func hint() -> String:
	return Text.label("design_corner_second" if first_set else "design_corner_first")


func _process(_delta: float) -> void:
	if not active or not builder.target.get("hit", false):
		outline.hide()
		return
	second = builder.target.cell
	show_box(first if first_set else second, second)


func show_box(a: Vector3i, b: Vector3i) -> void:
	var low := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var high := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	outline.position = Vector3(low)
	outline.scale = Vector3(high - low + Vector3i.ONE)
	material.albedo_color = Color("e6c27a") if _problem(a, b).is_empty() else Color("e57373")
	outline.show()


func _problem(a: Vector3i, b: Vector3i) -> String:
	if sim.god.dormant:
		return "edit_dormant"
	for cell in [a, b]:
		if not sim.voxels.in_bounds(cell):
			return "template_bounds"
	# All four horizontal corners must lie inside the circular presence zone.
	for x in [a.x, b.x]:
		for z in [a.z, b.z]:
			if not sim.in_zone(Vector3(x + 0.5, 0, z + 0.5)):
				return "edit_outside_zone"
	var span := Vector3i(absi(a.x - b.x) + 1, absi(a.y - b.y) + 1, absi(a.z - b.z) + 1)
	var limits: Array = Data.template_limits().max_size
	for axis in range(3):
		if span[axis] > int(limits[axis]):
			return "template_size"
	return ""


func mark(cell: Vector3i) -> void:
	var problem: String = _problem(first if first_set else cell, cell)
	if not problem.is_empty():
		message.emit(Text.label(problem), true)
		return
	if not first_set:
		first = cell
		first_set = true
		return
	var result: Array = Capture.capture(sim.voxels, first, cell, Text.label("design_default_name"))
	if result[0] == null:
		message.emit(Text.label(result[1]), true)
		return
	finish()
	captured.emit(result[0])


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("break_block") and builder.target.get("hit", false):
		mark(builder.target.cell)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("place_block"):
		first_set = false
		get_viewport().set_input_as_handled()
