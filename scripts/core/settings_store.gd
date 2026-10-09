extends RefCounted
## Preferences never share a file or schema with earned progression.
const Keys = preload("res://scripts/core/key_bindings.gd")
const Pad = preload("res://scripts/core/pad_bindings.gd")
## A saved `values` dictionary missing a newer key defaults it in on load, so a
## single added setting cannot invalidate every existing preferences file.
## Numbers are fractions 0..1 (volumes, look sensitivity); graphics toggles let
## weaker GPUs drop Forward+ effects.
const CURRENT_SCHEMA: int = 1
const DEFAULTS: Dictionary = {
	"master": 1.0, "music": 1.0, "effects": 1.0, "muted": false,
	"look_sensitivity": 0.5, "invert_look": false,
	"fullscreen": false, "reduce_motion": false,
	"ssao": true, "glow": true, "shadows": true,
}
var values: Dictionary = DEFAULTS.duplicate()
var key_bindings: Dictionary = Keys.defaults()
var pad_bindings: Dictionary = Pad.defaults()
var save_enabled: bool = true
var path: String = "user://settings.json"
var last_error: String = ""
var writes_blocked: bool = false


func valid(data: Variant) -> bool:
	if not data is Dictionary or not (data.get("schema") is int or data.get("schema") is float):
		return false
	var schema: int = int(data.schema)
	if schema < 1 or schema > CURRENT_SCHEMA or not data.get("values") is Dictionary:
		return false
	var candidate: Dictionary = data.values
	# Validate only the keys actually present; a missing key is a migration
	# (defaulted on load), not a corrupt file.
	for key in candidate:
		if not DEFAULTS.has(key):
			continue
		if DEFAULTS[key] is bool:
			if not candidate[key] is bool:
				return false
		else:
			if not (candidate[key] is float or candidate[key] is int):
				return false
			var amount: float = float(candidate[key])
			if not is_finite(amount) or amount < 0.0 or amount > 1.0:
				return false
	if data.has("pad_bindings") and not Pad.valid(data.pad_bindings):
		return false
	return not data.has("key_bindings") or Keys.valid(data.key_bindings)


func _read(filename: String) -> Variant:
	if not FileAccess.file_exists(filename):
		return null
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(filename)) == OK else null


func _migrated(data: Dictionary) -> Dictionary:
	# A present key is trusted (validated already); an absent one defaults in,
	# so a preferences file written before a setting existed still loads.
	var merged: Dictionary = DEFAULTS.duplicate()
	merged.merge(data.values, true)
	return merged


func load_settings() -> void:
	if not save_enabled:
		return
	var data: Variant = _read(path)
	if valid(data):
		values = _migrated(data)
		key_bindings = Keys.normalized(data.get("key_bindings", Keys.defaults()))
		pad_bindings = Pad.normalized(data.get("pad_bindings", Pad.defaults()))
		return
	# Preserve a genuinely future format rather than replacing it with an older backup.
	if data is Dictionary and (data.get("schema") is int or data.get("schema") is float) and int(data.schema) > CURRENT_SCHEMA:
		writes_blocked = true
		last_error = "Settings use an unsupported version. Changes last this session."
		return
	var backup: Variant = _read(path + ".bak")
	if valid(backup):
		values = _migrated(backup)
		key_bindings = Keys.normalized(backup.get("key_bindings", Keys.defaults()))
		pad_bindings = Pad.normalized(backup.get("pad_bindings", Pad.defaults()))
		last_error = "Recovered settings from backup."
	elif FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
		writes_blocked = true
		last_error = "Saved settings could not be read. Changes last this session."


func save_settings() -> bool:
	if not save_enabled:
		return true
	if writes_blocked:
		return false
	var snapshot := {"schema": CURRENT_SCHEMA, "values": values, "key_bindings": key_bindings, "pad_bindings": pad_bindings}
	if not valid(snapshot):
		last_error = "Settings are invalid and could not be saved."
		return false
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failed()
	file.store_string(JSON.stringify(snapshot))
	file.flush()
	file.close()
	if not valid(_read(temporary)):
		return _failed()
	if FileAccess.file_exists(path):
		if valid(_read(path)):
			if DirAccess.copy_absolute(path, path + ".bak") != OK:
				return _failed()
		elif FileAccess.file_exists(path + ".corrupt"):
			last_error = "A previous .corrupt recovery file already exists; damaged settings preserved. Move it aside before saving again."
			return false
		elif DirAccess.copy_absolute(path, path + ".corrupt") != OK:
			return _failed()
	if DirAccess.rename_absolute(temporary, path) != OK:
		return _failed()
	last_error = ""
	return true


func _failed() -> bool:
	last_error = "Could not save settings. Changes last this session."
	return false


## Push every stored preference into the engine: bindings, window mode and the
## master bus. Graphics toggles are read by the world environment each frame.
func apply_all(_tree: SceneTree) -> void:
	Keys.apply(key_bindings)
	Pad.apply(pad_bindings)
	var fullscreen: bool = bool(values.fullscreen)
	if DisplayServer.get_name() != "headless":
		var mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode and (fullscreen or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN):
			DisplayServer.window_set_mode(mode)
	for bus in ["Master", "Music", "Effects"]:
		var index: int = AudioServer.get_bus_index(bus)
		if index < 0:
			continue
		var level: float = float(values[bus.to_lower()])
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, 0.0001)))
		AudioServer.set_bus_mute(index, bool(values.muted) or level <= 0.001)


func rebind(action: String, slot: int, code: int) -> String:
	var error: String = Keys.change_error(key_bindings, action, slot, code)
	if error.is_empty():
		key_bindings[action][slot] = code
		Keys.apply(key_bindings)
	return error


func reset_keys() -> void:
	key_bindings = Keys.defaults()
	Keys.apply(key_bindings)


func rebind_pad(action: String, button: int) -> String:
	var error: String = Pad.change_error(pad_bindings, action, button)
	if error.is_empty():
		pad_bindings[action] = button
		Pad.apply(pad_bindings)
	return error


func reset_pad() -> void:
	pad_bindings = Pad.defaults()
	Pad.apply(pad_bindings)
