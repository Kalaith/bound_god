extends RefCounted
## How a settlement comes to know designs without the god: someone works
## one out, hour by hour, for a building the settlement wants and nobody
## living there knows how to raise; or someone sets out from the valley and
## comes back days later with the plans of places beyond it.
##
## Working out: ordinary people work out the ways of building of valley and
## ridge folk (the starters by those authors); only a sect's master and
## elders work out the grand halls of the wandering cultivators, the master
## fastest. Progress is kept per settlement and function in its record
## (`study`), so many hands add to one design. The design worked out is the
## cheapest starter with that function; it is learned by everyone living
## there, and from then on travels like any other design.
##
## Setting out: the traveller is away (not present: they eat nothing, do
## nothing and cannot be met) until their day of return, kept in the
## settlement's record (`trips`). They bring back designs for what the
## settlement wants then, of any author, learned by everyone living there.
const Balance = preload("res://scripts/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")
const AbstractBuild = preload("res://scripts/sim/abstract/abstract_build.gd")
const SectHallWants = preload("res://scripts/sim/sect_hall_wants.gd")
const SectPlaces = preload("res://scripts/sim/sect_places.gd")
const Movement = preload("res://scripts/sim/movement.gd")

## Housing is worked out by the vernacular rule (vernacular.gd), not here.
const SKIP: Array[String] = ["dwelling", "shelter"]

static var _lacking: Dictionary = {}


## Every design anyone living in the settlement knows, as a set.
static func known_in(sim: RefCounted, id: int) -> Dictionary:
	var settlement: Dictionary = sim.settlements.entries[id]
	var known: Dictionary = {}
	for template_id in settlement.known_templates:
		known[template_id] = true
	for agent_id in settlement.residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present():
			for template_id in agent.beliefs.known_templates:
				known[template_id] = true
	return known


## What the settlement wants and nobody there knows a design for, most
## pressing first: [function, sect] pairs. Worked out once an hour.
static func lacking(sim: RefCounted, id: int) -> Array:
	var key: String = "%d:%d" % [sim.get_instance_id(), id]
	var hour: int = sim.calendar.tick / sim.calendar.ticks_per_hour()
	var cached: Array = _lacking.get(key, [-1, []])
	if int(cached[0]) == hour:
		return cached[1]
	var known: Dictionary = known_in(sim, id)
	var result: Array = []
	var seen: Dictionary = {}
	for want in AbstractBuild.wants(sim, id):
		var function: String = str(want[0])
		if SKIP.has(function) or seen.has(function) or _knows(sim, known, function):
			continue
		seen[function] = true
		result.append([function, SectHallWants.PURPOSES.has(str(want[1]))])
	_lacking[key] = [hour, result]
	return result


static func _knows(sim: RefCounted, known: Dictionary, function: String) -> bool:
	for template_id in known:
		var template: RefCounted = sim.template(template_id)
		if template != null and template.functions.has(function):
			return true
	return false


## The cheapest starter with `function` among those by `authors` (any
## author when empty), or "".
static func starter_for(sim: RefCounted, function: String, authors: Array) -> String:
	var best: String = ""
	var best_blocks: int = 0
	for entry in Data.file("templates").get("starters", []):
		if not authors.is_empty() and not authors.has(str(entry.get("author", ""))):
			continue
		var template: RefCounted = sim.template(str(entry.id))
		if template == null or not template.functions.has(function):
			continue
		if best.is_empty() or template.block_count() < best_blocks or (template.block_count() == best_blocks and str(entry.id) < best):
			best = str(entry.id)
			best_blocks = template.block_count()
	return best


static func authors(sect: bool) -> Array:
	return Balance.list("designs.sect_authors" if sect else "designs.village_authors")


## Whether this person could work on a design for this want: anyone grown
## for the village's buildings, only the sect's master and elders for its
## halls; a camp of a few people has no hours to spare for it.
static func may_study(sim: RefCounted, agent: RefCounted, sect: bool) -> bool:
	if agent.is_child or agent.settlement_id < 0 or present(sim, agent.settlement_id) < Balance.integer("designs.study_min_people"):
		return false
	return SectPlaces.leads(sim, agent) if sect else true


static func present(sim: RefCounted, id: int) -> int:
	var count: int = 0
	for agent_id in sim.settlements.entries[id].residents:
		count += 1 if sim.agents[agent_id].is_present() else 0
	return count


## The sect's master works the grand halls out faster than an elder.
static func is_master(sim: RefCounted, agent: RefCounted) -> bool:
	if sim.sects == null:
		return false
	var sect: Dictionary = sim.sects.in_settlement(agent.settlement_id)
	return not sect.is_empty() and int(sect.get("master", -1)) == agent.id


## Hours of study a design takes: by its size, longer for a sect's hall.
static func hours_for(sim: RefCounted, template_id: String, sect: bool) -> float:
	var template: RefCounted = sim.template(template_id)
	var blocks: int = template.block_count() if template != null else 50
	return blocks * Balance.number("designs.hours_per_block") * (Balance.number("designs.sect_factor") if sect else 1.0)


## `hours` of someone's study toward a design for `function`; when it is
## enough the settlement knows the design. Returns the design id worked out, or "".
static func study(sim: RefCounted, agent: RefCounted, function: String, sect: bool, hours: float) -> String:
	var id: int = agent.settlement_id
	if not sim.settlements.entries.has(id):
		return ""
	var template_id: String = starter_for(sim, function, authors(sect))
	if template_id.is_empty() or known_in(sim, id).has(template_id):
		return ""
	var settlement: Dictionary = sim.settlements.entries[id]
	var progress: Dictionary = settlement.get("study", {})
	var pace: float = Balance.number("designs.master_pace") if sect and is_master(sim, agent) else 1.0
	progress[function] = float(progress.get(function, 0.0)) + hours * pace
	settlement["study"] = progress
	if float(progress[function]) < hours_for(sim, template_id, sect):
		return ""
	progress.erase(function)
	learn(sim, id, template_id)
	sim.chronicle_event("design_worked_out", id, {"name": agent.full_name(), "design": sim.template_name(template_id),
		"function": "function_" + function}, "cause_lacked_design|function_" + function, [agent.id])
	_lacking.erase("%d:%d" % [sim.get_instance_id(), id])
	return template_id


## Everyone living in the settlement knows the design from now on.
static func learn(sim: RefCounted, id: int, template_id: String) -> void:
	var settlement: Dictionary = sim.settlements.entries[id]
	if not settlement.known_templates.has(template_id):
		settlement.known_templates.append(template_id)
	for agent_id in settlement.residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present() and not agent.beliefs.known_templates.has(template_id):
			agent.beliefs.known_templates.append(template_id)
	_lacking.erase("%d:%d" % [sim.get_instance_id(), id])


## A design of the valley's ways (or, where a sect stands, of the wandering
## cultivators') that nobody in the settlement knows yet, or "".
static func unknown_design(sim: RefCounted, id: int, rng: RandomNumberGenerator) -> String:
	var known: Dictionary = known_in(sim, id)
	var from: Array = authors(false)
	if sim.sects != null and not sim.sects.in_settlement(id).is_empty():
		from = from + authors(true)
	var unknown: Array = []
	for entry in Data.file("templates").get("starters", []):
		if from.has(str(entry.get("author", ""))) and not known.has(str(entry.id)):
			unknown.append(str(entry.id))
	unknown.sort()
	return str(unknown[rng.randi_range(0, unknown.size() - 1)]) if not unknown.is_empty() else ""


## Whether someone from the settlement is away fetching plans.
static func away(sim: RefCounted, id: int) -> bool:
	return not sim.settlements.entries[id].get("trips", []).is_empty()


## The traveller leaves the valley for a while, chronicled with why.
static func set_out(sim: RefCounted, agent: RefCounted) -> void:
	var id: int = agent.settlement_id
	if not sim.settlements.entries.has(id) or not agent.is_present():
		return
	var span: Array = Balance.list("designs.trip_days")
	var days: int = sim.rng.randi_range(int(span[0]), int(span[1]))
	var settlement: Dictionary = sim.settlements.entries[id]
	var trips: Array = settlement.get("trips", [])
	trips.append({"agent": agent.id, "back": sim.calendar.tick + days * sim.calendar.ticks_per_day})
	settlement["trips"] = trips
	agent.life = "away"
	agent.intention = {}
	agent.path.clear()
	agent.inside = -1
	sim.goal_version += 1
	var wanted: Array = lacking(sim, id)
	var function: String = "function_" + str(wanted[0][0]) if not wanted.is_empty() else "function_unrecognised"
	sim.chronicle_event("set_out_for_plans", id, {"name": agent.full_name(), "days": days}, "cause_lacked_design|" + function, [agent.id])


## Daily: travellers due home come back with designs for what is lacking.
static func daily(sim: RefCounted) -> void:
	for id in sim.settlements.ids():
		var settlement: Dictionary = sim.settlements.entries[id]
		var trips: Array = settlement.get("trips", [])
		for trip in trips.duplicate():
			if int(trip.back) > sim.calendar.tick:
				continue
			trips.erase(trip)
			_come_back(sim, id, sim.agents[int(trip.agent)])


static func _come_back(sim: RefCounted, id: int, agent: RefCounted) -> void:
	if agent.life != "away":
		return
	agent.life = "present"
	var settlement: Dictionary = sim.settlements.entries[id]
	var cell: Vector3i = sim.nav.nearest_walkable(settlement.camp, 6)
	if cell.x >= 0:
		agent.cell = cell
		agent.position = Movement.center(cell)
		agent.previous_position = agent.position
	agent.activity = "idle"
	agent.next_deliberation = sim.calendar.tick
	sim.goal_version += 1
	var brought: Array = []
	for want in lacking(sim, id):
		if brought.size() >= Balance.integer("designs.trip_designs"):
			break
		var template_id: String = starter_for(sim, str(want[0]), [])
		if not template_id.is_empty() and not brought.has(template_id):
			brought.append(template_id)
			learn(sim, id, template_id)
	# Nothing lacking any more: they bring what caught their eye on the road.
	if brought.is_empty():
		var seen: String = unknown_design(sim, id, sim.rng)
		if not seen.is_empty():
			brought.append(seen)
			learn(sim, id, seen)
	var names: Array = brought.map(func(template_id: String) -> String: return sim.template_name(template_id))
	sim.chronicle_event("returned_with_plans" if not names.is_empty() else "returned_empty_handed", id,
		{"name": agent.full_name(), "designs": ", ".join(names)}, "", [agent.id])


## Abstract days (meditation): the settlement's people study what it lacks
## and, now and then, one of them sets out, by the same rules in day-sized steps.
static func abstract_day(sim: RefCounted, id: int) -> void:
	var wanted: Array = lacking(sim, id)
	if wanted.is_empty():
		return
	var village: Array = wanted.filter(func(want: Array) -> bool: return not bool(want[1]))
	var sect_wants: Array = wanted.filter(func(want: Array) -> bool: return bool(want[1]))
	var hours: float = Balance.number("designs.abstract_hours_per_day")
	var scholar: RefCounted = _scholar(sim, id, false)
	if not village.is_empty() and scholar != null:
		study(sim, scholar, str(village[0][0]), false, hours)
	var master: RefCounted = _scholar(sim, id, true)
	if not sect_wants.is_empty() and master != null:
		study(sim, master, str(sect_wants[0][0]), true, hours)
	if not village.is_empty() and not away(sim, id) and not sim.calendar.is_winter() \
			and sim.rng.randf() < Balance.number("designs.abstract_trip_chance"):
		var traveller: RefCounted = _traveller(sim, id)
		if traveller != null:
			set_out(sim, traveller)


## Who studies in the abstract: for the sect its master (else an elder); for
## the village its most curious grown person.
static func _scholar(sim: RefCounted, id: int, sect: bool) -> RefCounted:
	var best: RefCounted = null
	for agent_id in sim.settlements.entries[id].residents:
		var agent: RefCounted = sim.agents[agent_id]
		if not agent.is_present() or not may_study(sim, agent, sect):
			continue
		if sect and is_master(sim, agent):
			return agent
		if best == null or agent.personality.curiosity > best.personality.curiosity:
			best = agent
	return best


static func _traveller(sim: RefCounted, id: int) -> RefCounted:
	var best: RefCounted = null
	var best_score: float = -INF
	for agent_id in sim.settlements.entries[id].residents:
		var agent: RefCounted = sim.agents[agent_id]
		if not agent.is_present() or not may_travel(sim, agent):
			continue
		var score: float = agent.personality.curiosity + agent.personality.bravery * 0.5
		if score > best_score:
			best = agent
			best_score = score
	return best


## Who may set out: a grown, healthy person who leads no sect and has lived
## long enough in the settlement to know what it lacks, from a settlement
## with hands enough to spare one.
static func may_travel(sim: RefCounted, agent: RefCounted) -> bool:
	if agent.is_child or agent.settlement_id < 0 or SectPlaces.leads(sim, agent) or float(agent.health.hp) < 70.0:
		return false
	if sim.calendar.day() - agent.joined_day < Balance.integer("designs.trip_settled_days"):
		return false
	return present(sim, agent.settlement_id) >= Balance.integer("designs.trip_min_people")


## Applies a design action at the end of the tick; false when it is not one.
static func apply(sim: RefCounted, agent: RefCounted, action: Dictionary) -> bool:
	match str(action.type):
		"study":
			study(sim, agent, str(action.function), bool(action.sect), float(action.hours))
		"set_out":
			set_out(sim, agent)
		_:
			return false
	return true
