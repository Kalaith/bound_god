extends RefCounted
## Homes (user request, 2026-10-11): a bed sleeps a couple, partners move in
## together, the homeless take free beds while the valley is abstract, and
## the dead no longer count among a settlement's homeless.
const Sim = preload("res://scripts/sim/sim.gd")
const Build = preload("res://tools/checks/build.gd")
const Homes = preload("res://scripts/sim/homes.gd")
const Lifecycle = preload("res://scripts/sim/lifecycle.gd")
const Director = preload("res://scripts/sim/director.gd")
const Population = preload("res://scripts/sim/population.gd")
const Generation = preload("res://scripts/agents/generation.gd")


## Tree Hollow with `count` grown people beside the camp and two cottages
## stamped where its people would build them. Returns [sim, people, homes].
func _hollow(count: int) -> Array:
	var sim: RefCounted = Sim.create(11)
	var camp: Vector3i = sim.settlements.entries[1].camp
	var people: Array = []
	for agent in sim.agents:
		if agent.settlement_id == 1:
			people.append(agent)
	while people.size() < count:
		var agent: RefCounted = Generation.adult(sim.rng, sim.agents.size())
		Population.arrive(sim, agent, sim.nav.nearest_walkable(camp + Vector3i(people.size() % 3, 0, 2), 4), 1, "")
		people.append(agent)
	var homes: Array = []
	for i in range(2):
		Build.stamp(sim, 1, "timber_cottage")
		for entry in sim.structures.built():
			if entry.functions.has("dwelling") and sim.settlements.at_cell(entry.anchor) == 1 and not homes.has(entry.id):
				homes.append(entry.id)
	return [sim, people, homes]


func _pair(sim: RefCounted, a: RefCounted, b: RefCounted) -> void:
	a.partner = b.id
	b.partner = a.id


func check_partners_share_a_bed_and_move_in_together():
	var made: Array = _hollow(3)
	var sim: RefCounted = made[0]
	var people: Array = made[1]
	var homes: Array = made[2]
	if homes.size() < 2:
		return "only %d cottages could be stamped" % homes.size()
	var a: RefCounted = people[0]
	var b: RefCounted = people[1]
	var stranger: RefCounted = people[2]
	var home: Dictionary = sim.structures.entries[homes[0]]
	var beds: int = int(home.capacity.get("beds", 0))
	# Fill every bed of the first cottage with `a` and strangers.
	sim.set_home(a, home.id)
	for i in range(beds - 1):
		var filler: RefCounted = Generation.adult(sim.rng, sim.agents.size())
		Population.arrive(sim, filler, a.cell, 1, "")
		sim.set_home(filler, home.id)
	sim.set_home(b, homes[1])
	_pair(sim, a, b)
	if Homes.free_beds(sim, home) != 0:
		return "the first cottage should be full, has %d free" % Homes.free_beds(sim, home)
	if Homes.has_room(sim, home, stranger):
		return "a stranger found room in a full home"
	if not Homes.has_room(sim, home, b):
		return "a partner found no room beside their partner's bed"
	Homes.daily(sim, false)
	if a.home != b.home:
		return "partners still live apart (%d, %d)" % [a.home, b.home]
	if Homes.free_beds(sim, home) != 0 or sim.structures.entries[homes[1]].residents.size() != 0:
		return "moving in together should free the other cottage"
	var noted: bool = false
	for entry in sim.chronicle.entries:
		noted = noted or str(entry.kind) == "moved_in_together"
	if not noted:
		return "the move was not chronicled"
	return ""


func check_the_homeless_take_free_beds_only_while_abstract():
	var made: Array = _hollow(2)
	var sim: RefCounted = made[0]
	var people: Array = made[1]
	if made[2].is_empty():
		return "no cottage could be stamped"
	for agent in people:
		sim.set_home(agent, -1)
	Homes.daily(sim, false)
	for agent in people:
		if agent.home >= 0:
			return "a bed was claimed by the daily rule in the detailed world"
	Homes.daily(sim, true)
	for agent in people:
		if agent.home < 0:
			return "%s stayed homeless beside a free bed while abstract" % agent.given_name
		if sim.settlements.at_cell(sim.structures.entries[agent.home].anchor) != agent.settlement_id:
			return "a bed was claimed in another settlement"
	# The ridge folk never take Tree Hollow's beds.
	for agent in sim.agents:
		if agent.settlement_id != 1 and agent.home >= 0 and sim.settlements.at_cell(sim.structures.entries[agent.home].anchor) == 1:
			return "a hamlet miner moved into Tree Hollow"
	return ""


func check_the_dead_are_not_counted_homeless():
	var made: Array = _hollow(4)
	var sim: RefCounted = made[0]
	var people: Array = made[1]
	var before: float = float(Director.attractiveness(sim, 1)[0])
	for agent in people.slice(0, 3):
		sim.set_home(agent, -1)
		Lifecycle.die(sim, agent, "cause_old_age")
	if sim.settlements.entries[1].residents.has(people[0].id):
		return "the dead stayed on the settlement's list"
	# An older save still lists its dead: they drop off at the day's turn.
	sim.settlements.entries[1].residents.append(people[1].id)
	Homes.daily(sim, false)
	if sim.settlements.entries[1].residents.has(people[1].id):
		return "the dead listed by an older save stayed listed"
	var after: float = float(Director.attractiveness(sim, 1)[0])
	if after < before - 0.001:
		return "the dead still weigh on the migrants' choice (%.2f before, %.2f after)" % [before, after]
	return ""
