extends RefCounted
## Who should have the tree's spirit fruit: the master's judgement, read
## through the sect's doctrine. The readiest for Heaven first; a closed sect
## favours those its master likes, a merciful one the weakest foundation, an
## ambitious one the greatest promise. Returns [recipient id, reason key] or
## [-1, ""] when nobody is near enough to the peak to need it.
const Data = preload("res://scripts/core/data.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")


static func wants_fruit(sim: RefCounted, agent: RefCounted) -> bool:
	var c: Dictionary = agent.cultivation
	if not agent.is_present() or c.is_empty() or int(c.realm) < 1 or not CultivationState.has_next(c) or bool(c.get("fruit", false)):
		return false
	if sim.tribulations != null and not sim.tribulations.of(agent.id).is_empty() and sim.tribulations.of(agent.id).state == "storm":
		return false
	return float(c.progress) >= CultivationState.needed(c) * float(Data.tree_growth().fruit.near_peak)


static func choose(sim: RefCounted, sect: Dictionary, chooser: RefCounted) -> Array:
	var doctrine: Dictionary = sect.doctrine
	var best: int = -1
	var best_score: float = -INF
	var best_reason: String = ""
	var members: Array = sect.members.keys()
	members.sort()
	for id in members:
		var member: RefCounted = sim.agents[id]
		if not wants_fruit(sim, member):
			continue
		var c: Dictionary = member.cultivation
		var parts: Dictionary = {
			"cause_fruit_readiest": float(c.progress) / CultivationState.needed(c) + (0.5 if CultivationState.at_peak(c) else 0.0),
			"cause_fruit_favourite": (chooser.beliefs.opinion_of(id) / 100.0) * (1.0 - float(doctrine.openness)) * 0.8 if id != chooser.id else 0.0,
			"cause_fruit_mercy": float(doctrine.mercy) * (1.0 - float(c.foundation)) * 0.8,
			"cause_fruit_promise": float(doctrine.ambition) * float(c.talent) * 0.8,
		}
		var score: float = 0.0
		var reason: String = "cause_fruit_readiest"
		var biggest: float = -INF
		for key in ["cause_fruit_readiest", "cause_fruit_favourite", "cause_fruit_mercy", "cause_fruit_promise"]:
			score += float(parts[key])
			# Readiness is weighed against the rest at a discount: it is the
			# expected reason, so another one names the choice only when it tips it.
			var weight: float = float(parts[key]) * (0.5 if key == "cause_fruit_readiest" else 1.0)
			if weight > biggest:
				biggest = weight
				reason = key
		if score > best_score:
			best = id
			best_score = score
			best_reason = reason
	return [best, best_reason]
