extends RefCounted
## Face-culled meshing of one 16^3 chunk into plain arrays (no nodes). The
## chunk is first copied with a one-cell border into a padded 18^3 array using
## native row slices, so every neighbour and ambient-occlusion test is a local
## index lookup. Three surfaces: opaque, cutout (leaves, grass, glass, bushes)
## and water; plus collision triangles for solid faces bordering non-solid cells.
const Registry = preload("res://scripts/world/block_registry.gd")

const SURFACE_OPAQUE: int = 0
const SURFACE_CUTOUT: int = 1
const SURFACE_WATER: int = 2
const AO_LEVELS: Array[float] = [0.5, 0.68, 0.84, 1.0]
const WATER_ID: int = 7
const DOOR_OPEN: int = Registry.DOOR_OPEN
const P: int = 18
const PP: int = 324

const NORMALS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
## Unit-cube corners per face, wound clockwise seen from outside (Godot's front faces).
static var CORNERS: Array = [
	[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1)],
	[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)],
	[Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)],
]
const SHADE: Array[float] = [0.86, 0.86, 1.0, 0.62, 0.78, 0.78]
static var _ready: bool = false
## Padded-index offset of the neighbour across each face.
static var FACE_OFFSET := PackedInt32Array()
## Per face, per corner: three padded offsets (side, side, diagonal) for AO.
static var AO_OFFSET: Array = []
## Per face: the four corner UVs in unit tile space.
static var FACE_UV: Array = []


## Builds the lookup tables. Call once on the main thread before any worker
## meshes (WorldView.build_all does), so threads only ever read them.
static func prepare() -> void:
	if _ready:
		return
	Registry.build()
	for face in range(6):
		var c: Array = CORNERS[face]
		var cross: Vector3 = (c[1] - c[0]).cross(c[2] - c[0])
		if cross.dot(Vector3(NORMALS[face])) > 0.0:
			CORNERS[face] = [c[0], c[3], c[2], c[1]]
	for face in range(6):
		var n: Vector3i = NORMALS[face]
		FACE_OFFSET.append(_offset(n))
		var axis: int = 0 if n.x != 0 else (1 if n.y != 0 else 2)
		var t1: int = (axis + 1) % 3
		var t2: int = (axis + 2) % 3
		var corner_offsets: Array = []
		var uvs: Array = []
		for corner in CORNERS[face]:
			var s1 := Vector3i.ZERO
			var s2 := Vector3i.ZERO
			s1[t1] = 1 if corner[t1] > 0.5 else -1
			s2[t2] = 1 if corner[t2] > 0.5 else -1
			corner_offsets.append(PackedInt32Array([_offset(n + s1), _offset(n + s2), _offset(n + s1 + s2)]))
			uvs.append(_uv(corner, face))
		AO_OFFSET.append(corner_offsets)
		FACE_UV.append(uvs)
	_ready = true


static func _offset(v: Vector3i) -> int:
	return v.x + v.z * P + v.y * PP


static func _uv(corner: Vector3, face: int) -> Vector2:
	match face:
		0:
			return Vector2(1.0 - corner.z, 1.0 - corner.y)
		1:
			return Vector2(corner.z, 1.0 - corner.y)
		4:
			return Vector2(corner.x, 1.0 - corner.y)
		5:
			return Vector2(1.0 - corner.x, 1.0 - corner.y)
	return Vector2(corner.x, corner.z)


## The chunk plus a one-cell border as block ids; outside the world is air
## (bedrock below), matching VoxelWorld.get_block.
static func padded(world: RefCounted, origin: Vector3i) -> PackedByteArray:
	var size: Vector3i = world.size
	var blocks: PackedByteArray = world.blocks
	var result := PackedByteArray()
	var empty := PackedByteArray()
	empty.resize(P)
	var bedrock := PackedByteArray()
	bedrock.resize(P)
	bedrock.fill(8)
	var one := PackedByteArray([0])
	# Rows are appended in layout order (x fastest, then z, then y).
	for py in range(P):
		var y: int = origin.y + py - 1
		for pz in range(P):
			var z: int = origin.z + pz - 1
			if y < 0:
				result.append_array(bedrock)
				continue
			if y >= size.y or z < 0 or z >= size.z:
				result.append_array(empty)
				continue
			var start: int = result.size()
			var x0: int = origin.x - 1
			var x1: int = mini(origin.x + 17, size.x)
			if x0 < 0:
				result.append_array(one)
				x0 = 0
			var row: int = z * world.stride_z + y * world.stride_y
			result.append_array(blocks.slice(row + x0, row + x1))
			# Air past the world's far edge.
			result.resize(start + P)
	return result


## Returns {surfaces: [opaque, cutout, water] (dictionaries of packed arrays),
## collision: PackedVector3Array}.
static func build(world: RefCounted, chunk: Vector3i) -> Dictionary:
	prepare()
	var origin: Vector3i = chunk * 16
	var pad: PackedByteArray = padded(world, origin)
	var verts: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var normals: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var uvs: Array = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	var colors: Array = [PackedColorArray(), PackedColorArray(), PackedColorArray()]
	var indices: Array = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	var collision := PackedVector3Array()
	var result: Dictionary = {"surfaces": [], "collision": collision}
	for s in range(3):
		result.surfaces.append({"verts": verts[s], "normals": normals[s], "uvs": uvs[s], "colors": colors[s], "indices": indices[s]})
	# A chunk with no air and nothing see-through inside or around has no faces.
	var opaque_table: PackedByteArray = Registry.opaque
	var solid_table: PackedByteArray = Registry.solid
	var shape_table: PackedByteArray = Registry.shape
	var tiles: Array = Registry.tiles
	var empty_tiles: Dictionary = Registry.empty_tiles
	var tile_size := Vector2(1.0 / Registry.atlas_size.x, 1.0 / Registry.atlas_size.y)
	var inset: Vector2 = tile_size * 0.002
	var span: Vector2 = tile_size - inset * 2.0
	for py in range(1, 17):
		for pz in range(1, 17):
			var row: int = pz * P + py * PP
			for px in range(1, 17):
				var pi: int = row + px
				var block: int = pad[pi]
				if block == 0:
					continue
				var cell := Vector3i(origin.x + px - 1, origin.y + py - 1, origin.z + pz - 1)
				if shape_table[block] != Registry.SHAPE_CUBE:
					_special(world, cell, block, shape_table[block], result.surfaces, collision, tile_size)
					continue
				var opaque: bool = opaque_table[block] == 1
				var solid: bool = solid_table[block] == 1
				var s: int = SURFACE_OPAQUE if opaque else (SURFACE_WATER if block == WATER_ID else SURFACE_CUTOUT)
				var at := Vector3(cell)
				var faces: Array = tiles[block]
				if empty_tiles.has(block) and world.block_meta(cell) == 0:
					faces = [empty_tiles[block], empty_tiles[block], empty_tiles[block]]
				for face in range(6):
					var neighbour: int = pad[pi + FACE_OFFSET[face]]
					if solid and solid_table[neighbour] == 0:
						var c: Array = CORNERS[face]
						collision.append_array([at + c[0], at + c[1], at + c[2], at + c[0], at + c[2], at + c[3]])
					if opaque_table[neighbour] == 1 or (not opaque and neighbour == block):
						continue
					if block == WATER_ID and solid_table[neighbour] == 1:
						continue
					var tile: Vector2i = faces[1 if face == 2 else (2 if face == 3 else 0)]
					var base_uv := Vector2(tile.x * tile_size.x, tile.y * tile_size.y) + inset
					var shade: float = SHADE[face] * (0.96 + float((cell.x * 7 + cell.y * 13 + cell.z * 5) % 9) * 0.01)
					var start: int = verts[s].size()
					var ao0: int = 3
					var ao1: int = 3
					var ao2: int = 3
					var ao3: int = 3
					if opaque:
						var corner_offsets: Array = AO_OFFSET[face]
						var levels: Array = [3, 3, 3, 3]
						for k in range(4):
							var o: PackedInt32Array = corner_offsets[k]
							var a: int = opaque_table[pad[pi + o[0]]]
							var b: int = opaque_table[pad[pi + o[1]]]
							levels[k] = 0 if a + b == 2 else 3 - a - b - opaque_table[pad[pi + o[2]]]
						ao0 = levels[0]
						ao1 = levels[1]
						ao2 = levels[2]
						ao3 = levels[3]
					var c: Array = CORNERS[face]
					var face_uv: Array = FACE_UV[face]
					var n := Vector3(NORMALS[face])
					var drop := Vector3(0, 0.12, 0) if block == WATER_ID and face == 2 else Vector3.ZERO
					verts[s].append_array([at + c[0] - drop, at + c[1] - drop, at + c[2] - drop, at + c[3] - drop])
					normals[s].append_array([n, n, n, n])
					uvs[s].append_array([base_uv + face_uv[0] * span, base_uv + face_uv[1] * span, base_uv + face_uv[2] * span, base_uv + face_uv[3] * span])
					var l0: float = AO_LEVELS[ao0] * shade
					var l1: float = AO_LEVELS[ao1] * shade
					var l2: float = AO_LEVELS[ao2] * shade
					var l3: float = AO_LEVELS[ao3] * shade
					colors[s].append_array([Color(l0, l0, l0), Color(l1, l1, l1), Color(l2, l2, l2), Color(l3, l3, l3)])
					# Flip the split so occlusion interpolates without a crease.
					if ao0 + ao2 < ao1 + ao3:
						indices[s].append_array([start + 1, start + 2, start + 3, start + 1, start + 3, start])
					else:
						indices[s].append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	return result


## Slabs (beds), panels (doors), posts (fences) and crosses (tall grass).
static func _special(world: RefCounted, cell: Vector3i, block: int, shape: int, surfaces: Array, collision: PackedVector3Array, tile_size: Vector2) -> void:
	var at := Vector3(cell)
	if shape == Registry.SHAPE_CROSS:
		var surface: Dictionary = surfaces[SURFACE_CUTOUT]
		var tile: Vector2i = Registry.tiles[block][0]
		var base_uv := Vector2(tile.x * tile_size.x, tile.y * tile_size.y)
		var quads: Array = [
			[Vector3(0.1, 0, 0.1), Vector3(0.9, 0, 0.9), Vector3(0.9, 1, 0.9), Vector3(0.1, 1, 0.1)],
			[Vector3(0.9, 0, 0.1), Vector3(0.1, 0, 0.9), Vector3(0.1, 1, 0.9), Vector3(0.9, 1, 0.1)],
		]
		for quad in quads:
			var start: int = surface.verts.size()
			var corner_uvs: Array = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			for index in range(4):
				surface.verts.append(at + quad[index])
				surface.normals.append(Vector3.UP)
				surface.uvs.append(base_uv + corner_uvs[index] * tile_size)
				surface.colors.append(Color(0.95, 0.95, 0.95))
			surface.indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
		return
	var low := Vector3.ZERO
	var high := Vector3.ONE
	match shape:
		Registry.SHAPE_SLAB:
			high.y = 0.5625
		Registry.SHAPE_POST:
			low = Vector3(0.35, 0.0, 0.35)
			high = Vector3(0.65, 1.0, 0.65)
		Registry.SHAPE_PANEL:
			# Bit 0 is which way a door faces; bit 1 means it stands open,
			# swung back against its hinge side.
			var value: int = world.block_meta(cell)
			var open: bool = value & DOOR_OPEN != 0
			if value % 2 == 0:
				if open:
					high.x = 0.16
				else:
					low.z = 0.42
					high.z = 0.58
			elif open:
				high.z = 0.16
			else:
				low.x = 0.42
				high.x = 0.58
	var surface: Dictionary = surfaces[SURFACE_OPAQUE]
	for face in range(6):
		var n: Vector3i = NORMALS[face]
		if face == 3 and Registry.opaque[world.get_block(cell + n)] == 1:
			continue
		var tile: Vector2i = Registry.tiles[block][1 if face == 2 else (2 if face == 3 else 0)]
		var base_uv := Vector2(tile.x * tile_size.x, tile.y * tile_size.y)
		var start: int = surface.verts.size()
		for index in range(4):
			var corner: Vector3 = CORNERS[face][index]
			var local := Vector3(lerpf(low.x, high.x, corner.x), lerpf(low.y, high.y, corner.y), lerpf(low.z, high.z, corner.z))
			surface.verts.append(at + local)
			surface.normals.append(Vector3(n))
			surface.uvs.append(base_uv + _uv(local, face) * tile_size * 0.998)
			var light: float = SHADE[face]
			surface.colors.append(Color(light, light, light))
		surface.indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	if Registry.solid[block] == 1:
		for face in range(6):
			var c: Array = CORNERS[face]
			collision.append_array([at + c[0], at + c[1], at + c[2], at + c[0], at + c[2], at + c[3]])
	elif shape == Registry.SHAPE_PANEL and world.block_meta(cell) & DOOR_OPEN == 0:
		# A shut door stops the avatar; people open doors as they pass.
		for face in range(6):
			var c: Array = CORNERS[face]
			var quad: Array = []
			for corner in c:
				quad.append(at + Vector3(lerpf(low.x, high.x, corner.x), lerpf(low.y, high.y, corner.y), lerpf(low.z, high.z, corner.z)))
			collision.append_array([quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]])
