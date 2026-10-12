extends RefCounted
## Player-facing text from data/text.json. `label` fails loudly on an unknown
## key in debug builds (the coverage check in sim_checks catches it first).
const Data = preload("res://scripts/core/data.gd")


static func has(key: String) -> bool:
	return Data.labels().has(key)


## The pseudo-language for layout testing (M24): accented, a third longer,
## bracketed, so text that does not come from the catalogs stands out and
## longer languages can be tried for fit.
static var pseudo: bool = false
const _ACCENTS: Dictionary = {"a": "á", "e": "é", "i": "ï", "o": "ö", "u": "ü", "A": "Å", "E": "É", "O": "Ø"}


static func label(key: String) -> String:
	var labels: Dictionary = Data.labels()
	if not labels.has(key):
		push_error("Text has no label " + key)
		return key
	return pseudo_of(str(labels[key])) if pseudo else str(labels[key])


## A label in the pseudo-language; `{placeholders}` are kept as they are.
static func pseudo_of(text: String) -> String:
	var out: String = ""
	var inside: bool = false
	for ch in text:
		if ch == "{":
			inside = true
		elif ch == "}":
			inside = false
		out += ch if inside or not _ACCENTS.has(ch) else str(_ACCENTS[ch])
	var pad: int = maxi(text.length() / 3, 1)
	return "[" + out + " " + "~".repeat(pad) + "]"


## `{name}` placeholders are replaced from `args`; unknown placeholders stay.
static func fill(template: String, args: Dictionary) -> String:
	var result: String = template
	for key in args:
		result = result.replace("{" + str(key) + "}", str(args[key]))
	return result


static func format(key: String, args: Dictionary) -> String:
	return fill(label(key), args)
