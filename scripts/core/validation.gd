extends RefCounted
## Semantic checks over every catalog. Each check takes the parsed data so the
## headless runner can feed a deliberately broken copy; `run()` checks the
## shipped files. An empty result means the data is sound.
const Data = preload("res://scripts/core/data.gd")
const Balance = preload("res://scripts/core/balance.gd")
const ValidationFood = preload("res://scripts/core/validation_food.gd")
const ValidationCultivation = preload("res://scripts/core/validation_cultivation.gd")

## Code records these thoughts by id, so the catalog must hold them.
const REQUIRED_THOUGHTS: Array[String] = [
	"ate_raw", "ate_a_meal", "ate_foraged", "went_hungry", "slept_bed", "slept_ground", "exposed", "good_chat",
	"insulted", "comforted", "new_partner", "friend_died", "partner_died", "ambition_fulfilled",
	"frustrated", "injured", "child_born", "witnessed_attack", "helped_friend", "refused_help",
	"arrived", "learned", "fought", "mental_break", "death_witness", "cared_for", "saw_the_god",
	"feared_the_god", "prayer_answered", "prayer_unheard", "witnessed_miracle", "whispered_to",
	"strange_voice", "shrine_fell", "home_built", "raided", "lost_home", "heard_of_god",
	"quest_done", "blessed", "mourned_shrine", "strangers_watching",
]
const PERSONALITY_KEYS: Array[String] = [
	"sociability", "bravery", "kindness", "diligence", "curiosity", "romance", "temper",
	"optimism", "leadership", "night_owl", "need_decay", "skill_speed",
]
const AMBITION_KINDS: Array[String] = [
	"master_skill", "raise_family", "befriend_village", "map_the_wilds", "raise_shrine",
	"build_home", "lead_village",
]
## Miracle effects that sim/miracles.gd implements; the catalog may not name others.
const IMPLEMENTED_EFFECTS: Array[String] = ["whisper", "bless_growth", "kindle", "veil_of_fog", "mend", "bless_cultivation", "shield_trial", "defy_heaven"]
## Kept in step with FunctionRules.FUNCTIONS (not preloaded: the rules load data).
const FUNCTION_IDS: Array[String] = ["dwelling", "storehouse", "workshop", "shrine", "shelter", "hall", "garden", "field", "kitchen", "granary"]
const BALANCE_SECTIONS: Array[String] = [
	"time", "needs", "agents", "social", "mood", "health", "work", "construction", "world",
	"settlements", "food", "farming", "population", "faith", "shrines", "miracle_costs", "threats", "decay", "avatar",
	"cultivation",
]


static func run() -> Array[String]:
	for name in Data.FILES:
		Data.file(name)
	var errors: Array[String] = []
	errors.append_array(Data.load_errors)
	errors.append_array(check_blocks(Data.file("blocks")))
	errors.append_array(check_people(Data.file("people")))
	errors.append_array(check_society(Data.file("society")))
	errors.append_array(check_templates(Data.file("templates"), Data.file("blocks")))
	errors.append_array(check_miracles(Data.file("miracles")))
	errors.append_array(ValidationFood.check_crops(Data.file("crops"), Data.file("blocks")))
	errors.append_array(ValidationFood.check_recipes(Data.file("recipes"), Data.file("blocks"), Data.file("people").get("skills", []), FUNCTION_IDS))
	errors.append_array(check_balance(Balance.data()))
	var trait_ids: Array = []
	for entry in Data.traits():
		trait_ids.append(entry.get("id"))
	errors.append_array(ValidationCultivation.check(Data.file("cultivation"), Data.labels(), trait_ids))
	errors.append_array(ValidationCultivation.check_tribulations(Data.file("tribulations"), Data.realms().size(), Data.file("blocks"), Data.labels()))
	var seen: Dictionary = {}
	for name in Data.TEXT_FILES:
		errors.append_array(check_text(Data.file(name)))
		for key in Data.file(name).get("labels", {}):
			if seen.has(key):
				errors.append("text: label " + str(key) + " is defined in both " + seen[key] + " and " + name)
			seen[key] = name
	return errors


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _schema(data: Dictionary, name: String, errors: Array[String]) -> void:
	if not _number(data.get("schema_version")) or int(data.schema_version) != 1:
		errors.append(name + ": schema_version must be 1")


static func check_blocks(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_schema(data, "blocks", errors)
	var components: Array = data.get("components", [])
	var shapes: Array = data.get("shapes", [])
	var resources: Array = data.get("resources", []) + data.get("divine_only", [])
	var size: Array = data.get("atlas_size", [0, 0])
	var ids: Dictionary = {}
	var names: Dictionary = {}
	var list: Variant = data.get("blocks")
	if not list is Array or list.is_empty():
		errors.append("blocks: the block list is missing")
		return errors
	for entry in list:
		if not entry is Dictionary:
			errors.append("blocks: an entry is not an object")
			continue
		var label: String = "blocks[" + str(entry.get("name", "?")) + "]"
		if not _number(entry.get("id")) or int(entry.id) < 0 or int(entry.id) > 255:
			errors.append(label + ": id must be 0..255")
			continue
		if ids.has(int(entry.id)):
			errors.append(label + ": duplicate id " + str(int(entry.id)))
		ids[int(entry.id)] = true
		if not entry.get("name") is String or names.has(entry.name):
			errors.append(label + ": name must be a unique string")
		names[entry.get("name")] = true
		for key in ["solid", "opaque", "passable", "transparent", "breakable", "placeable"]:
			if not entry.get(key) is bool:
				errors.append(label + ": " + key + " must be true or false")
		if not entry.get("resource") is String or (entry.resource != "" and not resources.has(entry.resource)):
			errors.append(label + ": unknown resource " + str(entry.get("resource")))
		if not _number(entry.get("yield")):
			errors.append(label + ": yield must be a number")
		if not shapes.has(entry.get("shape")):
			errors.append(label + ": unknown shape " + str(entry.get("shape")))
		for key in ["atlas", "atlas_top", "atlas_bottom", "atlas_empty"]:
			if key == "atlas" or entry.has(key):
				var tile: Variant = entry.get(key)
				if not tile is Array or tile.size() != 2 or not _number(tile[0]) or not _number(tile[1]) \
						or int(tile[0]) >= int(size[0]) or int(tile[1]) >= int(size[1]):
					errors.append(label + ": " + key + " is outside the atlas")
		for tile in entry.get("atlas_stages", []):
			if not tile is Array or tile.size() != 2 or not _number(tile[0]) or not _number(tile[1]) 					or int(tile[0]) >= int(size[0]) or int(tile[1]) >= int(size[1]):
				errors.append(label + ": a growth stage tile is outside the atlas")
		if entry.has("component") and not components.has(entry.component):
			errors.append(label + ": unknown component " + str(entry.component))
	if not ids.has(0) or Data.block(0).get("name", "air") != "air":
		errors.append("blocks: id 0 must be air")
	return errors


static func check_people(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_schema(data, "people", errors)
	var skills: Array = data.get("skills", [])
	var needs: Array = data.get("needs", [])
	if skills.size() != 8 or needs.size() != 6:
		errors.append("people: there must be 8 skills and 6 needs")
	var trait_ids: Dictionary = {}
	for entry in data.get("traits", []):
		if not entry is Dictionary or not entry.get("id") is String or trait_ids.has(entry.id):
			errors.append("people: trait ids must be unique strings")
			continue
		trait_ids[entry.id] = entry
	for id in trait_ids:
		var entry: Dictionary = trait_ids[id]
		for key in ["excludes", "clashes_with", "bonds_with"]:
			if not entry.get(key) is Array:
				errors.append("people: trait " + id + " needs a " + key + " list")
				continue
			for other in entry[key]:
				if not trait_ids.has(other):
					errors.append("people: trait " + id + " " + key + " names unknown trait " + str(other))
		var modifiers: Variant = entry.get("modifiers")
		if not modifiers is Dictionary:
			errors.append("people: trait " + id + " has no modifiers")
			continue
		for key in modifiers:
			if not PERSONALITY_KEYS.has(key):
				errors.append("people: trait " + id + " modifies unknown " + str(key))
		for need in modifiers.get("need_decay", {}):
			if not needs.has(need):
				errors.append("people: trait " + id + " changes unknown need " + str(need))
		for skill in modifiers.get("skill_speed", {}):
			if not skills.has(skill):
				errors.append("people: trait " + id + " speeds unknown skill " + str(skill))
	var ambition_ids: Dictionary = {}
	for entry in data.get("ambitions", []):
		if not entry is Dictionary or not entry.get("id") is String or ambition_ids.has(entry.id):
			errors.append("people: ambition ids must be unique strings")
			continue
		ambition_ids[entry.id] = true
		if not AMBITION_KINDS.has(entry.get("kind")) or not _number(entry.get("target")):
			errors.append("people: ambition " + entry.id + " needs a known kind and a target")
	if ambition_ids.is_empty():
		errors.append("people: at least one ambition is required")
	var names: Variant = data.get("names")
	if not names is Dictionary:
		errors.append("people: names are missing")
		return errors
	for key in ["given", "family", "origins", "memories", "former_roles", "miner_roles"]:
		if not names.get(key) is Array or names[key].is_empty():
			errors.append("people: names." + key + " must be a non-empty list")
	for key in ["former_roles", "miner_roles"]:
		for role in names.get(key, []):
			if not role is Dictionary or not skills.has(role.get("skill")):
				errors.append("people: a role in " + key + " has an unknown skill")
	return errors


static func check_society(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_schema(data, "society", errors)
	var ids: Dictionary = {}
	for entry in data.get("thoughts", []):
		if not entry is Dictionary or not entry.get("id") is String or ids.has(entry.id):
			errors.append("society: thought ids must be unique strings")
			continue
		ids[entry.id] = true
		if not _number(entry.get("mood")) or not _number(entry.get("days")) or not _number(entry.get("max_stack")) \
				or not entry.get("text") is String:
			errors.append("society: thought " + entry.id + " needs text, mood, days and max_stack")
	for required in REQUIRED_THOUGHTS:
		if not ids.has(required):
			errors.append("society: required thought missing: " + required)
	return errors


static func check_templates(data: Dictionary, blocks: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_schema(data, "templates", errors)
	var components: Array = blocks.get("components", [])
	var names: Dictionary = {}
	for entry in blocks.get("blocks", []):
		names[entry.get("name")] = true
	var seen: Dictionary = {}
	for rule in data.get("functions", []):
		if not rule is Dictionary or not rule.get("requires") is Dictionary or not rule.get("requires_any") is Array or not rule.get("roofed") is Array or not rule.get("capacity") is Dictionary or not _number(rule.get("roof_reach")):
			errors.append("templates: malformed function rule")
			continue
		if not FUNCTION_IDS.has(rule.get("id")):
			errors.append("templates: unknown function " + str(rule.get("id")))
			continue
		seen[rule.id] = true
		for key in rule.get("requires", {}):
			if not _number(rule.requires[key]) or float(rule.requires[key]) <= 0:
				errors.append("templates: component count must be positive")
			if not components.has(key):
				errors.append("templates: " + rule.id + " requires unknown component " + key)
		for key in rule.get("requires_any", []) + rule.get("roofed", []) + rule.get("open_sky", []):
			if not components.has(key):
				errors.append("templates: " + rule.id + " names unknown component " + str(key))
		for key in rule.capacity:
			if not key in ["beds", "stock", "workers", "sleepers", "seats", "plots", "furrows", "cooks", "grain"] or not (rule.capacity[key] in components or rule.capacity[key] == "roofed_floor"):
				errors.append("templates: unknown capacity mapping")
		for key in ["sky_or_tree_within", "min_roofed_floor"]:
			if rule.has(key) and (not _number(rule[key]) or float(rule[key]) < 0):
				errors.append("templates: invalid " + key)
	for id in FUNCTION_IDS:
		if not seen.has(id):
			errors.append("templates: function rule missing: " + id)
	var limits: Variant = data.get("limits", {}).get("max_size")
	if not limits is Array or limits.size() != 3:
		errors.append("templates: limits.max_size must be [x, y, z]")
	else:
		for value in limits:
			if not _number(value) or float(value) < 1 or float(value) != floor(float(value)):
				errors.append("templates: size limits must be positive integers")
	for key in ["max_palette", "max_file_bytes"]:
		if not _number(data.get("limits", {}).get(key)) or float(data.limits[key]) < 1:
			errors.append("templates: missing or invalid " + key)
	for starter in data.get("starters", []):
		var label: String = "templates: starter " + str(starter.get("id"))
		var legend: Variant = starter.get("legend")
		var layers: Variant = starter.get("layers")
		if not legend is Dictionary or not layers is Array or layers.is_empty():
			errors.append(label + " needs a legend and layers")
			continue
		for key in legend:
			if not names.has(legend[key]):
				errors.append(label + " uses unknown block " + str(legend[key]))
		var depth: int = layers[0].size()
		var width: int = str(layers[0][0]).length() if depth > 0 else 0
		for layer in layers:
			if layer.size() != depth:
				errors.append(label + " has ragged layers")
				break
			for row in layer:
				if str(row).length() != width:
					errors.append(label + " has ragged rows")
					break
				for character in str(row):
					if not legend.has(character):
						errors.append(label + " uses a character with no legend: " + character)
	var starters: Array = []
	for starter in data.get("starters", []):
		starters.append(starter.get("id"))
	for id in Balance.data().get("population", {}).get("migrant_designs", []):
		if not starters.has(id):
			errors.append("balance: migrants bring an unknown design " + str(id))
	return errors


static func check_miracles(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_schema(data, "miracles", errors)
	var aspects: Array = data.get("aspects", [])
	if aspects.size() != 5:
		errors.append("miracles: there must be five aspects")
	var ids: Dictionary = {}
	for entry in data.get("miracles", []):
		if not entry is Dictionary or not entry.get("id") is String or ids.has(entry.id):
			errors.append("miracles: ids must be unique strings")
			continue
		ids[entry.id] = true
		if not IMPLEMENTED_EFFECTS.has(entry.get("effect")):
			errors.append("miracles: " + entry.id + " has an unimplemented effect " + str(entry.get("effect")))
		if entry.get("aspect") != "" and not aspects.has(entry.get("aspect")):
			errors.append("miracles: " + entry.id + " has an unknown aspect")
		for key in ["cost", "radius", "renown_required"]:
			if not _number(entry.get(key)):
				errors.append("miracles: " + entry.id + " needs a numeric " + key)
	return errors


static func check_balance(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_schema(data, "balance", errors)
	for section in BALANCE_SECTIONS:
		if not data.get(section) is Dictionary:
			errors.append("balance: section missing: " + section)
	return errors


static func check_text(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_schema(data, "text", errors)
	if not data.get("labels") is Dictionary:
		errors.append("text: labels are missing")
		return errors
	for key in data.labels:
		if not data.labels[key] is String:
			errors.append("text: label " + str(key) + " is not a string")
	return errors
