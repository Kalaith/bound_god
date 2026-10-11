extends RefCounted
## Spirit herbs (M20, kinds M20b): once the tree has grown into its Spirit
## Root phase (the `spirit_herbs` unlock), herbs sprout where each kind's
## conditions hold (`alchemy.json` `herbs`): the common spirit herb on open
## grass in deep qi (or round a nurtured spot), jade ginseng in shade, thunder
## root on earth Heaven's lightning scorched, frost lotus beside water in
## winter. A herb's ripeness is its block meta: sprout, growing, ripe. A ripe
## herb is gathered as a resource site (like a bush) and grows again from the
## root; a kind out of its season rests, or withers if it is a winter flower.
## The beds of a herb garden sprout herbs of their own, faster to ripen.
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Calendar = preload("res://scripts/sim/calendar.gd")

const RIPE: int = 2
## How far below a bank's grass the water may lie for frost lotus.
const BANK: int = 2
const NONE := Vector3i(-1, -1, -1)

## herb cell -> days grown toward the next stage
var plants: Dictionary = {}
## While the valley passes abstractly the herbs are counted, not placed:
## {kind id: {"plants": int, "ripe": float}} (applied on materialising).
var pool: Dictionary = {}
## Cells of earth Heaven scorched, where thunder root may take: Vector3i -> true
var scorched: Dictionary = {}
## Kinds whose first herbs have been chronicled: id -> true
var found: Dictionary = {}
## Whether an older save's scorched earth has been looked for (not saved).
var _scanned: bool = true
## Grass beside water within reach of the tree (rebuilt on demand, not saved).
var _waterside: Array = []
var _waterside_built: bool = false


static func kinds() -> Array:
	return Data.alchemy().get("herbs", [])


static func kind(id: String) -> Dictionary:
	for entry in kinds():
		if entry.id == id:
			return entry
	return {}


static func search() -> Dictionary:
	return Data.alchemy().herb_search


static func garden() -> Dictionary:
	return Data.alchemy().garden


## The common spirit herb's settings (M20's checks read these).
static func settings() -> Dictionary:
	return kind("spirit_herb")


static func block_id(id: String = "spirit_herb") -> int:
	return Registry.id(id)


## The kind a herb block is, or {} for any other block.
static func kind_of_block(block: int) -> Dictionary:
	return kind(Registry.block_name(block)) if block > 0 else {}


static func is_herb(block: int) -> bool:
	return not kind_of_block(block).is_empty()


## Herb block names by the resource they give.
static func by_resource(resource: String) -> Dictionary:
	for entry in kinds():
		if entry.resource == resource:
			return entry
	return {}


static func resources() -> Array:
	var result: Array = []
	for entry in kinds():
		result.append(str(entry.resource))
	return result


static func unlocked(sim: RefCounted) -> bool:
	return sim.tree_growth != null and sim.tree_growth.has_unlock("spirit_herbs")


static func in_season(sim: RefCounted, entry: Dictionary) -> bool:
	return Calendar.SEASONS[sim.calendar.season()] in entry.seasons


func count() -> int:
	return plants.size()


## Herbs of one kind standing in the valley.
func count_of(sim: RefCounted, id: String) -> int:
	var block: int = block_id(id)
	var result: int = 0
	for cell in plants:
		result += 1 if sim.voxels.get_block(cell) == block else 0
	return result


## Herbs of a kind growing wild (not in a garden's beds).
func wild_count(sim: RefCounted, id: String) -> int:
	var block: int = block_id(id)
	var bed: int = Registry.id("herb_bed")
	var result: int = 0
	for cell in plants:
		if sim.voxels.get_block(cell) == block and sim.voxels.get_block(cell + Vector3i.DOWN) != bed:
			result += 1
	return result


## Keeps the record true to the world: a herb broken or burned is gone, and
## earth Heaven scorched is remembered for thunder root.
func on_block(cell: Vector3i, block: int) -> void:
	if is_herb(block):
		if not plants.has(cell):
			plants[cell] = 0
	elif plants.has(cell):
		plants.erase(cell)
	if block == Registry.id("scorched_earth"):
		scorched[cell] = true
	elif scorched.has(cell):
		scorched.erase(cell)


func _sorted_cells(sim: RefCounted) -> Array:
	var cells: Array = plants.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return sim.voxels.index_of(a) < sim.voxels.index_of(b))
	return cells


func daily(sim: RefCounted) -> void:
	if not unlocked(sim):
		return
	_scan_scorched(sim)
	var bed: int = Registry.id("herb_bed")
	for cell in _sorted_cells(sim):
		var entry: Dictionary = kind_of_block(sim.voxels.get_block(cell))
		if entry.is_empty():
			continue
		if not in_season(sim, entry):
			# A winter flower is gone with the snow; the others rest.
			if bool(entry.withers):
				sim.set_block(cell, 0, 0, "growth")
			continue
		var stage: int = sim.voxels.block_meta(cell)
		if stage >= RIPE:
			continue
		var days: float = float(entry.ripen_days)
		if sim.voxels.get_block(cell + Vector3i.DOWN) == bed:
			days /= float(garden().ripen)
		plants[cell] = int(plants[cell]) + 1
		if float(plants[cell]) * RIPE >= days * (stage + 1):
			sim.set_block(cell, sim.voxels.get_block(cell), stage + 1, "growth")
	for entry in kinds():
		if in_season(sim, entry):
			_sprout(sim, entry)
	_gardens(sim)


func _sprout(sim: RefCounted, entry: Dictionary) -> void:
	var wild: int = wild_count(sim, entry.id)
	var sprouted: int = 0
	for i in range(int(entry.per_day)):
		if wild + sprouted >= int(entry.most):
			break
		var cell: Vector3i = spot(sim, entry)
		if cell.x < 0:
			continue
		sim.set_block(cell, block_id(entry.id), 0, "growth")
		sprouted += 1
	if sprouted > 0:
		_first(sim, entry, sprouted)


## The first herbs of each kind are chronicled.
func _first(sim: RefCounted, entry: Dictionary, sprouted: int) -> void:
	if found.has(entry.id):
		return
	found[entry.id] = true
	var where: Vector3i = sim.features.get("sacred_tree", Vector3i.ZERO)
	var event: String = "herbs_sprouted" if entry.id == "spirit_herb" else "herb_found"
	sim.chronicle_event(event, sim.settlements.at_cell(where), {"count": sprouted, "herb": "resource_" + str(entry.resource)}, "cause_herb_%s" % entry.grows)


## Empty beds in a herb garden sprout herbs: a spirit herb under the open
## sky, jade ginseng in shade.
func _gardens(sim: RefCounted) -> void:
	var config: Dictionary = garden()
	for entry in sim.structures.built():
		if not entry.functions.has("herb_garden"):
			continue
		var beds: Array = entry.components.get("herb_bed", []).duplicate()
		beds.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return sim.voxels.index_of(a) < sim.voxels.index_of(b))
		var sprouted: int = 0
		for bed in beds:
			if sprouted >= int(config.per_day):
				break
			var cell: Vector3i = bed + Vector3i.UP
			if sim.voxels.get_block(cell) != 0 or sim.is_occupied(cell) or sim.is_reserved_cell(cell):
				continue
			var herb: Dictionary = kind(str(config.sun if sim.voxels.sees_sky(cell) else config.shade))
			if not in_season(sim, herb):
				continue
			sim.set_block(cell, block_id(herb.id), 0, "growth")
			sprouted += 1


## A free cell where a kind of herb may take root, or NONE; tries a few times.
func spot(sim: RefCounted, entry: Dictionary) -> Vector3i:
	match str(entry.grows):
		"scar":
			return _scar_spot(sim)
		"waterside":
			return _waterside_spot(sim, entry)
	return _qi_spot(sim, entry, str(entry.grows) == "shade")


func _free(sim: RefCounted, cell: Vector3i) -> bool:
	return sim.voxels.get_block(cell) == 0 and not sim.is_occupied(cell) and not sim.is_reserved_cell(cell) and not plants.has(cell)


## Round the tree or a nurtured spot: open grass for the spirit herb, the
## floor under leaves or a roof for ginseng; the qi must be deep enough.
func _qi_spot(sim: RefCounted, entry: Dictionary, shade: bool) -> Vector3i:
	var centres: Array = [sim.features.get("sacred_tree", NONE)]
	if sim.tree_growth != null:
		for nurtured in sim.tree_growth.nurtured:
			centres.append(nurtured.cell)
	var grass: int = Registry.id("grass")
	var dirt: int = Registry.id("dirt")
	var reach: int = int(search().reach)
	for attempt in range(int(search().tries)):
		var centre: Vector3i = centres[sim.rng.randi_range(0, centres.size() - 1)]
		if centre.x < 0:
			continue
		var column := Vector2i(centre.x + sim.rng.randi_range(-reach, reach), centre.z + sim.rng.randi_range(-reach, reach))
		if not sim.voxels.in_bounds(Vector3i(column.x, 0, column.y)):
			continue
		var cell: Vector3i = _ground(sim, column, shade)
		if cell.x < 0 or not _free(sim, cell):
			continue
		var below: int = sim.voxels.get_block(cell + Vector3i.DOWN)
		if below != grass and not (shade and below == dirt):
			continue
		if shade == sim.voxels.sees_sky(cell):
			continue
		if sim.qi.density(sim, cell) < float(entry.qi):
			continue
		return cell
	return NONE


## The open cell over a column's ground: its top, or for shade the first
## grass or earth with air over it beneath leaves or a roof.
func _ground(sim: RefCounted, column: Vector2i, shade: bool) -> Vector3i:
	var top: int = sim.voxels.top_solid_y(column.x, column.y)
	if top < 0:
		return NONE
	if not shade:
		return Vector3i(column.x, top + 1, column.y)
	var grass: int = Registry.id("grass")
	var dirt: int = Registry.id("dirt")
	for y in range(top, 0, -1):
		var block: int = sim.voxels.get_xyz(column.x, y, column.y)
		if (block == grass or block == dirt) and sim.voxels.get_xyz(column.x, y + 1, column.y) == 0:
			return Vector3i(column.x, y + 1, column.y)
	return NONE


## Thunder root takes on scorched earth with open air over it.
func _scar_spot(sim: RefCounted) -> Vector3i:
	if scorched.is_empty():
		return NONE
	var cells: Array = scorched.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return sim.voxels.index_of(a) < sim.voxels.index_of(b))
	for attempt in range(int(search().tries)):
		var cell: Vector3i = cells[sim.rng.randi_range(0, cells.size() - 1)] + Vector3i.UP
		if _free(sim, cell):
			return cell
	return NONE


## Frost lotus on grass at the water's edge, within reach of the tree.
func _waterside_spot(sim: RefCounted, entry: Dictionary) -> Vector3i:
	if not _waterside_built:
		_build_waterside(sim)
	if _waterside.is_empty():
		return NONE
	for attempt in range(int(search().tries)):
		var cell: Vector3i = _waterside[sim.rng.randi_range(0, _waterside.size() - 1)]
		if _free(sim, cell) and sim.voxels.get_block(cell + Vector3i.DOWN) == Registry.id("grass") \
				and sim.qi.density(sim, cell) >= float(entry.qi):
			return cell
	return NONE


func _build_waterside(sim: RefCounted) -> void:
	_waterside_built = true
	_waterside.clear()
	var tree: Vector3i = sim.features.get("sacred_tree", NONE)
	if tree.x < 0:
		return
	var config: Dictionary = search()
	var reach: int = int(config.waterside_reach)
	var near: int = int(config.water_reach)
	var grass: int = Registry.id("grass")
	var water: int = Registry.id("water")
	for z in range(tree.z - reach, tree.z + reach + 1):
		for x in range(tree.x - reach, tree.x + reach + 1):
			if Vector2(x - tree.x, z - tree.z).length() > reach:
				continue
			var top: int = sim.voxels.top_solid_y(x, z)
			if top < 0 or sim.voxels.get_xyz(x, top, z) != grass:
				continue
			# Water close at hand: beside the cell and not far below the bank.
			var wet: bool = false
			for dz in range(-near, near + 1):
				for dx in range(-near, near + 1):
					for dy in range(-BANK, 1):
						wet = wet or sim.voxels.get_xyz(x + dx, top + 1 + dy, z + dz) == water
			if wet:
				_waterside.append(Vector3i(x, top + 1, z))


## An older save's scorched earth, found once on the surface.
func _scan_scorched(sim: RefCounted) -> void:
	if _scanned:
		return
	_scanned = true
	if not scorched.is_empty():
		return
	var mark: int = Registry.id("scorched_earth")
	for z in range(sim.voxels.size.z):
		for x in range(sim.voxels.size.x):
			var top: int = sim.voxels.top_solid_y(x, z)
			if top >= 0 and sim.voxels.get_xyz(x, top, z) == mark:
				scorched[Vector3i(x, top, z)] = true


func _pool(id: String) -> Dictionary:
	if not pool.has(id):
		pool[id] = {"plants": 0, "ripe": 0.0}
	return pool[id]


## While abstract: herbs sprout and ripen as counts (no block changes). A
## kind needing scars has as many places as the scars allow; gardens add
## their beds' herbs.
func abstract_day(sim: RefCounted) -> void:
	if not unlocked(sim):
		return
	_scan_scorched(sim)
	var beds: Dictionary = _garden_beds(sim)
	for entry in kinds():
		var counted: Dictionary = _pool(entry.id)
		if not in_season(sim, entry):
			if bool(entry.withers):
				counted.plants = 0
				counted.ripe = 0.0
			continue
		var most: int = int(entry.most) + int(beds.get(entry.id, 0))
		if str(entry.grows) == "scar":
			most = mini(most, scorched.size())
		var standing: int = count_of(sim, entry.id)
		counted.plants = clampi(int(counted.plants) + int(entry.per_day) + int(beds.get(entry.id, 0)), 0, maxi(most - standing, 0))
		var total: int = standing + int(counted.plants)
		if total > 0:
			_first(sim, entry, total)
		var days: float = maxf(float(entry.ripen_days), 1.0)
		counted.ripe = minf(float(total), float(counted.ripe) + float(total) / days)


## How many beds each kind has in the valley's herb gardens.
func _garden_beds(sim: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	var config: Dictionary = garden()
	for entry in sim.structures.built():
		if not entry.functions.has("herb_garden"):
			continue
		for bed in entry.components.get("herb_bed", []):
			var id: String = str(config.sun if sim.voxels.sees_sky(bed + Vector3i.UP) else config.shade)
			result[id] = int(result.get(id, 0)) + 1
	return result


## Ripe herbs of a kind gathered while abstract; returns how many were taken.
func abstract_gather(id: String, most: int) -> int:
	var counted: Dictionary = _pool(id)
	var taken: int = mini(int(floor(float(counted.ripe))), most)
	counted.ripe = float(counted.ripe) - maxi(taken, 0)
	return maxi(taken, 0)


## Ripe herbs of a kind waiting while abstract.
func abstract_ripe(id: String) -> int:
	return int(floor(float(_pool(id).ripe)))


## On waking: the counted herbs take root and as many stand ripe as the pool holds.
func materialise(sim: RefCounted) -> void:
	for entry in kinds():
		var counted: Dictionary = _pool(entry.id)
		for i in range(int(counted.plants)):
			var cell: Vector3i = spot(sim, entry)
			if cell.x >= 0:
				sim.set_block(cell, block_id(entry.id), 0, "growth")
		var ripe: int = int(floor(float(counted.ripe)))
		var block: int = block_id(entry.id)
		for cell in _sorted_cells(sim):
			if sim.voxels.get_block(cell) != block:
				continue
			var stage: int = RIPE if ripe > 0 else 0
			ripe -= 1
			plants[cell] = 0
			if sim.voxels.block_meta(cell) != stage:
				sim.set_block(cell, block, stage, "growth")
	pool = {}


func to_dict() -> Dictionary:
	return {"plants": plants.duplicate(), "pool": pool.duplicate(true), "scorched": scorched.duplicate(), "found": found.duplicate()}


func from_dict(state: Dictionary) -> void:
	plants = state.get("plants", {})
	scorched = state.get("scorched", {})
	found = state.get("found", {"spirit_herb": true} if not plants.is_empty() else {})
	# An M20 save counted only the spirit herb.
	var saved: Dictionary = state.get("pool", {})
	pool = {"spirit_herb": saved} if saved.has("plants") else saved
	_scanned = state.has("scorched")
