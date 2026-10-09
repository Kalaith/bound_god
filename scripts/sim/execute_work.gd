extends RefCounted
## Work steps that touch the shared world: taking from and adding to the
## stores, foraging, harvesting, carrying, and building block by block. They
## push actions into Effects and read the result back on a later tick.
const Balance = preload("res://scripts/core/balance.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const ExecuteBuild = preload("res://scripts/sim/execute_build.gd")

const Op = Plans.Op
const Fail = Plans.Fail
const Need = Personality.Need
const Skill = Personality.Skill


static func _take_stock(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	if step_ticks == 0:
		sim.effects.action("take_stock", agent.id, {"settlement": agent.settlement_id, "resource": step.resource, "amount": int(step.amount)})
		agent.activity = "working"
		return Plans.RUNNING
	if not agent.step_result.has("took"):
		return Plans.RUNNING
	return Plans.DONE if int(agent.step_result.took) > 0 else Fail.STOCK_EMPTY


static func _deposit(sim: RefCounted, agent: RefCounted, step_ticks: int) -> int:
	if agent.carrying.is_empty():
		return Plans.DONE
	if step_ticks == 0:
		sim.effects.action("deposit", agent.id, {"settlement": agent.settlement_id})
		agent.activity = "working"
		return Plans.RUNNING
	if not agent.step_result.has("stored"):
		return Plans.RUNNING
	return Plans.DONE if int(agent.step_result.stored) > 0 else Fail.OCCUPIED


## Eat straight from a bush, a berry at a time, until full or the bush is bare.
static func _forage(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var site: Dictionary = sim.sites.get_site(int(step.site))
	if site.is_empty():
		return Fail.DEPLETED
	agent.activity = "eating"
	var work: int = int(Balance.dict("work.harvest_ticks_per_block").berries)
	if agent.step_result.has("ate"):
		var ate: int = int(agent.step_result.ate)
		var count: int = int(agent.step_result.get("count", 0)) + ate
		if ate == 0:
			return Plans.DONE if count > 0 else Fail.DEPLETED
		if agent.need(Need.FOOD) >= 90.0:
			return Plans.DONE
		agent.step_result = {"count": count}
	if agent.step_result.get("pending", false):
		return Plans.RUNNING
	if step_ticks % (work + 1) == work:
		agent.step_result["pending"] = true
		sim.effects.action("forage", agent.id, {"site": int(step.site), "cell": site.cells[0]})
	return Plans.RUNNING


## Gather from a site: work for a while, then take one block's yield.
static func _harvest(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var site: Dictionary = sim.sites.get_site(int(step.site))
	if site.is_empty():
		return Fail.DEPLETED
	var resource: String = sim.sites.resource_of(int(step.site))
	agent.activity = "working"
	if agent.step_result.has("got"):
		var got: int = int(agent.step_result.got)
		if got == 0:
			return Plans.DONE if agent.carried(resource) > 0.0 else Fail.DEPLETED
		var full: bool = agent.carried(resource) >= Balance.number("agents.carry_capacity") * 0.75
		if full or int(step.get("once", 0)) == 1:
			return Plans.DONE
		agent.step_result = {}
	if agent.step_result.get("pending", false):
		return Plans.RUNNING
	var skill: int = Skill.GATHERING
	var base: float = float(Balance.dict("work.harvest_ticks_per_block")[resource])
	var work: int = maxi(2, int(base / Personality.speed(agent, skill)))
	Personality.practise(agent, skill)
	if step_ticks % (work + 1) == work:
		agent.step_result["pending"] = true
		sim.effects.action("harvest", agent.id, {"site": int(step.site)})
	return Plans.RUNNING


static func _pick_up(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	if step_ticks == 0:
		sim.effects.action("pick_up", agent.id, {"item": int(step.item)})
		return Plans.RUNNING
	if not agent.step_result.has("picked"):
		return Plans.RUNNING
	return Plans.DONE if int(agent.step_result.picked) > 0 else Fail.TARGET_GONE


static func run(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	match int(step.op):
		Op.TAKE_STOCK:
			return _take_stock(sim, agent, step, step_ticks)
		Op.DEPOSIT:
			return _deposit(sim, agent, step_ticks)
		Op.FORAGE:
			return _forage(sim, agent, step, step_ticks)
		Op.HARVEST:
			return _harvest(sim, agent, step, step_ticks)
		Op.PICK_UP:
			return _pick_up(sim, agent, step, step_ticks)
	return ExecuteBuild.run(sim, agent, step, step_ticks)
