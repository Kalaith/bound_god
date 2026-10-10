extends RefCounted
## The first people and places: the tree hollow where two travellers arrive,
## and the ridge hamlet of miners who have never heard of the god.
const Balance = preload("res://scripts/core/balance.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const Text = preload("res://scripts/core/text.gd")


static func found(sim: RefCounted, options: Dictionary) -> void:
	var tree: Vector3i = sim.features.sacred_tree
	var camp: Vector3i = sim.nav.nearest_walkable(tree + Vector3i(4, 0, -3), 5)
	var hollow: int = sim.settlements.create(Text.label("place_tree_hollow"), tree, camp, sim.calendar.tick)
	if options.get("people", true):
		var count: int = int(options.get("travellers", Balance.integer("population.travellers")))
		for i in range(count):
			var agent: RefCounted = Generation.adult(sim.rng, sim.agents.size())
			var cell: Vector3i = sim.nav.nearest_walkable(tree + Vector3i(3 + i, 0, 4), 6)
			arrive(sim, agent, cell, hollow, "arrival_traveller")
			# The travellers' packs: a few days of berries. There is no chest yet.
			agent.carrying = {"resource": "berries", "amount": float(Balance.integer("population.traveller_berries"))}
	if sim.features.has("hamlet"):
		_found_hamlet(sim, options)


static func _found_hamlet(sim: RefCounted, options: Dictionary) -> void:
	var hamlet: Dictionary = sim.features.hamlet
	var center: Vector3i = hamlet.center
	var camp: Vector3i = sim.nav.nearest_walkable(center, 4)
	var id: int = sim.settlements.create(Text.label("place_ridge_hamlet"), center, camp, sim.calendar.tick)
	# The miners' goods lie in the chests on their square.
	var chests: Array = hamlet.get("chests", [])
	var goods: Dictionary = Balance.dict("population.hamlet_stock")
	var resources: Array = goods.keys()
	resources.sort()
	for resource in resources:
		var left: int = int(goods[resource])
		for chest in chests:
			left -= sim.settlements.chest_add(chest, resource, left)
	for building in hamlet.buildings:
		for entry in sim.structures.built():
			var offset: Vector3i = entry.anchor - building.origin
			if offset.x >= -6 and offset.x <= 6 and offset.z >= -6 and offset.z <= 6 and absi(offset.y) <= 3 and entry.template_id.is_empty():
				entry.template_id = building.template
	sim.settlements.entries[id].known_templates = ["miner_hut", "lean_to"]
	if not options.get("people", true) or not options.get("miners", true):
		return
	for i in range(Balance.integer("population.miners")):
		var agent: RefCounted = Generation.adult(sim.rng, sim.agents.size(), "miner_roles")
		agent.beliefs.known_templates = ["miner_hut", "lean_to"]
		var cell: Vector3i = sim.nav.nearest_walkable(center + Vector3i(i - 2, 0, 1 - i % 2), 4)
		arrive(sim, agent, cell, id, "")
		for entry in sim.structures.built():
			if entry.functions.has("dwelling") and int(entry.capacity.get("beds", 0)) > entry.residents.size():
				sim.set_home(agent, entry.id)
				break
	# Neighbours of years: the miners know one another.
	for agent in sim.agents:
		if agent.settlement_id != id:
			continue
		for other in sim.agents:
			if other.settlement_id == id and other.id != agent.id:
				var relation: Dictionary = agent.beliefs.relation(other.id)
				relation.familiarity = 40.0
				relation.opinion = float(sim.rng.randi_range(-5, 30))


## A person enters the world at `cell` and joins a settlement.
static func arrive(sim: RefCounted, agent: RefCounted, cell: Vector3i, settlement: int, chronicle_kind: String) -> void:
	agent.cell = cell
	agent.position = Movement.center(cell)
	agent.previous_position = agent.position
	agent.joined_day = sim.calendar.day()
	agent.next_deliberation = sim.calendar.tick + agent.id % 3
	sim.agents.append(agent)
	sim.settlements.join(agent, settlement)
	agent.beliefs.stock = sim.settlements.stock_of(settlement).duplicate()
	if not chronicle_kind.is_empty():
		Mind.add(agent, "arrived", sim.calendar.ticks_per_day)
		sim.chronicle_event(chronicle_kind, settlement, {"name": agent.full_name(), "origin": agent.backstory.origin}, "", [agent.id])
