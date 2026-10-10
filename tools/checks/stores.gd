extends RefCounted
## Check helpers for settlement stores, which now live in real chests: set a
## settlement's stock exactly, placing chests beside its camp when it has too
## few to hold the goods.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")


## Places a storage chest on open ground near the camp; returns its cell.
static func place_chest(sim: RefCounted, id: int) -> Vector3i:
	var camp: Vector3i = sim.settlements.entries[id].camp
	for ring in range(2, 8):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var cell: Vector3i = sim.nav.surface(camp.x + dx, camp.z + dz)
				if cell.x < 0 or sim.is_occupied(cell) or sim.is_reserved_cell(cell) or sim.settlements.chests.has(cell):
					continue
				# On the ground, not up in a tree's crown where nobody can reach it.
				if not Registry.component(sim.voxels.get_block(cell + Vector3i.DOWN)).is_empty() or sim.voxels.get_block(cell + Vector3i.DOWN) in [Registry.id("leaves"), Registry.id("sacred_leaves"), Registry.id("log")]:
					continue
				if sim.set_block(cell, Registry.id("storage_chest"), 0, "test"):
					return cell
	return Vector3i(-1, -1, -1)


## Empties the settlement's chests and fills them with `goods`.
static func fill(sim: RefCounted, id: int, goods: Dictionary) -> void:
	var needed: int = 0
	for resource in goods:
		needed += int(goods[resource])
	while sim.settlements.capacity(sim, id) < needed:
		if place_chest(sim, id).x < 0:
			break
	var chests: Array = sim.settlements.chest_cells(sim, id)
	for chest in chests:
		sim.settlements.chests[chest] = {}
	sim.settlements.version += 1
	var resources: Array = goods.keys()
	resources.sort()
	for resource in resources:
		var left: int = int(goods[resource])
		for chest in chests:
			left -= sim.settlements.chest_add(chest, resource, left)
