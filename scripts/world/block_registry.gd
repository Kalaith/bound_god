extends RefCounted
## Fast per-id lookups over data/blocks.json for the hot paths (meshing,
## navigation, probes). Built once; every table is indexed by block id.
const Data = preload("res://scripts/core/data.gd")

const AIR: int = 0
const SHAPE_CUBE: int = 0
const SHAPE_CROSS: int = 1
const SHAPE_PANEL: int = 2
const SHAPE_SLAB: int = 3
const SHAPE_POST: int = 4
const SHAPES: Array[String] = ["cube", "cross", "panel", "slab", "post"]
## Door meta: bit 0 is the facing, this bit means the door stands open.
const DOOR_OPEN: int = 2

static var _built: bool = false
static var solid := PackedByteArray()
static var opaque := PackedByteArray()
static var passable := PackedByteArray()
static var transparent := PackedByteArray()
static var breakable := PackedByteArray()
static var placeable := PackedByteArray()
static var shape := PackedByteArray()
## Atlas tile per face group: [side, top, bottom] as Vector2i.
static var tiles: Array = []
## Atlas tile for a block whose meta is 0 (a picked bush), by block id.
static var empty_tiles: Dictionary = {}
static var components: Array = []
static var resources: Array = []
static var yields := PackedInt32Array()
static var names: Array = []
static var ids: Dictionary = {}
static var atlas_size := Vector2i(8, 5)


static func build() -> void:
	if _built:
		return
	_built = true
	for table in [solid, opaque, passable, transparent, breakable, placeable, shape]:
		table.resize(256)
	yields.resize(256)
	tiles.resize(256)
	components.resize(256)
	resources.resize(256)
	names.resize(256)
	var size: Array = Data.file("blocks").get("atlas_size", [8, 5])
	atlas_size = Vector2i(int(size[0]), int(size[1]))
	for index in range(256):
		components[index] = ""
		resources[index] = ""
		names[index] = ""
		tiles[index] = [Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO]
		passable[index] = 1 if index == AIR else 0
	for entry in Data.blocks():
		var id: int = int(entry.id)
		solid[id] = int(bool(entry.solid))
		opaque[id] = int(bool(entry.opaque))
		passable[id] = int(bool(entry.passable))
		transparent[id] = int(bool(entry.transparent))
		breakable[id] = int(bool(entry.breakable))
		placeable[id] = int(bool(entry.placeable))
		shape[id] = maxi(SHAPES.find(str(entry.shape)), 0)
		yields[id] = int(entry.get("yield", 0))
		components[id] = str(entry.get("component", ""))
		resources[id] = str(entry.get("resource", ""))
		names[id] = str(entry.name)
		ids[str(entry.name)] = id
		var side := Vector2i(int(entry.atlas[0]), int(entry.atlas[1]))
		var top: Vector2i = side
		var bottom: Vector2i = side
		if entry.has("atlas_top"):
			top = Vector2i(int(entry.atlas_top[0]), int(entry.atlas_top[1]))
		if entry.has("atlas_bottom"):
			bottom = Vector2i(int(entry.atlas_bottom[0]), int(entry.atlas_bottom[1]))
		tiles[id] = [side, top, bottom]
		if entry.has("atlas_empty"):
			empty_tiles[id] = Vector2i(int(entry.atlas_empty[0]), int(entry.atlas_empty[1]))


static func id(name: String) -> int:
	build()
	if not ids.has(name):
		push_error("Unknown block " + name)
		return -1
	return int(ids[name])


static func is_solid(block: int) -> bool:
	return solid[block] == 1


static func is_opaque(block: int) -> bool:
	return opaque[block] == 1


static func is_passable(block: int) -> bool:
	return passable[block] == 1


static func component(block: int) -> String:
	return components[block]


static func resource(block: int) -> String:
	return resources[block]


static func block_name(block: int) -> String:
	return names[block]
