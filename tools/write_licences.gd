extends SceneTree
## Writes the licence texts that ship beside the build (M25) into `licences/`:
## the engine's licence and third-party notices (from the engine, so they
## match 4.2.2), the fonts' SIL Open Font Licence files and the game's
## credits. publish.ps1 copies them next to the executable.
## Godot --headless --path . --script res://tools/write_licences.gd
const CreditsText = preload("res://scripts/presentation/ui/credits_text.gd")


func _init() -> void:
	var out: String = ProjectSettings.globalize_path("res://licences")
	DirAccess.make_dir_recursive_absolute(out)
	_write(out + "/LICENSE-Godot.txt", Engine.get_license_text())
	_write(out + "/THIRD-PARTY-NOTICES-Godot.txt", CreditsText.third_party())
	for font in ["OFL-ShipporiMinchoB1.txt", "OFL-ZenKakuGothicNew.txt"]:
		_write(out + "/" + font, FileAccess.get_file_as_string("res://assets/fonts/" + font))
	quit(0)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text.replace("\r\n", "\n"))
	print("wrote %s (%d bytes)" % [path, text.length()])
