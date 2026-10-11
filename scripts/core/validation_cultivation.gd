extends RefCounted
## Semantic checks for the cultivation catalog: realms in order with growing
## needs, weighted talent and affinity tables, a falling qi curve, techniques
## with an implemented effect, sect names drawn from real labels, and a label
## for every id.
const Data = preload("res://scripts/core/data.gd")

## Where a technique can come from; sim/cultivation.gd handles each.
const TECHNIQUE_SOURCES: Array[String] = ["tree", "teacher"]


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _table(name: String, list: Variant, errors: Array[String]) -> void:
	if not list is Array or list.is_empty():
		errors.append("cultivation: " + name + " must be a weighted list")
		return
	for entry in list:
		var range: Variant = entry.get("range") if entry is Dictionary else null
		if not _number(entry.get("weight") if entry is Dictionary else null) or not range is Array or range.size() != 2 \
				or not _number(range[0]) or not _number(range[1]) or float(range[0]) < 0.0 or float(range[1]) > 1.0 or float(range[0]) > float(range[1]):
			errors.append("cultivation: " + name + " entries need a weight and a range within 0..1")


static func check(data: Dictionary, labels: Dictionary, traits: Array) -> Array[String]:
	var errors: Array[String] = []
	if not _number(data.get("schema_version")) or int(data.schema_version) != 1:
		errors.append("cultivation: schema_version must be 1")
	var realms: Variant = data.get("realms")
	if not realms is Array or realms.size() < 2:
		errors.append("cultivation: at least two realms are needed")
	else:
		var last: float = 0.0
		for i in range(realms.size()):
			var realm: Dictionary = realms[i] if realms[i] is Dictionary else {}
			if not realm.get("id") is String or not _number(realm.get("order")) or int(realm.order) != i:
				errors.append("cultivation: realm %d needs an id and order %d" % [i, i])
				continue
			if not _number(realm.get("progress_needed")) or float(realm.progress_needed) <= last:
				errors.append("cultivation: realm " + realm.id + " must need more progress than the one before")
			else:
				last = float(realm.progress_needed)
			if not _number(realm.get("lifespan_bonus")) or float(realm.lifespan_bonus) < 0.0:
				errors.append("cultivation: realm " + realm.id + " needs a lifespan_bonus")
			if not _number(realm.get("endurance")) or float(realm.endurance) <= 0.0 or float(realm.endurance) > 1.0:
				errors.append("cultivation: realm " + realm.id + " needs an endurance in (0, 1]")
			if not labels.has("realm_" + realm.id):
				errors.append("cultivation: realm " + realm.id + " has no label")
	_table("talent", data.get("talent"), errors)
	_table("seeker_talent", data.get("seeker_talent"), errors)
	var drive: Variant = data.get("drive")
	if not drive is Dictionary or not drive.get("ordinary") is Array or not drive.get("seeker") is Array:
		errors.append("cultivation: drive needs ordinary and seeker ranges")
	var affinities: Variant = data.get("affinities")
	if not affinities is Array or affinities.is_empty():
		errors.append("cultivation: affinities are missing")
	else:
		for entry in affinities:
			if not entry is Dictionary or not entry.get("id") is String or not _number(entry.get("weight")) \
					or not _number(entry.get("qi_bonus")) or not _number(entry.get("foundation_bonus")):
				errors.append("cultivation: an affinity needs an id, a weight, qi_bonus and foundation_bonus")
			elif not labels.has("affinity_" + entry.id):
				errors.append("cultivation: affinity " + entry.id + " has no label")
	var curve: Variant = data.get("qi", {}).get("curve") if data.get("qi") is Dictionary else null
	if not curve is Array or curve.size() < 2:
		errors.append("cultivation: the qi curve needs at least two points")
	else:
		var last_distance: float = -1.0
		var last_density: float = INF
		for point in curve:
			if not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]) \
					or float(point[0]) <= last_distance or float(point[1]) > last_density:
				errors.append("cultivation: the qi curve must fall with distance")
				break
			last_distance = float(point[0])
			last_density = float(point[1])
	if not _number(data.get("qi", {}).get("floor")):
		errors.append("cultivation: qi.floor must be a number")
	var techniques: Variant = data.get("techniques")
	if not techniques is Array or techniques.is_empty():
		errors.append("cultivation: the technique list is missing")
	else:
		for entry in techniques:
			if not entry is Dictionary or not entry.get("id") is String or not _number(entry.get("progress")) or float(entry.progress) < 1.0 \
					or not TECHNIQUE_SOURCES.has(entry.get("source")):
				errors.append("cultivation: a technique needs an id, a progress factor of at least 1 and a known source")
			elif not labels.has("technique_" + entry.id):
				errors.append("cultivation: technique " + entry.id + " has no label")
	var names: Variant = data.get("sect_names")
	if not names is Dictionary or not names.get("adjectives") is Dictionary or not names.get("nouns") is Array or names.nouns.is_empty():
		errors.append("cultivation: sect_names needs adjectives and nouns")
	else:
		var keys: Array = names.adjectives.values() + names.nouns + [names.get("default_adjective", ""), names.get("pattern", "")]
		for key in keys:
			if not labels.has(key):
				errors.append("cultivation: sect name part " + str(key) + " has no label")
		for trait_id in names.adjectives:
			if not traits.has(trait_id):
				errors.append("cultivation: sect adjective for unknown trait " + str(trait_id))
	return errors


## Tribulation kinds start at a real realm with a next one, with sensible
## ranges; odds and outcomes are numbers; scorching names real blocks.
static func check_tribulations(data: Dictionary, realms: int, blocks: Dictionary, labels: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _number(data.get("schema_version")) or int(data.schema_version) != 1:
		errors.append("tribulations: schema_version must be 1")
	var kinds: Variant = data.get("kinds")
	if not kinds is Array or kinds.is_empty():
		errors.append("tribulations: the kind list is missing")
	else:
		for kind in kinds:
			if not kind is Dictionary or not kind.get("id") is String:
				errors.append("tribulations: a kind needs an id")
				continue
			var label: String = "tribulations[" + kind.id + "]"
			if not _number(kind.get("realm_from")) or int(kind.realm_from) < 1 or int(kind.realm_from) + 1 >= realms:
				errors.append(label + ": realm_from must be a realm with a next one")
			for key in ["severity", "strikes"]:
				var range: Variant = kind.get(key)
				if not range is Array or range.size() != 2 or not _number(range[0]) or not _number(range[1]) or float(range[0]) > float(range[1]):
					errors.append(label + ": " + key + " must be a [low, high] range")
			for key in ["talent_severity", "radius", "storm_ticks", "warning_ticks", "insight"]:
				if not _number(kind.get(key)) or float(kind[key]) < 0.0:
					errors.append(label + ": " + key + " must be a number")
	for section in ["odds", "outcomes"]:
		var values: Variant = data.get(section)
		if not values is Dictionary or values.is_empty():
			errors.append("tribulations: " + section + " are missing")
			continue
		for key in values:
			var value: Variant = values[key]
			if not (_number(value) or (value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]))):
				errors.append("tribulations: " + section + "." + str(key) + " must be a number")
	var names: Dictionary = {}
	for entry in blocks.get("blocks", []):
		names[entry.get("name")] = true
	var scorch: Variant = data.get("scorch")
	if not scorch is Dictionary:
		errors.append("tribulations: scorch is missing")
	else:
		for key in ["charred_wood", "burned", "scorched_earth", "split"]:
			for name in scorch.get(key, []):
				if not names.has(name):
					errors.append("tribulations: scorch names unknown block " + str(name))
		for name in ["charred_wood", "scorched_earth", scorch.get("split_into", "")]:
			if not names.has(name):
				errors.append("tribulations: scorch turns blocks into unknown " + str(name))
				continue
			if not labels.has("block_" + str(name)):
				errors.append("tribulations: block " + str(name) + " has no label")
	return errors


## Unlock effects sim/tree_growth.gd and sim/tree_abilities.gd implement;
## the catalog may not name others.
const UNLOCK_EFFECTS: Array[String] = ["spirit_fruit", "spirit_herbs", "deep_roots", "sheltering_canopy", "awakening_fruit", "root_network"]
## What the tree learns from besides trials; sim/tree_growth.gd hooks each.
const LESSONS: Array[String] = ["winter", "drought", "teaching", "death"]


## The tree: maturity phases in order with labels, lessons with labels,
## unlocks gated on an insight a trial or a lesson can give (and on maturity
## or an earlier unlock), numbers where numbers belong.
static func check_tree(data: Dictionary, tribulations: Dictionary, labels: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _number(data.get("schema_version")) or int(data.schema_version) != 1:
		errors.append("tree: schema_version must be 1")
	var kinds: Array = []
	for kind in tribulations.get("kinds", []):
		kinds.append(kind.get("id"))
		if not labels.has("insight_" + str(kind.get("id"))):
			errors.append("tree: insight " + str(kind.get("id")) + " has no label")
	errors.append_array(_check_lessons(data, labels, kinds))
	for section in ["insight", "fruit", "herbs", "nurture", "scars", "awakening", "deep_roots", "canopy", "roots"]:
		var values: Variant = data.get(section)
		if not values is Dictionary or values.is_empty():
			errors.append("tree: " + section + " is missing")
			continue
		for key in values:
			if not _number(values[key]):
				errors.append("tree: " + section + "." + str(key) + " must be a number")
	for key in ["lesson_reach", "lesson_records"]:
		if not _number(data.get(key)):
			errors.append("tree: " + key + " must be a number")
	var maturity: Variant = data.get("maturity")
	if not maturity is Dictionary or not _number(maturity.get("per_day")) or not maturity.get("phases") is Array or maturity.phases.is_empty():
		errors.append("tree: maturity needs per_day and phases")
	else:
		var last: float = -1.0
		for entry in maturity.phases:
			if not entry is Dictionary or not entry.get("id") is String or not _number(entry.get("at")) or not _number(entry.get("crown")) or float(entry.at) <= last:
				errors.append("tree: maturity phases need ids, rising thresholds and a crown size")
				break
			last = float(entry.at)
			if not labels.has("phase_" + entry.id):
				errors.append("tree: phase " + entry.id + " has no label")
	var unlocks: Variant = data.get("unlocks")
	if not unlocks is Array:
		errors.append("tree: unlocks are missing")
	else:
		var earlier: Array = []
		for entry in unlocks:
			if not entry is Dictionary or not entry.get("id") is String or not UNLOCK_EFFECTS.has(entry.get("effect")):
				errors.append("tree: an unlock needs an id and an implemented effect")
				continue
			var needs: Variant = entry.get("requires")
			var by_maturity: bool = needs is Dictionary and _number(needs.get("maturity")) and float(needs.maturity) > 0.0
			var by_insight: bool = needs is Dictionary and kinds.has(needs.get("insight")) and _number(needs.get("amount"))
			if not by_maturity and not by_insight:
				errors.append("tree: unlock " + entry.id + " must require an insight a trial or lesson can give, or the tree's maturity")
			elif needs.has("insight") and not by_insight:
				errors.append("tree: unlock " + entry.id + " requires an unknown insight")
			if needs is Dictionary and needs.has("unlock") and not earlier.has(needs.unlock):
				errors.append("tree: unlock " + entry.id + " must follow the unlock it requires")
			if not labels.has("unlock_" + entry.id) or not labels.has("unlock_help_" + entry.id):
				errors.append("tree: unlock " + entry.id + " needs a label and a help line")
			earlier.append(entry.id)
	return errors


## Each lesson names an implemented hook and an insight with a label; the
## insights it gives join `kinds` for the unlocks.
static func _check_lessons(data: Dictionary, labels: Dictionary, kinds: Array) -> Array[String]:
	var errors: Array[String] = []
	var lessons: Variant = data.get("lessons")
	if not lessons is Array:
		return ["tree: lessons are missing"]
	for entry in lessons:
		if not entry is Dictionary or not LESSONS.has(entry.get("id")) or not entry.get("insight") is String \
				or not _number(entry.get("first")) or not _number(entry.get("repeat_factor")):
			errors.append("tree: a lesson needs an implemented id, an insight, first and repeat_factor")
			continue
		if not kinds.has(entry.insight):
			kinds.append(entry.insight)
		if not labels.has("insight_" + str(entry.insight)):
			errors.append("tree: insight " + str(entry.insight) + " has no label")
		if not labels.has("lesson_" + str(entry.id)):
			errors.append("tree: lesson " + str(entry.id) + " has no label")
	return errors
