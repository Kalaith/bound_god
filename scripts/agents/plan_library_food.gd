extends RefCounted
## Food plans: farming a field (reap what is ripe, weed what is untended, sow
## what is open) and cooking at a kitchen. Each reads the person's beliefs
## and the visible job board.
const Crafts = preload("res://scripts/sim/crafts.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const PlansWork = preload("res://scripts/agents/plan_library_work.gd")
const Crops = preload("res://scripts/sim/crops.gd")
const Kitchens = preload("res://scripts/sim/kitchens.gd")
const Food = preload("res://scripts/sim/food.gd")
const Standing = preload("res://scripts/sim/standing.gd")

const Kind = Goals.Kind
const Op = Plans.Op
const T = Plans.T


static func plans(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> Array:
	match int(goal.kind):
		Kind.FARM:
			return _farm(sim, agent, int(goal.target))
		Kind.COOK:
			return _cook(sim, agent, int(goal.target))
		Kind.SMITH:
			return _craft(sim, agent, int(goal.target), "smithy", clampi(Crafts.tools_short(sim, agent.settlement_id), 1, 3), "forge_tools")
	return []


static func _store(agent: RefCounted) -> Dictionary:
	return Plans.go_to(Plans.target(T.STORE, agent.settlement_id))


static func _field_work(sim: RefCounted, agent: RefCounted, field_id: int) -> Dictionary:
	for field in sim.settlement_life.board(agent.settlement_id).get("fields", []):
		if int(field.id) == field_id:
			return field
	return {}


## Walk to within reach of each cell in turn and do `op` there.
static func _rounds(sim: RefCounted, agent: RefCounted, cells: Array, op: int) -> Array:
	var steps: Array = []
	var from: Vector3i = agent.cell
	for cell in cells:
		var stand: Vector3i = PlansWork.plot_stand(sim, cell, from)
		if stand.x < 0:
			continue
		steps.append_array([Plans.go_cell(stand), Plans.step(op, {"cell": cell})])
		from = stand
	return steps


static func _farm(sim: RefCounted, agent: RefCounted, field_id: int) -> Array:
	var field: Dictionary = _field_work(sim, agent, field_id)
	if field.is_empty():
		return []
	var result: Array = []
	var crop: Dictionary = Crops.staple()
	# An armful of sheaves: about as much grain as one has room to carry.
	var room: float = Balance.number("agents.carry_capacity") - agent.carried(crop.harvest)
	var per_trip: int = maxi(1, ceili(room / float(crop.yield)))
	var reap: Array = _rounds(sim, agent, field.ripe.slice(0, per_trip), Op.REAP)
	if not reap.is_empty():
		result.append(H.option("reap_the_field", 1.3, H.free_hands(agent, crop.harvest) + reap + [_store(agent), Plans.step(Op.DEPOSIT)]))
	# Weeding: one stop tends every crop within reach, so stop at every other cell.
	var stops: Array = []
	for i in range(0, field.tend.size(), 2):
		stops.append(field.tend[i])
	var tend: Array = _rounds(sim, agent, stops, Op.TEND_CROPS)
	if not tend.is_empty():
		result.append(H.option("weed_the_field", 1.0, tend))
	_sow(sim, agent, field.sow, crop, result)
	return result


## Sow open plots with seed carried, fetched from the stores, picked up loose
## at home, or shaken from wild grass on the way.
static func _sow(sim: RefCounted, agent: RefCounted, open: Array, crop: Dictionary, result: Array) -> void:
	if open.is_empty():
		return
	var seed: String = crop.seed
	var carried: int = int(agent.carried(seed))
	if carried >= 1:
		var by_hand: Array = _rounds(sim, agent, open.slice(0, carried), Op.SOW)
		if not by_hand.is_empty():
			result.append(H.option("sow_carried", 1.15, by_hand))
	var steps: Array = _rounds(sim, agent, open, Op.SOW)
	if steps.is_empty():
		return
	if agent.beliefs.believes_stock(seed):
		result.append(H.option("fetch_seed_to_sow", 1.05, H.free_hands(agent, seed) + [_store(agent),
			Plans.step(Op.TAKE_STOCK, {"resource": seed, "amount": open.size()})] + steps))
	var loose: int = H.loose_item(sim, agent, seed)
	if loose >= 0:
		result.append(H.option("fetch_loose_seed", 0.95, H.free_hands(agent, seed) + [Plans.go_cell(sim.items[loose].cell),
			Plans.step(Op.PICK_UP, {"item": loose})] + steps))
	var grass: Array = H.known_sites(sim, agent, "grass")
	if not grass.is_empty():
		result.append(H.option("gather_wild_seed", 0.75, H.free_hands(agent, seed) + [Plans.go_to(Plans.target(T.SITE, grass[0])),
			Plans.step(Op.HARVEST, {"site": grass[0], "as": seed})] + steps))



## Fill the pot a load at a time (from the hands or the stores), cook the
## batches, and put the meals in the stores.
static func _cook(sim: RefCounted, agent: RefCounted, kitchen: int) -> Array:
	var recipe: Dictionary = Kitchens.recipe()
	var made: int = int(recipe.outputs.values()[0])
	var short: int = Food.meals_wanted(Standing.present(sim, agent.settlement_id)) - sim.settlements.amount(agent.settlement_id, "meal")
	var batches: int = clampi(ceili(float(short) / made), 1, Balance.integer("food.batch_most"))
	return _craft(sim, agent, kitchen, "kitchen", batches, "cook_a_meal")


## Fill a station's pot (a kitchen's, a furnace, an anvil) a load at a time
## from the hands or the stores, work the batches, and store what is made.
static func _craft(sim: RefCounted, agent: RefCounted, kitchen: int, station: String, batches: int, option: String) -> Array:
	var entry: Dictionary = sim.structures.entries.get(kitchen, {})
	if entry.is_empty() or not entry.functions.has(station):
		return []
	var go := Plans.go_to(Plans.target(T.STRUCTURE, kitchen))
	var put_away: Array = [_store(agent), Plans.step(Op.DEPOSIT)]
	var add := Plans.step(Op.ADD_TO_POT, {"kitchen": kitchen, "batches": batches, "station": station})
	var steps: Array = []
	var lacking: Dictionary = sim.station(station).lacking(kitchen, batches)
	var resources: Array = lacking.keys()
	resources.sort()
	# What will be in hand as the plan goes: what is carried, until it is
	# used up in the pot or put away in the stores.
	var hands: String = str(agent.carrying.get("resource", ""))
	if not hands.is_empty() and not lacking.has(hands):
		steps.append_array(H.free_hands(agent))
		hands = ""
	for resource in resources:
		if resource == hands and agent.carried(resource) >= 1.0:
			steps.append_array([go, add])
			hands = resource if agent.carried(resource) > int(lacking[resource]) else ""
		elif agent.beliefs.believes_stock(resource):
			if not hands.is_empty():
				steps.append_array(put_away)
				hands = ""
			steps.append_array([_store(agent), Plans.step(Op.TAKE_STOCK, {"resource": resource, "amount": int(lacking[resource])}), go, add])
		else:
			return []
	if not hands.is_empty():
		steps.append_array(put_away)
	steps.append_array([go, Plans.step(Op.COOK, {"kitchen": kitchen, "station": station})] + put_away)
	return [H.option(option, 1.0, steps)]
