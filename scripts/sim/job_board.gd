extends RefCounted
## A settlement's job board, refreshed every 10 ticks: building sites and
## what they lack, repairs, how much each resource is wanted, loose items to
## haul and threats near home. Nothing on it is assigned; people read it.
const Balance = preload("res://scripts/core/balance.gd")

const RESOURCES: Array[String] = ["wood", "stone", "thatch", "berries", "ore"]
const SITE_KIND: Dictionary = {"wood": "tree", "stone": "rock", "thatch": "grass", "berries": "bush", "ore": "ore"}
## Stock a settlement likes to keep before anyone needs it: base + per resident.
const RESERVE: Dictionary = {"wood": [12, 2], "stone": [8, 1], "thatch": [8, 1], "berries": [6, 4], "ore": [0, 0]}


static func refresh(sim: RefCounted, settlement: Dictionary) -> Dictionary:
	var id: int = int(settlement.id)
	var board: Dictionary = {"builds": [], "repairs": [], "gather_demand": {}, "items": [], "loose": [], "threats": []}
	var stock: Dictionary = sim.settlements.stock_of(id)
	var site_need: Dictionary = {}
	for site_id in sim.construction.in_settlement(id):
		var missing: Dictionary = sim.construction.missing(site_id)
		board.builds.append({"site": site_id, "ready": sim.construction.ready_to_build(site_id), "missing": missing})
		for resource in missing:
			site_need[resource] = int(site_need.get(resource, 0)) + int(missing[resource])
	var loose: Dictionary = {}
	# Loose goods are worth hauling only when a chest has room for them.
	var room: bool = sim.settlements.capacity(sim, id) > sim.settlements.total(id)
	for item_id in _sorted(sim.items.keys()):
		var item: Dictionary = sim.items[item_id]
		if _distance(item.cell, settlement.center) <= float(settlement.radius):
			board.loose.append(item_id)
			if room:
				board.items.append(item_id)
			loose[item.resource] = float(loose.get(item.resource, 0.0)) + float(item.amount)
	var residents: int = settlement.residents.size()
	# Before winter, people want food put by for the months without berries.
	var autumn: bool = sim.calendar.season() == int(Balance.number("settlements.autumn_season"))
	for resource in RESOURCES:
		var reserve: Array = RESERVE[resource]
		var per_person: float = Balance.number("settlements.autumn_berries_per_person") if autumn and resource == "berries" else float(reserve[1])
		var wanted: float = float(reserve[0]) + per_person * residents + float(site_need.get(resource, 0))
		var have: float = float(stock.get(resource, 0)) + float(loose.get(resource, 0.0))
		if wanted > 0.0:
			board.gather_demand[resource] = clampf((wanted - have) / wanted, 0.0, 1.0)
	if sim.settlement_life != null:
		board.repairs = sim.settlement_life.repairs_for(sim, id)
	for threat in sim.threats_list():
		if _distance(threat.cell, settlement.center) <= float(settlement.radius) + 8.0:
			board.threats.append(threat.id)
	board["housing_deficit"] = housing_deficit(sim, id)
	board["plots"] = plots(sim, id)
	board["ripe"] = ripe(sim, id)
	return board


## Garden bushes worth picking: [garden id, bush site id], a few at most.
static func ripe(sim: RefCounted, id: int) -> Array:
	var result: Array = []
	var least: int = Balance.integer("world.garden_pick_at")
	for entry in sim.structures.built():
		if not entry.functions.has("garden") or sim.settlements.at_cell(entry.anchor) != id:
			continue
		var cells: Array = entry.components.get("planter", []).duplicate()
		cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return [a.y, a.z, a.x] < [b.y, b.z, b.x])
		for planter in cells:
			var site: int = int(sim.sites.by_cell.get(planter + Vector3i.UP, -1))
			if site >= 0 and sim.voxels.block_meta(planter + Vector3i.UP) >= least:
				result.append([int(entry.id), site])
				if result.size() >= 6:
					return result
	return result


## Empty planters in the settlement's gardens: [garden id, cell above], a
## few at most, in a stable order.
static func plots(sim: RefCounted, id: int) -> Array:
	var result: Array = []
	for entry in sim.structures.built():
		if not entry.functions.has("garden") or sim.settlements.at_cell(entry.anchor) != id:
			continue
		var cells: Array = entry.components.get("planter", []).duplicate()
		cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return [a.y, a.z, a.x] < [b.y, b.z, b.x])
		for planter in cells:
			var above: Vector3i = planter + Vector3i.UP
			if sim.voxels.get_block(above) == 0 and not sim.is_reserved_cell(above):
				result.append([int(entry.id), above])
				if result.size() >= 6:
					return result
	return result


## People in the settlement without a bed of their own.
static func housing_deficit(sim: RefCounted, id: int) -> int:
	var count: int = 0
	for agent_id in sim.settlements.entries[id].residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present() and agent.home < 0:
			count += 1
	return count


static func _sorted(keys: Array) -> Array:
	keys.sort()
	return keys


static func _distance(a: Vector3i, b: Vector3i) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
