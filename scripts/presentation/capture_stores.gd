extends RefCounted
## Debug-only captures of storage and things in the world the god can use:
## `stores_blocks` (the blocks screen), `stores_prompt` (looking at a chest),
## `stores_chest` (a chest opened and given goods), `stores_door` (a doorway
## swung open) and `stores_guide` (the first steps pointing at the chest).
const Registry = preload("res://scripts/world/block_registry.gd")


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var tree: Vector3i = sim.features.sacred_tree
	main.avatar.global_position = Vector3(tree.x + 0.5, tree.y + 0.1, tree.z + 7.5)
	main.camera_rig.yaw = PI
	main.camera_rig.pitch = -0.5
	for resource in ["wood", "stone", "thatch", "berries"]:
		sim.god.add_stock(resource, 30)
	for _frame in range(10):
		await main.get_tree().process_frame
	match scenario:
		"stores_blocks":
			_set_hotbar(sim, ["storage_chest", "planks", "door", "bed"])
			main.pause_world_input()
			main.inventory.open(4)
		"stores_prompt", "stores_chest":
			_set_hotbar(sim, ["storage_chest"])
			var cell: Vector3i = await _place_ahead(main, "storage_chest")
			if scenario == "stores_chest":
				sim.apply_command({"type": "transfer", "chest": cell, "resource": "wood", "amount": 10})
				sim.apply_command({"type": "transfer", "chest": cell, "resource": "berries", "amount": 10})
				main.interaction.use()
			print("STORES chest=%s owner=%d stock=%s prompt=%s" % [cell, sim.settlements.chest_owner(cell), sim.settlements.stock_of(1), main.interaction.prompt()])
		"stores_door":
			_set_hotbar(sim, ["door"])
			var low: Vector3i = await _place_ahead(main, "door")
			sim.apply_command({"type": "edit_block", "cell": low + Vector3i.UP, "id": Registry.id("door"), "meta": sim.voxels.block_meta(low)})
			for _frame in range(4):
				await main.get_tree().process_frame
			main.interaction.use()
			main.world_view.remesh_now()
			print("STORES door meta=%d,%d" % [sim.voxels.block_meta(low), sim.voxels.block_meta(low + Vector3i.UP)])
		"stores_guide":
			sim.apply_command({"type": "edit_block", "cell": main.builder.target.cell, "id": 0})
	shot.shoot_after(90 if scenario == "stores_guide" else 30)


static func _set_hotbar(sim: RefCounted, names: Array) -> void:
	var slots: Array = []
	for name in names:
		slots.append(Registry.id(name))
	while slots.size() < 9:
		slots.append(0)
	sim.apply_command({"type": "set_hotbar", "slots": slots})


## Places a block where the crosshair points, as the right button would.
static func _place_ahead(main: Node3D, name: String) -> Vector3i:
	var cell: Vector3i = main.builder.place_cell
	main.builder.select(main.sim.god.hotbar.find(Registry.id(name)))
	for _frame in range(2):
		await main.get_tree().process_frame
	cell = main.builder.place_cell
	main.builder._act(false)
	for _frame in range(4):
		await main.get_tree().process_frame
	return cell
