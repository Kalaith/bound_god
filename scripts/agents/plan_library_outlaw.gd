extends RefCounted
## An outlaw's plans (M22): to the target's stores and take what can be
## carried; then to its altar and break it, if its people pray; or back to
## the valley's edge and away, saying first why they turned.
const Plans = preload("res://scripts/agents/plans.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const Outlaws = preload("res://scripts/sim/outlaws.gd")
const DeliberationOutlaw = preload("res://scripts/agents/deliberation_outlaw.gd")

const Op = Plans.Op


static func plans(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> Array:
	var o: Dictionary = agent.backstory.outlaw
	if int(goal.kind) == Goals.Kind.RETREAT:
		var why: String = DeliberationOutlaw.fall_back(sim, agent)
		return [Plans.option("fall_back", 1.0, [Plans.step(Op.LEAVE_VALLEY, {"phase": "turn", "cause": why}), Plans.go_cell(o.home),
			Plans.step(Op.LEAVE_VALLEY, {"phase": "go", "cause": why})])]
	if not bool(o.looted):
		var store: Vector3i = sim.settlements.store_access(sim, int(o.target), agent.cell)
		if store.x < 0:
			store = sim.settlements.get_settlement(int(o.target)).get("camp", agent.cell)
		return [Plans.option("take_the_stores", 1.0, [Plans.go_cell(store), Plans.step(Op.LOOT)])]
	var shrine: Dictionary = Outlaws.target_shrine(sim, int(o.target))
	if bool(o.altar) and not shrine.is_empty():
		var stand: Vector3i = sim.nav.nearest_walkable(shrine.cell, 2)
		if stand.x >= 0:
			return [Plans.option("break_the_altar", 1.0, [Plans.go_cell(stand), Plans.step(Op.DESECRATE)])]
	return []
