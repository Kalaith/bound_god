extends RefCounted
## Semantic checks for alchemy (M20b): herb kinds with blocks, resources,
## growing places and seasons; preparations with an implemented use, a
## recipe that makes each and a label; alchemy buildings that are functions
## with rising tiers; the toxicity and refining numbers.
const Calendar = preload("res://scripts/sim/calendar.gd")
const DataRules = preload("res://addons/hatchery/core/data_rules.gd")

const GROWS: Array[String] = ["deep_qi", "shade", "scar", "waterside"]
const USES: Array[String] = ["trial", "sitting", "heal", "cleanse", "longevity"]
## Preparations the systems refer to by name.
const NEEDED: Array[String] = ["healing_draught", "awakening_tea", "pill", "qi_pill", "warding_pill", "cleansing_pill", "longevity_elixir"]
## The numbers each use reads.
const USE_KEYS: Dictionary = {"trial": ["preparation", "severity"], "sitting": ["factor", "days"], "heal": ["heal", "mend"], "cleanse": [], "longevity": ["years"]}


static func _share(value: Variant) -> bool:
	return DataRules.finite(value) and float(value) >= 0.0 and float(value) <= 1.0


static func check(data: Dictionary, recipes: Dictionary, blocks: Dictionary, labels: Dictionary, functions: Array) -> Array[String]:
	var errors: Array[String] = []
	if not DataRules.finite(data.get("schema_version")) or int(data.schema_version) != 1:
		errors.append("alchemy: schema_version must be 1")
	var resources: Array = blocks.get("resources", [])
	var block_names: Dictionary = {}
	for entry in blocks.get("blocks", []):
		block_names[entry.get("name")] = entry
	_herbs(data, resources, block_names, labels, errors)
	_elixirs(data, recipes, resources, labels, errors)
	_halls(data, functions, blocks.get("components", []), errors)
	var garden: Variant = data.get("garden")
	if not garden is Dictionary or not _share(garden.get("qi")) or not DataRules.finite(garden.get("ripen")) or float(garden.ripen) < 1.0 \
			or not DataRules.finite(garden.get("per_day")) or int(garden.per_day) < 1:
		errors.append("alchemy: garden needs qi (0-1), ripen (1+) and per_day (1+)")
	var toxicity: Variant = data.get("toxicity")
	if not toxicity is Dictionary:
		errors.append("alchemy: toxicity is missing")
	else:
		for key in ["decay", "rate", "preparation", "limit", "cleanse_at"]:
			if not _share(toxicity.get(key)):
				errors.append("alchemy.toxicity: " + key + " must be from 0 to 1")
	var refining: Variant = data.get("refining")
	if not refining is Dictionary:
		errors.append("alchemy: refining is missing")
	else:
		for key in ["fail_base", "fail_per_level", "fail_least", "cauldron_extra"]:
			if not _share(refining.get(key)):
				errors.append("alchemy.refining: " + key + " must be from 0 to 1")
		var bonus: Variant = refining.get("tier_bonus")
		if not bonus is Array or bonus.size() != 5:
			errors.append("alchemy.refining: tier_bonus needs one share per tier 0-4")
		if not DataRules.finite(refining.get("alchemist_level")) or not DataRules.finite(refining.get("alchemist_pull")):
			errors.append("alchemy.refining: alchemist_level and alchemist_pull must be numbers")
	return errors


static func _herbs(data: Dictionary, resources: Array, block_names: Dictionary, labels: Dictionary, errors: Array[String]) -> void:
	var search: Variant = data.get("herb_search")
	if not search is Dictionary:
		errors.append("alchemy: herb_search is missing")
	else:
		for key in ["reach", "tries", "water_reach", "waterside_reach"]:
			if not DataRules.finite(search.get(key)) or float(search[key]) < 1.0:
				errors.append("alchemy.herb_search: " + key + " must be at least 1")
	var list: Variant = data.get("herbs")
	if not list is Array or list.is_empty():
		errors.append("alchemy: the herb list is missing")
		return
	var ids: Dictionary = {}
	for entry in list:
		if not entry is Dictionary or not entry.get("id") is String or ids.has(entry.id):
			errors.append("alchemy: herb ids must be unique strings")
			continue
		ids[entry.id] = true
		var label: String = "alchemy.herbs[" + entry.id + "]"
		var block: Dictionary = block_names.get(entry.id, {})
		if block.is_empty() or block.get("shape") != "cross" or block.get("atlas_stages", []).size() != 3:
			errors.append(label + ": needs a cross block of its name with three growth stages")
		if not resources.has(entry.get("resource")) or block.get("resource") != entry.get("resource"):
			errors.append(label + ": its resource must be its block's")
		if not GROWS.has(entry.get("grows")):
			errors.append(label + ": grows must be one of " + str(GROWS))
		if not _share(entry.get("qi")):
			errors.append(label + ": qi must be from 0 to 1")
		for key in ["ripen_days", "most", "per_day"]:
			if not DataRules.finite(entry.get(key)) or int(entry[key]) < 1:
				errors.append(label + ": " + key + " must be at least 1")
		var seasons: Variant = entry.get("seasons")
		if not seasons is Array or seasons.is_empty():
			errors.append(label + ": seasons are missing")
		else:
			for season in seasons:
				if not Calendar.SEASONS.has(season):
					errors.append(label + ": unknown season " + str(season))
		if not entry.get("withers") is bool:
			errors.append(label + ": withers must be true or false")
		if not labels.has("herb_" + entry.id) or not labels.has("cause_herb_" + str(entry.get("grows"))):
			errors.append(label + ": needs labels herb_" + entry.id + " and cause_herb_" + str(entry.get("grows")))
	if not ids.has("spirit_herb"):
		errors.append("alchemy: the systems need the spirit_herb")
	var garden: Variant = data.get("garden")
	if garden is Dictionary and (not ids.has(garden.get("sun")) or not ids.has(garden.get("shade"))):
		errors.append("alchemy.garden: sun and shade must name herbs")


static func _elixirs(data: Dictionary, recipes: Dictionary, resources: Array, labels: Dictionary, errors: Array[String]) -> void:
	var made: Dictionary = {}
	for recipe in recipes.get("recipes", []):
		if recipe is Dictionary and recipe.get("station") == "alchemy" and recipe.get("outputs") is Dictionary:
			for resource in recipe.outputs:
				made[resource] = true
			if not labels.has("recipe_" + str(recipe.get("id"))):
				errors.append("recipes[" + str(recipe.get("id")) + "]: no label recipe_" + str(recipe.get("id")))
	var list: Variant = data.get("elixirs")
	if not list is Array:
		errors.append("alchemy: the elixir list is missing")
		return
	var ids: Dictionary = {}
	for entry in list:
		if not entry is Dictionary or not entry.get("id") is String or ids.has(entry.id):
			errors.append("alchemy: elixir ids must be unique strings")
			continue
		ids[entry.id] = true
		var label: String = "alchemy.elixirs[" + entry.id + "]"
		if not resources.has(entry.id) or not made.has(entry.id):
			errors.append(label + ": must be a resource an alchemy recipe makes")
		if not USES.has(entry.get("use")):
			errors.append(label + ": use must be one of " + str(USES))
			continue
		if not _share(entry.get("toxicity")) or not DataRules.finite(entry.get("priority")) or float(entry.priority) <= 0.0:
			errors.append(label + ": toxicity (0-1) and a positive priority are needed")
		for key in USE_KEYS[entry.use]:
			if not DataRules.finite(entry.get(key)) or float(entry[key]) < 0.0:
				errors.append(label + ": " + key + " must be a number")
		if entry.use == "sitting" and not entry.get("realm") in ["mortal", "cultivator"]:
			errors.append(label + ": realm must be mortal or cultivator")
		if not labels.has("resource_" + entry.id):
			errors.append(label + ": no label resource_" + entry.id)
	for id in NEEDED:
		if not ids.has(id):
			errors.append("alchemy: the systems need the preparation " + id)


static func _halls(data: Dictionary, functions: Array, components: Array, errors: Array[String]) -> void:
	var list: Variant = data.get("halls")
	if not list is Array or list.is_empty():
		errors.append("alchemy: the hall list is missing")
		return
	var tier: int = 0
	for entry in list:
		if not entry is Dictionary or not functions.has(entry.get("function")):
			errors.append("alchemy.halls: each needs a known function")
			continue
		var label: String = "alchemy.halls[" + str(entry.function) + "]"
		if not DataRules.finite(entry.get("tier")) or int(entry.tier) != tier + 1:
			errors.append(label + ": tiers must rise by one from 1")
		tier = int(entry.get("tier", tier + 1))
		var crafters: Variant = entry.get("crafters")
		if not crafters is Dictionary or crafters.is_empty():
			errors.append(label + ": crafters must name components")
		else:
			for component in crafters:
				if not components.has(component) or not DataRules.finite(crafters[component]):
					errors.append(label + ": unknown crafter component " + str(component))
		if not DataRules.finite(entry.get("crafters_most")) or int(entry.crafters_most) < 1:
			errors.append(label + ": crafters_most must be at least 1")
