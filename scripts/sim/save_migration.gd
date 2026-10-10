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
	return {"entries": entries, "next_id": data.next_id, "chests": chests, "stocks": stocks, "bins": {}, "lots": {}}


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


## Before schema 3 there were no lanterns, so an older world has none lit.
static func lanterns(state: Dictionary) -> Dictionary:
	if int(state.schema_version) < 3:
		return {}
	return state.lanterns


## Before schema 4 nothing spoiled and there were no granary bins: the food
## already in the chests and lying loose is dated the day the save loads.
static func food_from_3(state: Dictionary, settlements: Dictionary) -> Dictionary:
	if int(state.schema_version) >= 4:
		return settlements
	var day: int = int(state.tick) / Balance.integer("time.ticks_per_day") + 1
	var result: Dictionary = settlements.duplicate(true)
	var lots: Dictionary = {}
	for cell in result.chests:
		for resource in result.chests[cell]:
			if Balance.dict("food.spoil_days").has(resource):
				var held: Dictionary = lots.get(cell, {})
				held[resource] = [[day, int(result.chests[cell][resource])]]
				lots[cell] = held
	result["bins"] = {}
	result["lots"] = lots
	# Farming became a kind of work people's culture weighs.
	for id in result.entries:
		result.entries[id].culture["farm"] = 1.0
	for id in state.items:
		state.items[id]["day"] = day
	return result


## Before schema 4 nothing was sown.
static func crops(state: Dictionary) -> Dictionary:
	if int(state.schema_version) < 4:
		return {"plots": {}}
	return state.crops


## Before schema 4 nobody cooked.
static func kitchens(state: Dictionary) -> Dictionary:
	if int(state.schema_version) < 4:
		return {"pots": {}, "places": {}}
	return state.kitchens
