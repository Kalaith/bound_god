extends RefCounted
## Settlements: who lives where, the shared stock and where it is kept, and
## each settlement's culture weights. Stock lives in a pile at the centre
## plus every storage chest in the settlement's structures.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")

## id -> {id, name, center, radius, residents, stock, culture, known_templates,
##        site_ids, shrine_ids, pile, founded_tick}
var entries: Dictionary = {}
var next_id: int = 1
## settlement id -> [structures version, chest cells]
var _chest_cache: Dictionary = {}


func create(name: String, center: Vector3i, pile: Vector3i, tick: int) -> int:
	var culture: Dictionary = {}
	for work in Goals.WORK_TYPES:
		culture[work] = 1.0
	var id: int = next_id
	next_id += 1
	entries[id] = {"id": id, "name": name, "center": center, "radius": Balance.number("settlements.start_radius"),
		"residents": [], "stock": {}, "culture": culture, "known_templates": [], "site_ids": [], "shrine_ids": [],
		"pile": pile, "founded_tick": tick}
	return id


func get_settlement(id: int) -> Dictionary:
	return entries.get(id, {})


func ids() -> Array:
	var keys: Array = entries.keys()
	keys.sort()
	return keys


func stock_of(id: int) -> Dictionary:
	return entries[id].stock if entries.has(id) else {}


func amount(id: int, resource: String) -> int:
	return int(stock_of(id).get(resource, 0))


func total(id: int) -> int:
	var sum: int = 0
	for resource in stock_of(id):
		sum += int(stock_of(id)[resource])
	return sum


func chest_cells(sim: RefCounted, id: int) -> Array:
	var cached: Array = _chest_cache.get(id, [-1, []])
	if cached[0] == sim.structures.version:
		return cached[1]
	var result: Array = []
	var settlement: Dictionary = entries[id]
	for entry in sim.structures.built():
		if _distance(entry.anchor, settlement.center) > float(settlement.radius):
			continue
		for cell in entry.components.get("chest", []):
			result.append(cell)
	result.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return sim.voxels.index_of(a) < sim.voxels.index_of(b))
	_chest_cache[id] = [sim.structures.version, result]
	return result


func capacity(sim: RefCounted, id: int) -> int:
	return Balance.integer("settlements.pile_capacity") + chest_cells(sim, id).size() * Balance.integer("settlements.chest_capacity")


func add(sim: RefCounted, id: int, resource: String, count: int) -> int:
	if not entries.has(id) or count <= 0:
		return 0
	var room: int = capacity(sim, id) - total(id)
	var stored: int = mini(count, maxi(room, 0))
	if stored > 0:
		entries[id].stock[resource] = amount(id, resource) + stored
	return stored


func take(id: int, resource: String, count: int) -> int:
	var taken: int = mini(count, amount(id, resource))
	if taken > 0:
		entries[id].stock[resource] = amount(id, resource) - taken
		if entries[id].stock[resource] == 0:
			entries[id].stock.erase(resource)
	return taken


## Where to stand to use the stores: the pile itself or beside a chest.
func store_access(sim: RefCounted, id: int, from: Vector3i) -> Vector3i:
	if not entries.has(id):
		return Vector3i(-1, -1, -1)
	var best: Vector3i = entries[id].pile
	var best_distance: float = _distance(best, from)
	for chest in chest_cells(sim, id):
		var cell: Vector3i = sim.nav.nearest_walkable(chest, 1)
		if cell.x >= 0 and _distance(cell, from) < best_distance:
			best = cell
			best_distance = _distance(cell, from)
	return best


func at_store(sim: RefCounted, agent: RefCounted) -> bool:
	if not entries.has(agent.settlement_id):
		return false
	if _distance(entries[agent.settlement_id].pile, agent.cell) <= 1.5:
		return true
	for chest in chest_cells(sim, agent.settlement_id):
		if _distance(chest, agent.cell) <= 1.8:
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
	return {"entries": entries.duplicate(true), "next_id": next_id}


func from_dict(data: Dictionary) -> void:
	entries = data.entries
	next_id = int(data.next_id)
	_chest_cache.clear()
