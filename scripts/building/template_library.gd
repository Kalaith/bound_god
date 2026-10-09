extends RefCounted
## Private designs only. Saving or importing never offers or builds a design.
const Template = preload("res://scripts/building/template.gd")
const Data = preload("res://scripts/core/data.gd")

var root: String = "user://templates"
var designs: Array = []
var errors: Array[String] = []


func scan() -> void:
	designs.clear()
	errors.clear()
	if not DirAccess.dir_exists_absolute(root):
		return
	var names: Array[String] = []
	for file in DirAccess.get_files_at(root):
		var name: String = file.trim_suffix(".bak")
		if name.ends_with(".json") and not names.has(name):
			names.append(name)
	names.sort()
	for name in names:
		var path: String = root.path_join(name)
		var result: Array = read_file(path)
		if result[0] == null:
			var backup: Array = read_file(path + ".bak")
			if backup[0] == null:
				errors.append(name + ": " + result[1])
				continue
			# Preserve the damaged file, then restore the verified backup.
			if FileAccess.file_exists(path):
				if DirAccess.copy_absolute(path, path + ".corrupt") != OK:
					errors.append("template_io")
					continue
			if DirAccess.copy_absolute(path + ".bak", path) != OK:
				errors.append("template_io")
			result = backup
			errors.append("template_recovered")
		designs.append(result[0])


static func read_file(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return [null, "template_io"]
	if file.get_length() > int(Data.template_limits().max_file_bytes):
		return [null, "template_file_size"]
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return [null, "template_json"]
	return Template.from_dict(parser.data)


func save(design: RefCounted) -> String:
	if DirAccess.make_dir_recursive_absolute(root) != OK:
		return "template_io"
	var checked: Array = Template.from_dict(design.to_dict())
	if checked[0] == null:
		return checked[1]
	var path: String = root.path_join(design.id + ".json")
	# Never silently replace an unrelated imported design with the same id.
	if FileAccess.file_exists(path):
		var old: Array = read_file(path)
		if old[0] != null and old[0].to_dict() != checked[0].to_dict():
			return "template_conflict"
	return write_file(path, checked[0])


func import_file(path: String) -> Array:
	var result: Array = read_file(path)
	if result[0] == null:
		return result
	var problem: String = save(result[0])
	return result if problem.is_empty() else [null, problem]


static func write_file(path: String, design: RefCounted) -> String:
	var checked: Array = Template.from_dict(design.to_dict())
	if checked[0] == null:
		return checked[1]
	var bytes: PackedByteArray = (JSON.stringify(checked[0].to_dict(), "\t") + "\n").to_utf8_buffer()
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return "template_io"
	file.store_buffer(bytes)
	file.flush()
	file.close()
	if FileAccess.get_file_as_bytes(path + ".tmp") != bytes or read_file(path + ".tmp")[0] == null:
		return "template_io"
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak") and DirAccess.remove_absolute(path + ".bak") != OK:
			return "template_io"
		if DirAccess.rename_absolute(path, path + ".bak") != OK:
			return "template_io"
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		return "template_io"
	return ""
