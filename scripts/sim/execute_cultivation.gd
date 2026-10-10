extends RefCounted
## Cultivation steps. Meditating moves the person's own progress on, by
## their talent, technique, foundation and the qi where they sit; reaching a
## realm's threshold and passing on a technique are effects, applied at the
## end of the tick and chronicled there.
const Balance = preload("res://scripts/core/balance.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")
const SectPlaces = preload("res://scripts/sim/sect_places.gd")

const Op = Plans.Op
const Fail = Plans.Fail
const Need = Personality.Need


static func _near(a: Vector3i, b: Vector3i) -> bool:
	return absi(a.x - b.x) <= 2 and absi(a.z - b.z) <= 2 and absi(a.y - b.y) <= 1


static func _cultivate(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	agent.activity = "cultivating"
	var cultivation: Dictionary = agent.cultivation
	if agent.step_result.has("advanced"):
		return Plans.DONE
	# Hunger and exhaustion break a sitting off.
	if agent.need(Need.FOOD) < Balance.number("needs.urgent_threshold") or agent.need(Need.REST) < 15.0:
		return Plans.DONE
	var per_hour: float = float(sim.calendar.ticks_per_hour())
	var needed: float = CultivationState.needed(cultivation)
	var qi: float = sim.qi.density(sim, agent.cell)
	var rate: float = CultivationState.rate(cultivation, qi)
	if int(cultivation.blessed_until) > sim.calendar.tick:
		rate *= Balance.number("cultivation.bless_factor")
	# A mat in a meditation hall: shelter and a settled mind.
	if SectPlaces.in_hall(sim, agent.cell):
		rate *= Balance.number("cultivation.hall_factor")
	cultivation.progress = minf(float(cultivation.progress) + rate / per_hour, needed)
	if int(cultivation.realm) >= 1 and float(cultivation.progress) >= needed and int(cultivation.peak_tick) < 0:
		cultivation.peak_tick = sim.calendar.tick
	cultivation.hours = float(cultivation.hours) + 1.0 / per_hour
	# A mortal who reaches the threshold steps into Qi Refining; beyond it
	# only a breakthrough leads on.
	if int(cultivation.realm) == 0 and float(cultivation.progress) >= needed:
		if not agent.step_result.has("advancing"):
			agent.step_result = {"advancing": true}
			sim.effects.action("advance_realm", agent.id, {"qi": qi})
		return Plans.RUNNING
	return Plans.DONE if step_ticks >= int(step.ticks) else Plans.RUNNING


static func _teach(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var id: int = int(step.to)
	if id < 0 or id >= sim.agents.size() or not sim.agents[id].is_present():
		return Fail.TARGET_GONE
	var student: RefCounted = sim.agents[id]
	var lacking: Array = DeliberationCultivation.lacking(student, agent)
	if lacking.is_empty():
		return Plans.DONE
	if not _near(agent.cell, student.cell) or not student.available_to_talk():
		# The student wandered off or fell asleep: wait a little, then give up.
		return Fail.TARGET_GONE if step_ticks > 40 else Plans.RUNNING
	agent.activity = "teaching"
	if step_ticks < int(step.ticks):
		return Plans.RUNNING
	if not agent.step_result.has("taught"):
		if step_ticks == int(step.ticks):
			sim.effects.action("teach", agent.id, {"to": id, "technique": str(lacking[0])})
		return Plans.RUNNING
	return Plans.DONE


static func _wait_to_learn(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	agent.activity = "learning"
	var teacher: int = int(step.with)
	if int(agent.cultivation.teacher) == teacher and agent.step_result.has("learned"):
		return Plans.DONE
	if teacher < 0 or teacher >= sim.agents.size() or not sim.agents[teacher].is_present():
		return Fail.TARGET_GONE
	if step_ticks >= int(step.ticks):
		agent.beliefs.note_failure("teacher:%d" % teacher, sim.calendar.tick)
		return Fail.TIMED_OUT
	return Plans.RUNNING


static func _proclaim(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	agent.activity = "proclaiming"
	if step_ticks < int(step.ticks):
		return Plans.RUNNING
	if step_ticks == int(step.ticks):
		sim.effects.action("found_sect", agent.id)
		return Plans.RUNNING
	if not agent.step_result.has("sect"):
		return Plans.RUNNING
	return Plans.DONE if int(agent.step_result.sect) > 0 else Fail.REFUSED


static func run(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	match int(step.op):
		Op.CULTIVATE:
			return _cultivate(sim, agent, step, step_ticks)
		Op.TEACH:
			return _teach(sim, agent, step, step_ticks)
		Op.WAIT_TO_LEARN:
			return _wait_to_learn(sim, agent, step, step_ticks)
		Op.PROCLAIM:
			return _proclaim(sim, agent, step, step_ticks)
		Op.FACE_HEAVEN:
			return _face_heaven(sim, agent, step_ticks)
		Op.PICK_FRUIT:
			return _pick_fruit(sim, agent, step, step_ticks)
		Op.HAND_FRUIT:
			return _hand_fruit(sim, agent, step, step_ticks)
	return Fail.INTERRUPTED


## Announce the attempt, then sit and wait for Heaven; done when the storm
## has passed.
static func _face_heaven(sim: RefCounted, agent: RefCounted, step_ticks: int) -> int:
	agent.activity = "facing_heaven"
	var trial: Dictionary = sim.tribulations.of(agent.id)
	if trial.is_empty():
		if step_ticks == 0:
			sim.effects.action("announce_trial", agent.id, {"site": agent.cell})
			return Plans.RUNNING
		return Plans.DONE if agent.step_result.has("trial") else Plans.RUNNING
	return Plans.RUNNING


## Reach up into the crown for a fruit: for themselves it is theirs at once,
## for someone else it is carried to them.
static func _pick_fruit(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	agent.activity = "picking_fruit"
	if step_ticks < 8:
		return Plans.RUNNING
	if step_ticks == 8:
		sim.effects.action("pick_fruit", agent.id, {"for": int(step.with)})
		return Plans.RUNNING
	if not agent.step_result.has("picked"):
		return Plans.RUNNING
	return Plans.DONE if int(agent.step_result.picked) > 0 else Fail.TARGET_GONE


static func _hand_fruit(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var id: int = int(step.to)
	if agent.carrying.is_empty() or str(agent.carrying.resource) != "spirit_fruit":
		return Fail.STOCK_EMPTY
	if id < 0 or id >= sim.agents.size() or not sim.agents[id].is_present():
		return Fail.TARGET_GONE
	if id != agent.id and not _near(agent.cell, sim.agents[id].cell):
		return Fail.TARGET_GONE if step_ticks > 60 else Plans.RUNNING
	sim.effects.action("hand_fruit", agent.id, {"to": id})
	agent.carrying = {}
	return Plans.DONE
