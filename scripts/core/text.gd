extends RefCounted
## Player-facing text from the catalogs data.gd lists (data/text*.json),
## through the toolkit's TextCatalog: one key namespace, keys defined twice
## reported to validation, and `data/locale/<code>/*.json` laid over English.
## `label` fails loudly on an unknown key in debug builds (the coverage check
## in sim_checks catches it first).
const Data = preload("res://scripts/core/data.gd")
const TextCatalog = preload("res://addons/hatchery/core/text_catalog.gd")

static var catalog: RefCounted = _catalog()
## The pseudo-language for layout testing (M24): accented, a third longer,
## bracketed, so text that does not come from the catalogs stands out and
## longer languages can be tried for fit.
static var pseudo: bool = false


static func _catalog() -> RefCounted:
	var paths: Array[String] = []
	for name in Data.TEXT_FILES:
		paths.append(Data.FILES[name])
	return TextCatalog.new(paths)


static func has(key: String) -> bool:
	return catalog.has(key)


static func label(key: String) -> String:
	var text: String = catalog.label(key)
	return TextCatalog.pseudo_of(text) if pseudo and catalog.has(key) else text


## A label in the pseudo-language; `{placeholders}` are kept as they are.
static func pseudo_of(text: String) -> String:
	return TextCatalog.pseudo_of(text)


## `{name}` placeholders are replaced from `args`; unknown placeholders stay.
static func fill(template: String, args: Dictionary) -> String:
	return TextCatalog.fill(template, args)


static func format(key: String, args: Dictionary) -> String:
	return fill(label(key), args)


## The language text is shown in (M24): "en" uses the catalogs as they are;
## another code overlays `data/locale/<code>/*.json` (the same keys).
static func set_locale(code: String) -> void:
	catalog.set_locale(code)
