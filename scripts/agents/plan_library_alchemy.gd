extends RefCounted
## Alchemy plans (M20b): refine at a bench (a seat) of an alchemy
## building (fill it a load at a time from the hands or the stores, work the
## batch, put what is made in the stores), and take a preparation one needs
## from the stores. The stores are believed, not seen.
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const DeliberationCrafts = preload("res://scripts/agents/deliberation_crafts.gd")
const Elixirs = preload("res://scripts/sim/elixirs.gd")
const Alchemy = preload("res://scripts/sim/alchemy.gd")

const Kind = Goals.Kind
const Op = Plans.Op
const T = Plans.T


static func plans(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> Array:
	match int(goal.kind):
		Kind.REFINE:
			return _refine(sim, agent, int(goal.target), int(goal.extra))
		Kind.MEDICATE:
			var id: String = Elixirs.id_at(int(goal.target))
			if id.is_empty() or not Elixirs.would_take(sim, agent, id):
				return []
			return [H.option("take_%s" % id, 1.0, take(agent, id))]
	return []


static func _store(agent: RefCounted) -> Dictionary:
	return Plans.go_to(Plans.target(T.STORE, agent.settlement_id))


## Steps to take one preparation from the stores for oneself.
static func take(agent: RefCounted, id: String) -> Array:
	return [_store(agent), Plans.step(Op.TAKE_STOCK, {"resource": id, "amount": 1})]


static func _refine(sim: RefCounted, agent: RefCounted, room: int, seat: int) -> Array:
	var entry: Dictionary = sim.structures.entries.get(room, {})
	if entry.is_empty() or Alchemy.tier_of(entry) <= 0:
		return []
	var choice: Dictionary = DeliberationCrafts.choose(sim, agent, room, seat)
	if choice.is_empty():
		return []
	var recipe: String = choice.recipe
	var go := Plans.go_to(Plans.target(T.STRUCTURE, room))
	var put_away: Array = [_store(agent), Plans.step(Op.DEPOSIT)]
	var add := Plans.step(Op.ADD_TO_POT, {"kitchen": room, "seat": seat, "batches": 1, "station": Alchemy.STATION, "recipe": recipe})
	var lacking: Dictionary = sim.alchemy.lacking(room, seat, recipe, 1)
	var resources: Array = lacking.keys()
	resources.sort()
	var steps: Array = []
	# What will be in hand as the plan goes: what is carried, until it is
	# used up on the bench or put away in the stores.
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
	steps.append_array([go, Plans.step(Op.COOK, {"kitchen": room, "seat": seat, "station": Alchemy.STATION, "recipe": recipe})] + put_away)
	return [H.option("refine_%s" % recipe, 1.0, steps)]
