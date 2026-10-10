extends RefCounted
## Settlements: who lives where, the shared stock and where it is kept, and
## each settlement's culture weights. Stock is only what lies in the storage
## chests standing in a settlement's area, each chest holding its own goods.
## The camp is where people meet and where goods are set down loose while
## there is no chest with room; loose goods are never counted as stock.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

const NONE := Vector3i(-1, -1, -1)
## How far from a chest someone can reach into it.
const REACH: float = 1.8

## id -> {id, name, center, radius, residents, culture, known_templates,
##        site_ids, shrine_ids, camp, founded_tick}
var entries: Dictionary = {}
var next_id: int = 1
## chest cell -> {resource: int}, for every storage chest in the world.
var chests: Dictionary = {}
## Bumped whenever a chest appears, vanishes or its contents change.
var version: int = 0
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
	var was_chest: bool = Registry.component(old) == "chest"
	var is_chest: bool = Registry.component(block) == "chest"
	if is_chest and not chests.has(cell):
		chests[cell] = {}
		version += 1
	elif was_chest and not is_chest and chests.has(cell):
		var contents: Dictionary = chests[cell]
		chests.erase(cell)
		version += 1
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


func chest_room(cell: Vector3i) -> int:
	if not chests.has(cell):
		return 0
	return maxi(Balance.integer("settlements.chest_capacity") - chest_total(cell), 0)


## Puts up to `count` into one chest; returns how many fit.
func chest_add(cell: Vector3i, resource: String, count: int) -> int:
	var stored: int = mini(count, chest_room(cell))
	if stored <= 0 or resource.is_empty():
		return 0
	chests[cell][resource] = int(chests[cell].get(resource, 0)) + stored
	version += 1
	return stored


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
	version += 1
	return taken


## The settlement a chest belongs to, or -1 when it stands outside them all.
func chest_owner(cell: Vector3i) -> int:
	return at_cell(cell)


## The chests standing in a settlement's area, in a stable order.
func chest_cells(_sim: RefCounted, id: int) -> Array:
	if not entries.has(id):
		return []
	var key: Array = [version, float(entries[id].radius), entries.size()]
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
	return chest_cells(sim, id).size() * Balance.integer("settlements.chest_capacity")


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
func store_access(sim: RefCounted, id: int, from: Vector3i, resource: String = "", storing: bool = false) -> Vector3i:
	if not entries.has(id):
		return NONE
	var best: Vector3i = NONE
	var best_distance: float = INF
	for chest in chest_cells(sim, id):
		if storing and chest_room(chest) <= 0:
			continue
		if not storing and not resource.is_empty() and int(chests[chest].get(resource, 0)) <= 0:
			continue
		if not storing and resource.is_empty() and chest_total(chest) <= 0:
			continue
		var cell: Vector3i = chest_stand(sim, chest, from)
		if cell.x >= 0 and _distance(cell, from) < best_distance:
			best = cell
			best_distance = _distance(cell, from)
	if best.x < 0 and storing:
		return entries[id].camp
	return best


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


## The settlement whose area holds a cell, or -1.
func at_cell(cell: Vector3i) -> int:
	for id in ids():
		if _distance(cell, entries[id].center) <= float(entries[id].radius):
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
	return {"entries": entries.duplicate(true), "next_id": next_id, "chests": chests.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	entries = data.entries
	next_id = int(data.next_id)
	chests = data.chests
	version += 1
	_chest_cache.clear()
	_stock_cache.clear()
