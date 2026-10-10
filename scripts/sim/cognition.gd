extends RefCounted
## The deliberation cycle: when to reconsider, whether to switch goals, and
## choosing or replacing a plan. Commitment keeps people finishing what they
## start; a rival goal must beat the current one by a margin.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Deliberation = preload("res://scripts/agents/deliberation.gd")
const PlanLibrary = preload("res://scripts/agents/plan_library.gd")

const Kind = Goals.Kind


static func switch_threshold(current: Dictionary, best: Dictionary) -> float:
	var commitment: float = Balance.number("agents.commitment_bonus")
	if Goals.is_survival(current) and not Goals.is_survival(best):
		return 1.0 + commitment * 3.0
	return 1.0 + commitment


## Whether a new candidate is worth abandoning the current intention for.
static func should_switch(current_goal: Dictionary, current_utility: float, best: Dictionary) -> bool:
	if Goals.key(best.goal) == Goals.key(current_goal):
		return false
	if int(best.goal.kind) == Kind.BREAK:
		return true
	return best.utility > maxf(current_utility, 0.01) * switch_threshold(current_goal, best.goal)


## Carried loads stay with a person through any change of mind; plans that
## need free hands put the load in the stores first (PlanHelpers.free_hands).
## Final Landing drops loads on every change of goal, which on the valley's
## long walks wasted most of them. Only someone leaving sets the load down.
static func _drop_load(sim: RefCounted, agent: RefCounted, next: Dictionary) -> void:
	if agent.carrying.is_empty() or int(next.kind) != Kind.MIGRATE:
		return
	sim.effects.action("drop", agent.id, {"cell": agent.cell, "resource": agent.carrying.resource, "amount": agent.carrying.amount})
	agent.carrying = {}


static func adopt(sim: RefCounted, agent: RefCounted, best: Dictionary, interrupted_by: String) -> void:
	var tick: int = sim.calendar.tick
	if not interrupted_by.is_empty():
		agent.record(tick, "interrupted", {"by": interrupted_by})
	_drop_load(sim, agent, best.goal)
	agent.record(tick, "adopted", {"goal": best.goal.duplicate(), "utility": best.utility, "reason": best.reason,
		"value": best.value, "urged": best.get("urged", false)})
	agent.path.clear()
	agent.inside = -1
	sim.goal_version += 1
	agent.intention = {"goal": best.goal.duplicate(), "utility": best.utility, "reason": best.reason, "value": best.value,
		"urged": best.get("urged", false), "plan": {}, "tried": [], "started_tick": tick}


static func deliberate(sim: RefCounted, agent: RefCounted, interrupted: bool) -> void:
	var options: Array = Deliberation.candidates(sim, agent)
	var best: Dictionary = Deliberation.best(options)
	if best.is_empty():
		return
	if agent.intention.is_empty():
		adopt(sim, agent, best, "")
		return
	var current: Dictionary = agent.intention.goal
	var current_utility: float = 0.0
	for entry in options:
		if Goals.key(entry.goal) == Goals.key(current):
			current_utility = entry.utility
			break
	if should_switch(current, current_utility, best):
		var by: String = ""
		if interrupted:
			by = agent.interrupted_by if not agent.interrupted_by.is_empty() else "interrupt_percept"
		adopt(sim, agent, best, by)
	else:
		agent.intention.utility = current_utility


## Choose the best applicable plan not yet tried; give up if none remain.
static func ensure_plan(sim: RefCounted, agent: RefCounted) -> void:
	if agent.intention.is_empty() or not agent.intention.plan.is_empty():
		return
	var goal: Dictionary = agent.intention.goal
	var tried: Array = agent.intention.tried
	var chosen: Dictionary = {}
	if tried.size() < Balance.integer("agents.max_plan_attempts"):
		for option in PlanLibrary.plans_for(sim, agent, goal):
			if not tried.has(option.id):
				chosen = option
				break
	if chosen.is_empty():
		give_up(sim, agent, goal)
		return
	agent.record(sim.calendar.tick, "plan", {"plan": chosen.id})
	agent.intention.plan = Plans.plan_from(chosen)


## Every plan failed: back off from the goal for a while, and feel it.
static func give_up(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> void:
	var tick: int = sim.calendar.tick
	agent.record(tick, "gave_up", {"goal": goal.duplicate()})
	agent.back_off(Goals.key(goal), tick + Balance.integer("agents.goal_backoff_ticks"))
	if Goals.is_survival(goal) or Goals.is_social(goal):
		Mind.add(agent, "frustrated", sim.calendar.ticks_per_day)
	if int(goal.kind) == Kind.HELP:
		agent.help_task = {}
	if int(goal.kind) == Kind.QUEST and sim.requests != null:
		sim.requests.abandon(sim, agent)
	agent.intention = {}
	sim.goal_version += 1
	agent.activity = "idle"
	agent.next_deliberation = tick + 1


static func think(sim: RefCounted, agent: RefCounted, interrupted: bool) -> void:
	var due: bool = sim.calendar.tick >= agent.next_deliberation
	if agent.intention.is_empty() or due or interrupted:
		deliberate(sim, agent, interrupted)
		agent.next_deliberation = sim.calendar.tick + Balance.integer("agents.deliberation_interval") + agent.id % 3
	agent.interrupted_by = ""
	ensure_plan(sim, agent)
