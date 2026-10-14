extends RefCounted
## World saves under user://worlds/<slot>/: meta.json, sim.bin, chunks.bin,
## templates.json and, since the campaign (M22), regions.bin. The toolkit's
## SlotStore stages and verifies every file, keeps the previous copy as .bak,
## falls back to a backup when a file cannot be read, and preserves an
## unreadable file as .corrupt.
const SlotStore = preload("res://addons/hatchery/storage/slot_store.gd")
const JsonIO = preload("res://addons/hatchery/core/json_io.gd")

const ROOT: String = "user://worlds/"
const FILES: Array[String] = ["meta.json", "sim.bin", "chunks.bin", "templates.json"]
## Valleys saved before the campaign have no regions file.
const OPTIONAL: Array[String] = ["regions.bin"]

static var worlds: RefCounted = _worlds()


static func _worlds() -> RefCounted:
	var store: RefCounted = SlotStore.new(ROOT, FILES)
	store.optional = OPTIONAL
	return store


static func json_bytes(value: Variant) -> PackedByteArray:
	return JsonIO.bytes(value)


static func parse_json(bytes: PackedByteArray) -> Variant:
	return JsonIO.from_bytes(bytes)
