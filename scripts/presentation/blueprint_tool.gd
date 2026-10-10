extends Node3D
## "Lay blueprint" mode (M19): a design the god has offered follows the
## crosshair as a ghost; left click lays it as a proposal, right click turns
## it, Esc stops. The ghost is pale where the spot would serve as a site and
## red where it would not (checked only when the spot or turn changes).
signal message(text: String, bad: bool)
const Text = preload("res://scripts/core/text.gd")
const SiteFinder = preload("res://scripts/building/site_finder.gd")

var sim: RefCounted
var builder: Node3D
var active: bool = false
var design: RefCounted = null
var rotation_index: int = 0
var _ghost := MultiMeshInstance3D.new()
var _material := StandardMaterial3D.new()
var _shown: String = ""


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var box := BoxMesh.new()
	box.size = Vector3(0.96, 0.96, 0.96)
	_ghost.multimesh = MultiMesh.new()
	_ghost.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_ghost.multimesh.mesh = box
	_ghost.material_override = _material
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)
	_ghost.hide()


func begin(value: RefCounted) -> void:
	design = value
	active = true
	rotation_index = 0
	_shown = ""
	builder.enabled = false


func finish() -> void:
	active = false
	builder.enabled = true
	_ghost.hide()


func hint() -> String:
	return Text.format("blueprint_hint", {"design": design.name if design != null else ""})


func _corner() -> Vector3i:
	var cell: Vector3i = builder.target.cell
	var size: Vector3i = design.rotated_size(rotation_index)
	return Vector3i(cell.x - size.x / 2, cell.y + 1, cell.z - size.z / 2)


func _process(_delta: float) -> void:
	if not active or design == null or not builder.target.get("hit", false):
		_ghost.hide()
		return
	var corner: Vector3i = _corner()
	var key: String = "%s/%d" % [corner, rotation_index]
	if key == _shown:
		return
	_shown = key
	var settlement_id: int = sim.settlements.at_cell(corner)
	var fits: bool = settlement_id >= 0 and not SiteFinder.check(sim, design, Vector2i(corner.x, corner.z), rotation_index, sim.settlements.entries[settlement_id]).is_empty()
	_material.albedo_color = Color(0.6, 0.8, 1.0, 0.25) if fits else Color(0.9, 0.35, 0.3, 0.25)
	var cells: Array = []
	for entry in design.placement(rotation_index):
		if int(entry[1]) != 0:
			cells.append(corner + entry[0])
	_ghost.multimesh.instance_count = cells.size()
	for i in range(cells.size()):
		_ghost.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(cells[i]) + Vector3(0.5, 0.5, 0.5)))
	_ghost.show()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("break_block") and builder.target.get("hit", false):
		var result: Dictionary = sim.apply_command({"type": "lay_blueprint", "template": design.id, "origin": _corner(), "rotation": rotation_index})
		message.emit(Text.label(result.reason), not result.ok)
		if result.ok:
			finish()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("place_block"):
		rotation_index = (rotation_index + 1) % 4
		get_viewport().set_input_as_handled()
