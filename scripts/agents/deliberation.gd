extends RefCounted
## Deliberation: candidate goals and their utility, from the person's own
## needs, personality, relationships and beliefs. Reads the sim, never
## changes it. A candidate is {goal, utility, reason, value}.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const DeliberationSocial = preload("res://scripts/agents/deliberation_social.gd")
const DeliberationWork = preload("res://scripts/agents/deliberation_work.gd")
const DeliberationFaith = preload("res://scripts/agents/deliberation_faith.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")
const DeliberationDesigns = preload("res://scripts/agents/deliberation_designs.gd")
const DeliberationOutlaw = preload("res://scripts/agents/deliberation_outlaw.gd")

const Need = Personality.Need
const Kind = Goals.Kind


static func deficit(value: float) -> float:
	return clampf((100.0 - value) / 100.0, 0.0, 1.0)


static func candidate(kind: int, utility: float, reason: String, value: float = NAN, target: int = -1, extra: int = 0) -> Dictionary:
	return {"goal": Goals.make(kind, target, extra), "utility": utility, "reason": reason, "value": value}


static func is_work_hours(sim: RefCounted, agent: RefCounted) -> bool:
	return Schedule.is_work_hours(sim, agent)


static func is_sleep_time(sim: RefCounted, agent: RefCounted) -> bool:
	return Schedule.is_sleep_time(sim, agent)


static func _survival(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	var urgent: float = Balance.number("needs.urgent_threshold")
	var food: float = agent.need(Need.FOOD)
	var hour: float = sim.calendar.hour()
	var mealtime: bool = absf(hour - 7.5) < 1.0 or absf(hour - 12.5) < 1.0 or absf(hour - 18.5) < 1.0
	var eat: float = pow(deficit(food), 2) * 1.5
	if food < urgent:
		eat += 0.7
	if mealtime and food < 70.0:
		eat += 0.18
	out.append(candidate(Kind.EAT, eat, "reason_hunger", food))

	var rest: float = agent.need(Need.REST)
	var sleep: float
	# Someone already asleep sleeps the night through; a full rest need is no
	# reason to get up and chat in the dark.
	if is_sleep_time(sim, agent) and (rest < 92.0 or agent.activity == "sleeping"):
		sleep = 0.62 + deficit(rest) * 0.6
	else:
		sleep = pow(deficit(rest), 2) * 1.3 + (0.8 if rest < 15.0 else 0.0)
	var threat: Array = agent.beliefs.nearest_threat(agent.cell)
	# Nobody lies down beside a known danger unless they are collapsing.
	if not threat.is_empty() and threat[1] < 7.0 and rest > 5.0:
		sleep *= 0.25
	out.append(candidate(Kind.SLEEP, sleep, "reason_tired", rest))

	var shelter: float = agent.need(Need.SHELTER)
	# By day, only a roof is worth going to (a canopy does little more than
	# the open sky); settlers on open land find shelter by building a home.
	if shelter < 60.0 and (not sim.calendar.is_daylight() or _knows_roof(sim, agent)):
		var utility: float = pow(deficit(shelter), 2) * 1.6 + (0.6 if shelter < 20.0 else 0.0)
		out.append(candidate(Kind.TAKE_SHELTER, utility, "reason_exposed", shelter))

	if not threat.is_empty():
		var fearful: bool = bool(threat[0].dangerous) or agent.personality.bravery < -0.2 or agent.is_child
		if threat[1] < 7.0 and fearful:
			var courage: float = clampf(agent.personality.bravery, -0.5, 0.8)
			var utility: float = 1.4 * (1.0 - courage * 0.6) * maxf(1.0 - threat[1] / 10.0, 0.3)
			out.append(candidate(Kind.FLEE, utility, "reason_threat", threat[1]))

	if agent.needs_care(Balance.number("health.care_threshold")):
		var utility: float = (1.0 - float(agent.health.hp) / 100.0) * 1.3 + (0.45 if agent.health.ill else 0.0)
		out.append(candidate(Kind.SEEK_CARE, utility, "reason_health", float(agent.health.hp)))

	var recreation: float = agent.need(Need.RECREATION)
	if recreation < 65.0:
		var hours: float = 0.6 if is_work_hours(sim, agent) else 1.4
		out.append(candidate(Kind.RELAX, pow(deficit(recreation), 2) * 0.9 * hours, "reason_bored", recreation))


## Whether the person knows a roof: a home, or a shelter or dwelling they
## have seen in their own settlement.
static func _knows_roof(sim: RefCounted, agent: RefCounted) -> bool:
	if agent.home >= 0:
		return true
	for id in agent.beliefs.structures:
		var known: Dictionary = agent.beliefs.structures[id]
		if (known.functions.has("shelter") or known.functions.has("dwelling")) and sim.settlements.at_cell(known.cell) == agent.settlement_id:
			return true
	return false


static func _break_candidate(sim: RefCounted, agent: RefCounted) -> Dictionary:
	if agent.mental_break.is_empty() or int(agent.mental_break.until) <= sim.calendar.tick:
		return {}
	var kind: int = int(agent.mental_break.kind)
	if kind == Goals.BreakKind.LASH_OUT:
		var worst: int = -1
		var worst_opinion: float = INF
		var ids: Array = agent.beliefs.relations.keys()
		ids.sort()
		for other in ids:
			var opinion: float = agent.beliefs.opinion_of(other)
			if opinion < worst_opinion and sim.agents[other].is_present():
				worst = other
				worst_opinion = opinion
		if worst >= 0:
			return candidate(Kind.CHAT, 10.0, "reason_break", NAN, worst)
		kind = Goals.BreakKind.SULK
	return candidate(Kind.BREAK, 10.0, "reason_break", NAN, kind)


## All goals worth considering now, with utilities.
static func candidates(sim: RefCounted, agent: RefCounted) -> Array:
	# An outlaw weighs only the raid and the way out (M22).
	if agent.backstory.has("outlaw"):
		return DeliberationOutlaw.candidates(sim, agent)
	var out: Array = []
	var crisis: Dictionary = _break_candidate(sim, agent)
	if not crisis.is_empty():
		out.append(crisis)
		return out
	_survival(sim, agent, out)
	DeliberationSocial.add(sim, agent, out)
	DeliberationWork.add(sim, agent, out)
	DeliberationDesigns.add(sim, agent, out)
	DeliberationFaith.add(sim, agent, out)
	DeliberationCultivation.add(sim, agent, out)
	out.append(candidate(Kind.IDLE, 0.04, ""))
	var now: int = sim.calendar.tick
	var kept: Array = []
	for entry in out:
		if agent.is_backed_off(Goals.key(entry.goal), now):
			continue
		if not Goals.work_type(entry.goal).is_empty():
			entry.utility /= 1.0 + pursuing(sim, entry.goal, agent.id) * 0.35
		kept.append(entry)
	_apply_whispers(sim, agent, kept)
	return kept


## How many other people already pursue this goal.
static func pursuing(sim: RefCounted, goal: Dictionary, me: int) -> int:
	var ids: Array = sim.pursuers(Goals.key(goal))
	return ids.size() - (1 if ids.has(me) else 0)


## The god's urging raises a goal kind for a day; it never adds a goal the
## person would not consider, so deliberation still decides.
static func _apply_whispers(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if agent.whispers.is_empty():
		return
	var now: int = sim.calendar.tick
	var kept: Array = []
	for whisper in agent.whispers:
		if int(whisper.until) <= now:
			continue
		kept.append(whisper)
		for entry in out:
			if int(entry.goal.kind) == int(whisper.kind) and (int(whisper.target) < 0 or int(entry.goal.target) == int(whisper.target)):
				entry.utility += float(whisper.bonus)
				entry["urged"] = true
	agent.whispers = kept


static func best(options: Array) -> Dictionary:
	var result: Dictionary = {}
	for entry in options:
		if result.is_empty() or entry.utility > result.utility:
			result = entry
	return result
