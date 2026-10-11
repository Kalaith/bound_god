extends RefCounted
## Food steps that touch the shared world: sowing, weeding and reaping a
## field, filling a kitchen's pot and cooking. They push actions into Effects
## and read the result back on a later tick.
const WorkPace = preload("res://scripts/sim/work_pace.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Crops = preload("res://scripts/sim/crops.gd")
const Kitchens = preload("res://scripts/sim/kitchens.gd")
const Alchemy = preload("res://scripts/sim/alchemy.gd")
const Data = preload("res://scripts/core/data.gd")

const Op = Plans.Op
const Fail = Plans.Fail
const Skill = Personality.Skill


## Work for a while at `skill`, then push `action` once and wait for the
## result under `key`: done when it reports something done, else `fail`.
static func work_then(sim: RefCounted, agent: RefCounted, step_ticks: int, ticks: float, skill: int, action: String, args: Dictionary, key: String, fail: int) -> int:
	var work: int = maxi(2, int(ticks / WorkPace.speed(sim, agent, skill)))
	if step_ticks < work:
		Personality.practise(agent, skill)
		return Plans.RUNNING
	if step_ticks == work:
		sim.effects.action(action, agent.id, args)
		return Plans.RUNNING
	if not agent.step_result.has(key):
		return Plans.RUNNING
	return Plans.DONE if int(agent.step_result[key]) > 0 else fail


static func _sow(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	agent.activity = "sowing"
	if agent.carried(Crops.staple().seed) < 1.0:
		return Fail.STOCK_EMPTY
	return work_then(sim, agent, step_ticks, Balance.number("farming.sow_ticks"), Skill.GATHERING, "sow", {"cell": step.cell}, "sown", Fail.OCCUPIED)


static func _reap(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	agent.activity = "reaping"
	return work_then(sim, agent, step_ticks, Balance.number("farming.reap_ticks"), Skill.GATHERING, "reap", {"cell": step.cell}, "reaped", Fail.TARGET_GONE)


## Weeding tends every crop within reach; finding none weedy is no failure.
static func _tend(sim: RefCounted, agent: RefCounted, step_ticks: int) -> int:
	agent.activity = "tending"
	return work_then(sim, agent, step_ticks, Balance.number("farming.tend_ticks"), Skill.GATHERING, "tend_crops", {}, "tended", Plans.DONE)


## What working each station looks like.
const ACTIVITY: Dictionary = {"kitchen": "cooking", "alchemy": "refining", "smithy": "forging"}


## Put a carried ingredient into the kitchen's pot.
static func _add_to_pot(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	agent.activity = ACTIVITY.get(str(step.get("station", "kitchen")), "cooking")
	if step_ticks == 0:
		if agent.carrying.is_empty():
			return Fail.STOCK_EMPTY
		sim.effects.action("add_to_pot", agent.id, {"kitchen": int(step.kitchen), "batches": int(step.batches), "station": str(step.get("station", "kitchen")),
			"recipe": str(step.get("recipe", "")), "seat": int(step.get("seat", 0))})
		return Plans.RUNNING
	if not agent.step_result.has("added"):
		return Plans.RUNNING
	return Plans.DONE if int(agent.step_result.added) > 0 else Fail.REFUSED


## Cook what the pot holds into meals, a while per batch.
static func _cook(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var station: String = str(step.get("station", "kitchen"))
	agent.activity = ACTIVITY.get(station, "cooking")
	var kitchen: int = int(step.kitchen)
	# At an alchemy building each crafter works a bench (a seat) of it.
	var alchemy: bool = station == Alchemy.STATION
	var batches: int = sim.alchemy.batches_ready(kitchen, int(step.get("seat", 0))) if alchemy else sim.station(station).batches_ready(kitchen)
	if batches <= 0 and not agent.step_result.has("cooked"):
		return Fail.STOCK_EMPTY
	var recipe: Dictionary = Data.recipe(str(step.recipe)) if alchemy else Kitchens.recipe_for(station)
	var skill: int = Personality.SKILLS.find(recipe.skill)
	return work_then(sim, agent, step_ticks, float(recipe.ticks) * maxi(batches, 1), skill, "cook", {"kitchen": kitchen, "station": station, "seat": int(step.get("seat", 0))}, "cooked", Fail.STOCK_EMPTY)


static func run(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	match int(step.op):
		Op.SOW:
			return _sow(sim, agent, step, step_ticks)
		Op.REAP:
			return _reap(sim, agent, step, step_ticks)
		Op.TEND_CROPS:
			return _tend(sim, agent, step_ticks)
		Op.ADD_TO_POT:
			return _add_to_pot(sim, agent, step, step_ticks)
		Op.COOK:
			return _cook(sim, agent, step, step_ticks)
	return Fail.INTERRUPTED
