extends RefCounted
## Exact voxel traversal (Amanatides-Woo DDA) from a point along a direction.
## Returns the first targetable block and the face it was entered through;
## independent of physics. Air and water are passed through.
const Registry = preload("res://scripts/world/block_registry.gd")

const WATER_ID: int = 7


## {hit: bool, cell: Vector3i, normal: Vector3i, block: int, distance: float}
static func cast(world: RefCounted, origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var miss: Dictionary = {"hit": false, "cell": Vector3i.ZERO, "normal": Vector3i.ZERO, "block": 0, "distance": max_distance}
	if direction.length_squared() < 0.000001:
		return miss
	var dir: Vector3 = direction.normalized()
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for axis in range(3):
		if step[axis] == 0:
			t_max[axis] = INF
			t_delta[axis] = INF
		else:
			var boundary: float = float(cell[axis] + (1 if step[axis] > 0 else 0))
			t_max[axis] = (boundary - origin[axis]) / dir[axis]
			t_delta[axis] = absf(1.0 / dir[axis])
	var normal := Vector3i.ZERO
	var travelled: float = 0.0
	while travelled <= max_distance:
		var block: int = world.get_block(cell)
		if block != 0 and block != WATER_ID and cell.y >= 0:
			return {"hit": true, "cell": cell, "normal": normal, "block": block, "distance": travelled}
		var axis: int = 0
		if t_max.y < t_max[axis]:
			axis = 1
		if t_max.z < t_max[axis]:
			axis = 2
		travelled = t_max[axis]
		t_max[axis] += t_delta[axis]
		cell[axis] += step[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
		if cell.y < -1 or cell.y > world.size.y + 1:
			break
	return miss
