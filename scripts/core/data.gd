extends RefCounted
## Every hand-edited catalog, read once from data/*.json into a static cache.
## Balance numbers stay in balance.gd; this file owns blocks, people, society,
## templates, miracles, crops, recipes and text. Catalog shape is checked by
## validation.gd at startup; lookups by an unknown id return an empty Dictionary.

const FILES: Dictionary = {
	"blocks": "res://data/blocks.json",
	"people": "res://data/people.json",
	"society": "res://data/society.json",
	"templates": "res://data/templates.json",
	"miracles": "res://data/miracles.json",
	"crops": "res://data/crops.json",
	"recipes": "res://data/recipes.json",
	"text": "res://data/text.json",
	"text_agents": "res://data/text_agents.json",
	"text_ui": "res://data/text_ui.json",
}
## Text catalogs, split by responsibility; their labels share one namespace.
const TEXT_FILES: Array[String] = ["text", "text_agents", "text_ui"]

static var _files: Dictionary = {}
static var _blocks_by_id: Array = []
static var _block_ids: Dictionary = {}
static var _traits: Dictionary = {}
static var _thoughts: Dictionary = {}
static var _ambitions: Dictionary = {}
static var _miracles: Dictionary = {}
static var _labels: Dictionary = {}
## Parse errors from the last load, reported by validation.
static var load_errors: Array[String] = []


static func file(name: String) -> Dictionary:
	if not _files.has(name):
		var path: String = FILES[name]
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if not parsed is Dictionary:
			load_errors.append("Data file is missing or not a JSON object: " + path)
			parsed = {}
		_files[name] = parsed
	return _files[name]


static func reload() -> void:
	_files.clear()
	_blocks_by_id.clear()
	_block_ids.clear()
	_traits.clear()
	_thoughts.clear()
	_ambitions.clear()
	_miracles.clear()
	_labels.clear()
	load_errors.clear()


## Every label from every text catalog.
static func labels() -> Dictionary:
	if _labels.is_empty():
		for name in TEXT_FILES:
			_labels.merge(file(name).get("labels", {}))
	return _labels


# --- Blocks -----------------------------------------------------------------

static func _index_blocks() -> void:
	if not _blocks_by_id.is_empty():
		return
	_blocks_by_id.resize(256)
	for entry in file("blocks").get("blocks", []):
		if entry is Dictionary and (entry.get("id") is float or entry.get("id") is int):
			var id: int = int(entry.id)
			if id >= 0 and id < 256:
				_blocks_by_id[id] = entry
				_block_ids[str(entry.get("name", ""))] = id


static func block(id: int) -> Dictionary:
	_index_blocks()
	if id < 0 or id >= 256 or _blocks_by_id[id] == null:
		return {}
	return _blocks_by_id[id]


static func block_id(name: String) -> int:
	_index_blocks()
	return int(_block_ids.get(name, -1))


static func block_names() -> Array:
	_index_blocks()
	return _block_ids.keys()


static func blocks() -> Array:
	return file("blocks").get("blocks", [])


# --- People and society -----------------------------------------------------

static func traits() -> Array:
	return file("people").get("traits", [])


static func trait_def(id: String) -> Dictionary:
	if _traits.is_empty():
		for entry in traits():
			_traits[entry.id] = entry
	return _traits.get(id, {})


static func ambitions() -> Array:
	return file("people").get("ambitions", [])


static func ambition(id: String) -> Dictionary:
	if _ambitions.is_empty():
		for entry in ambitions():
			_ambitions[entry.id] = entry
	return _ambitions.get(id, {})


static func names() -> Dictionary:
	return file("people").get("names", {})


static func skills() -> Array:
	return file("people").get("skills", [])


static func thought(id: String) -> Dictionary:
	if _thoughts.is_empty():
		for entry in file("society").get("thoughts", []):
			_thoughts[entry.id] = entry
	return _thoughts.get(id, {})


static func thoughts() -> Array:
	return file("society").get("thoughts", [])


# --- Templates and miracles -------------------------------------------------

static func function_rules() -> Array:
	return file("templates").get("functions", [])


static func starter(id: String) -> Dictionary:
	for entry in file("templates").get("starters", []):
		if entry.get("id") == id:
			return entry
	return {}


static func template_limits() -> Dictionary:
	return file("templates").get("limits", {})


static func miracles() -> Array:
	return file("miracles").get("miracles", [])


static func miracle(id: String) -> Dictionary:
	if _miracles.is_empty():
		for entry in miracles():
			_miracles[entry.id] = entry
	return _miracles.get(id, {})


static func crops() -> Array:
	return file("crops").get("crops", [])


static func crop(id: String) -> Dictionary:
	for entry in crops():
		if entry.get("id") == id:
			return entry
	return {}


static func recipes() -> Array:
	return file("recipes").get("recipes", [])


static func aspects() -> Array:
	return file("miracles").get("aspects", [])
