extends RefCounted
## Food work candidates: farming a field the job board shows work in, and the
## food buildings a settlement lacks. Like all work, its pull comes from the
## settlement's culture weight, the person's aptitude and how much there is
## to do, never from an assignment.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const Food = preload("res://scripts/sim/food.gd")
const Kitchens = preload("res://scripts/sim/kitchens.gd")

const Kind = Goals.Kind
const Skill = Personality.Skill


## Whether a person can lay hands on seed: carried, believed stored, lying
## loose at home, or shaken from wild grass they know.
static func has_seed_means(sim: RefCounted, agent: RefCounted) -> bool:
	return agent.carried("seed") >= 1.0 or agent.beliefs.believes_stock("seed") or H.loose_item(sim, agent, "seed") >= 0 \
		or agent.beliefs.has_site("grass")


## `push` is deliberation_work's (goal, factor, reason) adder; `hungry` is
## its food pull while the chests hold under a day of food.
static func add(sim: RefCounted, agent: RefCounted, board: Dictionary, culture: Dictionary, aptitude: float, cook_aptitude: float, hungry: float, push: Callable) -> void:
	_cook(sim, agent, board, culture, cook_aptitude, push)
	var seed: bool = has_seed_means(sim, agent)
	for field in board.get("fields", []):
		var sow: int = field.sow.size() if seed else 0
		if field.ripe.is_empty() and field.tend.is_empty() and sow == 0:
			continue
		var pull: float = Balance.number("farming.field_pull") + field.ripe.size() * Balance.number("farming.ripe_pull") \
			+ sow * Balance.number("farming.sow_pull") + field.tend.size() * Balance.number("farming.tend_pull")
		push.call(Goals.make(Kind.FARM, int(field.id)), float(culture.farm) * aptitude * minf(pull, Balance.number("farming.pull_most")) * hungry, "reason_farm")
		return


## Food buildings a settlement lacks, as [function, reason, weight] for
## deliberation_work's proposals: fields while the stores hold less than a
## winter's food, a granary once there is grain to keep (in autumn, with too
## little put by, both weigh more), and a kitchen to cook the grain.
static func wants(sim: RefCounted, id: int, people: int, have: Dictionary) -> Array:
	var result: Array = []
	var fear: bool = Standing.fear_of_winter(sim, id)
	var fields_wanted: int = ceili(float(people) / Balance.number("farming.people_per_field"))
	if Standing.food_days(sim, id) < Balance.number("farming.winter_food_days") and int(have.get("field", 0)) < fields_wanted:
		result.append(["field", "reason_fear_of_winter" if fear else "reason_food_low", 0.95 if fear else 0.75])
	var grain: int = sim.settlements.amount(id, "grain")
	if int(have.get("granary", 0)) == 0 and (grain >= Balance.integer("farming.granary_grain") or (fear and int(have.get("field", 0)) > 0)):
		result.append(["granary", "reason_fear_of_winter" if fear else "reason_grain_to_keep", 0.9 if fear else 0.7])
	if int(have.get("kitchen", 0)) == 0 and grain >= Balance.integer("food.kitchen_grain"):
		result.append(["kitchen", "reason_no_kitchen", 0.65])
	return result



## Cook when the stores are short of meals and the pot, the person's hands
## or the stores they believe in hold what the recipe needs.
static func _cook(sim: RefCounted, agent: RefCounted, board: Dictionary, culture: Dictionary, aptitude: float, push: Callable) -> void:
	var kitchens: Array = board.get("kitchens", [])
	if kitchens.is_empty():
		return
	var wanted: int = Food.meals_wanted(Standing.present(sim, agent.settlement_id))
	var short: int = wanted - sim.settlements.amount(agent.settlement_id, "meal")
	if short <= 0:
		return
	var kitchen: int = int(kitchens[0])
	for resource in sim.kitchens.lacking(kitchen, 1):
		if agent.carried(resource) < 1.0 and not agent.beliefs.believes_stock(resource):
			return
	var pull: float = Balance.number("food.cook_pull") + Balance.number("food.cook_short_pull") * float(short) / maxf(wanted, 1.0)
	push.call(Goals.make(Kind.COOK, kitchen), float(culture.farm) * aptitude * pull, "reason_cook")
