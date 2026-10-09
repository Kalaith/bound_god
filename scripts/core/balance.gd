extends RefCounted
## Gameplay balance read once from data/balance.json. Scripts and tests read
## the same values as tools/sim_checks.gd, so a retune changes one file and no check literals.
## Paths are dot-separated keys, e.g. "agents.sight_radius".
## A missing or mistyped key is a data error: it is reported and fails fast.

const PATH: String = "res://data/balance.json"

static var _data: Dictionary = {}
## Resolved paths, so per-frame reads do not split strings again.
static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not parsed is Dictionary:
			push_error("Balance data is missing or invalid: " + PATH)
			assert(false, "Balance data is missing or invalid: " + PATH)
			return {}
		_data = parsed
	return _data


static func value(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]
	var node: Variant = data()
	for key in path.split("."):
		if not node is Dictionary or not (node as Dictionary).has(key):
			push_error("Balance data has no value at " + path)
			assert(false, "Balance data has no value at " + path)
			return null
		node = node[key]
	_cache[path] = node
	return node


static func number(path: String) -> float:
	return float(value(path))


static func integer(path: String) -> int:
	return int(value(path))


static func dict(path: String) -> Dictionary:
	var result: Variant = value(path)
	return result if result is Dictionary else {}


static func list(path: String) -> Array:
	var result: Variant = value(path)
	return result if result is Array else []


## JSON stores positions as [x, y].
static func vec(raw: Variant) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))
