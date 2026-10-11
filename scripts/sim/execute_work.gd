extends RefCounted
## Work steps that touch the shared world: taking from and adding to the
## stores, foraging, harvesting, carrying, and building block by block. They
## push actions into Effects and read the result back on a later tick.
const WorkPace = preload("res://scripts/sim/work_pace.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const ExecuteBuild = preload("res://scripts/sim/execute_build.gd")
const ExecuteFood = preload("res://scripts/sim/execute_food.gd")

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
	# Wild grass can be shaken for its seed instead of cut for thatch.
	var resource: String = str(step.get("as", sim.sites.resource_of(int(step.site))))
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
	# Work goes at the pace of the site's own yield (seed is shaken from grass).
	var base: float = float(Balance.dict("work.harvest_ticks_per_block")[sim.sites.resource_of(int(step.site))])
	var work: int = maxi(2, int(base / WorkPace.speed(sim, agent, skill)))
	Personality.practise(agent, skill)
	if step_ticks % (work + 1) == work:
		agent.step_result["pending"] = true
		sim.effects.action("harvest", agent.id, {"site": int(step.site), "as": str(step.get("as", ""))})
	return Plans.RUNNING


static func _pick_up(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	if step_ticks == 0:
		sim.effects.action("pick_up", agent.id, {"item": int(step.item)})
		return Plans.RUNNING
	if not agent.step_result.has("picked"):
		return Plans.RUNNING
	return Plans.DONE if int(agent.step_result.picked) > 0 else Fail.TARGET_GONE


## Set a berry into an empty planter, where it grows into a bush, or a tree
## seed into open ground, where it grows into a tree.
static func _plant(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	agent.activity = "gardening"
	var seed_resource: String = str(step.get("seed", "berries"))
	if agent.carried(seed_resource) < 1.0:
		return Fail.STOCK_EMPTY
	var work: int = int(Balance.dict("work.harvest_ticks_per_block").berries)
	if step_ticks < work:
		return Plans.RUNNING
	if step_ticks == work:
		sim.effects.action("plant", agent.id, {"cell": step.cell, "seed": seed_resource})
		return Plans.RUNNING
	if not agent.step_result.has("planted"):
		return Plans.RUNNING
	return Plans.DONE if int(agent.step_result.planted) > 0 else Fail.OCCUPIED


## Work a design out a sitting at a time; the hours count when it ends.
## Hunger or exhaustion breaks a sitting off, and what was done still counts.
static func _study(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	agent.activity = "studying"
	var tired: bool = agent.need(Personality.Need.FOOD) < Balance.number("needs.urgent_threshold") or agent.need(Personality.Need.REST) < 15.0
	if step_ticks < int(step.ticks) and not tired:
		Personality.practise(agent, Personality.Skill.CONSTRUCTION)
		return Plans.RUNNING
	sim.effects.action("study", agent.id, {"function": str(step.function), "sect": bool(step.sect),
		"hours": float(step_ticks) / float(sim.calendar.ticks_per_hour())})
	return Plans.DONE


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
		Op.PLANT:
			return _plant(sim, agent, step, step_ticks)
		Op.SOW, Op.REAP, Op.TEND_CROPS, Op.ADD_TO_POT, Op.COOK:
			return ExecuteFood.run(sim, agent, step, step_ticks)
		Op.STUDY:
			return _study(sim, agent, step, step_ticks)
		Op.SET_OUT:
			sim.effects.action("set_out", agent.id)
			return Plans.DONE
	return ExecuteBuild.run(sim, agent, step, step_ticks)
