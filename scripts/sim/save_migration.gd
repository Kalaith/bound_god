extends RefCounted
## Brings saves from older schemas up to the current one before they load.
const Registry = preload("res://scripts/world/block_registry.gd")
const Balance = preload("res://scripts/core/balance.gd")


## Schema 1 kept each settlement's stock as one pooled count in a pile. From
## schema 2 goods live in real chests: the old stock goes into the chests
## standing in each settlement and whatever does not fit lies loose at the camp.
static func settlements_from_1(sim: RefCounted, data: Dictionary) -> Dictionary:
	var entries: Dictionary = data.entries.duplicate(true)
	var stocks: Dictionary = {}
	for id in entries:
		var entry: Dictionary = entries[id]
		entry["camp"] = entry.get("pile", entry.center)
		entry.erase("pile")
		stocks[id] = entry.get("stock", {})
		entry.erase("stock")
	var chests: Dictionary = {}
	var chest_id: int = Registry.id("storage_chest")
	var blocks: PackedByteArray = sim.voxels.blocks
	var size: Vector3i = sim.voxels.size
	for index in range(blocks.size()):
		if blocks[index] == chest_id:
			chests[Vector3i(index % size.x, index / (size.x * size.z), (index / size.x) % size.z)] = {}
	return {"entries": entries, "next_id": data.next_id, "chests": chests, "stocks": stocks}


## Schema 1 had no chosen hotbar; the god starts with empty slots.
static func empty_hotbar() -> Array:
	var slots: Array = []
	slots.resize(Balance.integer("avatar.hotbar_slots"))
	slots.fill(0)
	return slots


## After the migrated settlements are in place: fill their chests.
static func store_old_stock(sim: RefCounted, stocks: Dictionary) -> void:
	var ids: Array = stocks.keys()
	ids.sort()
	for id in ids:
		var chests: Array = sim.settlements.chest_cells(sim, id)
		var resources: Array = stocks[id].keys()
		resources.sort()
		for resource in resources:
			var left: int = int(stocks[id][resource])
			for chest in chests:
				left -= sim.settlements.chest_add(chest, resource, left)
			if left > 0:
				sim.drop_item(sim.settlements.entries[id].camp, resource, float(left))
