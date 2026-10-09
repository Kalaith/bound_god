extends RefCounted
## M2 acceptance: edits conserve stock, respect the shrine, and replay.
const Sim = preload("res://scripts/sim/sim.gd")
const Registry = preload("res://scripts/world/block_registry.gd")


func _sim() -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(48, 16, 48), "ground": 4})


func _edit(sim: RefCounted, cell: Vector3i, name: String = "air", meta: int = 0) -> Dictionary:
	return sim.apply_command({"type": "edit_block", "cell": cell, "id": Registry.id(name), "meta": meta})


func check_edit_stock_and_immediate_dirty_chunks() -> String:
	var sim: RefCounted = _sim()
	var cell := Vector3i(24, 5, 24)
	sim.set_block(cell, Registry.id("log"))
	sim.voxels.take_dirty_chunks()
	var tick: int = sim.calendar.tick
	if not _edit(sim, cell).ok or sim.god.stock("wood") != 4:
		return "breaking a log must yield four wood"
	if sim.voxels.get_block(cell) != 0 or sim.voxels.take_dirty_chunks().is_empty():
		return "breaking must change the grid and dirty its mesh immediately"
	if not _edit(sim, cell, "door", 2).ok or sim.god.stock("wood") != 3:
		return "placing a door must spend one wood"
	if sim.voxels.get_block(cell) != Registry.id("door") or sim.voxels.block_meta(cell) != 2:
		return "the placed door lost its block or orientation"
	if sim.calendar.tick != tick or sim.edit_sources.get(cell) != "god":
		return "edits must apply between ticks with their source recorded"
	var soil := Vector3i(25, 4, 24)
	if not _edit(sim, soil).ok or sim.god.stock("soil") != 1:
		return "grass terrain must yield one soil"
	if not _edit(sim, soil, "dirt").ok or sim.god.stock("soil") != 0:
		return "replacing terrain must spend the gathered soil"
	return ""


func check_edit_rejections_leave_state_unchanged() -> String:
	var sim: RefCounted = _sim()
	var tree := Vector3i(24, 5, 24)
	sim.set_block(tree, Registry.id("sacred_tree"))
	var cases: Array = [
		[Vector3i(25, 5, 24), "planks", "edit_no_stock"],
		[Vector3i(0, 4, 0), "air", "edit_outside_zone"],
		[Vector3i(-1, 4, 24), "air", "edit_outside_world"],
		[Vector3i(24, 0, 24), "air", "edit_unbreakable"],
		[tree, "air", "edit_unbreakable"],
		[Vector3i(24, 4, 24), "planks", "edit_occupied"],
		[Vector3i(25, 5, 24), "bedrock", "edit_unplaceable"],
	]
	for sample in cases:
		var before: PackedByteArray = _state(sim)
		var result: Dictionary = _edit(sim, sample[0], sample[1])
		if result.ok or result.reason != sample[2]:
			return "expected %s, got %s" % [sample[2], result]
		if _state(sim) != before:
			return "rejected edit changed state: " + str(sample[2])
	sim.god.dormant = true
	var before: PackedByteArray = _state(sim)
	var result: Dictionary = _edit(sim, Vector3i(25, 4, 24))
	if result.ok or result.reason != "edit_dormant" or _state(sim) != before:
		return "a dormant god must not edit or gain resources"
	return ""


func check_edit_bush_harvest_keeps_site_and_clears_berries() -> String:
	var sim: RefCounted = _sim()
	var cell := Vector3i(24, 5, 24)
	sim.set_block(cell, Registry.id("berry_bush"), 6)
	var site_id: int = sim.sites.by_cell[cell]
	var result: Dictionary = _edit(sim, cell)
	if not result.ok or result.reason != "edit_harvested" or sim.god.stock("berries") != 6:
		return "harvesting must collect the bush's ripe berries"
	if sim.voxels.get_block(cell) != Registry.id("berry_bush") or sim.voxels.block_meta(cell) != 0:
		return "harvest must leave an empty bush"
	if sim.sites.by_cell.get(cell) != site_id or sim.sites.get_site(site_id).amount != 0:
		return "harvest must retain the depleted resource site"
	if not _edit(sim, cell).ok or sim.god.stock("berries") != 7:
		return "dismantling the empty bush must return only its one-unit material yield"
	if sim.voxels.get_block(cell) != 0 or sim.sites.by_cell.has(cell):
		return "removing the empty bush must remove its resource site"
	if not _edit(sim, cell, "berry_bush", 99).ok:
		return "gathered berries must allow planting a bush"
	if sim.god.stock("berries") != 6 or sim.voxels.block_meta(cell) != 0:
		return "a planted bush costs one berry and cannot start ripe"
	return ""


func check_edit_command_log_replays_at_recorded_ticks() -> String:
	var original: RefCounted = _sim()
	var cell := Vector3i(24, 4, 24)
	if not _edit(original, cell).ok:
		return "could not gather replay fixture soil"
	original.run_ticks(7)
	var command: Dictionary = {"type": "edit_block", "cell": cell, "id": Registry.id("dirt")}
	if not original.apply_command(command).ok:
		return "could not place replay fixture dirt"
	command.id = Registry.id("stone")
	if original.command_log[1].command.id != Registry.id("dirt"):
		return "command log must own a copy of the submitted command"
	original.run_ticks(13)
	var replay: RefCounted = _sim()
	for entry in original.command_log:
		replay.run_ticks(int(entry.tick) - int(replay.calendar.tick))
		if not replay.apply_command(entry.command).ok:
			return "recorded command was rejected during replay"
	replay.run_ticks(int(original.calendar.tick) - int(replay.calendar.tick))
	if _state(original) != _state(replay):
		return "same seed and timed command log produced different state"
	return ""


func _state(sim: RefCounted) -> PackedByteArray:
	return var_to_bytes([
		sim.voxels.blocks, sim.voxels.meta, sim.voxels.edited_chunks,
		sim.god.to_dict(), sim.sites.to_dict(), sim.command_log,
		sim.edit_sources, sim.calendar.tick, sim.rng.state,
	])
