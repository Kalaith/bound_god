extends RefCounted
## Player-facing text from data/text.json. `label` fails loudly on an unknown
## key in debug builds (the coverage check in sim_checks catches it first).
const Data = preload("res://scripts/core/data.gd")


static func has(key: String) -> bool:
	return Data.file("text").get("labels", {}).has(key)


static func label(key: String) -> String:
	var labels: Dictionary = Data.file("text").get("labels", {})
	if not labels.has(key):
		push_error("Text has no label " + key)
		return key
	return str(labels[key])


## `{name}` placeholders are replaced from `args`; unknown placeholders stay.
static func fill(template: String, args: Dictionary) -> String:
	var result: String = template
	for key in args:
		result = result.replace("{" + str(key) + "}", str(args[key]))
	return result


static func format(key: String, args: Dictionary) -> String:
	return fill(label(key), args)
