extends RefCounted
## Data catalogs load, validate, and report broken keys loudly.
const Data = preload("res://scripts/core/data.gd")
const Validation = preload("res://scripts/core/validation.gd")


func check_shipped_data_is_valid():
	var errors: Array[String] = Validation.run()
	return "" if errors.is_empty() else "; ".join(errors)


## Every script under res://scripts loads, so a parse error in presentation
## code fails here rather than only when the game is run.
func check_all_scripts_parse():
	var broken: Array[String] = []
	var folders: Array[String] = ["res://scripts"]
	while not folders.is_empty():
		var folder: String = folders.pop_back()
		for sub in DirAccess.get_directories_at(folder):
			folders.append(folder + "/" + sub)
		for name in DirAccess.get_files_at(folder):
			if name.ends_with(".gd"):
				var script: Variant = load(folder + "/" + name)
				if not script is GDScript or not (script as GDScript).can_instantiate():
					broken.append(folder + "/" + name)
	return "" if broken.is_empty() else "scripts failed to parse: " + ", ".join(broken)


func check_broken_data_is_reported():
	var blocks: Dictionary = Data.file("blocks").duplicate(true)
	blocks.blocks[3].erase("solid")
	blocks.blocks[4]["component"] = "spaceship"
	var people: Dictionary = Data.file("people").duplicate(true)
	people.traits[0].bonds_with.append("no_such_trait")
	var miracles: Dictionary = Data.file("miracles").duplicate(true)
	miracles.miracles.append({"id": "smite", "tier": "large", "cost": 1, "radius": 1, "aspect": "wrath", "renown_required": 0, "effect": "smite"})
	var found: Array[String] = []
	found.append_array(Validation.check_blocks(blocks))
	found.append_array(Validation.check_people(people))
	found.append_array(Validation.check_miracles(miracles))
	var expected: Array[String] = ["solid", "spaceship", "no_such_trait", "smite"]
	for needle in expected:
		if not found.any(func(error: String) -> bool: return error.contains(needle)):
			return "validation missed a broken " + needle + " (found: " + "; ".join(found) + ")"
	return ""
