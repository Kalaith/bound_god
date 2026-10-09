extends RefCounted
## Life steps: eating, sleeping, shelter, relaxing, recovering, hiding,
## waiting, mental breaks, scouting and defence.
const Balance = preload("res://scripts/core/balance.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const ExecuteDefence = preload("res://scripts/sim/execute_defence.gd")

const Op = Plans.Op
const Fail = Plans.Fail
const Need = Personality.Need
const EAT_TICKS: int = 10


## Step inside the structure whose cells hold where the person stands.
static func enter_here(sim: RefCounted, agent: RefCounted) -> void:
	if agent.inside < 0:
		agent.inside = sim.structure_id_at(agent.cell)


static func _eat(sim: RefCounted, agent: RefCounted, step_ticks: int) -> int:
	if agent.carried("berries") < 0.5:
		return Fail.STOCK_EMPTY
	agent.activity = "eating"
	if step_ticks < EAT_TICKS:
		return Plans.RUNNING
	var amount: float = float(agent.carrying.amount)
	agent.change_need(Need.FOOD, Balance.number("needs.raw_food_restore") * maxf(minf(amount, 1.0), 0.5))
	Mind.add(agent, "ate_raw", sim.calendar.ticks_per_day)
	Mind.remove(agent, "went_hungry")
	if amount - 1.0 > 0.05:
		agent.carrying.amount = amount - 1.0
	else:
		agent.carrying = {}
	return Plans.DONE


static func _sleep(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var bed: int = int(step.get("structure", -1))
	var in_bed: bool = false
	if bed >= 0:
		var entry: Dictionary = sim.structures.entries.get(bed, {})
		if entry.is_empty():
			return Fail.TARGET_GONE
		if not entry.residents.has(agent.id):
			if step_ticks == 0:
				sim.effects.action("claim_bed", agent.id, {"structure": bed})
				return Plans.RUNNING
			return Fail.OCCUPIED
		in_bed = true
		agent.inside = bed
	else:
		enter_here(sim, agent)
	agent.activity = "sleeping"
	var rate: float = Balance.number("needs.bed_rest_per_day") if in_bed else Balance.number("needs.ground_rest_per_day")
	agent.change_need(Need.REST, sim.calendar.per_tick(rate))
	var rested: bool = agent.need(Need.REST) >= 99.0
	var too_long: bool = step_ticks > sim.calendar.ticks_per_day * 6 / 10
	if (rested and not Schedule.is_sleep_time(sim, agent)) or too_long or (rested and step_ticks > 200):
		Mind.add(agent, "slept_bed" if in_bed else "slept_ground", sim.calendar.ticks_per_day)
		agent.inside = -1
		return Plans.DONE
	return Plans.RUNNING


static func _shelter(sim: RefCounted, agent: RefCounted, ticks: int, step_ticks: int) -> int:
	enter_here(sim, agent)
	agent.activity = "sheltering"
	var covered: bool = agent.inside >= 0 or sim.voxels.is_roofed(agent.cell + Vector3i.UP, 6)
	if agent.need(Need.SHELTER) >= 85.0 or step_ticks >= (ticks * 3 if covered else ticks):
		agent.inside = -1
		return Plans.DONE
	return Plans.RUNNING


static func _relax(sim: RefCounted, agent: RefCounted, ticks: int, step_ticks: int) -> int:
	agent.activity = "relaxing"
	agent.change_need(Need.RECREATION, sim.calendar.per_tick(Balance.number("needs.recreation_gain_per_day") * 0.8))
	if step_ticks >= ticks or agent.need(Need.RECREATION) >= 96.0:
		return Plans.DONE
	return Plans.RUNNING


static func _recover(sim: RefCounted, agent: RefCounted, ticks: int, step_ticks: int) -> int:
	enter_here(sim, agent)
	agent.activity = "recovering"
	var healed: bool = float(agent.health.hp) >= Balance.number("health.care_threshold") + 10.0 and not agent.health.ill
	if healed or step_ticks >= ticks:
		agent.inside = -1
		return Plans.DONE
	return Plans.RUNNING


static func _hide(sim: RefCounted, agent: RefCounted, ticks: int, step_ticks: int) -> int:
	enter_here(sim, agent)
	agent.activity = "fleeing"
	var threat: Array = agent.beliefs.nearest_threat(agent.cell)
	var near: bool = not threat.is_empty() and threat[1] < 6.0
	if step_ticks >= ticks and (not near or step_ticks >= ticks * 3):
		agent.inside = -1
		return Plans.DONE
	return Plans.RUNNING


static func _break(sim: RefCounted, agent: RefCounted, ticks: int, step_ticks: int) -> int:
	agent.activity = "breaking"
	if agent.carried("berries") > 0.0:
		agent.change_need(Need.FOOD, float(agent.carrying.amount) * 10.0)
		agent.carrying = {}
	if step_ticks >= ticks:
		agent.mental_break = {}
		Mind.add(agent, "mental_break", sim.calendar.ticks_per_day)
		return Plans.DONE
	return Plans.RUNNING


static func run(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	match int(step.op):
		Op.EAT:
			return _eat(sim, agent, step_ticks)
		Op.SLEEP:
			return _sleep(sim, agent, step, step_ticks)
		Op.SHELTER:
			return _shelter(sim, agent, int(step.ticks), step_ticks)
		Op.RELAX:
			return _relax(sim, agent, int(step.ticks), step_ticks)
		Op.RECOVER:
			return _recover(sim, agent, int(step.ticks), step_ticks)
		Op.HIDE:
			return _hide(sim, agent, int(step.ticks), step_ticks)
		Op.BREAK:
			return _break(sim, agent, int(step.ticks), step_ticks)
		Op.WAIT:
			agent.activity = "idle"
			return Plans.DONE if step_ticks >= int(step.ticks) else Plans.RUNNING
		Op.ATTACK, Op.SCOUT:
			return ExecuteDefence.run(sim, agent, step, step_ticks)
	return Fail.INTERRUPTED
