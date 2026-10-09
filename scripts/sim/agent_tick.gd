extends RefCounted
## One tick for every present person, in id order: body, perception, inbox,
## cognition, execution, movement. Then the tick's effects apply at once and
## the dead are resolved.
const Body = preload("res://scripts/sim/body.gd")
const Perception = preload("res://scripts/sim/perception.gd")
const Inbox = preload("res://scripts/sim/inbox.gd")
const Cognition = preload("res://scripts/sim/cognition.gd")
const Execute = preload("res://scripts/sim/execute.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const EffectsApply = preload("res://scripts/sim/effects_apply.gd")
const Lifecycle = preload("res://scripts/sim/lifecycle.gd")


static func update_agents(sim: RefCounted) -> void:
	for agent in sim.agents:
		if not agent.is_present():
			continue
		Body.update(sim, agent)
		var alarmed: bool = Perception.perceive(sim, agent)
		var urgent: bool = Inbox.process(sim, agent)
		if alarmed and agent.interrupted_by.is_empty():
			agent.interrupted_by = "interrupt_percept"
		Cognition.think(sim, agent, alarmed or urgent)
		Execute.run_step(sim, agent)
		Movement.advance(sim, agent)


static func after_agents(sim: RefCounted) -> void:
	EffectsApply.apply(sim)
	Lifecycle.resolve_deaths(sim)
