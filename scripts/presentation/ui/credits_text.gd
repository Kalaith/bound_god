extends RefCounted
## The Credits page (M25): who made the game, the engine's licence and its
## third-party notices (read from the engine itself, so they always match the
## build), and the fonts' licence. `tools/write_licences.gd` writes the same
## notices as plain text beside the build.
const Text = preload("res://scripts/core/text.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")

const FONTS: Array = [
	["Shippori Mincho B1", "Copyright 2021 The Shippori Mincho Project Authors"],
	["Zen Kaku Gothic New", "Copyright 2022 The Zen Kaku Gothic Project Authors"],
]


## The page's lines, in BBCode.
static func lines() -> Array:
	var result: Array = []
	result.append("[color=#%s]%s[/color]" % [Style.GOLD.to_html(false), Text.label("credits_game")])
	result.append(Text.format("credits_made", {"version": str(ProjectSettings.get_setting("application/config/version", ""))}))
	result.append("")
	result.append("[color=#%s]%s[/color]" % [Style.GOLD.to_html(false), Text.label("credits_fonts")])
	for font in FONTS:
		result.append("%s — %s" % [font[0], font[1]])
	result.append(Text.label("credits_fonts_licence"))
	result.append("")
	result.append("[color=#%s]%s[/color]" % [Style.GOLD.to_html(false), Text.label("credits_engine")])
	result.append(_escaped(Engine.get_license_text()))
	result.append("")
	result.append("[color=#%s]%s[/color]" % [Style.GOLD.to_html(false), Text.label("credits_third_party")])
	result.append(_escaped(third_party()))
	result.append("")
	result.append(Text.label("credits_beside"))
	return result


## Every component the engine is built from, with its copyright and licence
## name, then each licence's text: Godot's own required notice.
static func third_party() -> String:
	var parts: PackedStringArray = []
	for component in Engine.get_copyright_info():
		parts.append("%s" % str(component.name))
		for part in component.parts:
			parts.append("  %s: %s" % [", ".join(part.get("files", [])), str(part.get("license", ""))])
			for holder in part.get("copyright", []):
				parts.append("  © %s" % str(holder))
	var licences: Dictionary = Engine.get_license_info()
	var names: Array = licences.keys()
	names.sort()
	for name in names:
		parts.append("")
		parts.append("----- %s -----" % str(name))
		parts.append(str(licences[name]))
	return "\n".join(parts)


static func _escaped(text: String) -> String:
	return text.replace("[", "[lb]")
