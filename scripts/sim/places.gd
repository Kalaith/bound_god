extends RefCounted
## Where to stand to use a place: a structure's room, a resource site, a
## covered spot. Answers are cached on the place while still walkable.
const Registry = preload("res://scripts/world/block_registry.gd")

const NONE := Vector3i(-1, -1, -1)


static func _distance(a: Vector3i, b: Vector3i) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length() + absf(a.y - b.y)


## A walkable cell inside the structure, nearest its anchor; for open-air
## places, the walkable cell nearest the anchor.
static func structure_access(sim: RefCounted, id: int, _from: Vector3i) -> Vector3i:
	var entry: Dictionary = sim.structures.entries.get(id, {})
	if entry.is_empty():
		return NONE
	var cached: Vector3i = entry.get("access", NONE)
	if cached.x >= 0 and sim.nav.is_walkable(cached):
		return cached
	var best: Vector3i = NONE
	var best_distance: float = INF
	for cell in entry.inside:
		if not sim.nav.is_walkable(cell):
			continue
		var d: float = _distance(cell, entry.anchor)
		if d < best_distance or (d == best_distance and sim.voxels.index_of(cell) < sim.voxels.index_of(best)):
			best = cell
			best_distance = d
	if best.x < 0:
		best = sim.nav.nearest_walkable(entry.anchor, 2)
	entry["access"] = best
	return best


static func site_access(sim: RefCounted, id: int) -> Vector3i:
	var site: Dictionary = sim.sites.get_site(id)
	if site.is_empty() or site.cells.is_empty():
		return NONE
	var cached: Vector3i = site.get("access", NONE)
	if cached.x >= 0 and sim.nav.is_walkable(cached):
		return cached
	# Never stand on the site itself: harvesting would take the floor away.
	var cells: Dictionary = {}
	for cell in site.cells:
		cells[cell] = true
	var best: Vector3i = NONE
	var best_distance: float = INF
	for target in site.cells:
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					var cell: Vector3i = target + Vector3i(dx, dy, dz)
					if cells.has(cell + Vector3i.DOWN) or not sim.nav.is_walkable(cell):
						continue
					var d: float = Vector3(cell).distance_to(Vector3(target))
					if d < best_distance or (d == best_distance and sim.voxels.index_of(cell) < sim.voxels.index_of(best)):
						best = cell
						best_distance = d
		if best.x >= 0:
			break
	site["access"] = best
	return best


static func structure_id_at(sim: RefCounted, cell: Vector3i) -> int:
	for entry in sim.structures.built():
		if entry.inside.has(cell):
			return entry.id
	return -1


static func is_under_canopy(sim: RefCounted, cell: Vector3i) -> bool:
	var head: Vector3i = cell + Vector3i.UP
	if sim.voxels.is_roofed(head, 6):
		return true
	for dy in range(1, 9):
		var block: int = sim.voxels.get_block(head + Vector3i(0, dy, 0))
		if block == Registry.id("leaves") or block == Registry.id("sacred_leaves"):
			return true
	return false
