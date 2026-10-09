extends RefCounted
## Faith plans: praying at the shrine they attend or where they stand,
## tending a shrine, restoring a fallen altar, telling the god's story and
## answering a request.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const DeliberationFaith = preload("res://scripts/agents/deliberation_faith.gd")

const Kind = Goals.Kind
const Op = Plans.Op
const T = Plans.T


static func plans(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> Array:
	var ticks: int = Balance.integer("faith.prayer_ticks")
	match int(goal.kind):
		Kind.PRAY:
			var result: Array = []
			var shrine: int = DeliberationFaith.attended_shrine(sim, agent)
			if shrine >= 0:
				result.append(H.option("pray_at_shrine", 1.0, [Plans.go_to(Plans.target(T.SHRINE, shrine)), Plans.step(Op.PRAY, {"shrine": shrine, "ticks": ticks})]))
			result.append(H.option("pray_here", 0.3, [Plans.step(Op.PRAY, {"shrine": -1, "ticks": ticks})]))
			return result
		Kind.TEND_SHRINE:
			var shrine: int = int(goal.target)
			return [H.option("tend_shrine", 1.0, [Plans.go_to(Plans.target(T.SHRINE, shrine)), Plans.step(Op.TEND, {"shrine": shrine, "ticks": 60})])]
	if sim.requests != null:
		return sim.requests.plans(sim, agent, goal)
	return []
