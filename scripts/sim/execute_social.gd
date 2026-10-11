extends RefCounted
## Social steps: talking, sending messages, giving, waiting for help,
## tending someone, joining a settlement and leaving the valley.
const Balance = preload("res://scripts/core/balance.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Goals = preload("res://scripts/agents/goals.gd")

const Op = Plans.Op
const Fail = Plans.Fail
const Need = Personality.Need
const TREAT_TICKS: float = 40.0


static func _other(sim: RefCounted, id: int) -> RefCounted:
	if id < 0 or id >= sim.agents.size() or not sim.agents[id].is_present():
		return null
	return sim.agents[id]


## Walk to within two cells of someone; null when close enough.
static func _approach(sim: RefCounted, agent: RefCounted, cell: Vector3i, step_ticks: int) -> Variant:
	if absi(cell.x - agent.cell.x) <= 2 and absi(cell.z - agent.cell.z) <= 2 and absi(cell.y - agent.cell.y) <= 1:
		agent.path.clear()
		return null
	if step_ticks > 160:
		return Fail.TIMED_OUT
	if agent.path.is_empty() or step_ticks % 8 == 0:
		if not sim.nav.can_path():
			return Plans.RUNNING
		var destination: Vector3i = sim.nav.nearest_walkable(cell, 1)
		var route: Array[Vector3i] = sim.nav.find_path(agent.cell, destination if destination.x >= 0 else cell)
		if route.is_empty() and agent.cell != destination:
			return Fail.NO_PATH
		agent.path = route
	agent.activity = "walking"
	return Plans.RUNNING


static func _talk(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var other: RefCounted = _other(sim, int(step.with))
	if other == null:
		return Fail.TARGET_GONE
	if not other.available_to_talk():
		return Fail.REFUSED
	var moving: Variant = _approach(sim, agent, other.cell, step_ticks)
	if moving != null:
		return moving
	agent.inside = -1
	agent.activity = "talking"
	var chat_ticks: int = Balance.integer("social.chat_ticks")
	var relation: Dictionary = agent.beliefs.relation(other.id)
	var started: int = int(relation.last_chat_tick)
	var elapsed: int = sim.calendar.tick - started
	if started < 0 or elapsed > chat_ticks * 4:
		relation.last_chat_tick = sim.calendar.tick
		return Plans.RUNNING
	if elapsed < chat_ticks:
		return Plans.RUNNING
	agent.change_need(Need.SOCIAL, Balance.number("social.chat_social_gain"))
	agent.change_need(Need.RECREATION, 6.0)
	Personality.practise(agent, Personality.Skill.SOCIAL)
	sim.effects.interaction(agent.id, other.id, int(step.topic))
	# One fight spends a lash-out; the rest of the break is sulking.
	if int(step.topic) == Plans.Topic.INSULT and not agent.mental_break.is_empty():
		agent.mental_break.kind = Goals.BreakKind.SULK
	return Plans.DONE


static func _send(sim: RefCounted, agent: RefCounted, step: Dictionary) -> int:
	if _other(sim, int(step.to)) == null:
		return Fail.TARGET_GONE
	var fields: Dictionary = step.duplicate()
	fields.erase("op")
	fields.erase("to")
	fields.erase("kind")
	fields["place"] = agent.cell
	sim.effects.message(agent.id, int(step.to), str(step.kind), sim.calendar.tick, fields)
	return Plans.DONE


static func _give(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var other: RefCounted = _other(sim, int(step.to))
	if other == null:
		return Fail.TARGET_GONE
	var moving: Variant = _approach(sim, agent, other.cell, step_ticks)
	if moving != null:
		return moving
	if agent.carrying.is_empty():
		return Fail.STOCK_EMPTY
	sim.effects.action("gift", agent.id, {"to": other.id, "resource": agent.carrying.resource, "amount": float(agent.carrying.amount)})
	agent.carrying = {}
	sim.effects.message(agent.id, other.id, "delivered", sim.calendar.tick)
	return Plans.DONE


static func _wait_for_help(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	agent.activity = "waiting"
	if agent.carried("berries") >= 0.5 or agent.health.treated:
		return Plans.DONE
	if step_ticks >= int(step.ticks):
		Mind.add(agent, "refused_help", sim.calendar.ticks_per_day)
		return Fail.TIMED_OUT
	return Plans.RUNNING


static func _treat(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var other: RefCounted = _other(sim, int(step.to))
	if other == null:
		return Fail.TARGET_GONE
	if not other.needs_care(Balance.number("health.care_threshold")):
		return Plans.DONE
	var moving: Variant = _approach(sim, agent, other.cell, step_ticks)
	if moving != null:
		return moving
	agent.activity = "working"
	Personality.practise(agent, Personality.Skill.MEDICINE)
	var rate: float = maxf(Personality.speed(agent, Personality.Skill.MEDICINE), 0.3)
	var work: int = int(agent.step_result.get("work", 0)) + 1
	agent.step_result["work"] = work
	if work < int(TREAT_TICKS / rate):
		return Plans.RUNNING
	sim.effects.action("treat", agent.id, {"to": other.id})
	return Plans.DONE


static func run(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	match int(step.op):
		Op.TALK:
			return _talk(sim, agent, step, step_ticks)
		Op.SEND:
			return _send(sim, agent, step)
		Op.GIVE:
			return _give(sim, agent, step, step_ticks)
		Op.WAIT_FOR_HELP:
			return _wait_for_help(sim, agent, step, step_ticks)
		Op.TREAT:
			return _treat(sim, agent, step, step_ticks)
		Op.JOIN:
			sim.effects.action("join", agent.id, {"settlement": int(step.settlement)})
			return Plans.DONE
		Op.SETTLE:
			if step_ticks == 0:
				agent.activity = "settling"
				sim.effects.action("settle", agent.id, {"ground": int(step.ground), "branch": int(step.get("branch", 0))})
				return Plans.RUNNING
			if not agent.step_result.has("settled"):
				return Plans.RUNNING
			return Plans.DONE if int(agent.step_result.settled) > 0 else Fail.OCCUPIED
		Op.LEAVE:
			sim.effects.action("leave", agent.id)
			return Plans.DONE
	return Fail.INTERRUPTED
