extends RefCounted
## A building design: a palette and a grid of palette indices (x + z*sx +
## y*sx*sz), with its entrance, detected functions and materials bill. Block
## names, not ids, are stored so files survive registry changes. Functions,
## capacity and bill are always recomputed, never trusted from a file.
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

const TemplateValidation = preload("res://scripts/building/template_validation.gd")
const VoxelWorld = preload("res://scripts/world/voxel_world.gd")
const RoomProbe = preload("res://scripts/world/room_probe.gd")
const Rules = preload("res://scripts/building/function_rules.gd")

const SCHEMA: int = 1

var id: String = ""
var name: String = ""
var author: String = "local"
var size := Vector3i.ONE
var palette: Array = ["air"]
var cells := PackedByteArray()
## Palette-grid index -> meta value (door orientation).
var meta: Dictionary = {}
var entrance := Vector3i.ZERO
var functions: Array = []
var capacity: Dictionary = {}
var bill: Dictionary = {}


func index_of(local: Vector3i) -> int:
	return local.x + local.z * size.x + local.y * size.x * size.z


func block_at(local: Vector3i) -> int:
	if local.x < 0 or local.y < 0 or local.z < 0 or local.x >= size.x or local.y >= size.y or local.z >= size.z:
		return 0
	return Registry.id(palette[cells[index_of(local)]])


func meta_at(local: Vector3i) -> int:
	return int(meta.get(index_of(local), 0))


## Size after rotating by `rotation` quarter turns (clockwise from above).
func rotated_size(rotation: int) -> Vector3i:
	return Vector3i(size.z, size.y, size.x) if rotation % 2 == 1 else size


func rotate_local(local: Vector3i, rotation: int) -> Vector3i:
	match rotation % 4:
		1:
			return Vector3i(size.z - 1 - local.z, local.y, local.x)
		2:
			return Vector3i(size.x - 1 - local.x, local.y, size.z - 1 - local.z)
		3:
			return Vector3i(local.z, local.y, size.x - 1 - local.x)
	return local


## Every non-air cell as [offset, block id, meta], bottom layer first and
## outer walls before interior, so a structure visibly rises.
func placement(rotation: int) -> Array:
	var result: Array = []
	var centre := Vector2((size.x - 1) * 0.5, (size.z - 1) * 0.5)
	for y in range(size.y):
		var layer: Array = []
		for z in range(size.z):
			for x in range(size.x):
				var local := Vector3i(x, y, z)
				var block: int = block_at(local)
				if block == 0:
					continue
				var value: int = meta_at(local)
				if Registry.component(block) == "door" and rotation % 2 == 1:
					value = 1 - value
				var outer: float = maxf(absf(x - centre.x) / maxf(centre.x, 0.5), absf(z - centre.y) / maxf(centre.y, 0.5))
				layer.append([rotate_local(local, rotation), block, value, outer])
		layer.sort_custom(func(a: Array, b: Array) -> bool:
			if a[3] != b[3]:
				return a[3] > b[3]
			if a[0].z != b[0].z:
				return a[0].z < b[0].z
			return a[0].x < b[0].x)
		for entry in layer:
			result.append([entry[0], entry[1], entry[2]])
	return result


func compute_bill() -> void:
	bill = {}
	for index in range(cells.size()):
		var block: int = Registry.id(palette[cells[index]])
		var resource: String = Registry.resource(block)
		if block == 0 or resource.is_empty():
			continue
		bill[resource] = int(bill.get(resource, 0)) + 1


func block_count() -> int:
	var total: int = 0
	for index in range(cells.size()):
		if palette[cells[index]] != "air":
			total += 1
	return total


static func from_starter(def: Dictionary) -> RefCounted:
	var template = load("res://scripts/building/template.gd").new()
	template.id = str(def.id)
	template.name = str(def.name)
	template.author = str(def.get("author", "local"))
	var layers: Array = def.layers
	template.size = Vector3i(str(layers[0][0]).length(), layers.size(), layers[0].size())
	var legend: Dictionary = def.legend
	template.palette = ["air"]
	for key in legend:
		if not template.palette.has(legend[key]):
			template.palette.append(legend[key])
	template.cells.resize(template.size.x * template.size.y * template.size.z)
	for y in range(template.size.y):
		for z in range(template.size.z):
			var row: String = str(layers[y][z])
			for x in range(template.size.x):
				template.cells[template.index_of(Vector3i(x, y, z))] = template.palette.find(legend[row[x]])
	var door: Array = def.get("entrance", [0, 0, 0])
	template.entrance = Vector3i(int(door[0]), int(door[1]), int(door[2]))
	template.recompute()
	return template


func to_dict() -> Dictionary:
	var meta_out: Dictionary = {}
	for key in meta:
		meta_out[str(key)] = int(meta[key])
	return {
		"schema_version": SCHEMA, "id": id, "name": name, "author": author,
		"size": [size.x, size.y, size.z], "palette": palette.duplicate(),
		"blocks": Marshalls.raw_to_base64(cells), "meta": meta_out,
		"entrance": [entrance.x, entrance.y, entrance.z],
		"functions": functions.duplicate(), "capacity": capacity.duplicate(), "bill": bill.duplicate(),
	}


## Parses an untrusted design without repairing malformed values silently.
static func from_dict(data: Variant) -> Array:
	var problem: String = TemplateValidation.problem(data)
	if not problem.is_empty():
		return [null, problem]
	var template: RefCounted = load("res://scripts/building/template.gd").new()
	template.id = data.id
	template.name = data.name
	template.author = data.author
	template.size = Vector3i(int(data.size[0]), int(data.size[1]), int(data.size[2]))
	template.palette = data.palette.duplicate()
	template.cells = Marshalls.base64_to_raw(data.blocks)
	for key in data.meta:
		template.meta[int(key)] = int(data.meta[key])
	template.recompute()
	return [template, ""]


func recompute() -> void:
	compute_bill()
	var world := VoxelWorld.new(size)
	for y in range(size.y):
		for z in range(size.z):
			for x in range(size.x):
				var cell := Vector3i(x, y, z)
				world.fill(cell, block_at(cell))
	var seen: Dictionary = {}
	functions = []
	capacity = {}
	entrance = Vector3i.ZERO
	var found_door: bool = false
	for index in range(world.blocks.size()):
		var cell: Vector3i = world.cell_of(index)
		var kind: String = Registry.component(world.blocks[index])
		if kind == "door" and not found_door:
			entrance = cell
			found_door = true
		if not kind in RoomProbe.ANCHORS or seen.has(cell):
			continue
		var room: Dictionary = RoomProbe.probe(world, cell)
		seen.merge(room.inside)
		var result: Dictionary = Rules.evaluate(world, room.cells)
		for function in result.functions:
			if not functions.has(function):
				functions.append(function)
		for key in result.capacity:
			capacity[key] = int(capacity.get(key, 0)) + int(result.capacity[key])
	functions.sort()
