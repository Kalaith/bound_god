extends RefCounted
## Births, ageing, deaths and departures.
const Balance = preload("res://scripts/core/balance.gd")
const Mind = preload("res://scripts/agents/mind.gd")


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


static func daily(sim: RefCounted) -> void:
	var year_days: float = float(sim.calendar.days_per_season * 4)
	for agent in sim.agents:
		if not agent.is_present():
			continue
		agent.age_years += 1.0 / year_days
		if agent.is_child and agent.age_years * year_days >= Balance.number("agents.child_growth_days"):
			agent.is_child = false
			agent.age_years = Balance.number("agents.adult_age_years")
			sim.chronicle_event("grew_up", agent.settlement_id, {"name": agent.full_name()}, "", [agent.id])
