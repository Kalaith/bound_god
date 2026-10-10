extends Node3D
## Hands-on building around the avatar: the crosshair picks a block face with
## an exact voxel ray, break and place go to the simulation as commands, and
## the chunk re-meshes the same frame. The preview tints red with a reason
## when the god cannot act there.
signal message(text: String, bad: bool)

const Registry = preload("res://scripts/world/block_registry.gd")
const VoxelRay = preload("res://scripts/world/voxel_ray.gd")
const Commands = preload("res://scripts/sim/commands.gd")
const Text = preload("res://scripts/core/text.gd")
const REPEAT_SECONDS: float = 0.22

var sim: RefCounted
var world_view: Node3D
var camera_rig: Node3D
var avatar: Node3D
var enabled: bool = true
var selected: int = 0
var rotate_flip: bool = false
var target: Dictionary = {}
var place_cell := Vector3i.ZERO
var place_problem: String = ""
var break_problem: String = ""
var _outline: MeshInstance3D
var _ghost: MeshInstance3D
var _outline_material := StandardMaterial3D.new()
var _ghost_material := StandardMaterial3D.new()
var _repeat: float = 0.0


func _ready() -> void:
	Registry.build()
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_material.albedo_color = Color(1, 1, 1, 0.9)
	_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_material.no_depth_test = false
	_outline = MeshInstance3D.new()
	_outline.mesh = _box_lines()
	_outline.material_override = _outline_material
	add_child(_outline)
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = Color(0.6, 1.0, 0.6, 0.25)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE * 1.002
	_ghost = MeshInstance3D.new()
	_ghost.mesh = cube
	_ghost.material_override = _ghost_material
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghost)


func _box_lines() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var lo := Vector3.ONE * -0.004
	var hi := Vector3.ONE * 1.004
	var corners: Array = []
	for i in range(8):
		corners.append(Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z))
	for pair in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		mesh.surface_add_vertex(corners[pair[0]])
		mesh.surface_add_vertex(corners[pair[1]])
	mesh.surface_end()
	return mesh


## The god's hotbar, chosen and ordered in the blocks screen (0 = empty).
func hotbar() -> Array:
	return sim.god.hotbar if sim != null else []


func selected_block() -> int:
	var slots: Array = hotbar()
	return int(slots[selected]) if selected < slots.size() else 0


func select(index: int) -> void:
	selected = posmod(index, maxi(hotbar().size(), 1))


func door_meta() -> int:
	var forward: Vector3 = -camera_rig.camera.global_transform.basis.z
	var auto: int = 1 if absf(forward.x) > absf(forward.z) else 0
	return auto ^ (1 if rotate_flip else 0)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	for slot in range(9):
		if event.is_action_pressed("hotbar_%d" % (slot + 1)):
			select(slot)
			return
	if event.is_action_pressed("hotbar_next") and not Input.is_key_pressed(KEY_CTRL):
		select(selected + 1)
	elif event.is_action_pressed("hotbar_prev") and not Input.is_key_pressed(KEY_CTRL):
		select(selected - 1)
	elif event.is_action_pressed("rotate_block"):
		rotate_flip = not rotate_flip
	elif event.is_action_pressed("break_block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_act(true)
		_repeat = REPEAT_SECONDS * 1.6
	elif event.is_action_pressed("place_block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_act(false)
		_repeat = REPEAT_SECONDS * 1.6


func _process(delta: float) -> void:
	if sim == null or camera_rig == null:
		return
	_update_target()
	if not enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var breaking: bool = Input.is_action_pressed("break_block")
	var placing: bool = Input.is_action_pressed("place_block")
	if breaking or placing:
		_repeat -= delta
		if _repeat <= 0.0:
			_repeat = REPEAT_SECONDS
			_act(breaking)


func _head() -> Vector3:
	return avatar.global_position + Vector3(0, 1.5, 0)


func _update_target() -> void:
	var ray: Array = camera_rig.aim_ray()
	var reach: float = camera_rig.reach()
	var span: float = camera_rig.arm.get_hit_length() + reach + 2.0
	target = VoxelRay.cast(sim.voxels, ray[0], ray[1], span)
	if not enabled or not target.hit:
		_outline.visible = false
		_ghost.visible = false
		place_problem = ""
		break_problem = ""
		return
	var cell: Vector3i = target.cell
	break_problem = Commands.edit_problem(sim, cell, 0, _head(), reach)
	place_cell = cell + target.normal
	# Tall grass and similar soft blocks are replaced in place.
	if Registry.passable[target.block] == 1 and Registry.solid[target.block] == 0:
		place_cell = cell
	if selected_block() == 0:
		place_problem = "hotbar_empty"
	else:
		place_problem = Commands.edit_problem(sim, place_cell, selected_block(), _head(), reach)
	if place_problem.is_empty() and Registry.solid[selected_block()] == 1 and _touches_avatar(place_cell):
		place_problem = "edit_someone_there"
	_outline.visible = true
	_outline.global_position = Vector3(cell)
	_outline_material.albedo_color = Color(1, 1, 1, 0.9) if break_problem.is_empty() else Color(1, 0.45, 0.4, 0.9)
	_ghost.visible = selected_block() != 0
	_ghost.global_position = Vector3(place_cell) + Vector3(0.5, 0.5, 0.5)
	_ghost_material.albedo_color = Color(0.6, 1.0, 0.6, 0.22) if place_problem.is_empty() else Color(1.0, 0.4, 0.35, 0.22)


func _touches_avatar(cell: Vector3i) -> bool:
	var feet: Vector3 = avatar.global_position
	var low: Vector3 = Vector3(cell)
	var high: Vector3 = low + Vector3.ONE
	return feet.x + 0.35 > low.x and feet.x - 0.35 < high.x and feet.z + 0.35 > low.z and feet.z - 0.35 < high.z \
		and feet.y + 1.75 > low.y and feet.y < high.y


func _act(breaking: bool) -> void:
	if not target.get("hit", false):
		return
	var problem: String = break_problem if breaking else place_problem
	if not problem.is_empty():
		message.emit(problem_text(problem), true)
		return
	var block: int = 0 if breaking else selected_block()
	if not breaking and block == 0:
		return
	var cell: Vector3i = target.cell if breaking else place_cell
	var meta: int = door_meta() if Registry.component(block) == "door" else 0
	var result: Dictionary = sim.apply_command({"type": "edit_block", "cell": cell, "id": block, "meta": meta})
	if result.ok:
		world_view.remesh_now()
		if not str(result.reason).is_empty():
			message.emit(Text.label(result.reason), false)
	else:
		message.emit(problem_text(result.reason), true)


func problem_text(problem: String) -> String:
	if problem == "edit_no_stock":
		var resource: String = Registry.resource(selected_block())
		return Text.format("edit_no_stock", {"resource": Text.label("resource_" + resource)})
	return Text.label(problem)
