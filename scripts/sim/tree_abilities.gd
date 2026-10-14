extends RefCounted
## What the tree's later unlocks do (user request, 2026-10-11), each one a
## real effect so the catalog stays honest:
## - deep roots: a field in the tree's qi keeps growing through a dry spell;
## - sheltering canopy: within the crown's reach the tree is a roof;
## - awakening fruit: a spirit fruit eaten by a mortal deepens their talent
##   or their drive (never a realm);
## - root network: the tree's qi and the god's reach run along worn paths
##   joined to the tree, as far as feet have worn them;
## - warding formation (M23): wolves keep out of a circle round the trunk
##   and outlaws inside it fall back;
## - root realm (M23): the hidden realm in the roots opens (campaign.gd).
const Data = preload("res://scripts/core/data.gd")
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Mind = preload("res://scripts/agents/mind.gd")


static func _settings(key: String) -> Dictionary:
	return Data.tree_growth()[key]


static func has(sim: RefCounted, id: String) -> bool:
	return sim.tree_growth != null and sim.tree_growth.has_unlock(id)


# --- Deep roots ---------------------------------------------------------------

## Whether the tree's roots water a field at `cell` through a dry spell.
static func watered(sim: RefCounted, cell: Vector3i) -> bool:
	return has(sim, "deep_roots") and sim.qi != null and sim.qi.density(sim, cell) >= float(_settings("deep_roots").qi)


# --- Warding formation (M23) ------------------------------------------------------

## Whether the tree's formation wards `cell`: wolves will not enter, and
## outlaws inside fall back.
static func warded(sim: RefCounted, cell: Vector3i) -> bool:
	if not has(sim, "warding_formation"):
		return false
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	return tree.x >= 0 and Vector2(cell.x - tree.x, cell.z - tree.z).length() <= float(_settings("warding").reach)


# --- Sheltering canopy ----------------------------------------------------------

static func _within_crown(sim: RefCounted, cell: Vector3i) -> bool:
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	return tree.x >= 0 and Vector2(cell.x - tree.x, cell.z - tree.z).length() <= float(_settings("canopy").reach)


## Whether the crown is a roof over `cell`.
static func sheltered(sim: RefCounted, cell: Vector3i) -> bool:
	return has(sim, "sheltering_canopy") and _within_crown(sim, cell)


## While abstract: the homeless of a settlement centred under the crown
## sleep beneath it.
static func shelters_settlement(sim: RefCounted, settlement_id: int) -> bool:
	if not has(sim, "sheltering_canopy") or not sim.settlements.entries.has(settlement_id):
		return false
	return _within_crown(sim, sim.settlements.entries[settlement_id].center)


# --- Awakening fruit ------------------------------------------------------------

## A fruit reaches someone. A cultivator keeps it for their trial; a mortal,
## once the tree knows how, eats it at once and wakes to the Way a little:
## their talent or their drive deepens, whichever is weaker. No realm.
static func receive(sim: RefCounted, agent: RefCounted, giver: RefCounted) -> void:
	var c: Dictionary = agent.cultivation
	if int(c.realm) >= 1 or not has(sim, "awakening_fruit"):
		c.fruit = true
		return
	var settings: Dictionary = _settings("awakening")
	var what: String = "awakened_talent"
	if float(c.talent) <= float(c.drive):
		c.talent = minf(float(c.talent) + float(settings.talent), 1.0)
	else:
		c.drive = minf(float(c.drive) + float(settings.drive), 1.0)
		what = "awakened_drive"
	c["awakened"] = true
	Mind.add(agent, "fruit_awakened", sim.calendar.ticks_per_day * 3, giver.id if giver != null else -1)
	sim.chronicle_event("fruit_awakened", agent.settlement_id, {"name": agent.full_name(), "what": what}, "cause_awakening_fruit", [agent.id])


# --- Root network ---------------------------------------------------------------

static func daily(sim: RefCounted) -> void:
	refresh_roots(sim)


## Rebuilds the columns the roots reach: worn paths joined (with small gaps)
## to a path near the tree, widened by a step either side. Done at the
## day's turn, after paths wear, and when a world is loaded.
static func refresh_roots(sim: RefCounted) -> void:
	var growth: RefCounted = sim.tree_growth
	growth.rooted_day = sim.calendar.day()
	var before: Dictionary = growth.rooted
	var reached: Dictionary = {}
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	growth.rooted_paths = []
	if has(sim, "root_network") and sim.paths != null and tree.x >= 0:
		reached = _reach(sim, tree, growth.rooted_paths)
	growth.rooted = reached
	if reached.size() != before.size() or reached.keys() != before.keys():
		sim.qi.clear_cache()


## The columns the roots reach; the path columns they run along are
## appended to `along`, sorted.
static func _reach(sim: RefCounted, tree: Vector3i, along: Array) -> Dictionary:
	var settings: Dictionary = _settings("roots")
	var path_block: int = Registry.id("path")
	var paths: Dictionary = {}
	for column in sim.paths.wear:
		var top: int = sim.voxels.top_solid_y(column.x, column.y)
		if top >= 0 and sim.voxels.get_xyz(column.x, top, column.y) == path_block:
			paths[column] = true
	var start: float = Balance.number("shrines.tree_min_radius")
	var frontier: Array = []
	var joined: Dictionary = {}
	var columns: Array = paths.keys()
	columns.sort()
	for column in columns:
		if Vector2(column.x - tree.x, column.y - tree.z).length() <= start:
			joined[column] = true
			frontier.append(column)
	var gap: int = int(settings.gap)
	while not frontier.is_empty():
		var column: Vector2i = frontier.pop_back()
		for dz in range(-gap, gap + 1):
			for dx in range(-gap, gap + 1):
				var next := Vector2i(column.x + dx, column.y + dz)
				if paths.has(next) and not joined.has(next):
					joined[next] = true
					frontier.append(next)
	along.append_array(joined.keys())
	along.sort()
	var reach: int = int(settings.reach)
	var result: Dictionary = {}
	for column in joined:
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				result[Vector2i(column.x + dx, column.y + dz)] = true
	return result


## Whether the roots reach the column under `point` (for the god's reach,
## only while manifested at the tree).
static func rooted(sim: RefCounted, point: Vector3) -> bool:
	return sim.tree_growth != null and sim.tree_growth.rooted.has(Vector2i(floori(point.x), floori(point.z)))


## The qi the roots carry to a column they reach, or 0.
static func root_qi(sim: RefCounted, column: Vector2i) -> float:
	if sim.tree_growth == null or not sim.tree_growth.rooted.has(column):
		return 0.0
	return float(_settings("roots").qi)
