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
		# A value may itself be a label key ("cause_raid"); it is worded here.
		args[str(i - 1)] = Text.label(parts[i]) if parts[i].begins_with("cause_") and Text.has(parts[i]) else parts[i]
	return Text.format(parts[0], args)


static func line(entry: Dictionary, with_day: bool = true) -> String:
	var text: String = Text.format("chronicle_" + str(entry.kind), entry.args)
	var why: String = cause(str(entry.cause))
	if not why.is_empty():
		text += " " + Text.format("chronicle_because", {"cause": why})
	var head: String = Text.format("chronicle_head", {"day": entry.day, "place": entry.place}) if with_day else ""
	return (head + "  " + text).strip_edges()
