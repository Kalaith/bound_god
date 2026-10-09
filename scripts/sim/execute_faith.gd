extends RefCounted
## Faith steps: praying (with the intent of their most pressing problem) and
## tending a shrine.
const Balance = preload("res://scripts/core/balance.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Mind = preload("res://scripts/agents/mind.gd")

const Op = Plans.Op
const Fail = Plans.Fail


## What a prayer asks for: the lowest need if it is pressing, else a believed
## danger, a hurt partner, or thanks.
static func intent(sim: RefCounted, agent: RefCounted) -> Dictionary:
	var lowest: int = agent.lowest_need()
	if agent.need(lowest) < 50.0:
		return {"kind": Personality.NEEDS[lowest], "level": agent.need(lowest)}
	if not agent.beliefs.threats.is_empty() or Mind.has(agent, "strangers_watching"):
		return {"kind": "threat", "level": 30.0}
	if agent.partner >= 0 and sim.agents[agent.partner].needs_care(Balance.number("health.care_threshold")):
		return {"kind": "partner", "level": 40.0}
	return {"kind": "thanks", "level": 100.0}


static func _pray(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	agent.activity = "praying"
	Personality.practise(agent, Personality.Skill.DEVOTION)
	if step_ticks < int(step.ticks):
		return Plans.RUNNING
	var shrine: int = int(step.shrine)
	if shrine >= 0 and sim.faith.get_shrine(shrine).get("state", "fallen") == "fallen":
		return Fail.TARGET_GONE
	sim.effects.action("prayer", agent.id, {"shrine": shrine, "intent": intent(sim, agent)})
	return Plans.DONE


static func _tend(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var shrine: Dictionary = sim.faith.get_shrine(int(step.shrine))
	if shrine.is_empty() or shrine.state == "fallen":
		return Fail.TARGET_GONE
	agent.activity = "working"
	Personality.practise(agent, Personality.Skill.DEVOTION)
	if step_ticks < int(step.ticks) and float(shrine.condition) + step_ticks * Balance.number("shrines.tend_per_tick") < 100.0:
		return Plans.RUNNING
	sim.effects.action("tend", agent.id, {"shrine": int(step.shrine), "amount": step_ticks * Balance.number("shrines.tend_per_tick")})
	return Plans.DONE


static func run(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	match int(step.op):
		Op.PRAY:
			return _pray(sim, agent, step, step_ticks)
		Op.TEND:
			return _tend(sim, agent, step, step_ticks)
	return Fail.INTERRUPTED
