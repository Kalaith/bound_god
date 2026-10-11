extends RefCounted
## Plans for designs: work one out by the settlement's hall (or round its
## camp), a sitting at a time; or walk to the valley's rim and set out.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const FunctionRules = preload("res://scripts/building/function_rules.gd")
const PlansSocial = preload("res://scripts/agents/plan_library_social.gd")

const Kind = Goals.Kind
const Op = Plans.Op


static func plans(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> Array:
	var settlement: Dictionary = sim.settlements.get_settlement(agent.settlement_id)
	if settlement.is_empty():
		return []
	match int(goal.kind):
		Kind.STUDY:
			var function: String = FunctionRules.FUNCTIONS[int(goal.target)] if int(goal.target) >= 0 else ""
			if function.is_empty():
				return []
			var study := Plans.step(Op.STUDY, {"function": function, "sect": int(goal.extra) == 1, "ticks": Balance.integer("designs.study_ticks")})
			var center: Vector3i = settlement.camp
			var spot: Vector3i = H.ring_cell(sim, Vector3(center.x + 0.5, center.y, center.z + 0.5), agent.id, 2.0, 6.0)
			var result: Array = [H.option("think_it_through_here", 0.3, [study])]
			if spot.x >= 0:
				result.append(H.option("think_it_through_by_the_camp", 1.0, [Plans.go_cell(spot), study]))
			return result
		Kind.SEEK_PLANS:
			var edge: Vector3i = PlansSocial.valley_edge(sim, agent)
			if edge.x < 0:
				return []
			return [H.option("set_out_from_the_valley", 1.0, [Plans.go_cell(edge), Plans.step(Op.SET_OUT)])]
	return []
