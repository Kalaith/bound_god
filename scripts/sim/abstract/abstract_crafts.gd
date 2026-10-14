extends RefCounted
## Crafts while the valley passes abstractly (M20): alchemy is
## `abstract_alchemy.gd`'s (M20b); where a smithy stands, ore and wood are
## forged into tools while hands lack them. Tools in the stores quicken the
## settlement's labour and wear out with it.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Crafts = preload("res://scripts/sim/crafts.gd")
const Kitchens = preload("res://scripts/sim/kitchens.gd")
const AbstractPeople = preload("res://scripts/sim/abstract/abstract_people.gd")
const AbstractAlchemy = preload("res://scripts/sim/abstract/abstract_alchemy.gd")

## Most batches a station works in a day.
const BATCHES_PER_DAY: int = 2
## Hours of work a day a set of tools sees.
const WORK_HOURS: float = 9.0


static func day(sim: RefCounted, id: int, record: Dictionary) -> void:
	AbstractAlchemy.day(sim, id)
	if not Crafts.stations(sim, id, "smithy").is_empty():
		_work(sim, id, Kitchens.recipe_for("smithy"), Crafts.tools_short(sim, id))
	_wear(sim, id, record)


## Up to `wanted` batches, as the stores' inputs allow.
static func _work(sim: RefCounted, id: int, recipe: Dictionary, wanted: int) -> void:
	for batch in range(mini(wanted, BATCHES_PER_DAY)):
		for resource in recipe.inputs:
			if sim.settlements.amount(id, resource) < int(recipe.inputs[resource]):
				return
		for resource in recipe.inputs:
			AbstractPeople.take(sim, id, resource, int(recipe.inputs[resource]))
		for resource in recipe.outputs:
			AbstractPeople.store(sim, id, resource, int(recipe.outputs[resource]))


## The settlement's tools wear a day's work at a time.
static func _wear(sim: RefCounted, id: int, record: Dictionary) -> void:
	var sets: int = sim.settlements.amount(id, "tools")
	if sets <= 0:
		return
	record["tool_wear"] = float(record.get("tool_wear", 0.0)) + float(sets) * WORK_HOURS / Balance.number("tools.wear_hours")
	var worn: int = int(floor(float(record.tool_wear)))
	if worn > 0:
		record.tool_wear = float(record.tool_wear) - worn
		AbstractPeople.take(sim, id, "tools", worn)


## How much faster the settlement's labour goes for the tools it holds.
static func pace(sim: RefCounted, id: int, people: int) -> float:
	var sets: int = sim.settlements.amount(id, "tools")
	if sets <= 0 or people <= 0:
		return 1.0
	var share: float = minf(float(sets) * Balance.number("tools.people_per_set") / float(people), 1.0)
	return 1.0 + (Balance.number("tools.speed") - 1.0) * share
