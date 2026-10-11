extends RefCounted
## Plans for branches (M21): setting out for a founding ground to found or
## follow a branch, packing as a founder of a settlement does, and carrying
## relics home from the ruins of a fallen shrine.
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const PlansQuest = preload("res://scripts/agents/plan_library_quest.gd")
const Relics = preload("res://scripts/sim/relics.gd")
const Branches = preload("res://scripts/sim/branches.gd")
const PlansSocial = preload("res://scripts/agents/plan_library_social.gd")

const Op = Plans.Op
const T = Plans.T


static func plans(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> Array:
	if int(goal.kind) == Goals.Kind.RECOVER_RELIC:
		return _recover(sim, agent, int(goal.target))
	if int(goal.kind) == Goals.Kind.ADMIT_GUEST:
		return [H.option("receive_the_guest", 1.0, [Plans.go_to(Plans.target(T.AGENT, int(goal.target))), Plans.step(Op.RECEIVE_GUEST, {"guest": int(goal.target)})])]
	if int(goal.kind) == Goals.Kind.SEEK_SANCTUARY:
		var edge: Vector3i = PlansSocial.valley_edge(sim, agent)
		if edge.x < 0:
			return []
		return [H.option("set_out_for_the_tree", 1.0, H.free_hands(agent) + [Plans.go_cell(edge), Plans.step(Op.EMIGRATE, {"target": -1, "cause": 0})])]
	return _branch(sim, agent, int(goal.target), int(goal.extra))


## The founding plans, with the settling step marked as a branch's: the
## founder's cause, or a follower's (who founds anew only if the branch is gone).
static func _branch(sim: RefCounted, agent: RefCounted, ground: int, cause: int) -> Array:
	# A ground in another region: out over the valley's rim (M22).
	if Branches.is_abroad(ground):
		var edge: Vector3i = PlansSocial.valley_edge(sim, agent)
		if edge.x < 0:
			return []
		return [H.option("set_out_for_far_ground", 1.0, H.free_hands(agent) + [Plans.go_cell(edge), Plans.step(Op.EMIGRATE, {"target": ground, "cause": cause})])]
	var options: Array = PlansQuest._found(sim, agent, ground)
	for option in options:
		for step in option.steps:
			if int(step.op) == Op.SETTLE:
				step["branch"] = cause if cause > 0 else Branches.Cause.AMBITION
	return options


## Walk to the ruin, take up its relics, carry them to a living shrine.
static func _recover(sim: RefCounted, agent: RefCounted, from: int) -> Array:
	var ruin: Dictionary = sim.faith.get_shrine(from)
	var to: int = Relics.shrine_home(sim, agent)
	if ruin.is_empty() or to < 0:
		return []
	var stand: Vector3i = sim.nav.nearest_walkable(ruin.cell, 3)
	if stand.x < 0:
		return []
	return [H.option("carry_relics_home", 1.0, H.free_hands(agent) + [Plans.go_cell(stand), Plans.step(Op.TAKE_RELICS, {"shrine": from}),
		Plans.go_to(Plans.target(T.SHRINE, to)), Plans.step(Op.LAY_RELICS, {"shrine": to})])]
