extends RefCounted
## Social candidates: talking, courting, comforting, making peace, helping
## someone who asked, and moving to a better settlement. Formulas as Final
## Landing; Migrate is new.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")

const Kind = Goals.Kind
const Need = Personality.Need


static func _deficit(value: float) -> float:
	return clampf((100.0 - value) / 100.0, 0.0, 1.0)


static func _candidate(kind: int, utility: float, reason: String, target: int, value: float = NAN, extra: int = 0) -> Dictionary:
	return {"goal": Goals.make(kind, target, extra), "utility": utility, "reason": reason, "value": value}


static func _distance(a: Vector3i, b: Vector3i) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length() + absf(a.y - b.y)


## The best person to talk to: liked, familiar, nearby and awake. [id, score] or [].
static func chat_partner(sim: RefCounted, agent: RefCounted) -> Array:
	var best: Array = []
	var reach: float = Balance.number("social.chat_range")
	for id in sim.spatial.near("agents", agent.cell, reach):
		if id == agent.id:
			continue
		var other: RefCounted = sim.agents[id]
		if not other.available_to_talk():
			continue
		var distance: float = _distance(other.cell, agent.cell)
		if distance >= reach:
			continue
		var relation: Dictionary = agent.beliefs.relations.get(id, {})
		var score: float = float(relation.get("opinion", 0.0)) * 0.02 + float(relation.get("familiarity", 0.0)) * 0.005 \
			+ (1.0 - distance / reach) + agent.personality.sociability * 0.2
		if best.is_empty() or score > best[1]:
			best = [id, score]
	return best


static func add(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	var social: float = agent.need(Need.SOCIAL)
	var off_hours: float = 0.7 if Schedule.is_work_hours(sim, agent) else 1.4
	if social < 75.0:
		var partner: Array = chat_partner(sim, agent)
		if not partner.is_empty():
			var utility: float = pow(_deficit(social), 1.5) * 0.85 * (1.0 + agent.personality.sociability * 0.6) * off_hours + maxf(partner[1], 0.0) * 0.05
			out.append(_candidate(Kind.CHAT, utility, "reason_lonely", partner[0], social))
	_court(sim, agent, out, off_hours)
	if agent.personality.kindness > 0.0:
		for other in sim.agents:
			if other.id == agent.id or not other.is_present() or other.mood >= 30.0:
				continue
			if agent.beliefs.opinion_of(other.id) > 20.0 and _distance(other.cell, agent.cell) < 20.0:
				out.append(_candidate(Kind.COMFORT, 0.55 * (0.5 + agent.personality.kindness), "reason_friend_low", other.id, other.mood))
				break
	if agent.personality.kindness > 0.0 or agent.personality.leadership > 0.0:
		var ids: Array = agent.beliefs.relations.keys()
		ids.sort()
		for other_id in ids:
			if agent.beliefs.bond_with(other_id) == "rival" and sim.agents[other_id].available_to_talk():
				out.append(_candidate(Kind.RECONCILE, 0.2, "reason_rivalry", other_id, agent.beliefs.opinion_of(other_id)))
				break
	_help(sim, agent, out)
	_migrate(sim, agent, out)


static func _court(sim: RefCounted, agent: RefCounted, out: Array, off_hours: float) -> void:
	if agent.is_child or agent.partner >= 0:
		return
	var smitten: bool = false
	for id in agent.beliefs.relations:
		smitten = smitten or agent.beliefs.opinion_of(id) > 55.0
	if agent.personality.romance <= 0.0 and agent.ambition.get("id", "") != "raise_family" and not smitten:
		return
	var best: int = -1
	var best_score: float = -INF
	var ids: Array = agent.beliefs.relations.keys()
	ids.sort()
	for id in ids:
		var relation: Dictionary = agent.beliefs.relations[id]
		var other: RefCounted = sim.agents[id]
		var eligible: bool = float(relation.romance) > 15.0 or (float(relation.opinion) > 45.0 and not other.is_child and other.partner < 0 and other.is_present())
		if not eligible or not other.is_present():
			continue
		var score: float = float(relation.romance) + float(relation.opinion)
		if score > best_score:
			best = id
			best_score = score
	if best >= 0:
		var romance: float = float(agent.beliefs.relations[best].romance)
		out.append(_candidate(Kind.COURT, 0.3 * (1.0 + agent.personality.romance) * off_hours + romance * 0.004, "reason_romance", best, romance))


static func _help(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	if agent.help_task.is_empty():
		return
	var requester: int = int(agent.help_task.requester)
	if not sim.agents[requester].is_present():
		agent.help_task = {}
		return
	var need: int = int(agent.help_task.need)
	# Being asked to teach is weighed with cultivation (deliberation_cultivation.gd).
	if need == Goals.HelpNeed.TEACHING:
		return
	var utility: float = 1.0 if need != Goals.HelpNeed.DEFENCE else 0.9 * (0.5 + agent.personality.bravery)
	out.append(_candidate(Kind.HELP, utility, "reason_asked", requester, NAN, need))


## Unhappy people who believe in a better place consider moving there.
static func _migrate(sim: RefCounted, agent: RefCounted, out: Array) -> void:
	# Someone who has just moved gives the new place a while before moving on.
	if agent.is_child or agent.low_mood_ticks <= 0 or sim.calendar.day() - agent.joined_day < Balance.integer("mood.settle_days"):
		return
	var days: float = float(agent.low_mood_ticks) / sim.calendar.ticks_per_day
	var target: int = better_settlement(sim, agent)
	var departing: bool = days >= Balance.number("mood.departure_days")
	if target < 0 and not departing:
		return
	var utility: float = 1.6 if departing else 0.15 + days * 0.12 + maxf(30.0 - agent.mood, 0.0) * 0.01
	out.append(_candidate(Kind.MIGRATE, utility, "reason_unhappy", target, agent.mood, 1 if departing else 0))


## A settlement the person believes in, other than their own, or -1.
static func better_settlement(sim: RefCounted, agent: RefCounted) -> int:
	var best: int = -1
	var keys: Array = agent.beliefs.places.keys()
	keys.sort()
	for key in keys:
		var place: Dictionary = agent.beliefs.places[key]
		if place.kind != "settlement" or int(place.id) == agent.settlement_id:
			continue
		if not sim.settlements.entries.has(int(place.id)):
			continue
		best = int(place.id)
		break
	return best
