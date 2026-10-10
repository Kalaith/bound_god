extends RefCounted
## Trees that come and go. A tree seed set in open ground is a sapling, and
## after some growing days (none in winter) it rises into a tree people can
## fell. Leaves left with no trunk beside them fall away a few at a time, and
## now and then a falling leaf drops a tree seed on the ground below.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const WorldGen = preload("res://scripts/world/world_gen.gd")

## sapling cell -> growing days so far
var saplings: Dictionary = {}
## leaf cell -> true for leaves with no trunk to hold them
var falling: Dictionary = {}


## Whether a seed can take root at `cell`: open (or grassy) and on grass or earth.
static func can_root(sim: RefCounted, cell: Vector3i) -> bool:
	var here: int = sim.voxels.get_block(cell)
	if here != 0 and here != Registry.id("tall_grass"):
		return false
	var ground: int = sim.voxels.get_block(cell + Vector3i.DOWN)
	return ground == Registry.id("grass") or ground == Registry.id("dirt")


## Whether a leaf still has a log beside it, at most one above or below.
static func supported(sim: RefCounted, leaf: Vector3i) -> bool:
	var trunk: int = Registry.id("log")
	for dy in range(-1, 2):
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if sim.voxels.get_block(leaf + Vector3i(dx, dy, dz)) == trunk:
					return true
	return false


## Breaking a leaf by hand finds a seed in it about one time in four; which
## leaves hold one follows from where they hang, so a replay agrees.
static func leaf_holds_seed(cell: Vector3i) -> bool:
	var roll: int = posmod(cell.x * 73856093 ^ cell.y * 19349663 ^ cell.z * 83492791, 1000)
	return roll < int(Balance.number("world.hand_leaf_seed_chance") * 1000.0)


func on_block(sim: RefCounted, cell: Vector3i, old: int, block: int) -> void:
	var sapling: int = Registry.id("sapling")
	if block == sapling:
		if not saplings.has(cell):
			saplings[cell] = 0
	elif saplings.has(cell):
		saplings.erase(cell)
	if falling.has(cell) and block != Registry.id("leaves"):
		falling.erase(cell)
	if old == Registry.id("log"):
		_check_leaves_near(sim, cell)


## A log gone: any leaf it was holding up begins to fall.
func _check_leaves_near(sim: RefCounted, cell: Vector3i) -> void:
	var leaves: int = Registry.id("leaves")
	for dy in range(-1, 2):
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var leaf: Vector3i = cell + Vector3i(dx, dy, dz)
				if not falling.has(leaf) and sim.voxels.get_block(leaf) == leaves and not supported(sim, leaf):
					falling[leaf] = true


## Each hour some loose leaves fall, and a few leave a seed where they land.
func hourly(sim: RefCounted) -> void:
	if falling.is_empty():
		return
	var chance: float = Balance.number("world.leaf_fall_chance")
	var seed_chance: float = Balance.number("world.leaf_seed_chance")
	var leaves: int = Registry.id("leaves")
	var cells: Array = falling.keys()
	cells.sort()
	for cell in cells:
		if sim.voxels.get_block(cell) != leaves or supported(sim, cell):
			falling.erase(cell)
			continue
		if sim.rng.randf() >= chance:
			continue
		falling.erase(cell)
		sim.set_block(cell, 0, 0, "growth")
		if sim.rng.randf() < seed_chance:
			var ground: Vector3i = _ground_below(sim, cell)
			if ground.x >= 0:
				sim.drop_item(ground, "tree_seed", 1.0)


## The open cell on the ground under a falling leaf, or (-1,-1,-1).
static func _ground_below(sim: RefCounted, cell: Vector3i) -> Vector3i:
	var leaves: int = Registry.id("leaves")
	for y in range(cell.y, 0, -1):
		var below: int = sim.voxels.get_block(Vector3i(cell.x, y - 1, cell.z))
		if Registry.solid[below] == 1 and below != leaves:
			var at := Vector3i(cell.x, y, cell.z)
			return at if Registry.passable[sim.voxels.get_block(at)] == 1 else Vector3i(-1, -1, -1)
	return Vector3i(-1, -1, -1)


## Saplings count growing days outside winter and rise when they have enough.
func daily(sim: RefCounted) -> void:
	if saplings.is_empty() or sim.calendar.is_winter():
		return
	var needed: int = Balance.integer("world.sapling_grow_days")
	var sapling: int = Registry.id("sapling")
	var cells: Array = saplings.keys()
	cells.sort()
	for cell in cells:
		if sim.voxels.get_block(cell) != sapling:
			saplings.erase(cell)
			continue
		saplings[cell] = int(saplings[cell]) + 1
		if int(saplings[cell]) >= needed:
			grow(sim, cell)


## Raise a tree from the sapling at `cell`. A trunk blocked by a block or a
## person waits for another day. Returns the new tree's site id, or -1.
func grow(sim: RefCounted, cell: Vector3i) -> int:
	var height: int = 4 + sim.rng.randi_range(0, 1)
	for y in range(height):
		var trunk: Vector3i = cell + Vector3i(0, y, 0)
		if not sim.voxels.in_bounds(trunk) or (y > 0 and sim.voxels.get_block(trunk) != 0) or sim.is_occupied(trunk):
			return -1
	saplings.erase(cell)
	var wood: int = Registry.id("log")
	var logs: Array = []
	for y in range(height):
		sim.set_block(cell + Vector3i(0, y, 0), wood, 0, "growth")
		logs.append(cell + Vector3i(0, y, 0))
	var leaves: Array = []
	for leaf in WorldGen.crown_cells(cell, height):
		if sim.voxels.in_bounds(leaf) and sim.voxels.get_block(leaf) == 0 and not sim.is_occupied(leaf):
			sim.set_block(leaf, Registry.id("leaves"), 0, "growth")
			leaves.append(leaf)
	var id: int = sim.sites.add("tree", logs, logs.size() * Registry.yields[wood])
	sim.sites.get_site(id)["leaves"] = leaves
	return id


## How thin the woods near a settlement are: 0 with as many trees and
## saplings as people like nearby, 1 with none.
static func thinness(sim: RefCounted, settlement: Dictionary) -> float:
	var center: Vector3i = settlement.center
	var reach: float = float(settlement.radius) + Balance.number("world.grove_reach")
	var trees: int = 0
	for id in sim.sites.sites:
		var site: Dictionary = sim.sites.sites[id]
		if site.kind == "tree" and not site.cells.is_empty() and _flat(site.cells[0], center) <= reach:
			trees += 1
	for cell in sim.woods.saplings:
		if _flat(cell, center) <= reach:
			trees += 1
	var wanted: int = Balance.integer("world.grove_trees")
	return clampf(float(wanted - trees) / float(wanted), 0.0, 1.0)


## Open ground at the settlement's edge where a tree could be planted: a few
## cells at most, in a stable order.
static func grove_spots(sim: RefCounted, settlement: Dictionary) -> Array:
	var center: Vector3i = settlement.center
	var radius: float = float(settlement.radius)
	var spots: Array = []
	for ring in [3.0, 6.0]:
		for step in range(12):
			var angle: float = step * TAU / 12.0 + ring * 0.25
			var x: int = center.x + roundi(cos(angle) * (radius + ring))
			var z: int = center.z + roundi(sin(angle) * (radius + ring))
			if x < 3 or z < 3 or x >= sim.voxels.size.x - 3 or z >= sim.voxels.size.z - 3:
				continue
			var cell: Vector3i = sim.nav.surface(x, z)
			if cell.x >= 0 and room_for_tree(sim, cell):
				spots.append(cell)
				if spots.size() >= Balance.integer("world.grove_spots"):
					return spots
	return spots


## Whether a tree could stand at `cell`: rooted ground, nobody's building or
## building site, and air for its crown with no trunk or sapling too close.
static func room_for_tree(sim: RefCounted, cell: Vector3i) -> bool:
	if not can_root(sim, cell) or sim.is_reserved_cell(cell) or sim.structure_id_at(cell) >= 0:
		return false
	var tall_grass: int = Registry.id("tall_grass")
	for dy in range(0, 7):
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var block: int = sim.voxels.get_block(cell + Vector3i(dx, dy, dz))
				if block != 0 and block != tall_grass:
					return false
	return true


static func _flat(a: Vector3i, b: Vector3i) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func to_dict() -> Dictionary:
	return {"saplings": saplings.duplicate(), "falling": falling.duplicate()}


func from_dict(data: Dictionary) -> void:
	saplings = data.get("saplings", {}).duplicate()
	falling = data.get("falling", {}).duplicate()
