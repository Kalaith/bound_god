extends RefCounted
const Data = preload("res://scripts/core/data.gd")


static func integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


static func problem(data: Variant) -> String:
	if not data is Dictionary:
		return "template_object"
	if not integer(data.get("schema_version")) or data.schema_version != 1:
		return "template_version"
	for key in ["id", "name", "author"]:
		if not data.get(key) is String or data[key].strip_edges().is_empty() or data[key].length() > 64:
			return "template_identity"
	var safe := RegEx.new()
	safe.compile("^[a-zA-Z0-9_-]+$")
	if safe.search(data.id) == null:
		return "template_identity"
	var limits: Dictionary = Data.template_limits()
	if not data.get("size") is Array or data.size.size() != 3:
		return "template_size"
	for axis in range(3):
		if not integer(data.size[axis]) or data.size[axis] < 1 or data.size[axis] > limits.max_size[axis]:
			return "template_size"
	var palette: Variant = data.get("palette")
	if not palette is Array or palette.is_empty() or palette.size() > int(limits.max_palette) or palette[0] != "air":
		return "template_palette"
	var unique: Dictionary = {}
	for name in palette:
		if not name is String or unique.has(name) or Data.block_id(name) < 0:
			return "template_palette"
		if name != "air" and not Data.block(Data.block_id(name)).placeable:
			return "template_palette"
		unique[name] = true
	var expected: int = int(data.size[0]) * int(data.size[1]) * int(data.size[2])
	if not data.get("blocks") is String or data.blocks.length() != 4 * ceili(expected / 3.0):
		return "template_blocks"
	safe.compile("^[A-Za-z0-9+/]*={0,2}$")
	if safe.search(data.blocks) == null:
		return "template_blocks"
	var bytes: PackedByteArray = Marshalls.base64_to_raw(data.blocks)
	if bytes.size() != expected or Marshalls.raw_to_base64(bytes) != data.blocks:
		return "template_blocks"
	var occupied: bool = false
	for value in bytes:
		if value >= palette.size():
			return "template_blocks"
		occupied = occupied or value != 0
	if not occupied:
		return "template_empty"
	if not data.get("meta") is Dictionary:
		return "template_meta"
	for key in data.meta:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 0 or int(key) >= expected:
			return "template_meta"
		if not integer(data.meta[key]) or data.meta[key] < 0 or data.meta[key] > 1 or palette[bytes[int(key)]] != "door":
			return "template_meta"
	if not data.get("entrance") is Array or data.entrance.size() != 3:
		return "template_entrance"
	for axis in range(3):
		if not integer(data.entrance[axis]) or data.entrance[axis] < 0 or data.entrance[axis] >= data.size[axis]:
			return "template_entrance"
	return ""
