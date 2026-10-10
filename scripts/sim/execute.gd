extends RefCounted
## Runs one tick of the current plan step, and recovers when a step fails:
## failure corrects beliefs so the next plan does not repeat the mistake.
const Balance = preload("res://scripts/core/balance.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Cognition = preload("res://scripts/sim/cognition.gd")
const ExecuteLife = preload("res://scripts/sim/execute_life.gd")
const ExecuteWork = preload("res://scripts/sim/execute_work.gd")
const ExecuteSocial = preload("res://scripts/sim/execute_social.gd")
const ExecuteFaith = preload("res://scripts/sim/execute_faith.gd")
const ExecuteCultivation = preload("res://scripts/sim/execute_cultivation.gd")

const Op = Plans.Op
const T = Plans.T
const Fail = Plans.Fail
const NONE := Vector3i(-1, -1, -1)
const WORK_OPS: Array[int] = [Op.TAKE_STOCK, Op.DEPOSIT, Op.DELIVER, Op.PLACE_BLOCK, Op.MARK_SITE, Op.HARVEST,
	Op.FORAGE, Op.PICK_UP, Op.REPAIR_BLOCK, Op.PLANT, Op.SOW, Op.REAP, Op.TEND_CROPS, Op.ADD_TO_POT, Op.COOK]
const SOCIAL_OPS: Array[int] = [Op.TALK, Op.SEND, Op.GIVE, Op.WAIT_FOR_HELP, Op.JOIN, Op.LEAVE, Op.TREAT, Op.SETTLE]
const FAITH_OPS: Array[int] = [Op.PRAY, Op.TEND]
const CULTIVATION_OPS: Array[int] = [Op.CULTIVATE, Op.TEACH, Op.WAIT_TO_LEARN, Op.PROCLAIM]


## Where a movement target currently is, as a cell to stand on.
static func resolve_target(sim: RefCounted, agent: RefCounted, where: Dictionary) -> Vector3i:
	match int(where.type):
		T.CELL:
			return sim.nav.nearest_walkable(where.cell, 2)
		T.STRUCTURE:
			return sim.structure_access(int(where.id), agent.cell)
		T.SITE:
			return sim.site_access(int(where.id))
		T.AGENT:
			var id: int = int(where.id)
			if id < 0 or id >= sim.agents.size() or not sim.agents[id].is_present():
				return NONE
			var other: RefCounted = sim.agents[id]
			return sim.structure_access(other.inside, agent.cell) if other.inside >= 0 else other.cell
		T.STORE:
			var purpose: Array = _store_purpose(agent)
			# Keep walking to the chest already chosen while it still serves;
			# picking afresh each step changed the goal and re-ran the route.
			if not agent.path.is_empty() and sim.settlements.store_serves(sim, int(where.id), agent.path.back(), purpose[0], purpose[1]):
				return agent.path.back()
			return sim.settlements.store_access(sim, int(where.id), agent.cell, purpose[0], purpose[1], agent)
		T.SHRINE:
			return sim.faith.shrine_access(sim, int(where.id), agent.cell) if sim.faith != null else NONE
		T.CONSTRUCTION:
			return sim.construction_access(int(where.id), agent.cell)
	return NONE


## What the walk to the stores is for, read from the next step of the plan:
## [resource to take, or "", whether it is to store a load].
static func _store_purpose(agent: RefCounted) -> Array:
	var plan: Dictionary = agent.intention.get("plan", {}) if not agent.intention.is_empty() else {}
	var next: int = int(plan.get("cursor", 0)) + 1
	# A load is stored where there is room for that load (a bin takes only grain).
	var load: String = str(agent.carrying.get("resource", ""))
	if plan.is_empty() or next >= plan.steps.size():
		return [load, not agent.carrying.is_empty()]
	var step: Dictionary = plan.steps[next]
	if int(step.op) == Op.TAKE_STOCK:
		return [str(step.resource), false]
	return [load, int(step.op) == Op.DEPOSIT or not agent.carrying.is_empty()]


static func _near(a: Vector3i, b: Vector3i) -> bool:
	return absi(a.x - b.x) <= 1 and absi(a.z - b.z) <= 1 and absi(a.y - b.y) <= 1


static func go_to(sim: RefCounted, agent: RefCounted, where: Dictionary, step_ticks: int) -> int:
	var destination: Vector3i = resolve_target(sim, agent, where)
	if destination.x < 0:
		return Fail.TARGET_GONE
	var arrived: bool = _near(agent.cell, destination) if int(where.type) == T.AGENT else agent.cell == destination
	if arrived:
		agent.path.clear()
		return Plans.DONE
	if step_ticks > Balance.integer("agents.move_timeout_ticks"):
		return Fail.TIMED_OUT
	var needs_path: bool = agent.path.is_empty() or agent.path.back() != destination
	if int(where.type) == T.AGENT and step_ticks % 8 == 0:
		needs_path = true
	if needs_path:
		if not sim.nav.can_path():
			# Too many people asked for a route this tick; ask again next tick.
			return Plans.RUNNING
		var route: Array[Vector3i] = sim.nav.find_path(agent.cell, destination)
		if route.is_empty() and Movement.scramble(sim, agent, destination):
			return Plans.RUNNING
		if route.is_empty():
			return Fail.NO_PATH
		agent.path = route
	agent.inside = -1
	if agent.activity != "fleeing":
		agent.activity = "hauling" if not agent.carrying.is_empty() else "walking"
	return Plans.RUNNING


static func _dispatch(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var op: int = int(step.op)
	if op == Op.GO_TO:
		return go_to(sim, agent, step.target, step_ticks)
	if op in WORK_OPS:
		return ExecuteWork.run(sim, agent, step, step_ticks)
	if op in SOCIAL_OPS:
		return ExecuteSocial.run(sim, agent, step, step_ticks)
	if op in FAITH_OPS:
		return ExecuteFaith.run(sim, agent, step, step_ticks)
	if op in CULTIVATION_OPS:
		return ExecuteCultivation.run(sim, agent, step, step_ticks)
	return ExecuteLife.run(sim, agent, step, step_ticks)


static func _learn(sim: RefCounted, agent: RefCounted, step: Dictionary, reason: int) -> void:
	var now: int = sim.calendar.tick
	var op: int = int(step.op)
	var site: int = -1
	if op in [Op.HARVEST, Op.FORAGE]:
		site = int(step.site)
	elif op == Op.GO_TO and int(step.target.type) == T.SITE:
		site = int(step.target.id)
	if site >= 0:
		agent.beliefs.forget_site(site)
		agent.beliefs.note_failure("site:%d" % site, now)
		return
	if op == Op.TAKE_STOCK and reason == Fail.STOCK_EMPTY or op == Op.GO_TO and int(step.target.type) == T.STORE:
		agent.beliefs.stock = sim.settlements.stock_of(agent.settlement_id).duplicate()
		if op == Op.GO_TO and reason == Fail.NO_PATH:
			var stand: Vector3i = resolve_target(sim, agent, step.target)
			if stand.x >= 0:
				agent.beliefs.note_failure("cell:%s" % str(stand), now)
	elif op == Op.GO_TO and int(step.target.type) == T.STRUCTURE:
		agent.beliefs.note_failure("structure:%d" % int(step.target.id), now)
	elif op == Op.SLEEP and int(step.get("structure", -1)) >= 0:
		agent.beliefs.note_failure("structure:%d" % int(step.structure), now)
	elif op == Op.GO_TO and int(step.target.type) == T.CELL:
		agent.beliefs.note_failure("cell:%s" % str(step.target.cell), now)


static func _fail(sim: RefCounted, agent: RefCounted, step: Dictionary, reason: int) -> void:
	_learn(sim, agent, step, reason)
	agent.path.clear()
	if agent.intention.is_empty():
		return
	var plan_id: String = agent.intention.plan.get("id", "")
	agent.intention.plan = {}
	agent.intention.tried.append(plan_id)
	agent.record(sim.calendar.tick, "failed", {"plan": plan_id, "reason": reason})
	agent.activity = "idle"
	agent.step_result = {}


static func _achieve(sim: RefCounted, agent: RefCounted) -> void:
	var intention: Dictionary = agent.intention
	agent.intention = {}
	sim.goal_version += 1
	if not intention.tried.is_empty():
		agent.stats.plans_recovered += 1
	if int(intention.goal.kind) in [Goals.Kind.HELP, Goals.Kind.TEACH]:
		agent.help_task = {}
		agent.stats.helped_others += 1
	agent.record(sim.calendar.tick, "achieved", {"goal": intention.goal})
	agent.next_deliberation = sim.calendar.tick
	agent.step_result = {}


static func run_step(sim: RefCounted, agent: RefCounted) -> void:
	if agent.intention.is_empty():
		agent.activity = "idle"
		return
	var plan: Dictionary = agent.intention.plan
	if plan.is_empty():
		return
	var step: Dictionary = Plans.current(plan)
	if step.is_empty():
		_achieve(sim, agent)
		return
	var outcome: int = _dispatch(sim, agent, step, int(plan.step_ticks))
	if outcome == Plans.RUNNING:
		plan.step_ticks += 1
	elif outcome == Plans.DONE:
		plan.cursor += 1
		plan.step_ticks = 0
		agent.step_result = {}
		if plan.cursor >= plan.steps.size():
			_achieve(sim, agent)
	else:
		_fail(sim, agent, step, outcome)
		if agent.intention.tried.size() >= Balance.integer("agents.max_plan_attempts"):
			Cognition.give_up(sim, agent, agent.intention.goal)
