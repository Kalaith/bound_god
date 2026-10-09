extends RefCounted
## The plan library: alternative ways to achieve each goal. Every plan has a
## context condition, checked against the person's beliefs and what they can
## see, and a preference. A failed plan is excluded and the next is tried.
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const PlansNeeds = preload("res://scripts/agents/plan_library_needs.gd")
const PlansWork = preload("res://scripts/agents/plan_library_work.gd")
const PlansSocial = preload("res://scripts/agents/plan_library_social.gd")
const PlansFaith = preload("res://scripts/agents/plan_library_faith.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")

const Kind = Goals.Kind


## Every applicable plan for a goal, best preference first.
static func plans_for(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> Array:
	var kind: int = int(goal.kind)
	var plans: Array
	match kind:
		Kind.EAT:
			plans = PlansNeeds.eat(sim, agent)
		Kind.SLEEP:
			plans = PlansNeeds.sleep(sim, agent)
		Kind.TAKE_SHELTER:
			plans = PlansNeeds.shelter(sim, agent)
		Kind.FLEE:
			plans = PlansNeeds.flee(sim, agent)
		Kind.SEEK_CARE:
			plans = PlansNeeds.care(sim, agent)
		Kind.RELAX:
			plans = PlansNeeds.relax(sim, agent)
		Kind.IDLE:
			plans = [Plans.option("loiter", 1.0, [Plans.go_cell(H.wander_cell(sim, agent)), Plans.step(Plans.Op.WAIT, {"ticks": 20})])]
		Kind.CHAT, Kind.COMFORT, Kind.COURT, Kind.RECONCILE, Kind.HELP, Kind.BREAK, Kind.MIGRATE:
			plans = PlansSocial.plans(sim, agent, goal)
		Kind.PRAY, Kind.TEND_SHRINE, Kind.RESTORE_SHRINE, Kind.PREACH, Kind.QUEST:
			plans = PlansFaith.plans(sim, agent, goal)
		_:
			plans = PlansWork.plans(sim, agent, goal)
	Plans.sort_options(plans)
	return plans
