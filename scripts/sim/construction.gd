extends RefCounted
## Construction sites: a template placed at an origin and rotation, raised a
## block at a time, bottom layer first and outer walls before interior. Site
## cells are reserved so the god and other sites avoid them. A site with no
## progress for `construction.abandon_days` is abandoned and its delivered
## materials are left lying.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

const NONE := Vector3i(-1, -1, -1)

## id -> {id, template_id, origin, rotation, settlement_id, founder, purpose,
##        order: Array of [cell, block, meta], cursor, delivered: resource -> int,
##        last_progress_tick, started_tick, builders: Array}
var sites: Dictionary = {}
## Vector3i -> site id for every cell a site will touch.
var reserved: Dictionary = {}
var next_id: int = 1


func is_reserved(cell: Vector3i) -> bool:
	return reserved.has(cell)


func get_site(id: int) -> Dictionary:
	return sites.get(id, {})


func ids() -> Array:
	var keys: Array = sites.keys()
	keys.sort()
	return keys


func in_settlement(settlement: int) -> Array:
	var result: Array = []
	for id in ids():
		if int(sites[id].settlement_id) == settlement:
			result.append(id)
	return result


## Lay out a site. `order` already includes foundation and clearing entries.
func create(template_id: String, origin: Vector3i, rotation: int, settlement: int, founder: int, purpose: String, order: Array, tick: int) -> int:
	var id: int = next_id
	next_id += 1
	sites[id] = {"id": id, "template_id": template_id, "origin": origin, "rotation": rotation,
		"settlement_id": settlement, "founder": founder, "purpose": purpose, "order": order, "cursor": 0,
		"delivered": {}, "last_progress_tick": tick, "started_tick": tick, "builders": [], "solid_left": {}}
	for entry in order:
		reserved[entry[0]] = id
		if Registry.passable[entry[1]] == 0:
			sites[id].solid_left[entry[0]] = true
	return id


## The next entry still to place, or [] when complete.
func next_entry(id: int) -> Array:
	var site: Dictionary = sites.get(id, {})
	if site.is_empty() or int(site.cursor) >= site.order.size():
		return []
	return site.order[site.cursor]


## Plain materials builders may raise in planks when none is to hand: stone
## walling and thatch roofs, by the resource that is lacking. Components (a
## hearth, an altar, a mat) are never swapped, so a building keeps its function.
## Where each make-do resource is gathered (as JobBoard names places).
const SITE_OF: Dictionary = {"stone": "rock", "thatch": "grass"}
const MAKE_DO: Dictionary = {"stone": ["cobble", "cut_stone", "stone"], "thatch": ["thatch"]}
## Why a site made do, by the resource it lacked.
const MAKE_DO_CAUSE: Dictionary = {"stone": "cause_no_stone", "thatch": "cause_no_grass"}


static func is_walling(block: int) -> bool:
	return Registry.block_name(block) in MAKE_DO.stone


## Swaps the plain `resource` blocks still to be placed in `order` (from
## `from` on) for planks; returns how many blocks changed.
static func in_planks(order: Array, from: int, resource: String) -> int:
	var changed: int = 0
	var names: Array = MAKE_DO.get(resource, [])
	for index in range(from, order.size()):
		if Registry.block_name(int(order[index][1])) in names:
			order[index][1] = Registry.id("planks")
			changed += 1
	return changed


static func in_timber(order: Array, from: int) -> int:
	return in_planks(order, from, "stone")


## Whether a person knows stone to hand: carried, in their stores, or a rock
## they believe in within a short walk of their settlement.
static func knows_stone_near(sim: RefCounted, agent: RefCounted) -> bool:
	return knows_near(sim, agent, "stone")


## The same for any resource gathered from a kind of place (rock, grass).
static func knows_near(sim: RefCounted, agent: RefCounted, resource: String) -> bool:
	if agent.carried(resource) >= 1.0 or agent.beliefs.believes_stock(resource):
		return true
	var settlement: Dictionary = sim.settlements.get_settlement(agent.settlement_id)
	var home: Vector3i = settlement.get("center", agent.cell)
	var reach: float = float(settlement.get("radius", 22.0)) + Balance.number("construction.stone_walk")
	for id in agent.beliefs.known_sites(str(SITE_OF.get(resource, "")), home):
		var cell: Vector3i = agent.beliefs.sites[id].cell
		return Vector2(cell.x - home.x, cell.z - home.z).length() <= reach
	return false


## Whether a design needs stone only for walling.
static func stone_is_walling(template: RefCounted) -> bool:
	return only_plain(template, "stone")


## Whether every block of `resource` in a design is plain enough to make do.
static func only_plain(template: RefCounted, resource: String) -> bool:
	var names: Array = MAKE_DO.get(resource, [])
	for index in range(template.cells.size()):
		var block: int = Registry.id(template.palette[template.cells[index]])
		if Registry.resource(block) == resource and not Registry.block_name(block) in names:
			return false
	return true


static func resource_for(block: int) -> String:
	return Registry.build_resource(block) if block != 0 else ""


## Materials still needed beyond what has been delivered: resource -> int.
func missing(id: int) -> Dictionary:
	var site: Dictionary = sites[id]
	var need: Dictionary = {}
	for i in range(int(site.cursor), site.order.size()):
		var resource: String = resource_for(site.order[i][1])
		if not resource.is_empty():
			need[resource] = int(need.get(resource, 0)) + 1
	var result: Dictionary = {}
	for resource in need:
		var short: int = int(need[resource]) - int(site.delivered.get(resource, 0))
		if short > 0:
			result[resource] = short
	return result


## Whether the next block can be placed with what is already on site.
func ready_to_build(id: int) -> bool:
	var entry: Array = next_entry(id)
	if entry.is_empty():
		return false
	var resource: String = resource_for(entry[1])
	return resource.is_empty() or int(sites[id].delivered.get(resource, 0)) > 0


## Where a builder stands to reach the next block: a walkable cell within
## reach that no remaining solid block will fill.
func access(sim: RefCounted, id: int, from: Vector3i) -> Vector3i:
	var entry: Array = next_entry(id)
	if entry.is_empty():
		return NONE
	var site: Dictionary = sites[id]
	var cached: Array = site.get("access", [-1, NONE])
	if int(cached[0]) == int(site.cursor) and sim.nav.is_walkable(cached[1]):
		return cached[1]
	var cell: Vector3i = stand_cell(sim, id, entry[0], from)
	site["access"] = [int(site.cursor), cell]
	return cell


## The best cell within reach of `target` that the builder can actually walk
## to from `from`, preferring short walks and close work.
func stand_cell(sim: RefCounted, id: int, target: Vector3i, from: Vector3i) -> Vector3i:
	var site: Dictionary = sites[id]
	var reach: float = Balance.number("agents.reach")
	var options: Array = []
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			for dy in range(-3, 2):
				var cell: Vector3i = target + Vector3i(dx, dy, dz)
				if cell == target or not sim.nav.is_walkable(cell):
					continue
				if Vector3(cell + Vector3i.UP).distance_to(Vector3(target)) > reach + 0.5:
					continue
				if _will_fill(site, cell) or _will_fill(site, cell + Vector3i.UP):
					continue
				# Not on top of the building itself: its walls and roof are no floor to reach.
				if int(reserved.get(cell + Vector3i.DOWN, -1)) == id:
					continue
				var score: float = Vector3(cell).distance_to(Vector3(from)) * 0.2 + Vector3(cell).distance_to(Vector3(target))
				options.append([score, sim.voxels.index_of(cell), cell])
	options.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	for i in range(mini(options.size(), 8)):
		var cell: Vector3i = options[i][2]
		if cell == from or not sim.nav.find_path(from, cell).is_empty():
			return cell
	return NONE


func solid_left_has(id: int, cell: Vector3i) -> bool:
	return sites.has(id) and sites[id].solid_left.has(cell)


func _will_fill(site: Dictionary, cell: Vector3i) -> bool:
	return site.solid_left.has(cell)


## Advance past the current entry once it is placed or skipped.
func advance(id: int, tick: int) -> void:
	var site: Dictionary = sites[id]
	var entry: Array = site.order[site.cursor]
	site.solid_left.erase(entry[0])
	site.cursor = int(site.cursor) + 1
	site.last_progress_tick = tick


func release(id: int) -> void:
	var site: Dictionary = sites.get(id, {})
	for entry in site.get("order", []):
		if int(reserved.get(entry[0], -1)) == id:
			reserved.erase(entry[0])
	sites.erase(id)


func to_dict() -> Dictionary:
	return {"sites": sites.duplicate(true), "next_id": next_id}


func from_dict(data: Dictionary) -> void:
	sites = data.sites
	next_id = int(data.next_id)
	reserved.clear()
	for id in sites:
		for entry in sites[id].order:
			reserved[entry[0]] = id
