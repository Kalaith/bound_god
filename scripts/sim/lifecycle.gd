extends RefCounted
## Births, ageing, deaths and departures.
const Balance = preload("res://scripts/core/balance.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Data = preload("res://scripts/core/data.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Movement = preload("res://scripts/sim/movement.gd")


## Anyone at zero health dies; the chronicle and those who knew them remember.
static func resolve_deaths(sim: RefCounted) -> void:
	for agent in sim.agents:
		if agent.is_present() and float(agent.health.hp) <= 0.0:
			die(sim, agent, agent.life_cause if not agent.life_cause.is_empty() else _cause(agent))


static func _cause(agent: RefCounted) -> String:
	if agent.need(0) <= 0.5:
		return "cause_starvation"
	if agent.need(2) <= 0.5:
		return "cause_exposure"
	return "cause_wounds"


static func die(sim: RefCounted, agent: RefCounted, cause: String) -> void:
	agent.life = "dead"
	agent.life_day = sim.calendar.day()
	agent.life_cause = cause
	agent.intention = {}
	sim.goal_version += 1
	agent.path.clear()
	agent.activity = "idle"
	sim.set_home(agent, -1)
	var day_ticks: int = sim.calendar.ticks_per_day
	for other in sim.agents:
		if other.id == agent.id or not other.is_present():
			continue
		if other.partner == agent.id:
			Mind.add(other, "partner_died", day_ticks, agent.id)
			other.partner = -1
		elif other.beliefs.opinion_of(agent.id) >= Balance.number("social.friend_threshold"):
			Mind.add(other, "friend_died", day_ticks, agent.id)
		elif other.beliefs.relations.has(agent.id):
			Mind.add(other, "death_witness", day_ticks, agent.id)
	sim.chronicle_event("death", agent.settlement_id, {"name": agent.full_name()}, cause, [agent.id])


## Hourly: a person at a breaking point may lose control, in a way that
## follows their nature.
static func hourly(sim: RefCounted) -> void:
	var chance: float = Balance.number("mood.break_chance_per_day") / 24.0
	for agent in sim.agents:
		if not agent.is_present() or not agent.mental_break.is_empty() or agent.mood >= Balance.number("mood.break_threshold"):
			continue
		var roll: float = chance * (1.5 if agent.mood < Balance.number("mood.extreme_threshold") else 1.0)
		if sim.rng.randf() >= roll:
			continue
		var kind: int = Goals.BreakKind.WANDER
		if agent.personality.temper > 0.3:
			kind = Goals.BreakKind.LASH_OUT
		elif agent.has_trait("gourmand") or agent.has_trait("lazy"):
			kind = Goals.BreakKind.BINGE
		elif agent.personality.sociability < 0.0:
			kind = Goals.BreakKind.SULK
		agent.mental_break = {"kind": kind, "until": sim.calendar.tick + Balance.integer("mood.break_ticks") * 2}
		agent.next_deliberation = sim.calendar.tick
		sim.chronicle_event("mental_break", agent.settlement_id, {"name": agent.given_name}, "cause_misery", [agent.id])


static func _births(sim: RefCounted) -> void:
	for agent in sim.agents:
		if not agent.is_present() or agent.partner < agent.id or agent.is_child:
			continue
		var other: RefCounted = sim.agents[agent.partner]
		if not other.is_present() or other.partner != agent.id or other.is_child or agent.home < 0 or agent.home != other.home:
			continue
		if sim.present_count() >= Balance.integer("population.cap"):
			return
		if sim.rng.randf() >= Balance.number("social.child_chance_per_day"):
			continue
		var child: RefCounted = Generation.child(sim.rng, sim.agents.size(), agent, other)
		child.cell = agent.cell
		child.position = Movement.center(agent.cell)
		child.previous_position = child.position
		child.joined_day = sim.calendar.day()
		child.beliefs.known_templates = agent.beliefs.known_templates.duplicate()
		child.faith = agent.faith.duplicate(true)
		child.faith.stories_heard = 0
		for parent in [agent, other]:
			child.beliefs.relation(parent.id).opinion = 50.0
			parent.beliefs.relation(child.id).opinion = 60.0
			Mind.add(parent, "child_born", sim.calendar.ticks_per_day, child.id)
		sim.agents.append(child)
		sim.settlements.join(child, agent.settlement_id)
		sim.set_home(child, agent.home)
		sim.chronicle_event("birth", agent.settlement_id, {"name": child.given_name, "a": agent.given_name, "b": other.given_name}, "", [child.id, agent.id, other.id])


## How far each person has come toward what they want from life.
static func _ambitions(sim: RefCounted) -> void:
	for agent in sim.agents:
		if not agent.is_present() or agent.ambition.is_empty() or agent.ambition.fulfilled:
			continue
		var definition: Dictionary = Data.ambition(agent.ambition.id)
		var target: float = maxf(float(definition.get("target", 1.0)), 0.01)
		var value: float = 0.0
		match str(definition.get("kind", "")):
			"master_skill":
				for level in agent.skills.levels:
					value = maxf(value, float(level))
			"raise_family":
				for other in sim.agents:
					value += 1.0 if other.parents.has(agent.id) else 0.0
			"befriend_village":
				for id in agent.beliefs.relations:
					value += 1.0 if agent.beliefs.opinion_of(id) >= Balance.number("social.friend_threshold") else 0.0
			"map_the_wilds":
				value = float(agent.beliefs.places.size())
			"raise_shrine":
				# An altar standing where they live, raised or restored since they came.
				if sim.faith != null:
					for shrine_id in sim.settlements.get_settlement(agent.settlement_id).get("shrine_ids", []):
						var shrine: Dictionary = sim.faith.get_shrine(shrine_id)
						if shrine.get("kind", "") == "altar" and shrine.state != "fallen" and int(shrine.get("restored_tick", shrine.created_tick)) >= (agent.joined_day - 1) * sim.calendar.ticks_per_day:
							value = 1.0
			"build_home":
				value = 1.0 if agent.home >= 0 and Mind.has(agent, "home_built") else float(agent.ambition.progress) * target
			"lead_village":
				for other in sim.agents:
					if other.id != agent.id and other.settlement_id == agent.settlement_id:
						value += maxf(other.beliefs.opinion_of(agent.id), 0.0) / 10.0
		agent.ambition.progress = clampf(value / target, 0.0, 1.0)
		if agent.ambition.progress >= 1.0:
			agent.ambition.fulfilled = true
			Mind.add(agent, "ambition_fulfilled", sim.calendar.ticks_per_day)
			sim.chronicle_event("ambition", agent.settlement_id, {"name": agent.full_name(), "ambition": definition.get("name", "")}, "", [agent.id])


static func daily(sim: RefCounted) -> void:
	_births(sim)
	_ambitions(sim)
	var year_days: float = float(sim.calendar.days_per_season * 4)
	for agent in sim.agents:
		if not agent.is_present():
			continue
		agent.age_years += 1.0 / year_days
		if agent.is_child and agent.age_years * year_days >= Balance.number("agents.child_growth_days"):
			agent.is_child = false
			agent.age_years = Balance.number("agents.adult_age_years")
			sim.chronicle_event("grew_up", agent.settlement_id, {"name": agent.full_name()}, "", [agent.id])
