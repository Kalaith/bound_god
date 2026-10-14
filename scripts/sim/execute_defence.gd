extends RefCounted
## Defence and scouting steps.
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Balance = preload("res://addons/hatchery/core/balance.gd")

const Op = Plans.Op
const Fail = Plans.Fail


## Stand and look: perception does the rest while they linger.
static func _scout(agent: RefCounted, ticks: int, step_ticks: int) -> int:
	agent.activity = "scouting"
	Personality.practise(agent, Personality.Skill.EXPLORATION)
	return Plans.DONE if step_ticks >= ticks else Plans.RUNNING


static func run(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	match int(step.op):
		Op.SCOUT:
			return _scout(agent, int(step.ticks), step_ticks)
		Op.ATTACK:
			return sim.threats.attack_step(sim, agent, step, step_ticks) if sim.threats != null else Plans.DONE
	return Fail.INTERRUPTED
