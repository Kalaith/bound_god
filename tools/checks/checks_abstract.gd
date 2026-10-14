extends RefCounted
## The abstract settlement model (architecture §1): frozen people thaw whole, and
## a year passes in hourly steps by the detailed rules, cheaply.
const Sim = preload("res://scripts/sim/sim.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")
const Stores = preload("res://tools/checks/stores.gd")
const Build = preload("res://tools/checks/build.gd")


static func _settle(sim: RefCounted, people: int) -> void:
	var camp: Vector3i = sim.settlements.entries[1].camp
	var i: int = 0
	while Standing.present(sim, 1) < people:
		var cell: Vector3i = sim.nav.nearest_walkable(camp + Vector3i(i % 6 - 3, 0, i / 6 - 3), 6)
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), cell, 1, "")
		i += 1


## Forty people frozen and thawed keep who they are, what they know and
## whom they love; they come back on ground they can stand on.
func check_frozen_people_thaw_whole():
	var sim: RefCounted = Sim.create(11)
	_settle(sim, 40)
	sim.run_ticks(60)
	var before: Dictionary = {}
	for agent in sim.agents:
		if agent.is_present():
			before[agent.id] = [agent.needs, agent.faith.duplicate(true), agent.beliefs.relations.duplicate(true), agent.home, agent.beliefs.known_templates.duplicate()]
	var started: int = Time.get_ticks_usec()
	var model: RefCounted = AbstractWorld.begin(sim)
	model.finish(sim)
	var elapsed: float = (Time.get_ticks_usec() - started) / 1000.0
	print("      froze and thawed %d people in %.1f ms" % [before.size(), elapsed])
	for id in before:
		var agent: RefCounted = sim.agents[id]
		var now: Array = [agent.needs, agent.faith, agent.beliefs.relations, agent.home, agent.beliefs.known_templates]
		for i in range(now.size()):
			if var_to_bytes(now[i]) != var_to_bytes(before[id][i]):
				return "%s changed while frozen (part %d)" % [agent.full_name(), i]
		if not sim.nav.is_walkable(agent.cell) or not agent.intention.is_empty():
			return "%s thawed off the ground or still holding a plan" % agent.full_name()
	sim.run_ticks(30)
	return ""


## A year of a settlement in hourly steps: twelve people with a field and
## some stores. It must be cheap (architecture §3: < 0.2 ms an hour a settlement;
## checked here against 1 ms to leave room for slower machines), keep stock
## whole and give every death a cause; it reports how the year went.
func check_a_year_passes_abstractly():
	var sim: RefCounted = Sim.create(11)
	_settle(sim, 12)
	sim.run_ticks(12)
	Stores.place_chest(sim, 1)
	Stores.fill(sim, 1, {"berries": 60, "grain": 40, "wood": 20})
	if Build.stamp(sim, 1, "field_plot").x < 0:
		return "no room for the field"
	var dead_before: int = 0
	for entry in sim.chronicle.entries:
		dead_before += 1 if entry.kind == "death" else 0
	var model: RefCounted = AbstractWorld.begin(sim)
	var hours: int = sim.calendar.days_per_season * 4 * 24
	var started: int = Time.get_ticks_usec()
	model.run_hours(sim, hours)
	var elapsed: float = (Time.get_ticks_usec() - started) / 1000.0
	var begun: int = Time.get_ticks_usec()
	model.finish(sim)
	var thaw_ms: float = (Time.get_ticks_usec() - begun) / 1000.0
	var per_hour: float = elapsed / hours / sim.settlements.ids().size()
	var deaths: Dictionary = {}
	var harvests: int = 0
	for entry in sim.chronicle.entries:
		if entry.kind == "death":
			if str(entry.cause).is_empty():
				return "a death without a cause"
			deaths[entry.cause] = int(deaths.get(entry.cause, 0)) + 1
		harvests += 1 if entry.kind == "first_harvest" else 0
	print("      a year in %.2f s (%.3f ms an hour a settlement), thaw %.0f ms; Tree Hollow %d people, %s; deaths %s; first harvest %s" % [
		elapsed / 1000.0, per_hour, thaw_ms, Standing.present(sim, 1), str(sim.settlements.stock_of(1)), str(deaths), harvests > 0])
	for cell in sim.settlements.chests:
		for resource in sim.settlements.chests[cell]:
			if int(sim.settlements.chests[cell][resource]) < 0:
				return "negative stock in a chest"
	if per_hour > 1.0:
		return "an abstract hour costs %.3f ms a settlement" % per_hour
	if harvests == 0:
		return "the field was never reaped"
	sim.run_ticks(60)
	return ""
