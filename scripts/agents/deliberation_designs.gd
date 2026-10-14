extends RefCounted
## Designs a settlement lacks (designs_lore.gd): a grown person may spend
## working hours working one out, weighed as building work by their skill
## and curiosity; a sect's master and elders weigh working out its halls
## beside their cultivation, the master most. A curious, hardy person may
## set out from the valley to bring plans back, while nobody else from
## there is away and it is not winter.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const FunctionRules = preload("res://scripts/building/function_rules.gd")
const DeliberationWork = preload("res://scripts/agents/deliberation_work.gd")
const Lore = preload("res://scripts/sim/designs_lore.gd")

const Kind = Goals.Kind
const Skill = Personality.Skill


static func add(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if agent.is_child or agent.settlement_id < 0 or sim.settlement_life == null or not sim.settlements.entries.has(agent.settlement_id):
		return
	if Schedule.is_sleep_time(sim, agent):
		return
	var wanted: Array = Lore.lacking(sim, agent.settlement_id)
	if wanted.is_empty():
		return
	var culture: Dictionary = sim.settlements.entries[agent.settlement_id].culture
	var base: float = DeliberationWork.base_utility(sim, agent)
	var curious: float = 0.6 + agent.personality.curiosity
	for want in wanted:
		var sect: bool = bool(want[1])
		if not Lore.may_study(sim, agent, sect):
			continue
		var goal: Dictionary = Goals.make(Kind.STUDY, FunctionRules.FUNCTIONS.find(str(want[0])), 1 if sect else 0)
		var pull: float = Balance.number("designs.study_pull") * curious
		if sect:
			pull *= Balance.number("designs.master_pull") if Lore.is_master(sim, agent) else 1.0
		else:
			pull *= float(culture.build) * DeliberationWork.aptitude(agent, Skill.CONSTRUCTION)
		var utility: float = base * pull * DeliberationWork.company(sim, agent, goal)
		if utility > 0.01:
			out.append({"goal": goal, "utility": utility, "reason": "reason_study", "value": NAN})
		break
	_set_out(sim, agent, base, culture, wanted, out)


static func _set_out(sim: RefCounted, agent: RefCounted, base: float, culture: Dictionary, wanted: Array, out: Array) -> void:
	if sim.calendar.is_winter() or Lore.away(sim, agent.settlement_id) or not Lore.may_travel(sim, agent):
		return
	if not wanted.any(func(want: Array) -> bool: return not bool(want[1])):
		return
	var goal: Dictionary = Goals.make(Kind.SEEK_PLANS)
	for other in sim.pursuers(Goals.key(goal)):
		if other != agent.id and sim.agents[other].settlement_id == agent.settlement_id:
			return
	var nerve: float = 0.4 + agent.personality.curiosity + 0.5 * agent.personality.bravery
	var utility: float = base * float(culture.scout) * Balance.number("designs.trip_pull") * nerve
	if utility > 0.01:
		out.append({"goal": goal, "utility": utility, "reason": "reason_seek_plans", "value": NAN})
