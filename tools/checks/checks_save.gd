extends RefCounted
## M11 acceptance: a saved world continues exactly as the one that played on,
## through the staged save files, and a season of rest fits in a minute.
const Sim = preload("res://scripts/sim/sim.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const SaveStore = preload("res://scripts/core/save_store.gd")


func check_a_saved_world_continues_identically():
	var a: RefCounted = Sim.create(11)
	a.run_ticks(a.calendar.ticks_per_day + 137)
	var saved: Dictionary = SimState.capture(a)
	var state: Variant = bytes_to_var(var_to_bytes(saved.sim))
	var chunks: Variant = bytes_to_var(var_to_bytes(saved.chunks))
	var problem: String = SimState.problem(state, chunks)
	if not problem.is_empty():
		return "a fresh save does not validate: " + problem
	var b: RefCounted = SimState.restore(state, chunks)
	if a.state_hash() != b.state_hash():
		return "the restored world differs from the saved one"
	a.run_ticks(a.calendar.ticks_per_day)
	b.run_ticks(b.calendar.ticks_per_day)
	if a.state_hash() != b.state_hash():
		return "the restored world played on differently from the original"
	return ""


func check_a_save_survives_the_store_and_a_damaged_file():
	var sim: RefCounted = Sim.create(21, {"world": "flat", "size": Vector3i(48, 16, 48), "ground": 4})
	sim.run_ticks(200)
	var saved: Dictionary = SimState.capture(sim)
	var slot: String = "verification_m11"
	var payload: Dictionary = {"meta.json": SaveStore.json_bytes({"schema_version": 1, "seed": sim.world_seed, "day": sim.calendar.day()}),
		"sim.bin": var_to_bytes(saved.sim), "chunks.bin": var_to_bytes(saved.chunks), "templates.json": SaveStore.json_bytes(sim.god.offered)}
	if not SaveStore.write(slot, payload) or not SaveStore.write(slot, payload):
		return "the save could not be written: " + SaveStore.last_error
	# Readable bytes that are not a world: the store must fall back to the backup.
	var file := FileAccess.open(SaveStore.folder(slot) + "sim.bin", FileAccess.WRITE)
	file.store_buffer(var_to_bytes("damaged"))
	file.close()
	var files: Dictionary = SaveStore.read(slot, func(name: String, bytes: PackedByteArray) -> bool:
		return name.ends_with(".json") or bytes_to_var(bytes) is Dictionary)
	if files.is_empty():
		return "a damaged save did not fall back to its backup: " + SaveStore.last_error
	var restored: RefCounted = SimState.restore(bytes_to_var(files["sim.bin"]), bytes_to_var(files["chunks.bin"]))
	if restored.state_hash() != sim.state_hash():
		return "the recovered save differs from what was written"
	for name in DirAccess.get_files_at(SaveStore.folder(slot)):
		DirAccess.remove_absolute(SaveStore.folder(slot) + name)
	DirAccess.remove_absolute(SaveStore.folder(slot))
	return ""


func check_a_season_of_rest_fits_in_a_minute():
	var sim: RefCounted = Sim.create(11)
	var started: int = Time.get_ticks_msec()
	sim.run_ticks(sim.calendar.ticks_per_day * sim.calendar.days_per_season)
	var seconds: float = (Time.get_ticks_msec() - started) / 1000.0
	print("      a season of rest: %.1fs, %d people" % [seconds, sim.present_count()])
	if seconds >= 60.0:
		return "resting a season took %.1fs" % seconds
	return ""


## A save made by the vertical slice (schema 2, before lanterns) loads through
## the migration path and plays on for a day; a save from a newer version is
## refused rather than half-loaded.
func check_the_slice_save_loads_through_migration():
	var file := FileAccess.open_compressed("res://tools/fixtures/save_v2_slice.zst", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return "the slice fixture save is missing"
	var saved: Variant = bytes_to_var(file.get_buffer(file.get_length()))
	if not saved is Dictionary or int(saved.sim.get("schema_version", -1)) != 2:
		return "the fixture is not a schema 2 save"
	var problem: String = SimState.problem(saved.sim, saved.chunks)
	if not problem.is_empty():
		return "the slice save is refused: " + problem
	var sim: RefCounted = SimState.restore(saved.sim, saved.chunks)
	if sim.present_count() != 8 or sim.calendar.day() != 4:
		return "the slice save restored the wrong world: %d people on day %d" % [sim.present_count(), sim.calendar.day()]
	sim.run_ticks(sim.calendar.ticks_per_day)
	if sim.present_count() < 6:
		return "the migrated world lost its people within a day"
	var again: Dictionary = SimState.capture(sim)
	if int(again.sim.schema_version) != SimState.SCHEMA or not again.sim.lanterns is Dictionary:
		return "the migrated world does not save in the current schema"
	var newer: Dictionary = again.sim.duplicate()
	newer.schema_version = SimState.SCHEMA + 1
	if SimState.problem(newer, again.chunks) != "save_version":
		return "a save from a newer version was not refused"
	return ""
