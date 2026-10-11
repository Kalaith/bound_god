extends RefCounted
## Semantic checks for the food catalogs: crops and recipes. Every crop
## grows on a real block from and into real resources, in real seasons; every
## recipe turns real resources into real resources at a real function, worked
## with a real skill.
const Calendar = preload("res://scripts/sim/calendar.gd")


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func check_crops(data: Dictionary, blocks: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _number(data.get("schema_version")) or int(data.schema_version) != 1:
		errors.append("crops: schema_version must be 1")
	var resources: Array = blocks.get("resources", [])
	var stage_counts: Dictionary = {}
	for entry in blocks.get("blocks", []):
		if entry is Dictionary and entry.has("atlas_stages"):
			stage_counts[entry.get("name")] = entry.atlas_stages.size()
	var list: Variant = data.get("crops")
	if not list is Array or list.is_empty():
		errors.append("crops: the crop list is missing")
		return errors
	var ids: Dictionary = {}
	for entry in list:
		if not entry is Dictionary or not entry.get("id") is String or ids.has(entry.id):
			errors.append("crops: crop ids must be unique strings")
			continue
		ids[entry.id] = true
		var label: String = "crops[" + entry.id + "]"
		if not stage_counts.has(entry.get("block")):
			errors.append(label + ": block must be a block with growth stages")
		elif not _number(entry.get("stages")) or int(entry.stages) < 2 or int(entry.stages) != int(stage_counts[entry.block]):
			errors.append(label + ": stages must match the block's stage tiles")
		if not _number(entry.get("rain_need")) or int(entry.rain_need) < 1:
			errors.append(label + ": rain_need must be at least one day")
		for key in ["days_per_stage", "yield", "seed_return"]:
			if not _number(entry.get(key)) or float(entry[key]) < 0 or (key != "seed_return" and float(entry[key]) < 1):
				errors.append(label + ": " + key + " must be a positive number")
		for key in ["harvest", "seed"]:
			if not resources.has(entry.get(key)):
				errors.append(label + ": " + key + " must be a resource")
		for key in ["seasons", "sow_seasons"]:
			if not entry.get(key) is Array or entry[key].is_empty():
				errors.append(label + ": " + key + " must be a list of seasons")
				continue
			for season in entry[key]:
				if not Calendar.SEASONS.has(season):
					errors.append(label + ": unknown season " + str(season))
	return errors


static func check_recipes(data: Dictionary, blocks: Dictionary, skills: Array, functions: Array) -> Array[String]:
	var errors: Array[String] = []
	if not _number(data.get("schema_version")) or int(data.schema_version) != 1:
		errors.append("recipes: schema_version must be 1")
	var resources: Array = blocks.get("resources", [])
	var list: Variant = data.get("recipes")
	if not list is Array or list.is_empty():
		errors.append("recipes: the recipe list is missing")
		return errors
	var ids: Dictionary = {}
	for entry in list:
		if not entry is Dictionary or not entry.get("id") is String or ids.has(entry.id):
			errors.append("recipes: recipe ids must be unique strings")
			continue
		ids[entry.id] = true
		var label: String = "recipes[" + entry.id + "]"
		# Alchemy recipes are worked at any alchemy building of their tier or above.
		if entry.get("station") == "alchemy":
			if not _number(entry.get("tier")) or int(entry.tier) < 1 or int(entry.tier) > 4:
				errors.append(label + ": an alchemy recipe needs a tier from 1 to 4")
		elif not functions.has(entry.get("station")):
			errors.append(label + ": station must be a function")
		if not skills.has(entry.get("skill")):
			errors.append(label + ": unknown skill " + str(entry.get("skill")))
		if not _number(entry.get("ticks")) or float(entry.ticks) < 1:
			errors.append(label + ": ticks must be positive")
		for key in ["inputs", "outputs"]:
			if not entry.get(key) is Dictionary or entry[key].is_empty():
				errors.append(label + ": " + key + " must name resources")
				continue
			for resource in entry[key]:
				if not resources.has(resource) or not _number(entry[key][resource]) or float(entry[key][resource]) < 1:
					errors.append(label + ": " + key + " has an unknown resource or amount " + str(resource))
	return errors
