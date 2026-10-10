extends RefCounted
## Settlements: who lives where, the shared stock and where it is kept, and
## each settlement's culture weights. Stock is only what lies in the storage
## chests and granary bins standing in a settlement's area, each holding its
## own goods (a bin holds grain only). Food that spoils is kept in dated lots.
## The camp is where people meet and where goods are set down loose while
## there is no chest with room; loose goods are never counted as stock.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

const NONE := Vector3i(-1, -1, -1)
## How far from a chest someone can reach into it.
const REACH: float = 1.8
## Components that hold goods.
const CONTAINERS: Array[String] = ["chest", "granary_bin"]

## id -> {id, name, center, radius, residents, culture, known_templates,
##        site_ids, shrine_ids, camp, founded_tick}
var entries: Dictionary = {}
var next_id: int = 1
## Designs settlements have devised themselves (sim/vernacular.gd):
## template id -> Template dictionary.
var designs: Dictionary = {}
var next_design: int = 1
## container cell -> {resource: int}, for every chest and granary bin in the world.
var chests: Dictionary = {}
## container cell -> true for the granary bins among them.
var bins: Dictionary = {}
## container cell -> {resource: Array of [day stored, count]}, oldest first,
## for the goods that spoil; the counts add up to the container's.
var lots: Dictionary = {}
## The day lots are dated with; kept by the calendar's daily turn.
var today: int = 1
## Bumped whenever a chest appears, vanishes or its contents change.
var version: int = 0
## Bumped only when a container appears or vanishes (or settlements change),
## so the cached list of where a settlement's chests stand survives meals.
var places_version: int = 0
## settlement id -> [key, chest cells]
var _chest_cache: Dictionary = {}
## settlement id -> [key, stock]
var _stock_cache: Dictionary = {}


func create(name: String, center: Vector3i, camp: Vector3i, tick: int) -> int:
	var culture: Dictionary = {}
	for work in Goals.WORK_TYPES:
		culture[work] = 1.0
	var id: int = next_id
	next_id += 1
	entries[id] = {"id": id, "name": name, "center": center, "radius": Balance.number("settlements.start_radius"),
		"residents": [], "culture": culture, "known_templates": [], "site_ids": [], "shrine_ids": [],
		"camp": camp, "founded_tick": tick}
	version += 1
	return id


func get_settlement(id: int) -> Dictionary:
	return entries.get(id, {})


func ids() -> Array:
	var keys: Array = entries.keys()
	keys.sort()
	return keys


# --- Chests -------------------------------------------------------------------

## Keeps the chest registry in step with the world: a new chest starts empty,
## a broken one spills what it held beside it as loose goods.
func on_block(sim: RefCounted, cell: Vector3i, old: int, block: int) -> void:
	var was_chest: bool = Registry.component(old) in CONTAINERS
	var is_chest: bool = Registry.component(block) in CONTAINERS
	if is_chest and not chests.has(cell):
		chests[cell] = {}
		if Registry.component(block) == "granary_bin":
			bins[cell] = true
		version += 1
		places_version += 1
	elif was_chest and not is_chest and chests.has(cell):
		var contents: Dictionary = chests[cell]
		chests.erase(cell)
		bins.erase(cell)
		lots.erase(cell)
		version += 1
		places_version += 1
		var spill: Vector3i = sim.nav.nearest_walkable(cell, 2) if sim.nav != null else cell
		var resources: Array = contents.keys()
		resources.sort()
		for resource in resources:
			sim.drop_item(spill if spill.x >= 0 else cell, resource, float(contents[resource]))


func chest_contents(cell: Vector3i) -> Dictionary:
	return chests.get(cell, {})


func chest_total(cell: Vector3i) -> int:
	var sum: int = 0
	for resource in chest_contents(cell):
		sum += int(chests[cell][resource])
	return sum


## Room left in a container, for `resource` when given: a granary bin has
## no room for anything but grain.
func chest_room(cell: Vector3i, resource: String = "") -> int:
	if not chests.has(cell):
		return 0
	if bins.has(cell) and not resource.is_empty() and not Balance.list("settlements.bin_holds").has(resource):
		return 0
	return maxi(container_capacity(cell) - chest_total(cell), 0)


func container_capacity(cell: Vector3i) -> int:
	return Balance.integer("settlements.bin_capacity" if bins.has(cell) else "settlements.chest_capacity")


## Puts up to `count` into one container; returns how many fit.
func chest_add(cell: Vector3i, resource: String, count: int) -> int:
	var stored: int = mini(count, chest_room(cell, resource))
	if stored <= 0 or resource.is_empty():
		return 0
	chests[cell][resource] = int(chests[cell].get(resource, 0)) + stored
	if perishable(resource):
		var held: Dictionary = lots.get(cell, {})
		var dated: Array = held.get(resource, [])
		if not dated.is_empty() and int(dated.back()[0]) == today:
			dated.back()[1] = int(dated.back()[1]) + stored
		else:
			dated.append([today, stored])
		held[resource] = dated
		lots[cell] = held
	version += 1
	return stored


static func perishable(resource: String) -> bool:
	return Balance.dict("food.spoil_days").has(resource)


## Takes up to `count` from one chest; returns how many were there.
func chest_take(cell: Vector3i, resource: String, count: int) -> int:
	var held: int = int(chest_contents(cell).get(resource, 0))
	var taken: int = mini(count, held)
	if taken <= 0:
		return 0
	if held == taken:
		chests[cell].erase(resource)
	else:
		chests[cell][resource] = held - taken
	_take_lots(cell, resource, taken)
	version += 1
	return taken


## The oldest goods go first.
func _take_lots(cell: Vector3i, resource: String, count: int) -> void:
	var dated: Array = lots.get(cell, {}).get(resource, [])
	var left: int = count
	while left > 0 and not dated.is_empty():
		var used: int = mini(left, int(dated[0][1]))
		dated[0][1] = int(dated[0][1]) - used
		left -= used
		if int(dated[0][1]) <= 0:
			dated.pop_front()
	if dated.is_empty() and lots.has(cell):
		lots[cell].erase(resource)


## The settlement a chest belongs to, or -1 when it stands outside them all.
func chest_owner(cell: Vector3i) -> int:
	return at_cell(cell)


## The chests standing in a settlement's area, in a stable order.
func chest_cells(_sim: RefCounted, id: int) -> Array:
	if not entries.has(id):
		return []
	var key: Array = [places_version, chests.size(), float(entries[id].radius), entries.size()]
	var cached: Array = _chest_cache.get(id, [[], []])
	if cached[0] == key:
		return cached[1]
	var result: Array = []
	for cell in chests:
		if at_cell(cell) == id:
			result.append(cell)
	result.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return [a.y, a.z, a.x] < [b.y, b.z, b.x])
	_chest_cache[id] = [key, result]
	return result


# --- Stock --------------------------------------------------------------------

## The sum of what a settlement's chests hold (shared: duplicate to keep).
func stock_of(id: int) -> Dictionary:
	if not entries.has(id):
		return {}
	var key: Array = [version, float(entries[id].radius), entries.size()]
	var cached: Array = _stock_cache.get(id, [[], {}])
	if cached[0] == key:
		return cached[1]
	var sum: Dictionary = {}
	for cell in chest_cells(null, id):
		for resource in chests[cell]:
			sum[resource] = int(sum.get(resource, 0)) + int(chests[cell][resource])
	_stock_cache[id] = [key, sum]
	return sum


func amount(id: int, resource: String) -> int:
	return int(stock_of(id).get(resource, 0))


func total(id: int) -> int:
	var sum: int = 0
	var stock: Dictionary = stock_of(id)
	for resource in stock:
		sum += int(stock[resource])
	return sum


func capacity(sim: RefCounted, id: int) -> int:
	var sum: int = 0
	for cell in chest_cells(sim, id):
		sum += container_capacity(cell)
	return sum


## Room for `resource` across a settlement's containers (bins only for grain).
func room_for(sim: RefCounted, id: int, resource: String) -> int:
	var sum: int = 0
	for cell in chest_cells(sim, id):
		sum += chest_room(cell, resource)
	return sum


## What a settlement's containers could hold of `resource` if empty.
func capacity_for(sim: RefCounted, id: int, resource: String) -> int:
	var sum: int = 0
	for cell in chest_cells(sim, id):
		if not bins.has(cell) or Balance.list("settlements.bin_holds").has(resource):
			sum += container_capacity(cell)
	return sum


## Stores into the settlement's chests within reach of `near`, nearest first.
func add(sim: RefCounted, id: int, resource: String, count: int, near: Vector3i) -> int:
	if not entries.has(id) or count <= 0:
		return 0
	var stored: int = 0
	for cell in _reachable(sim, id, near):
		if stored >= count:
			break
		stored += chest_add(cell, resource, count - stored)
	return stored


## Takes from the settlement's chests within reach of `near`, nearest first.
func take(sim: RefCounted, id: int, resource: String, count: int, near: Vector3i) -> int:
	if not entries.has(id) or count <= 0:
		return 0
	var taken: int = 0
	for cell in _reachable(sim, id, near):
		if taken >= count:
			break
		taken += chest_take(cell, resource, count - taken)
	return taken


func _reachable(sim: RefCounted, id: int, near: Vector3i) -> Array:
	var ranked: Array = []
	for cell in chest_cells(sim, id):
		if can_reach(cell, near):
			ranked.append([_distance(cell, near), cell.y, cell.z, cell.x, cell])
	ranked.sort()
	var result: Array = []
	for entry in ranked:
		result.append(entry[4])
	return result


static func can_reach(chest: Vector3i, from: Vector3i) -> bool:
	return _distance(chest, from) <= REACH and absi(chest.y - from.y) <= 2


## Where to stand to use the stores. Taking a resource leads to the nearest
## chest holding it, storing to the nearest with room; with no such chest,
## storing leads to the camp (to set the load down) and taking leads nowhere.
func store_access(sim: RefCounted, id: int, from: Vector3i, resource: String = "", storing: bool = false, agent: RefCounted = null) -> Vector3i:
	if not entries.has(id):
		return NONE
	var best: Vector3i = NONE
	var best_distance: float = INF
	for chest in chest_cells(sim, id):
		if storing and chest_room(chest, resource) <= 0:
			continue
		if not storing and not resource.is_empty() and int(chests[chest].get(resource, 0)) <= 0:
			continue
		if not storing and resource.is_empty() and chest_total(chest) <= 0:
			continue
		var cell: Vector3i = chest_stand(sim, chest, from)
		# Someone who found no way to a chest tries another for a while.
		if agent != null and cell.x >= 0 and agent.beliefs.recently_failed("cell:%s" % str(cell), sim.calendar.tick, Balance.integer("agents.failure_memory_ticks")):
			continue
		if cell.x >= 0 and _distance(cell, from) < best_distance:
			best = cell
			best_distance = _distance(cell, from)
	if best.x < 0 and storing:
		return entries[id].camp
	return best


## Whether a chest beside `stand` can still be used for this purpose: one
## holding the resource to take, or with room for the load to store.
func store_serves(sim: RefCounted, id: int, stand: Vector3i, resource: String = "", storing: bool = false) -> bool:
	if not entries.has(id):
		return false
	for chest in chest_cells(sim, id):
		if not can_reach(chest, stand):
			continue
		if storing and chest_room(chest, resource) > 0:
			return true
		if not storing and not resource.is_empty() and int(chests[chest].get(resource, 0)) > 0:
			return true
		if not storing and resource.is_empty() and chest_total(chest) > 0:
			return true
	return false


## A walkable cell beside a chest (not on top of it), nearest to `from`.
static func chest_stand(sim: RefCounted, chest: Vector3i, from: Vector3i) -> Vector3i:
	var best: Vector3i = NONE
	var best_distance: float = INF
	for side in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		for dy in [0, -1, 1]:
			var cell: Vector3i = chest + side + Vector3i(0, dy, 0)
			if not sim.nav.is_walkable(cell):
				continue
			var distance: float = Vector3(cell).distance_to(Vector3(from))
			if distance < best_distance:
				best = cell
				best_distance = distance
			break
	return best if best.x >= 0 else sim.nav.nearest_walkable(chest, 1)


func at_store(sim: RefCounted, agent: RefCounted) -> bool:
	if not entries.has(agent.settlement_id):
		return false
	for chest in chest_cells(sim, agent.settlement_id):
		if can_reach(chest, agent.cell):
			return true
	return false


## The settlement whose area holds a cell, or -1. Where two areas overlap,
## the cell belongs to the nearer centre (the lower id on a tie).
func at_cell(cell: Vector3i) -> int:
	var best: int = -1
	var best_distance: float = INF
	for id in ids():
		var distance: float = _distance(cell, entries[id].center)
		if distance <= float(entries[id].radius) and distance < best_distance:
			best = id
			best_distance = distance
	return best


## The settlement founded on a founding ground, or -1.
func on_ground(index: int) -> int:
	for id in ids():
		if int(entries[id].get("ground", -1)) == index:
			return id
	return -1


func join(agent: RefCounted, id: int) -> void:
	if agent.settlement_id == id:
		return
	if entries.has(agent.settlement_id):
		entries[agent.settlement_id].residents.erase(agent.id)
	agent.settlement_id = id
	if entries.has(id) and not entries[id].residents.has(agent.id):
		entries[id].residents.append(agent.id)


static func _distance(a: Vector3i, b: Vector3i) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "next_id": next_id, "chests": chests.duplicate(true), "bins": bins.duplicate(),
		"lots": lots.duplicate(true), "designs": designs.duplicate(true), "next_design": next_design}


func from_dict(data: Dictionary) -> void:
	entries = data.entries
	next_id = int(data.next_id)
	chests = data.chests
	bins = data.bins
	lots = data.lots
	# Devised designs came with M19 (schema 5 worlds may lack them).
	designs = data.get("designs", {})
	next_design = int(data.get("next_design", 1))
	version += 1
	_chest_cache.clear()
	_stock_cache.clear()
