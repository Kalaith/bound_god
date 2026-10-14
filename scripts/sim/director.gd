extends RefCounted
## The world's pressures from outside: migrants drawn to settlements worth
## living in, and later raiders drawn to wealth. Every arrival has a cause.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const Perception = preload("res://scripts/sim/perception.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const SectHalls = preload("res://scripts/sim/sect_halls.gd")

var raid_hooks: RefCounted = null


func daily(sim: RefCounted) -> void:
	var day: int = sim.calendar.day()
	var first: int = Balance.integer("population.first_migrant_day")
	var every: int = Balance.integer("population.migrant_roll_days")
	if day >= first and (day - first) % every == 0:
		_migrants(sim)
	# A world begun without outlaws has none (M23 new-world options).
	if raid_hooks != null and sim.options.get("outlaws", true):
		raid_hooks.daily(sim)


## How attractive a settlement looks to someone on the road, and why.
static func attractiveness(sim: RefCounted, id: int) -> Array:
	var settlement: Dictionary = sim.settlements.entries[id]
	# A home with people living in it does not look free from the road, even
	# where a couple shares one bed: beds beyond the residents are spare.
	var spare: int = 0
	for entry in sim.structures.built():
		if Vector2(entry.anchor.x - settlement.center.x, entry.anchor.z - settlement.center.z).length() <= float(settlement.radius):
			spare += maxi(int(entry.capacity.get("beds", 0)) - entry.residents.size(), 0)
	var homeless: int = 0
	for agent_id in settlement.residents:
		if sim.agents[agent_id].is_present() and sim.agents[agent_id].home < 0:
			homeless += 1
	var food_days: float = Standing.food_days(sim, id)
	var safety: float = 0.05 if threatened(sim, id) else 0.2
	var renown: float = sim.faith.settlement_renown(sim, id) if sim.faith != null else 0.0
	var standing: float = float(Balance.list("population.migrant_standing_pull")[Standing.rank(str(settlement.get("standing", "camp")))])
	# The tree's qi draws those who would cultivate.
	var qi: float = sim.qi.density(sim, settlement.center) * Balance.number("cultivation.qi_pull") if sim.qi != null else 0.0
	var score: float = spare * 0.08 + minf(food_days, 2.0) * 0.12 + safety + renown + standing + qi - homeless * 0.03
	# Word travels that a place is going hungry.
	if food_days < Balance.number("population.hungry_food_days") and Standing.present(sim, id) > Balance.integer("population.hungry_people"):
		score -= Balance.number("population.hungry_penalty")
	return [score, spare, food_days]


## A threat near the settlement, not a wolf somewhere in the valley. Wolves
## do not count against a settlement lit by lanterns.
static func threatened(sim: RefCounted, id: int) -> bool:
	var settlement: Dictionary = sim.settlements.entries[id]
	var reach: float = float(settlement.radius) + Balance.number("population.safety_reach")
	var lit: int = 0
	for cell in sim.lanterns:
		if sim.settlements.at_cell(cell) == id:
			lit += 1
	for threat in sim.threats_list():
		if threat.kind == "wolf" and lit >= Balance.integer("population.lit_lanterns"):
			continue
		if Vector2(threat.cell.x - settlement.center.x, threat.cell.z - settlement.center.z).length() <= reach:
			return true
	return false


func _migrants(sim: RefCounted) -> void:
	var cap: int = sim.migrant_cap()
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
		var seekers: Array = []
		var seek_chance: float = Balance.number("cultivation.seeker_chance") * (sim.qi.density(sim, settlement.center) if sim.qi != null else 0.0)
		# A mountain gate is seen from the road: seekers of the Way turn in.
		seek_chance = minf(seek_chance * SectHalls.seek_factor(sim, id), 1.0)
		for i in range(count):
			var agent: RefCounted = Generation.adult(sim.rng, sim.agents.size())
			if sim.rng.randf() < seek_chance:
				agent.cultivation = CultivationState.roll(sim.rng, true)
				seekers.append(agent.full_name())
			if sim.rng.randf() < 0.5:
				agent.beliefs.known_templates.append("lean_to")
			# Newcomers bring the ways of building where they came from.
			if sim.rng.randf() < Balance.number("population.migrant_design_chance"):
				var designs: Array = Balance.list("population.migrant_designs")
				var design: String = str(designs[sim.rng.randi_range(0, designs.size() - 1)])
				if not agent.beliefs.known_templates.has(design):
					agent.beliefs.known_templates.append(design)
			# They passed open land on the road and remember it.
			var grounds: Array = sim.features.get("grounds", [])
			if not grounds.is_empty() and sim.rng.randf() < Balance.number("population.migrant_knows_ground"):
				Perception.note_ground(sim, agent, sim.rng.randi_range(0, grounds.size() - 1))
			var cell: Vector3i = sim.nav.nearest_walkable(edge + Vector3i(i, 0, 0), 8)
			if cell.x < 0:
				cell = settlement.camp
			Population.arrive(sim, agent, cell, id, "")
			names.append(agent.full_name())
		var cause: String = "cause_attractive|%d|%d" % [int(reason[1]), floori(float(reason[2]))]
		sim.chronicle_event("arrival_migrants", id, {"names": ", ".join(names), "count": count}, cause, [])
		if not seekers.is_empty():
			sim.chronicle_event("arrival_seekers", id, {"names": ", ".join(seekers)}, "cause_drawn_by_qi", [])
