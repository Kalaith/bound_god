extends RefCounted
## What a person notices, every `perception_interval` ticks staggered by id:
## resource sites, people, their store's stock, structures, threats, and the
## god. Writes beliefs only; returns true when something demands a rethink.
const Balance = preload("res://scripts/core/balance.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Beliefs = preload("res://scripts/agents/beliefs.gd")


## How far a person sees: less at night, unless a lantern lights their way.
static func sight_radius(sim: RefCounted, cell: Vector3i = Vector3i(-1, -1, -1)) -> float:
	var radius: float = Balance.number("agents.sight_radius")
	if not sim.calendar.is_daylight() and (cell.x < 0 or not sim.is_lit(cell)):
		radius *= Balance.number("agents.night_sight_factor")
	return radius


static func _distance(a: Vector3i, b: Vector3i) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length() + absf(a.y - b.y) * 0.5


static func _sites(sim: RefCounted, agent: RefCounted, radius: float) -> void:
	var now: int = sim.calendar.tick
	var all: Dictionary = sim.sites.sites
	for id in sim.spatial.near("sites", agent.cell, radius):
		if not all.has(id):
			continue
		var site: Dictionary = all[id]
		if not site.cells.is_empty() and _distance(site.cells[0], agent.cell) <= radius:
			agent.beliefs.note_site(id, site.kind, site.cells[0], int(site.amount), now)
	# Remembered sites in view that are gone are forgotten: they were used up.
	var gone: Array = []
	for id in agent.beliefs.sites:
		if not all.has(id) and _distance(agent.beliefs.sites[id].cell, agent.cell) <= radius:
			gone.append(id)
	for id in gone:
		agent.beliefs.forget_site(id)


static func _people(sim: RefCounted, agent: RefCounted, radius: float) -> void:
	var interval: float = Balance.number("agents.perception_interval")
	var familiarity: float = sim.calendar.per_tick(Balance.number("social.proximity_familiarity_per_day")) * interval
	var shared: float = sim.calendar.per_tick(Balance.number("social.shared_work_opinion_per_day")) * interval
	var goal: Dictionary = agent.current_goal()
	var my_key: int = Goals.key(goal) if not goal.is_empty() and not Goals.work_type(goal).is_empty() else -1
	agent.beliefs.nearby.clear()
	for other_id in sim.spatial.near("agents", agent.cell, radius):
		if other_id == agent.id:
			continue
		var other: RefCounted = sim.agents[other_id]
		if not other.is_present() or _distance(other.cell, agent.cell) > radius:
			continue
		agent.beliefs.nearby.append({"id": other_id, "cell": other.cell})
		var relation: Dictionary = agent.beliefs.relation(other_id)
		relation.familiarity = minf(float(relation.familiarity) + familiarity, 100.0)
		var other_goal: Dictionary = other.current_goal()
		if my_key >= 0 and not other_goal.is_empty() and Goals.key(other_goal) == my_key:
			Beliefs.change_opinion(relation, shared)


static func _structures(sim: RefCounted, agent: RefCounted, radius: float) -> void:
	var now: int = sim.calendar.tick
	for entry in sim.structures.built():
		if _distance(entry.anchor, agent.cell) <= radius:
			var known: Dictionary = agent.beliefs.structures.get(entry.id, {})
			if known.is_empty() or known.functions != entry.functions or known.template_id != entry.template_id:
				agent.beliefs.structures[entry.id] = {"functions": entry.functions.duplicate(), "cell": entry.anchor,
					"template_id": entry.template_id, "seen_tick": now}
			else:
				known.seen_tick = now
			if not entry.template_id.is_empty() and not agent.beliefs.known_templates.has(entry.template_id) \
					and sim.god.offered.has(entry.template_id):
				agent.beliefs.known_templates.append(entry.template_id)
	for id in agent.beliefs.structures.keys():
		var belief: Dictionary = agent.beliefs.structures[id]
		if _distance(belief.cell, agent.cell) <= radius and not sim.structures.entries.has(id):
			agent.beliefs.structures.erase(id)


## Settlements seen with their own eyes are remembered as places.
static func _places(sim: RefCounted, agent: RefCounted, radius: float) -> void:
	for id in sim.settlements.ids():
		var settlement: Dictionary = sim.settlements.entries[id]
		if _distance(settlement.center, agent.cell) <= radius + 6.0:
			var key: String = "settlement:%d" % id
			var known: Dictionary = agent.beliefs.places.get(key, {})
			if known.is_empty():
				agent.beliefs.places[key] = {"kind": "settlement", "id": id, "cell": settlement.center, "state": "seen", "seen_tick": sim.calendar.tick}
			else:
				known.seen_tick = sim.calendar.tick
	var grounds: Array = sim.features.get("grounds", [])
	for index in range(grounds.size()):
		if _distance(grounds[index].center, agent.cell) <= radius + 6.0:
			note_ground(sim, agent, index)


## Open land where a settlement could stand, remembered as a place.
static func note_ground(sim: RefCounted, agent: RefCounted, index: int) -> void:
	var key: String = "ground:%d" % index
	if agent.beliefs.places.has(key):
		agent.beliefs.places[key].seen_tick = sim.calendar.tick
		return
	agent.beliefs.places[key] = {"kind": "ground", "id": index, "cell": sim.features.grounds[index].center, "state": "seen", "seen_tick": sim.calendar.tick}


static func _threats(sim: RefCounted, agent: RefCounted, radius: float) -> bool:
	var now: int = sim.calendar.tick
	var alarmed: bool = false
	for threat in sim.threats_list():
		if _distance(threat.cell, agent.cell) > radius:
			continue
		if sim.is_veiled(threat.cell, agent.cell):
			continue
		if agent.beliefs.note_threat(threat.id, threat.kind, threat.cell, threat.aggressive, now):
			alarmed = true
			agent.change_need(Personality.Need.SAFETY, -Balance.number("needs.safety_loss_on_threat"))
			_warn(sim, agent, threat)
	var kept: Array = []
	for belief in agent.beliefs.threats:
		if _distance(belief.cell, agent.cell) > radius or sim.threat_exists(belief.id):
			kept.append(belief)
	agent.beliefs.threats = kept
	return alarmed


static func _warn(sim: RefCounted, agent: RefCounted, threat: Dictionary) -> void:
	var earshot: float = Balance.number("agents.earshot")
	for other_id in sim.spatial.near("agents", agent.cell, earshot):
		var other: RefCounted = sim.agents[other_id]
		if other_id != agent.id and other.is_present() and _distance(other.cell, agent.cell) <= earshot:
			sim.effects.message(agent.id, other_id, "warn", sim.calendar.tick,
				{"threat": threat.id, "threat_kind": threat.kind, "cell": threat.cell, "dangerous": threat.aggressive})


static func perceive(sim: RefCounted, agent: RefCounted) -> bool:
	var interval: int = Balance.integer("agents.perception_interval")
	if (sim.calendar.tick + agent.id) % interval != 0:
		return false
	var radius: float = sight_radius(sim, agent.cell)
	_sites(sim, agent, radius)
	_people(sim, agent, radius)
	_structures(sim, agent, radius)
	if sim.settlements.at_store(sim, agent):
		agent.beliefs.stock = sim.settlements.stock_of(agent.settlement_id).duplicate()
	_places(sim, agent, radius)
	var alarmed: bool = _threats(sim, agent, radius)
	if sim.faith != null and sim.faith.perceive(sim, agent, radius):
		alarmed = true
	return alarmed
