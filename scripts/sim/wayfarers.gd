extends RefCounted
## Wayfarers: every so often (`designs.wayfarer_days` apart, never in
## winter) someone passing through the valley stops at a settlement for a
## night or two, shares the plans of a building it lacks (or one its people
## have never seen), and moves on. They are people like any other while they
## stay, but build no home of their own (`backstory.wayfarer`). The next
## visit and the guests now staying are kept in the settlement's record
## (`next_wayfarer`, `guests`). Their comings draw on a stream of their own,
## seeded from the world, the settlement and the day, so the valley's other
## chances fall as they would without them.
const Balance = preload("res://scripts/core/balance.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const Lore = preload("res://scripts/sim/designs_lore.gd")


## Whether this person is only passing through.
static func passing(agent: RefCounted) -> bool:
	return bool(agent.backstory.get("wayfarer", false))


static func _stream(sim: RefCounted, id: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.world_seed, id, sim.calendar.day(), "wayfarer"])
	return rng


static func daily(sim: RefCounted) -> void:
	var gap: Array = Balance.list("designs.wayfarer_days")
	for id in sim.settlements.ids():
		var settlement: Dictionary = sim.settlements.entries[id]
		_see_off(sim, id, settlement)
		var rng: RandomNumberGenerator = _stream(sim, id)
		if not settlement.has("next_wayfarer"):
			settlement["next_wayfarer"] = sim.calendar.tick + rng.randi_range(int(gap[0]), int(gap[1])) * sim.calendar.ticks_per_day
			continue
		if int(settlement.next_wayfarer) > sim.calendar.tick or sim.calendar.is_winter():
			continue
		settlement["next_wayfarer"] = sim.calendar.tick + rng.randi_range(int(gap[0]), int(gap[1])) * sim.calendar.ticks_per_day
		var design: String = _plans_for(sim, id, rng)
		if not design.is_empty():
			_arrive(sim, id, settlement, design, rng)


## What a wayfarer would share: plans for something the settlement lacks,
## else a design of the valley's ways (or, where a sect stands, of the
## wandering cultivators') that nobody there knows yet.
static func _plans_for(sim: RefCounted, id: int, rng: RandomNumberGenerator) -> String:
	for want in Lore.lacking(sim, id):
		var template_id: String = Lore.starter_for(sim, str(want[0]), [])
		if not template_id.is_empty():
			return template_id
	return Lore.unknown_design(sim, id, rng)


static func _arrive(sim: RefCounted, id: int, settlement: Dictionary, design: String, rng: RandomNumberGenerator) -> void:
	var agent: RefCounted = Generation.adult(rng, sim.agents.size())
	agent.backstory["wayfarer"] = true
	agent.beliefs.known_templates.append(design)
	var cell: Vector3i = sim.nav.nearest_walkable(settlement.camp + Vector3i(3, 0, 3), 6)
	if cell.x < 0:
		cell = settlement.camp
	Population.arrive(sim, agent, cell, id, "")
	Lore.learn(sim, id, design)
	var stay: Array = Balance.list("designs.wayfarer_stay_days")
	var guests: Array = settlement.get("guests", [])
	guests.append({"agent": agent.id, "leave": sim.calendar.tick + rng.randi_range(int(stay[0]), int(stay[1])) * sim.calendar.ticks_per_day})
	settlement["guests"] = guests
	sim.chronicle_event("wayfarer_came", id, {"name": agent.full_name(), "origin": agent.backstory.origin, "design": sim.template_name(design)}, "", [agent.id])


## Guests whose stay is over go on their way.
static func _see_off(sim: RefCounted, id: int, settlement: Dictionary) -> void:
	var guests: Array = settlement.get("guests", [])
	for guest in guests.duplicate():
		if int(guest.leave) > sim.calendar.tick:
			continue
		guests.erase(guest)
		var agent: RefCounted = sim.agents[int(guest.agent)]
		if not agent.is_present():
			continue
		agent.life = "departed"
		agent.life_day = sim.calendar.day()
		agent.intention = {}
		agent.path.clear()
		sim.goal_version += 1
		sim.set_home(agent, -1)
		settlement.residents.erase(agent.id)
		if agent.partner >= 0 and sim.agents[agent.partner].partner == agent.id:
			sim.agents[agent.partner].partner = -1
		sim.chronicle_event("wayfarer_moved_on", id, {"name": agent.full_name()}, "", [agent.id])
