extends RefCounted
## Where people can stand and how they get there. A cell is standable when it
## and the cell above are passable and the cell below is a solid floor. Points
## live in an AStar3D keyed by the voxel index; edits reconnect only the
## columns around them. Pure data: no nodes, no physics.
const Registry = preload("res://scripts/world/block_registry.gd")

const HORIZONTAL: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const CLIMB_COST: float = 0.5
## A worn path's cost to stand on, against 1 for any other ground.
const PATH_WEIGHT: float = 0.85

var world: RefCounted
## The worn path block, looked up when the graph is built.
var _path_block: int = -1
var astar := AStar3D.new()
## Paths found this tick, reset by the sim; agents over the cap wait.
var paths_this_tick: int = 0
var path_cap: int = 12


func _init(target: RefCounted) -> void:
	world = target


## Feet go on opaque solid blocks: not bushes, leaves, fences or beds.
func is_floor(cell: Vector3i) -> bool:
	var block: int = world.get_block(cell)
	return Registry.solid[block] == 1 and Registry.opaque[block] == 1


func is_clear(cell: Vector3i) -> bool:
	return world.in_bounds(cell) and Registry.passable[world.get_block(cell)] == 1


func standable(cell: Vector3i) -> bool:
	return is_clear(cell) and is_clear(cell + Vector3i.UP) and is_floor(cell + Vector3i.DOWN)


func is_walkable(cell: Vector3i) -> bool:
	return astar.has_point(world.index_of(cell)) if world.in_bounds(cell) else false


## Full build from the grid with flat index arithmetic: GDScript call
## overhead dominates here, so the hot loops avoid helper functions.
func build() -> void:
	_path_block = Registry.id("path")
	astar.clear()
	var size: Vector3i = world.size
	var stride_y: int = size.x * size.z
	var blocks: PackedByteArray = world.blocks
	var clear := PackedByteArray()
	var floor := PackedByteArray()
	clear.resize(256)
	floor.resize(256)
	for id in range(Registry.passable.size()):
		clear[id] = Registry.passable[id]
		floor[id] = 1 if Registry.solid[id] == 1 and Registry.opaque[id] == 1 else 0
	var stand := PackedByteArray()
	stand.resize(blocks.size())
	var count: int = 0
	for z in range(size.z):
		for x in range(size.x):
			var column: int = x + z * size.x
			var top: int = mini(world.top_solid_y(x, z) + 1, size.y - 2)
			for y in range(1, top + 1):
				var index: int = column + y * stride_y
				if clear[blocks[index]] == 1 and clear[blocks[index + stride_y]] == 1 and floor[blocks[index - stride_y]] == 1:
					stand[index] = 1
					count += 1
	if count > astar.get_point_capacity():
		astar.reserve_space(count)
	for index in range(stand.size()):
		if stand[index] == 1:
			var cell: Vector3i = world.cell_of(index)
			astar.add_point(index, Vector3(cell), _weight(cell))
	for index in range(stand.size()):
		if stand[index] == 0:
			continue
		var y: int = index / stride_y
		var rest: int = index - y * stride_y
		var x: int = rest % size.x
		var z: int = rest / size.x
		for direction in HORIZONTAL:
			var nx: int = x + direction.x
			var nz: int = z + direction.y
			if nx < 0 or nz < 0 or nx >= size.x or nz >= size.z:
				continue
			var base: int = nx + nz * size.x
			for dy in [0, 1, -1]:
				var ny: int = y + dy
				if ny < 1 or ny >= size.y - 1:
					continue
				var other: int = base + ny * stride_y
				if stand[other] == 0:
					continue
				if (dy != 0 or (direction.x != 0 and direction.y != 0)) and not _can_step(Vector3i(x, y, z), Vector3i(nx, ny, nz)):
					break
				astar.connect_points(index, other, false)
				break


func _add_column(x: int, z: int, y_low: int, y_high: int) -> void:
	for y in range(maxi(y_low, 1), mini(y_high, world.size.y - 2) + 1):
		var cell := Vector3i(x, y, z)
		var id: int = world.index_of(cell)
		var stand: bool = standable(cell)
		if stand and not astar.has_point(id):
			astar.add_point(id, Vector3(x, y, z), _weight(cell))
		elif not stand and astar.has_point(id):
			astar.remove_point(id)


## Standing on a worn path costs a little less, so routes drift onto paths.
func _weight(cell: Vector3i) -> float:
	return PATH_WEIGHT if world.get_block(cell + Vector3i.DOWN) == _path_block else 1.0


## After the ground under a standing place changes (grass worn to path).
func set_ground_weight(ground: Vector3i) -> void:
	var id: int = world.index_of(ground + Vector3i.UP)
	if world.in_bounds(ground + Vector3i.UP) and astar.has_point(id):
		astar.set_point_weight_scale(id, _weight(ground + Vector3i.UP))


func _connect_column(x: int, z: int, y_low: int, y_high: int) -> void:
	for y in range(maxi(y_low, 1), mini(y_high, world.size.y - 2) + 1):
		var cell := Vector3i(x, y, z)
		var id: int = world.index_of(cell)
		if not astar.has_point(id):
			continue
		for direction in HORIZONTAL:
			for dy in [0, 1, -1]:
				var other := Vector3i(x + direction.x, y + dy, z + direction.y)
				if not world.in_bounds(other):
					continue
				var other_id: int = world.index_of(other)
				if not astar.has_point(other_id) or not _can_step(cell, other):
					continue
				if not astar.are_points_connected(id, other_id, false):
					astar.connect_points(id, other_id, false)
				break


## Headroom for climbing and dropping; diagonals need both sides open.
## Steps are at most one block up or down, so every move can be walked back:
## nobody drops into a pit they cannot climb out of.
func _can_step(from: Vector3i, to: Vector3i) -> bool:
	var top: int = maxi(from.y, to.y)
	if to.y > from.y and not is_clear(from + Vector3i(0, 2, 0)):
		return false
	if to.y < from.y:
		for y in range(to.y, from.y + 2):
			if not is_clear(Vector3i(to.x, y, to.z)):
				return false
	if from.x != to.x and from.z != to.z:
		for side in [Vector3i(to.x, top, from.z), Vector3i(from.x, top, to.z)]:
			if not is_clear(side) or not is_clear(side + Vector3i.UP):
				return false
	return true


## Recompute standability around edited cells and reconnect those points.
func update_cells(edits: Array) -> void:
	var relevant: Array = []
	for cell in edits:
		if _matters(cell):
			relevant.append(cell)
	if relevant.is_empty():
		return
	var columns: Dictionary = {}
	for cell in relevant:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var key := Vector2i(cell.x + dx, cell.z + dz)
				var span: Vector2i = columns.get(key, Vector2i(cell.y, cell.y))
				columns[key] = Vector2i(mini(span.x, cell.y), maxi(span.y, cell.y))
	for key in columns:
		if key.x < 0 or key.y < 0 or key.x >= world.size.x or key.y >= world.size.z:
			continue
		_add_column(key.x, key.y, columns[key].x - 3, columns[key].y + 3)
	for key in columns:
		if key.x < 0 or key.y < 0 or key.x >= world.size.x or key.y >= world.size.z:
			continue
		var span: Vector2i = columns[key]
		for y in range(maxi(span.x - 4, 1), mini(span.y + 4, world.size.y - 2) + 1):
			var id: int = world.index_of(Vector3i(key.x, y, key.y))
			if astar.has_point(id):
				for other in astar.get_point_connections(id):
					astar.disconnect_points(id, other, false)
		_connect_column(key.x, key.y, span.x - 4, span.y + 4)
	# Neighbours outside the rebuilt block still need their links back in.
	var ring: Dictionary = {}
	for key in columns:
		for direction in HORIZONTAL:
			var outer: Vector2i = key + direction
			if not columns.has(outer):
				ring[outer] = columns[key]
	for key in ring:
		if key.x >= 0 and key.y >= 0 and key.x < world.size.x and key.y < world.size.z:
			_connect_column(key.x, key.y, ring[key].x - 4, ring[key].y + 4)


## Whether an edit at `cell` can change the graph. Standability reads a
## cell and the ones above and below it; a step's headroom and a diagonal's
## sides read at most two above the lower end. So only points within one
## column of the edit, from two below it to one above, can change: with none
## there before or after (a leaf high in a crown), nothing does.
func _matters(cell: Vector3i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for y in range(cell.y - 2, cell.y + 2):
				var other := Vector3i(cell.x + dx, y, cell.z + dz)
				if world.in_bounds(other) and (astar.has_point(world.index_of(other)) or standable(other)):
					return true
	return false


## Cells from `from` (exclusive) to `to` (inclusive), or [] when unreachable.
func find_path(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if not is_walkable(from) or not is_walkable(to):
		return result
	paths_this_tick += 1
	var ids: PackedInt64Array = astar.get_id_path(world.index_of(from), world.index_of(to))
	for i in range(1, ids.size()):
		result.append(world.cell_of(ids[i]))
	return result


func can_path() -> bool:
	return paths_this_tick < path_cap


## Closest standable cell to `cell` within `radius` cells, or (-1,-1,-1).
func nearest_walkable(cell: Vector3i, radius: int) -> Vector3i:
	if is_walkable(cell):
		return cell
	var best := Vector3i(-1, -1, -1)
	var best_distance: float = INF
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x: int = cell.x + dx
			var z: int = cell.z + dz
			if x < 0 or z < 0 or x >= world.size.x or z >= world.size.z:
				continue
			for dy in range(-4, 5):
				var other := Vector3i(x, cell.y + dy, z)
				if not is_walkable(other):
					continue
				var distance: float = Vector2(dx, dz).length() + absf(dy) * 0.5
				if distance < best_distance or (distance == best_distance and world.index_of(other) < world.index_of(best)):
					best_distance = distance
					best = other
	return best


## A standable cell on the surface of a column, or (-1,-1,-1).
func surface(x: int, z: int) -> Vector3i:
	var top: int = world.top_solid_y(x, z)
	if top < 0:
		return Vector3i(-1, -1, -1)
	return nearest_walkable(Vector3i(x, top + 1, z), 2)


func move_cost(from: Vector3i, to: Vector3i) -> float:
	var flat: float = 1.41 if from.x != to.x and from.z != to.z else 1.0
	return flat + (CLIMB_COST if to.y > from.y else 0.0)
