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
	var board: Dictionary = {"builds": [], "repairs": [], "gather_demand": {}, "items": [], "threats": []}
	var stock: Dictionary = settlement.stock
	var site_need: Dictionary = {}
	for site_id in sim.construction.in_settlement(id):
		var missing: Dictionary = sim.construction.missing(site_id)
		board.builds.append({"site": site_id, "ready": sim.construction.ready_to_build(site_id), "missing": missing})
		for resource in missing:
			site_need[resource] = int(site_need.get(resource, 0)) + int(missing[resource])
	var loose: Dictionary = {}
	for item_id in _sorted(sim.items.keys()):
		var item: Dictionary = sim.items[item_id]
		if _distance(item.cell, settlement.center) <= float(settlement.radius):
			board.items.append(item_id)
			loose[item.resource] = float(loose.get(item.resource, 0.0)) + float(item.amount)
	var residents: int = settlement.residents.size()
	for resource in RESOURCES:
		var reserve: Array = RESERVE[resource]
		var wanted: float = float(reserve[0]) + float(reserve[1]) * residents + float(site_need.get(resource, 0))
		var have: float = float(stock.get(resource, 0)) + float(loose.get(resource, 0.0))
		if wanted > 0.0:
			board.gather_demand[resource] = clampf((wanted - have) / wanted, 0.0, 1.0)
	if sim.settlement_life != null:
		board.repairs = sim.settlement_life.repairs_for(sim, id)
	for threat in sim.threats_list():
		if _distance(threat.cell, settlement.center) <= float(settlement.radius) + 8.0:
			board.threats.append(threat.id)
	board["housing_deficit"] = housing_deficit(sim, id)
	return board


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
