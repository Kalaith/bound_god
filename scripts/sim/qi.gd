extends RefCounted
## The sacred tree's qi field: densest under its crown, thinning with
## distance along the curve in cultivation.json. Qi is not spent; it only
## makes cultivation go faster where it is dense. Queried per cell, cached
## per column; the cache is cleared when the field changes.
const Data = preload("res://scripts/core/data.gd")
const Balance = preload("res://scripts/core/balance.gd")
const SectHalls = preload("res://scripts/sim/sect_halls.gd")
const TreeAbilities = preload("res://scripts/sim/tree_abilities.gd")

## Vector2i column -> density
var _cache: Dictionary = {}
## The structures' version the cache was filled at (arrays come and go).
var _version: int = -1


static func curve_at(distance: float) -> float:
	var qi: Dictionary = Data.cultivation().qi
	var points: Array = qi.curve
	if distance <= float(points[0][0]):
		return float(points[0][1])
	for i in range(1, points.size()):
		if distance <= float(points[i][0]):
			var a: Array = points[i - 1]
			var b: Array = points[i]
			var t: float = (distance - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return lerpf(float(a[1]), float(b[1]), t)
	return float(qi.floor)


## The tree's trunk centre in the xz plane.
static func source(sim: RefCounted) -> Vector2:
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	return Vector2(tree.x + 1.0, tree.z + 1.0)


func density(sim: RefCounted, cell: Vector3i) -> float:
	var column := Vector2i(cell.x, cell.z)
	if sim.structures.version != _version:
		_version = sim.structures.version
		_cache.clear()
	if _cache.has(column):
		return _cache[column]
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	var value: float = float(Data.cultivation().qi.floor)
	if tree.x >= 0:
		value = maxf(curve_at(Vector2(cell.x + 0.5, cell.z + 0.5).distance_to(source(sim))), value)
	# Spots the god has nurtured hold dense qi for a season.
	if sim.tree_growth != null:
		for spot in sim.tree_growth.nurtured:
			var d: float = Vector2(cell.x - spot.cell.x, cell.z - spot.cell.z).length()
			if d <= float(spot.radius):
				value = maxf(value, float(spot.qi) * (1.0 - 0.3 * d / maxf(float(spot.radius), 0.1)))
	# A sect's spirit-gathering array holds dense qi round it.
	value = maxf(value, SectHalls.array_qi(sim, cell))
	# The root network carries qi along the worn paths it reaches.
	value = maxf(value, TreeAbilities.root_qi(sim, column))
	# A living cutting of the tree carries its qi to a branch.
	value = maxf(value, cutting_qi(sim.voxels, cell))
	_cache[column] = value
	return value


## Qi round a living cutting of the tree (M21), dense at its stem and gone
## by `branches.cutting_curve`'s last point.
static func cutting_curve(distance: float) -> float:
	var points: Array = Balance.list("branches.cutting_curve")
	if distance <= float(points[0][0]):
		return float(points[0][1])
	for i in range(1, points.size()):
		if distance <= float(points[i][0]):
			var a: Array = points[i - 1]
			var b: Array = points[i]
			return lerpf(float(a[1]), float(b[1]), (distance - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
	return 0.0


## The densest qi any living cutting in `world` gives a cell.
static func cutting_qi(world: RefCounted, cell: Vector3i) -> float:
	var best: float = 0.0
	for at in world.qi_sources:
		best = maxf(best, cutting_curve(Vector2(cell.x - at.x, cell.z - at.z).length()))
	return best


func clear_cache() -> void:
	_cache.clear()
