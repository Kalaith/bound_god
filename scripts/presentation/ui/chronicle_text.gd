extends RefCounted
## One chronicle entry as a line: what happened, where, and why. Causes are a
## label key, optionally with "|"-separated values for {0}, {1}...
const Text = preload("res://scripts/core/text.gd")


static func cause(value: String) -> String:
	if value.is_empty():
		return ""
	var parts: PackedStringArray = value.split("|")
	if not Text.has(parts[0]):
		return parts[0]
	var args: Dictionary = {}
	for i in range(1, parts.size()):
		args[str(i - 1)] = word(parts[i])
	return Text.format(parts[0], args)


## A value may itself be a label key ("cause_raid", "standing_village",
## "resource_berries"); it is worded on display, so saved entries never hold
## translated text. A resource, a function or a threat is worded in lower
## case inside a sentence.
static func word(value: Variant) -> Variant:
	if value is String and value.begins_with("sect_name|"):
		var parts: PackedStringArray = value.split("|")
		return Text.format("sect_name", {"adjective": Text.label(parts[1]), "noun": Text.label(parts[2])}) if parts.size() == 3 else value
	if value is String and (value.begins_with("cause_") or value.begins_with("standing_") or value.begins_with("realm_")
			or value.begins_with("technique_") or value.begins_with("rank_") or value.begins_with("insight_")
			or value.begins_with("unlock_") or value.begins_with("phase_") or value.begins_with("awakened_")) and Text.has(value):
		return Text.label(value)
	if value is String and (value.begins_with("resource_") or value.begins_with("function_") or value.begins_with("threat_")) and Text.has(value):
		return Text.label(value).to_lower()
	return value


static func line(entry: Dictionary, with_day: bool = true) -> String:
	var args: Dictionary = {}
	for key in entry.args:
		args[key] = word(entry.args[key])
		# What the tree learned from names whoever taught or died.
		if str(entry.args[key]).begins_with("lesson_") and Text.has(str(entry.args[key])):
			args[key] = Text.format(str(entry.args[key]), {"name": entry.args.get("name", "")})
	var text: String = Text.format("chronicle_" + str(entry.kind), args)
	var why: String = cause(str(entry.cause))
	if not why.is_empty():
		text += " " + Text.format("chronicle_because", {"cause": why})
	var head: String = Text.format("chronicle_head", {"day": entry.day, "place": entry.place}) if with_day else ""
	return (head + "  " + text).strip_edges()
