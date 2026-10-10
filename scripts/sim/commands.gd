extends RefCounted
## Player commands, applied between ticks and logged with their tick so the
## same seed and command log replay the same world. Every command is checked
## here; the presentation asks `edit_problem` to colour its preview.
const Registry = preload("res://scripts/world/block_registry.gd")
const Woods = preload("res://scripts/sim/woods.gd")


## Why the god cannot set `cell` to `block` right now, or "" if it can.
static func edit_problem(sim: RefCounted, cell: Vector3i, block: int, from: Vector3 = Vector3.INF, reach: float = INF) -> String:
	if sim.god.dormant:
		return "edit_dormant"
	if not sim.voxels.in_bounds(cell):
		return "edit_outside_world"
	if not sim.in_zone(Vector3(cell) + Vector3(0.5, 0.0, 0.5)):
		return "edit_outside_zone"
	if from != Vector3.INF and from.distance_to(Vector3(cell) + Vector3(0.5, 0.5, 0.5)) > reach + 0.9:
		return "edit_out_of_reach"
	var current: int = sim.voxels.get_block(cell)
	if block == 0:
		if current == 0 or Registry.breakable[current] == 0:
			return "edit_unbreakable"
		if sim.is_reserved_cell(cell):
			return "edit_site_cell"
		return ""
	if Registry.placeable[block] == 0:
		return "edit_unplaceable"
	if current != 0 and Registry.passable[current] == 0 and current != Registry.id("water"):
		return "edit_occupied"
	if current == Registry.id("sacred_tree"):
		return "edit_unbreakable"
	if Registry.solid[block] == 1 and sim.is_occupied(cell):
		return "edit_someone_there"
	if block == Registry.id("sapling") and not Woods.can_root(sim, cell):
		return "edit_needs_ground"
	var resource: String = Registry.resource(block)
	if not resource.is_empty() and sim.god.stock(resource) < 1:
		return "edit_no_stock"
	return ""


## Apply one command. Returns {ok, reason}.
static func apply(sim: RefCounted, command: Dictionary) -> Dictionary:
	var result: Dictionary
	match str(command.get("type", "")):
		"edit_block":
			result = _edit(sim, command)
		_:
			if sim.has_method("apply_extended_command"):
				result = sim.apply_extended_command(command)
			else:
				result = {"ok": false, "reason": "command_unknown"}
	# The avatar's footsteps and the hotbar are state, not decisions; they are
	# not replayed.
	if result.ok and not command.get("type", "") in ["avatar_moved", "set_hotbar"]:
		sim.command_log.append({"tick": sim.calendar.tick, "command": command.duplicate(true)})
	return result


static func _edit(sim: RefCounted, command: Dictionary) -> Dictionary:
	var cell: Vector3i = command.cell
	var block: int = int(command.get("id", 0))
	var problem: String = edit_problem(sim, cell, block)
	if not problem.is_empty():
		return {"ok": false, "reason": problem}
	var current: int = sim.voxels.get_block(cell)
	if block == 0:
		# A ripe bush gives its berries and stays.
		if current == Registry.id("berry_bush") and sim.voxels.block_meta(cell) > 0:
			sim.god.add_stock("berries", sim.voxels.block_meta(cell))
			sim.set_block(cell, current, 0, "god")
			return {"ok": true, "reason": "edit_harvested"}
		sim.god.add_stock(Registry.resource(current), Registry.yields[current])
		# Some leaves hold a tree seed.
		if current == Registry.id("leaves") and Woods.leaf_holds_seed(cell):
			sim.god.add_stock("tree_seed", 1)
		sim.set_block(cell, 0, 0, "god")
		return {"ok": true, "reason": ""}
	var meta: int = int(command.get("meta", 0))
	if block == Registry.id("berry_bush"):
		meta = 0
	sim.god.add_stock(Registry.resource(block), -1)
	sim.set_block(cell, block, meta, "god")
	return {"ok": true, "reason": ""}
