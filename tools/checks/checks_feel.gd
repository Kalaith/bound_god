extends RefCounted
## M24 Look, sound and feel: localisation readiness (no literal player text
## in presentation, language overrides, the pseudo-language, action labels)
## and the new settings.
const Text = preload("res://scripts/core/text.gd")
const TextCatalog = preload("res://addons/hatchery/core/text_catalog.gd")
const SettingsStore = preload("res://scripts/core/settings_store.gd")


## Player-facing text set from a string literal starting with a letter.
func check_no_literal_player_text_in_presentation():
	var pattern := RegEx.new()
	pattern.compile("(Style\\.(label|heading|button|wrapped)|\\.text = |add_item|tooltip_text = |placeholder_text = )\\(?\"[A-Za-z]")
	var found: Array = []
	var folders: Array = ["res://scripts/presentation", "res://scripts/presentation/ui"]
	for folder in folders:
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".gd") or file.begins_with("capture"):
				continue
			var lines: PackedStringArray = FileAccess.get_file_as_string(folder.path_join(file)).split("\n")
			for i in range(lines.size()):
				if pattern.search(lines[i]) != null:
					found.append("%s:%d" % [file, i + 1])
	return "" if found.is_empty() else "literal player text at " + ", ".join(found)


func check_every_action_has_words():
	for action in SettingsStore.KEY_ACTIONS.keys() + SettingsStore.PAD_ACTIONS.keys():
		if not Text.has("action_" + str(action)):
			return "action %s has no label" % action
	for key in SettingsStore.DEFAULTS:
		if not Text.has("setting_" + str(key)):
			return "setting %s has no label" % key
	return ""


func check_a_language_lays_over_english():
	var root: String = "user://checks/text"
	DirAccess.make_dir_recursive_absolute(root + "/fr")
	var english := FileAccess.open(root + "/text.json", FileAccess.WRITE)
	english.store_string(JSON.stringify({"schema_version": 1, "labels": {"a": "Tree", "b": "Hollow"}}))
	english.close()
	var french := FileAccess.open(root + "/fr/text.json", FileAccess.WRITE)
	french.store_string(JSON.stringify({"schema_version": 1, "labels": {"a": "Arbre", "z": "stray"}}))
	french.close()
	var catalog: RefCounted = TextCatalog.new([root + "/text.json"])
	catalog.locale_root = root
	catalog.set_locale("fr")
	var base: Dictionary = catalog.labels().duplicate()
	catalog.set_locale("xx")
	var none: Dictionary = catalog.labels().duplicate()
	if base.get("a") != "Arbre" or base.get("b") != "Hollow" or base.has("z"):
		return "overrides gave %s" % str(base)
	if none.get("a") != "Tree":
		return "a language with no folder changed the labels: %s" % str(none)
	return ""


func check_the_pseudo_language_keeps_placeholders():
	var text: String = Text.pseudo_of("Day {day} · {season}")
	if not text.contains("{day}") or not text.contains("{season}") or not text.begins_with("[") or text.length() <= "Day {day} · {season}".length():
		return "pseudo gave %s" % text
	Text.pseudo = true
	var worded: String = Text.format("hud_day", {"day": 3, "season": "x", "clock": "y"})
	Text.pseudo = false
	if worded.contains("{day}") or not worded.contains("3"):
		return "a pseudo label lost its placeholder: %s" % worded
	return ""


func check_new_settings_default_and_validate():
	var store: RefCounted = SettingsStore.new()
	store.save_enabled = false
	for key in ["ui_scale", "colour_safe", "high_contrast", "captions", "pseudo_language"]:
		if not store.values.has(key):
			return "the setting %s has no default" % key
	if absf(store.ui_scale() - 1.0) > 0.01:
		return "the default interface scale is %.2f" % store.ui_scale()
	store.values.ui_scale = 1.0
	if absf(store.ui_scale() - 1.5) > 0.01:
		return "the largest interface scale is %.2f" % store.ui_scale()
	if not store.file.accepts({"schema": 1, "values": {"ui_scale": 0.5, "captions": true}}):
		return "a file with the new settings is refused"
	if store.file.accepts({"schema": 1, "values": {"captions": 3}}):
		return "a mistyped setting is accepted"
	return ""
