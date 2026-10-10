extends Node
## Using things in the world: Interact acts on the block under the crosshair
## when it is within reach. A chest opens its contents, a bed offers rest, a
## workbench opens the design library, a hearth is kindled, a door swings
## open or shut, and an altar or the sacred tree opens the shrine menu. With
## nothing usable in sight, Interact still opens the shrine menu nearby.
const Registry = preload("res://scripts/world/block_registry.gd")
const Text = preload("res://scripts/core/text.gd")
const ChestPanel = preload("res://scripts/presentation/ui/chest_panel.gd")
const ChoicePanel = preload("res://scripts/presentation/ui/choice_panel.gd")

const USABLE: Array[String] = ["chest", "granary_bin", "bed", "workbench", "hearth", "door", "altar", "sacred_tree"]

var main: Node3D
var sim: RefCounted
var chest_panel: Control
var choice_panel: Control


func _ready() -> void:
	chest_panel = ChestPanel.new()
	chest_panel.sim = sim
	main.ui_layer.add_child(chest_panel)
	chest_panel.closed.connect(func() -> void:
		chest_panel.hide()
		main.resume_world_input())
	chest_panel.transfer.connect(func(cell: Vector3i, resource: String, amount: int) -> void:
		var result: Dictionary = sim.apply_command({"type": "transfer", "chest": cell, "resource": resource, "amount": amount})
		chest_panel.notice(Text.label(result.reason), not result.ok))
	choice_panel = ChoicePanel.new()
	main.ui_layer.add_child(choice_panel)
	choice_panel.closed.connect(func() -> void:
		choice_panel.hide()
		if not main.modal_open():
			main.resume_world_input())


## The usable block under the crosshair within reach: {cell, kind} or {}.
func target() -> Dictionary:
	var hit: Dictionary = main.builder.target
	if not main.builder.enabled or not hit.get("hit", false):
		return {}
	var kind: String = Registry.component(int(hit.block))
	if not USABLE.has(kind):
		return {}
	var head: Vector3 = main.avatar.global_position + Vector3(0, 1.5, 0)
	if head.distance_to(Vector3(hit.cell) + Vector3(0.5, 0.5, 0.5)) > main.camera_rig.reach() + 0.9:
		return {}
	return {"cell": hit.cell, "kind": kind}


## The prompt shown under the crosshair, or "".
func prompt() -> String:
	var found: Dictionary = target()
	if found.is_empty():
		return ""
	var key: String = "use_" + str(found.kind)
	if found.kind == "door":
		key = "use_door_close" if sim.voxels.block_meta(found.cell) & Registry.DOOR_OPEN != 0 else "use_door_open"
	return Text.format("use_prompt", {"action": Text.label(key)})


func use() -> void:
	var found: Dictionary = target()
	if found.is_empty():
		if not main.faith.try_open_menu():
			main.hud.flash(Text.label("interact_nothing"), true)
		return
	var cell: Vector3i = found.cell
	match str(found.kind):
		"chest", "granary_bin":
			open_chest(cell)
		"bed":
			_rest_choices()
		"workbench":
			main.open_library()
		"hearth":
			main.faith.send({"type": "cast_miracle", "miracle": "kindle", "cell": cell + Vector3i.UP})
		"door":
			var result: Dictionary = sim.apply_command({"type": "toggle_door", "cell": cell})
			if result.ok:
				main.world_view.remesh_now()
			main.hud.flash(Text.label(result.reason), not result.ok)
		"altar", "sacred_tree":
			if not main.faith.try_open_menu():
				main.hud.flash(Text.label("interact_not_your_shrine"), true)


func open_chest(cell: Vector3i) -> void:
	main.pause_world_input()
	chest_panel.open(cell)


## The chest of a settlement nearest the avatar inside the presence, if any.
func open_settlement_chest(id: int) -> void:
	var here: Vector3 = main.avatar.global_position
	var best := Vector3i(-1, -1, -1)
	for chest in sim.settlements.chest_cells(sim, id):
		if not sim.in_zone(Vector3(chest) + Vector3(0.5, 0, 0.5)):
			continue
		if best.x < 0 or here.distance_to(Vector3(chest)) < here.distance_to(Vector3(best)):
			best = chest
	if best.x < 0:
		main.hud.flash(Text.label("stores_none_near"), true)
		return
	open_chest(best)


func _rest_choices() -> void:
	var choices: Array = []
	for days in [1.0, 5.0, 10.0]:
		choices.append([Text.format("shrine_menu_rest", {"days": int(days)}), func() -> void: main.rest(days)])
	main.pause_world_input()
	choice_panel.open(Text.label("bed_title"), Text.label("bed_hint"), choices)


func is_open() -> bool:
	return chest_panel.visible or choice_panel.visible
