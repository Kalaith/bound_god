extends RefCounted
## World saves under user://worlds/<slot>/: meta.json, sim.bin, chunks.bin and
## templates.json. Every file is staged (.tmp, verified), the previous copy is
## kept as .bak, and a file that cannot be read falls back to its backup; an
## unreadable file with no good backup is quarantined as .corrupt.

const ROOT: String = "user://worlds/"
const SCHEMA: int = 1
const FILES: Array[String] = ["meta.json", "sim.bin", "chunks.bin", "templates.json"]

static var last_error: String = ""


static func folder(slot: String) -> String:
	return ROOT + slot.validate_filename() + "/"


static func exists(slot: String) -> bool:
	var base: String = folder(slot)
	return FileAccess.file_exists(base + "meta.json") or FileAccess.file_exists(base + "meta.json.bak")


## `payload` maps file name -> PackedByteArray. Returns false and sets
## last_error when any file could not be written and verified.
static func write(slot: String, payload: Dictionary) -> bool:
	last_error = ""
	var base: String = folder(slot)
	if DirAccess.make_dir_recursive_absolute(base) != OK and not DirAccess.dir_exists_absolute(base):
		last_error = "Could not create the save folder."
		return false
	# Stage every file first so a failure leaves the previous save untouched.
	for name in payload:
		var temporary: String = base + name + ".tmp"
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file == null:
			last_error = "Could not write " + name + "."
			return false
		file.store_buffer(payload[name])
		file.flush()
		file.close()
		if FileAccess.get_file_as_bytes(temporary) != payload[name]:
			last_error = "A staged save file did not read back correctly: " + name
			return false
	for name in payload:
		var target: String = base + name
		if FileAccess.file_exists(target):
			if FileAccess.file_exists(target + ".bak"):
				DirAccess.remove_absolute(target + ".bak")
			if DirAccess.rename_absolute(target, target + ".bak") != OK:
				last_error = "Could not keep a backup of " + name + "."
				return false
		if DirAccess.rename_absolute(target + ".tmp", target) != OK:
			last_error = "Could not move " + name + " into place."
			return false
	return true


## Returns file name -> PackedByteArray for every file that `valid` accepts.
## `valid` is a Callable(name: String, bytes: PackedByteArray) -> bool.
static func read(slot: String, valid: Callable) -> Dictionary:
	last_error = ""
	var base: String = folder(slot)
	var result: Dictionary = {}
	for name in FILES:
		var path: String = base + name
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
		if not bytes.is_empty() and valid.call(name, bytes):
			result[name] = bytes
			continue
		var backup: PackedByteArray = FileAccess.get_file_as_bytes(path + ".bak") if FileAccess.file_exists(path + ".bak") else PackedByteArray()
		if not backup.is_empty() and valid.call(name, backup):
			result[name] = backup
			last_error = "Recovered " + name + " from its backup."
			if FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".corrupt"):
				DirAccess.rename_absolute(path, path + ".corrupt")
			continue
		if FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".corrupt"):
			DirAccess.copy_absolute(path, path + ".corrupt")
		last_error = "The saved world is damaged: " + name + " could not be read."
		return {}
	return result


static func json_bytes(value: Variant) -> PackedByteArray:
	return JSON.stringify(value, "\t").to_utf8_buffer()


static func parse_json(bytes: PackedByteArray) -> Variant:
	return JSON.parse_string(bytes.get_string_from_utf8())
