extends RefCounted
## Spirit herbs (M20): once the tree has grown into its Spirit Root phase
## (the `spirit_herbs` unlock), herbs sprout on open grass where its qi lies
## deep (or round a nurtured spot or a spirit-gathering array), a few a day
## outside winter, up to a limit in the valley. A herb's ripeness is its
## block meta: sprout, growing, ripe. A ripe herb is gathered as a resource
## site (like a bush) and grows again from the root.
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

const RIPE: int = 2

## herb cell -> days grown toward the next stage
var plants: Dictionary = {}
## While the valley passes abstractly the herbs are counted, not placed:
## sprouted and ripe herbs waiting there (applied on materialising).
var pool: Dictionary = {"plants": 0, "ripe": 0.0}


static func settings() -> Dictionary:
	return Data.tree_growth().herbs


static func block_id() -> int:
	return Registry.id("spirit_herb")


static func unlocked(sim: RefCounted) -> bool:
	return sim.tree_growth != null and sim.tree_growth.has_unlock("spirit_herbs")


func count() -> int:
	return plants.size()


## Keeps the record true to the world: a herb broken or burned is gone.
func on_block(cell: Vector3i, block: int) -> void:
	if block == block_id():
		if not plants.has(cell):
			plants[cell] = 0
	elif plants.has(cell):
		plants.erase(cell)


func daily(sim: RefCounted) -> void:
	if not unlocked(sim) or sim.calendar.is_winter():
		return
	var ripen: int = int(settings().ripen_days)
	var cells: Array = plants.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return sim.voxels.index_of(a) < sim.voxels.index_of(b))
	for cell in cells:
		var stage: int = sim.voxels.block_meta(cell)
		if stage >= RIPE:
			continue
		plants[cell] = int(plants[cell]) + 1
		if int(plants[cell]) * RIPE >= ripen * (stage + 1):
			sim.set_block(cell, block_id(), stage + 1, "growth")
	var first: bool = plants.is_empty()
	var sprouted: int = 0
	for i in range(int(settings().per_day)):
		if plants.size() >= int(settings().most):
			break
		var cell: Vector3i = _spot(sim)
		if cell.x < 0:
			continue
		sim.set_block(cell, block_id(), 0, "growth")
		sprouted += 1
	if first and sprouted > 0:
		sim.chronicle_event("herbs_sprouted", sim.settlements.at_cell(sim.features.get("sacred_tree", Vector3i.ZERO)), {"count": sprouted}, "cause_tree_qi")


## A random open grass cell where the qi is deep enough; tries a few times.
func _spot(sim: RefCounted) -> Vector3i:
	var config: Dictionary = settings()
	var centres: Array = [sim.features.get("sacred_tree", Vector3i(-1, -1, -1))]
	if sim.tree_growth != null:
		for spot in sim.tree_growth.nurtured:
			centres.append(spot.cell)
	var grass: int = Registry.id("grass")
	for attempt in range(int(config.tries)):
		var centre: Vector3i = centres[sim.rng.randi_range(0, centres.size() - 1)]
		if centre.x < 0:
			continue
		var reach: float = float(config.reach)
		var column := Vector2i(centre.x + sim.rng.randi_range(-int(reach), int(reach)), centre.z + sim.rng.randi_range(-int(reach), int(reach)))
		if not sim.voxels.in_bounds(Vector3i(column.x, 0, column.y)):
			continue
		var top: int = sim.voxels.top_solid_y(column.x, column.y)
		var cell := Vector3i(column.x, top + 1, column.y)
		if top < 0 or sim.voxels.get_block(cell - Vector3i.UP) != grass or sim.voxels.get_block(cell) != 0:
			continue
		if sim.is_occupied(cell) or sim.is_reserved_cell(cell) or plants.has(cell):
			continue
		if sim.qi.density(sim, cell) < float(config.qi):
			continue
		return cell
	return Vector3i(-1, -1, -1)


## While abstract: herbs sprout and ripen as counts (no block changes).
func abstract_day(sim: RefCounted) -> void:
	if not unlocked(sim) or sim.calendar.is_winter():
		return
	var config: Dictionary = settings()
	var before: int = count() + int(pool.plants)
	pool.plants = mini(int(config.most) - count(), int(pool.plants) + int(config.per_day))
	var total: int = count() + int(pool.plants)
	if before == 0 and total > 0:
		sim.chronicle_event("herbs_sprouted", sim.settlements.at_cell(sim.features.get("sacred_tree", Vector3i.ZERO)), {"count": total}, "cause_tree_qi")
	pool.ripe = minf(float(total), float(pool.ripe) + float(total) / maxf(float(config.ripen_days), 1.0))


## Ripe herbs gathered while abstract; returns how many were taken.
func abstract_gather(most: int) -> int:
	var taken: int = mini(int(floor(float(pool.ripe))), most)
	pool.ripe = float(pool.ripe) - taken
	return maxi(taken, 0)


## On waking: the counted herbs take root and as many stand ripe as the pool holds.
func materialise(sim: RefCounted) -> void:
	for i in range(int(pool.plants)):
		var cell: Vector3i = _spot(sim)
		if cell.x >= 0:
			sim.set_block(cell, block_id(), 0, "growth")
	var ripe: int = int(floor(float(pool.ripe)))
	var cells: Array = plants.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return sim.voxels.index_of(a) < sim.voxels.index_of(b))
	for cell in cells:
		var stage: int = RIPE if ripe > 0 else 0
		ripe -= 1
		plants[cell] = 0
		if sim.voxels.block_meta(cell) != stage:
			sim.set_block(cell, block_id(), stage, "growth")
	pool = {"plants": 0, "ripe": 0.0}


func to_dict() -> Dictionary:
	return {"plants": plants.duplicate(), "pool": pool.duplicate()}


func from_dict(state: Dictionary) -> void:
	plants = state.get("plants", {})
	pool = state.get("pool", {"plants": 0, "ripe": 0.0})
