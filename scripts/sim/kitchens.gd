extends RefCounted
## Kitchens: each keeps a pot that cooks fill with a recipe's inputs a load
## at a time, then cook into meals. A pot whose kitchen is gone spills what
## it held beside where the kitchen stood. The same works any station whose
## recipe is in `recipes.json` (M20): an alchemy room's furnace refines
## herbs into pills, a smithy's anvil forges ore and wood into tools.
const Data = preload("res://scripts/core/data.gd")

## The function whose structures this keeps pots for (a recipe's station).
var station: String = "kitchen"

## kitchen structure id -> {resource: int} in its pot
var pots: Dictionary = {}
## kitchen structure id -> Vector3i where its pot stands (its anchor)
var places: Dictionary = {}


func _init(station_id: String = "kitchen") -> void:
	station = station_id


## The recipe cooks follow.
static func recipe() -> Dictionary:
	return recipe_for("kitchen")


## The recipe worked at a station (one each).
static func recipe_for(station_id: String) -> Dictionary:
	for entry in Data.recipes():
		if str(entry.station) == station_id:
			return entry
	return {}


func own_recipe() -> Dictionary:
	return recipe_for(station)


func pot(id: int) -> Dictionary:
	return pots.get(id, {})


## What the pot still lacks for `batches` of the recipe: {resource: int}.
func lacking(id: int, batches: int) -> Dictionary:
	var result: Dictionary = {}
	var inputs: Dictionary = own_recipe().inputs
	var resources: Array = inputs.keys()
	resources.sort()
	for resource in resources:
		var short: int = int(inputs[resource]) * batches - int(pot(id).get(resource, 0))
		if short > 0:
			result[resource] = short
	return result


## How many whole batches the pot holds.
func batches_ready(id: int) -> int:
	var inputs: Dictionary = own_recipe().inputs
	var most: int = 1 << 30
	for resource in inputs:
		most = mini(most, int(pot(id).get(resource, 0)) / int(inputs[resource]))
	return most if not inputs.is_empty() else 0


## Puts up to what the recipe wants of `resource` for `batches` into the
## pot; returns how many went in.
func add(id: int, resource: String, amount: int, batches: int, at: Vector3i) -> int:
	var wanted: int = int(lacking(id, batches).get(resource, 0))
	var used: int = mini(wanted, amount)
	if used <= 0:
		return 0
	var held: Dictionary = pots.get(id, {})
	held[resource] = int(held.get(resource, 0)) + used
	pots[id] = held
	places[id] = at
	return used


## Cooks every whole batch in the pot; returns {resource: amount} made.
func cook(id: int) -> Dictionary:
	var batches: int = batches_ready(id)
	if batches <= 0:
		return {}
	var made: Dictionary = {}
	var definition: Dictionary = own_recipe()
	for resource in definition.inputs:
		pots[id][resource] = int(pots[id][resource]) - int(definition.inputs[resource]) * batches
		if int(pots[id][resource]) <= 0:
			pots[id].erase(resource)
	for resource in definition.outputs:
		made[resource] = int(definition.outputs[resource]) * batches
	return made


## A pot whose kitchen is no longer a kitchen spills where it stood.
func daily(sim: RefCounted) -> void:
	var ids: Array = pots.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = sim.structures.entries.get(id, {})
		if not entry.is_empty() and entry.functions.has(station):
			continue
		var spill: Vector3i = sim.nav.nearest_walkable(places[id], 2)
		var resources: Array = pots[id].keys()
		resources.sort()
		for resource in resources:
			sim.drop_item(spill if spill.x >= 0 else places[id], resource, float(pots[id][resource]))
		pots.erase(id)
		places.erase(id)


func to_dict() -> Dictionary:
	return {"pots": pots.duplicate(true), "places": places.duplicate()}


func from_dict(data: Dictionary) -> void:
	pots = data.pots
	places = data.places
