extends RefCounted
## Abstract construction (plan §3.1): what a settlement's people would build,
## built by labour-hours instead of walking builders. Each day a settlement
## short of a building it knows how to make (a home for the homeless, the
## food buildings its leaders would propose, a storehouse, a hall, a garden)
## reserves a site where the site finder would put it, through the same
## construction sites the detailed world uses. Each hour, hands not needed
## for food gather materials into the chests and raise sites a block at a
## time, spending the materials. Blocks reach the world when a site is
## finished (then the same completion as a builder's last block) or when the
## valley materialises.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const SiteFinder = preload("res://scripts/building/site_finder.gd")
const Blueprints = preload("res://scripts/sim/blueprints.gd")
const Construction = preload("res://scripts/sim/construction.gd")
const EffectsBuild = preload("res://scripts/sim/effects_build.gd")
const DeliberationFood = preload("res://scripts/agents/deliberation_food.gd")
const SectPlaces = preload("res://scripts/sim/sect_places.gd")
const SectHallWants = preload("res://scripts/sim/sect_hall_wants.gd")
const DeliberationWork = preload("res://scripts/agents/deliberation_work.gd")
const AbstractPeople = preload("res://scripts/sim/abstract/abstract_people.gd")
const Renovations = preload("res://scripts/sim/renovations.gd")

## Blocks one pair of hands sets in an hour, fetching included.
const BLOCKS_PER_HOUR: float = 3.0
## Materials one pair of hands brings in an hour from known places.
const GATHER_PER_HOUR: Dictionary = {"wood": 4.0, "stone": 2.0, "thatch": 3.0, "ore": 1.0}
## Days between a settlement's looks at what it lacks.
const PLAN_EVERY_DAYS: int = 3
## Candidates the site search gathers before choosing (the nearest rings).
const SEARCH_ENOUGH: int = 16
## Spots on the spiral looked at before giving up (0: the whole spiral;
## a cap left homes unbuilt, so the search stays whole).
const SEARCH_MOST: int = 0
## Share of free hands that build while a site waits.
const BUILD_SHARE: float = 0.5


## The cheapest design for a function that anyone living here knows.
static func design_for(sim: RefCounted, id: int, function: String) -> RefCounted:
	var known: Dictionary = {}
	for template_id in sim.settlements.entries[id].known_templates:
		known[template_id] = true
	for agent_id in sim.settlements.entries[id].residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present():
			for template_id in agent.beliefs.known_templates:
				known[template_id] = true
	var best: RefCounted = null
	var ids: Array = known.keys()
	ids.sort()
	for template_id in ids:
		var template: RefCounted = sim.template(template_id)
		if template == null or not template.functions.has(function):
			continue
		if best == null or template.block_count() < best.block_count():
			best = template
	return best


## What the settlement lacks, most pressing first: [function, purpose, founder id].
static func wants(sim: RefCounted, id: int) -> Array:
	var result: Array = []
	var settlement: Dictionary = sim.settlements.entries[id]
	var homeless: int = -1
	for agent_id in settlement.residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present() and not agent.is_child and agent.home < 0 and agent.age_years >= Balance.number("agents.adult_age_years"):
			if homeless < 0 or (agent.partner >= 0 and sim.agents[homeless].partner < 0):
				homeless = agent_id
	if homeless >= 0:
		result.append(["dwelling", "home", homeless])
	var have: Dictionary = DeliberationWork._functions_in(sim, id)
	var people: int = Standing.present(sim, id)
	var leader: int = _leader(sim, id)
	for want in DeliberationFood.wants(sim, id, people, have):
		result.append([want[0], want[0], leader])
	if Standing.food_days(sim, id) < Balance.number("construction.garden_food_days") and int(have.get("garden", 0)) < ceili(float(people) / Balance.number("construction.people_per_garden")):
		result.append(["garden", "garden", leader])
	var capacity: int = sim.settlements.capacity_for(sim, id, "wood")
	if capacity > 0 and sim.settlements.room_for(sim, id, "wood") <= int(capacity * 0.15):
		result.append(["storehouse", "storehouse", leader])
	if people >= Balance.integer("construction.hall_residents") and int(have.get("hall", 0)) == 0:
		result.append(["hall", "hall", leader])
	var sect: Dictionary = sim.sects.in_settlement(id) if sim.sects != null else {}
	for want in SectHallWants.all(sim, id, have):
		result.append([want[0], want[0], int(sect.get("master", leader))])
	return result


static var _leaders: Dictionary = {}


## The most respected resident, who would propose a common building
## (weighed again every ten days).
static func _leader(sim: RefCounted, id: int) -> int:
	# Keyed by world as well: several worlds may live in one run (checks).
	var key: String = "%d:%d" % [sim.get_instance_id(), id]
	var known: Array = _leaders.get(key, [-1, -1])
	if int(known[0]) >= 0 and sim.calendar.tick - int(known[0]) < sim.calendar.ticks_for_days(10.0) and int(known[1]) >= 0 			and int(known[1]) < sim.agents.size() and sim.agents[int(known[1])].is_present():
		return int(known[1])
	var best: int = _weigh_leader(sim, id)
	_leaders[key] = [sim.calendar.tick, best]
	return best


static func _weigh_leader(sim: RefCounted, id: int) -> int:
	var best: int = -1
	var best_score: float = -INF
	var residents: Array = sim.settlements.entries[id].residents.duplicate()
	residents.sort()
	for agent_id in residents:
		var agent: RefCounted = sim.agents[agent_id]
		if not agent.is_present() or agent.is_child:
			continue
		var score: float = float(agent.personality.leadership) * 50.0
		for other in residents:
			if other != agent_id:
				score += sim.agents[other].beliefs.opinion_of(agent_id)
		if score > best_score:
			best = agent_id
			best_score = score
	return best


## Daily: start the most pressing project there is room and a design for,
## one for the village and one for its sect (whose cultivators build their
## halls beside the village's work, as in the detailed world).
static func day(sim: RefCounted, id: int, record: Dictionary) -> void:
	var tried: Dictionary = record.get("no_site", {})
	var started: Dictionary = {}
	for want in wants(sim, id):
		var sect: bool = SectHallWants.PURPOSES.has(str(want[1]))
		if int(want[2]) < 0 or started.has(sect):
			continue
		var design: RefCounted = design_for(sim, id, str(want[0]))
		if design == null or _open_for(sim, id, str(want[1])):
			continue
		if not design.bill.is_empty() and SectHallWants.busy(sim, id, str(want[1])):
			continue
		# A standing building to add to comes before a new one.
		var renovation: Dictionary = Renovations.option(sim, id, str(want[0]))
		if not renovation.is_empty():
			_renovate(sim, id, renovation, want)
			started[sect] = true
			continue
		# The god's blueprint for this function, while its spot is free, first.
		var proposal: Dictionary = _blueprint(sim, id, str(want[0]))
		if not proposal.is_empty():
			design = proposal.template
			_mark(sim, id, design, proposal.choice, want)
			Blueprints.taken(sim, int(proposal.blueprint), sim.agents[int(want[2])])
			started[sect] = true
			continue
		var failed: Array = tried.get(design.id, [-1, 0, -1, -1])
		var ground: Array = [int(sim.structures.version), sim.construction.reserved.size()]
		# Nothing built, fallen or reserved since it last failed: it would fail again.
		if int(failed[0]) > sim.calendar.tick or (failed.size() > 3 and int(failed[2]) == ground[0] and int(failed[3]) == ground[1]):
			continue
		var choice: Dictionary = SiteFinder.find(sim, design, sim.settlements.entries[id], SEARCH_ENOUGH, SEARCH_MOST)
		if choice.is_empty():
			# No room yet: look again later, and later still each time it fails.
			var days: float = minf(5.0 * pow(2.0, int(failed[1])), 80.0)
			tried[design.id] = [sim.calendar.tick + sim.calendar.ticks_for_days(days), int(failed[1]) + 1, ground[0], ground[1]]
			record["no_site"] = tried
			continue
		tried.erase(design.id)
		_mark(sim, id, design, choice, want)
		started[sect] = true


static func _mark(sim: RefCounted, id: int, design: RefCounted, choice: Dictionary, want: Array) -> void:
	var site_id: int = sim.construction.create(design.id, choice.origin, int(choice.rotation), id, int(want[2]), str(want[1]), choice.order, sim.calendar.tick)
	var site: Dictionary = sim.construction.sites[site_id]
	site["cause"] = EffectsBuild._cause(sim, sim.agents[int(want[2])], str(want[1]))
	site["placed_to"] = 0
	sim.chronicle_event("site_marked", id, {"name": sim.agents[int(want[2])].full_name(), "design": sim.template_name(design.id)}, str(site.cause), [int(want[2])])


static func _renovate(sim: RefCounted, id: int, renovation: Dictionary, want: Array) -> void:
	var template_id: String = Renovations.PREFIX + str(renovation.renovation.id)
	var site_id: int = sim.construction.create(template_id, renovation.order[0][0], 0, id, int(want[2]), str(want[1]), renovation.order, sim.calendar.tick)
	var site: Dictionary = sim.construction.sites[site_id]
	site["cause"] = EffectsBuild._cause(sim, sim.agents[int(want[2])], str(want[1]))
	site["placed_to"] = 0
	sim.chronicle_event("site_marked", id, {"name": sim.agents[int(want[2])].full_name(), "design": sim.template_name(template_id)}, str(site.cause), [int(want[2])])


## A free blueprint in the settlement of a design its people know.
static func _blueprint(sim: RefCounted, id: int, function: String) -> Dictionary:
	for entry in sim.god.blueprints:
		if int(entry.settlement_id) != id:
			continue
		var design: RefCounted = design_for(sim, id, function)
		var known: bool = sim.settlements.entries[id].known_templates.has(entry.template_id)
		for agent_id in sim.settlements.entries[id].residents:
			known = known or sim.agents[agent_id].beliefs.known_templates.has(entry.template_id)
		if design != null and known:
			var found: Dictionary = Blueprints.still_free(sim, entry, function)
			if not found.is_empty():
				return found
	return {}


static func _open_for(sim: RefCounted, id: int, purpose: String) -> bool:
	for site_id in sim.construction.in_settlement(id):
		if str(sim.construction.get_site(site_id).purpose) == purpose:
			return true
	return false


## Hourly: `hands` free for building raise the settlement's sites, fetching
## what the next blocks need when the chests lack it.
static func hour(sim: RefCounted, id: int, hands: float) -> void:
	var sites: Array = sim.construction.in_settlement(id)
	if sites.is_empty() or hands <= 0.0:
		return
	var blocks: float = hands * BUILD_SHARE * BLOCKS_PER_HOUR
	for site_id in sites:
		var site: Dictionary = sim.construction.get_site(site_id)
		if not site.has("placed_to"):
			site["placed_to"] = int(site.cursor)
		site["budget"] = float(site.get("budget", 0.0)) + blocks / sites.size()
		while float(site.budget) >= 1.0 and int(site.cursor) < site.order.size():
			var entry: Array = site.order[int(site.cursor)]
			var resource: String = Construction.resource_for(int(entry[1]))
			if not resource.is_empty() and int(site.delivered.get(resource, 0)) <= 0:
				if AbstractPeople.take(sim, id, resource, 1) <= 0:
					# Fetched from where it grows straight to the site, as builders carry it.
					site.delivered[resource] = int(site.delivered.get(resource, 0)) + _gathered(resource, hands * BUILD_SHARE)
					break
				site.delivered[resource] = int(site.delivered.get(resource, 0)) + 1
			if not resource.is_empty():
				site.delivered[resource] = int(site.delivered[resource]) - 1
			sim.construction.advance(site_id, sim.calendar.tick)
			site.budget = float(site.budget) - 1.0
		if int(site.cursor) >= site.order.size():
			finish(sim, site)


## How much of a material `hands` bring in an hour from the places people
## know round their settlement.
static func _gathered(resource: String, hands: float) -> int:
	var rate: float = float(GATHER_PER_HOUR.get(resource, 0.0))
	return maxi(1, int(round(rate * hands))) if rate > 0.0 else 0


## The blocks a site has earned reach the world, from where they stopped.
static func stamp(sim: RefCounted, site: Dictionary) -> void:
	var from: int = int(site.get("placed_to", site.cursor))
	var grass: int = Registry.id("tall_grass")
	var batch: Array = []
	for index in range(from, int(site.cursor)):
		var entry: Array = site.order[index]
		var current: int = sim.voxels.get_block(entry[0])
		if current == 0 or current == grass or int(entry[1]) == 0:
			batch.append(entry)
	sim.set_blocks(batch, "npc:%d" % int(site.founder))
	site["placed_to"] = int(site.cursor)


## A site raised to its last block: stamped and finished as a builder would.
static func finish(sim: RefCounted, site: Dictionary) -> void:
	stamp(sim, site)
	EffectsBuild._complete(sim, site)
	sim._reconcile_homes("npc")
