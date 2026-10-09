extends RefCounted
## A building design: a palette and a grid of palette indices (x + z*sx +
## y*sx*sz), with its entrance, detected functions and materials bill. Block
## names, not ids, are stored so files survive registry changes. Functions,
## capacity and bill are always recomputed, never trusted from a file.
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

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
	template.compute_bill()
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


## Parses an untrusted template file. Returns [template, ""] or [null, reason].
static func from_dict(data: Variant) -> Array:
	if not data is Dictionary:
		return [null, "not a template"]
	if not (data.get("schema_version") is float or data.get("schema_version") is int) or int(data.schema_version) != SCHEMA:
		return [null, "unsupported template version"]
	var limits: Array = Data.template_limits().get("max_size", [16, 12, 16])
	var raw_size: Variant = data.get("size")
	if not raw_size is Array or raw_size.size() != 3:
		return [null, "size must be three numbers"]
	for axis in range(3):
		if not (raw_size[axis] is float or raw_size[axis] is int) or int(raw_size[axis]) < 1 or int(raw_size[axis]) > int(limits[axis]):
			return [null, "size is outside %dx%dx%d" % [limits[0], limits[1], limits[2]]]
	var raw_palette: Variant = data.get("palette")
	var max_palette: int = int(Data.template_limits().get("max_palette", 32))
	if not raw_palette is Array or raw_palette.is_empty() or raw_palette.size() > max_palette or raw_palette[0] != "air":
		return [null, "palette must start with air and hold at most %d blocks" % max_palette]
	for entry in raw_palette:
		if not entry is String or Data.block_id(entry) < 0:
			return [null, "palette names an unknown block: " + str(entry)]
		if entry != "air" and not bool(Data.block(Data.block_id(entry)).get("placeable", false)):
			return [null, "palette holds a block that cannot be built: " + str(entry)]
	if not data.get("blocks") is String:
		return [null, "blocks are missing"]
	var bytes: PackedByteArray = Marshalls.base64_to_raw(data.blocks)
	var expected: int = int(raw_size[0]) * int(raw_size[1]) * int(raw_size[2])
	if bytes.size() != expected:
		return [null, "blocks do not match the size"]
	for value in bytes:
		if value >= raw_palette.size():
			return [null, "a block points outside the palette"]
	var template = load("res://scripts/building/template.gd").new()
	template.id = str(data.get("id", "")).validate_filename().left(64)
	template.name = str(data.get("name", "Untitled")).strip_edges().left(40)
	template.author = str(data.get("author", "unknown")).left(40)
	template.size = Vector3i(int(raw_size[0]), int(raw_size[1]), int(raw_size[2]))
	template.palette = raw_palette.duplicate()
	template.cells = bytes
	var raw_meta: Variant = data.get("meta", {})
	if raw_meta is Dictionary:
		for key in raw_meta:
			if str(key).is_valid_int() and int(key) >= 0 and int(key) < expected and (raw_meta[key] is float or raw_meta[key] is int):
				template.meta[int(key)] = clampi(int(raw_meta[key]), 0, 3)
	var raw_entrance: Variant = data.get("entrance", [0, 0, 0])
	if raw_entrance is Array and raw_entrance.size() == 3:
		template.entrance = Vector3i(clampi(int(raw_entrance[0]), 0, template.size.x - 1), clampi(int(raw_entrance[1]), 0, template.size.y - 1), clampi(int(raw_entrance[2]), 0, template.size.z - 1))
	template.compute_bill()
	if template.block_count() == 0:
		return [null, "the design is empty"]
	if template.id.is_empty():
		template.id = template.name.to_snake_case().validate_filename() + "_" + str(abs(hash(bytes)) % 65536)
	return [template, ""]
