extends RefCounted
## The sacred tree's qi field: densest under its crown, thinning with
## distance along the curve in cultivation.json. Qi is not spent; it only
## makes cultivation go faster where it is dense. Queried per cell, cached
## per column; the cache is cleared when the field changes.
const Data = preload("res://scripts/core/data.gd")

## Vector2i column -> density
var _cache: Dictionary = {}


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
	if _cache.has(column):
		return _cache[column]
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	var value: float = float(Data.cultivation().qi.floor)
	if tree.x >= 0:
		value = maxf(curve_at(Vector2(cell.x + 0.5, cell.z + 0.5).distance_to(source(sim))), value)
	_cache[column] = value
	return value


func clear_cache() -> void:
	_cache.clear()
