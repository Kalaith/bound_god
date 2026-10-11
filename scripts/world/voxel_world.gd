extends RefCounted
## The block grid. One flat PackedByteArray (index x + z*W + y*W*D) is far
## faster in GDScript than a dictionary of chunk arrays; chunks remain the unit
## of meshing, dirtiness and saving. Never touches nodes.
const Registry = preload("res://scripts/world/block_registry.gd")

const CHUNK: int = 16

var size := Vector3i(160, 48, 160)
var chunks := Vector3i(10, 3, 10)
var blocks := PackedByteArray()
## Sparse per-cell state: cell index -> int (door orientation, bush berries).
var meta: Dictionary = {}
## Chunk coords whose mesh is stale: Vector3i -> true.
var _dirty: Dictionary = {}
## Cells changed since the simulation last looked (navigation, structures).
var _edits: Array[Vector3i] = []
## Chunks changed since generation, for saving only what differs.
var edited_chunks: Dictionary = {}
## Living cuttings of the sacred tree (cell -> true), kept by faith.gd so
## function rules, which see only the world, can read the qi they carry.
var qi_sources: Dictionary = {}
## A region's natural spirit springs (cell -> peak qi), fixed at generation (M22).
var qi_wells: Dictionary = {}
var stride_z: int = 160
var stride_y: int = 25600


func _init(world_size: Vector3i = Vector3i(160, 48, 160)) -> void:
	Registry.build()
	size = world_size
	chunks = Vector3i(ceili(size.x / float(CHUNK)), ceili(size.y / float(CHUNK)), ceili(size.z / float(CHUNK)))
	stride_z = size.x
	stride_y = size.x * size.z
	blocks.resize(size.x * size.y * size.z)


func in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < size.x and cell.y < size.y and cell.z < size.z


func index_of(cell: Vector3i) -> int:
	return cell.x + cell.z * stride_z + cell.y * stride_y


func cell_of(index: int) -> Vector3i:
	var y: int = index / stride_y
	var rest: int = index - y * stride_y
	return Vector3i(rest % stride_z, y, rest / stride_z)


## Below the world is bedrock; outside it on the sides and above is air.
func get_block(cell: Vector3i) -> int:
	if cell.y < 0:
		return 8
	if not in_bounds(cell):
		return 0
	return blocks[cell.x + cell.z * stride_z + cell.y * stride_y]


func get_xyz(x: int, y: int, z: int) -> int:
	if y < 0:
		return 8
	if x < 0 or z < 0 or x >= size.x or z >= size.z or y >= size.y:
		return 0
	return blocks[x + z * stride_z + y * stride_y]


func block_meta(cell: Vector3i) -> int:
	return int(meta.get(index_of(cell), 0))


func set_block_meta(cell: Vector3i, value: int) -> void:
	var index: int = index_of(cell)
	if value == 0:
		meta.erase(index)
	else:
		meta[index] = value
	_mark(cell)


## Generation writes go through here: no dirtiness, no edit log.
func fill(cell: Vector3i, id: int) -> void:
	if in_bounds(cell):
		blocks[cell.x + cell.z * stride_z + cell.y * stride_y] = id


func set_block(cell: Vector3i, id: int, value: int = 0) -> bool:
	if not in_bounds(cell):
		return false
	var index: int = index_of(cell)
	if blocks[index] == id and block_meta(cell) == value:
		return false
	blocks[index] = id
	if value == 0:
		meta.erase(index)
	else:
		meta[index] = value
	_mark(cell)
	_edits.append(cell)
	edited_chunks[Vector3i(cell.x >> 4, cell.y >> 4, cell.z >> 4)] = true
	return true


func _mark(cell: Vector3i) -> void:
	var chunk := Vector3i(cell.x >> 4, cell.y >> 4, cell.z >> 4)
	_dirty[chunk] = true
	# Faces and ambient occlusion of a neighbouring chunk can change too.
	var local := Vector3i(cell.x & 15, cell.y & 15, cell.z & 15)
	for axis in range(3):
		if local[axis] <= 1:
			var other: Vector3i = chunk
			other[axis] -= 1
			if other[axis] >= 0:
				_dirty[other] = true
		elif local[axis] >= 14:
			var other: Vector3i = chunk
			other[axis] += 1
			if other[axis] < chunks[axis]:
				_dirty[other] = true


func take_dirty_chunks() -> Array:
	var result: Array = _dirty.keys()
	_dirty.clear()
	return result


func take_edits() -> Array[Vector3i]:
	var result: Array[Vector3i] = _edits
	_edits = []
	return result


func is_solid(cell: Vector3i) -> bool:
	return Registry.solid[get_block(cell)] == 1


func is_passable(cell: Vector3i) -> bool:
	return Registry.passable[get_block(cell)] == 1


## Highest solid block in a column, or -1.
func top_solid_y(x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= size.x or z >= size.z:
		return -1
	var index: int = x + z * stride_z + (size.y - 1) * stride_y
	for y in range(size.y - 1, -1, -1):
		if Registry.solid[blocks[index]] == 1:
			return y
		index -= stride_y
	return -1


## A roof is any opaque block within `reach` cells above.
func is_roofed(cell: Vector3i, reach: int = 8) -> bool:
	for dy in range(1, reach + 1):
		var y: int = cell.y + dy
		if y >= size.y:
			return false
		if Registry.opaque[get_xyz(cell.x, y, cell.z)] == 1:
			return true
	return false


## Open sky straight up from a cell (nothing solid above it).
func sees_sky(cell: Vector3i) -> bool:
	for y in range(cell.y + 1, size.y):
		if Registry.solid[get_xyz(cell.x, y, cell.z)] == 1:
			return false
	return true


func chunk_bytes(chunk: Vector3i) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(CHUNK * CHUNK * CHUNK)
	var origin := chunk * CHUNK
	var write: int = 0
	for y in range(CHUNK):
		for z in range(CHUNK):
			for x in range(CHUNK):
				result[write] = get_xyz(origin.x + x, origin.y + y, origin.z + z)
				write += 1
	return result


func load_chunk_bytes(chunk: Vector3i, bytes: PackedByteArray) -> void:
	var origin := chunk * CHUNK
	var read: int = 0
	for y in range(CHUNK):
		for z in range(CHUNK):
			for x in range(CHUNK):
				var cell := Vector3i(origin.x + x, origin.y + y, origin.z + z)
				if in_bounds(cell):
					blocks[index_of(cell)] = bytes[read]
				read += 1
	edited_chunks[chunk] = true
	_dirty[chunk] = true


## A stable fingerprint of the whole grid and its metadata.
func hash_state() -> int:
	var keys: Array = meta.keys()
	keys.sort()
	var meta_list: Array = []
	for key in keys:
		meta_list.append([key, meta[key]])
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	context.update(blocks)
	return hash([context.finish().hex_encode(), meta_list])
