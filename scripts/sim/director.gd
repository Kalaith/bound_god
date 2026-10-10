extends RefCounted
## The world's pressures from outside: migrants drawn to settlements worth
## living in, and later raiders drawn to wealth. Every arrival has a cause.
const Balance = preload("res://scripts/core/balance.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const Standing = preload("res://scripts/sim/standing.gd")

var raid_hooks: RefCounted = null


func daily(sim: RefCounted) -> void:
	var day: int = sim.calendar.day()
	var first: int = Balance.integer("population.first_migrant_day")
	var every: int = Balance.integer("population.migrant_roll_days")
	if day >= first and (day - first) % every == 0:
		_migrants(sim)
	if raid_hooks != null:
		raid_hooks.daily(sim)


## How attractive a settlement looks to someone on the road, and why.
static func attractiveness(sim: RefCounted, id: int) -> Array:
	var settlement: Dictionary = sim.settlements.entries[id]
	var beds: int = 0
	var housed: int = 0
	for entry in sim.structures.built():
		if Vector2(entry.anchor.x - settlement.center.x, entry.anchor.z - settlement.center.z).length() <= float(settlement.radius):
			beds += int(entry.capacity.get("beds", 0))
			housed += entry.residents.size()
	var spare: int = maxi(beds - housed, 0)
	var residents: int = maxi(settlement.residents.size(), 1)
	var homeless: int = 0
	for agent_id in settlement.residents:
		if sim.agents[agent_id].home < 0:
			homeless += 1
	var food_days: float = Standing.food_days(sim, id)
	var safety: float = 0.05 if threatened(sim, id) else 0.2
	var renown: float = sim.faith.settlement_renown(sim, id) if sim.faith != null else 0.0
	var standing: float = float(Balance.list("population.migrant_standing_pull")[Standing.rank(str(settlement.get("standing", "camp")))])
	var score: float = spare * 0.08 + minf(food_days, 2.0) * 0.12 + safety + renown + standing - homeless * 0.03
	return [score, spare, food_days]


## A threat near the settlement, not a wolf somewhere in the valley.
static func threatened(sim: RefCounted, id: int) -> bool:
	var settlement: Dictionary = sim.settlements.entries[id]
	var reach: float = float(settlement.radius) + Balance.number("population.safety_reach")
	for threat in sim.threats_list():
		if Vector2(threat.cell.x - settlement.center.x, threat.cell.z - settlement.center.z).length() <= reach:
			return true
	return false


func _migrants(sim: RefCounted) -> void:
	var cap: int = Balance.integer("population.cap")
	for id in sim.settlements.ids():
		if sim.present_count() >= cap:
			return
		var reason: Array = attractiveness(sim, id)
		if float(reason[0]) < Balance.number("population.migrant_threshold") or sim.rng.randf() >= float(reason[0]):
			continue
		var group: Array = Balance.list("population.migrant_group")
		var settlement: Dictionary = sim.settlements.entries[id]
		var extra: int = int(Balance.list("population.migrant_standing_group")[Standing.rank(str(settlement.get("standing", "camp")))])
		var count: int = mini(sim.rng.randi_range(int(group[0]), int(group[1]) + extra), cap - sim.present_count())
		var angle: float = sim.rng.randf() * TAU
		var edge: Vector3i = settlement.center + Vector3i(roundi(cos(angle) * (float(settlement.radius) - 3.0)), 0, roundi(sin(angle) * (float(settlement.radius) - 3.0)))
		var names: Array = []
		for i in range(count):
			var agent: RefCounted = Generation.adult(sim.rng, sim.agents.size())
			if sim.rng.randf() < 0.5:
				agent.beliefs.known_templates.append("lean_to")
			# Newcomers bring the ways of building where they came from.
			if sim.rng.randf() < Balance.number("population.migrant_design_chance"):
				var designs: Array = Balance.list("population.migrant_designs")
				var design: String = str(designs[sim.rng.randi_range(0, designs.size() - 1)])
				if not agent.beliefs.known_templates.has(design):
					agent.beliefs.known_templates.append(design)
			var cell: Vector3i = sim.nav.nearest_walkable(edge + Vector3i(i, 0, 0), 8)
			if cell.x < 0:
				cell = settlement.camp
			Population.arrive(sim, agent, cell, id, "")
			names.append(agent.full_name())
		var cause: String = "cause_attractive|%d|%d" % [int(reason[1]), floori(float(reason[2]))]
		sim.chronicle_event("arrival_migrants", id, {"names": ", ".join(names), "count": count}, cause, [])
