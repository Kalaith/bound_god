extends Node
## Saving and loading the world for the scene: autosave at each dawn and
## before resting, quick save on demand, and restoring a slot at start. Files
## go through SaveStore's staged writes with backups.
const SaveStore = preload("res://scripts/core/save_store.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const CampaignState = preload("res://scripts/sim/campaign_state.gd")
const Text = preload("res://scripts/core/text.gd")
const Balance = preload("res://scripts/core/balance.gd")

var sim: RefCounted
## Every region is saved together (M22).
var campaign: RefCounted
var hud: Control
var slot: String = "world"
## The sim driver: no autosave while it rests or meditates.
var driver: Node = null
var played_seconds: float = 0.0
var _last_dawn_day: int = -1


## A restored campaign from `slot_name`, or null with SaveStore.last_error set.
static func load_slot(slot_name: String) -> RefCounted:
	var files: Dictionary = SaveStore.read(slot_name, func(name: String, bytes: PackedByteArray) -> bool:
		if name.ends_with(".json"):
			return SaveStore.parse_json(bytes) is Dictionary
		return bytes_to_var(bytes) is Dictionary)
	if files.is_empty():
		return null
	var state: Variant = bytes_to_var(files["sim.bin"])
	var chunks: Variant = bytes_to_var(files["chunks.bin"])
	var problem: String = SimState.problem(state, chunks)
	var regions: Variant = bytes_to_var(files["regions.bin"]) if files.has("regions.bin") else null
	if problem.is_empty() and regions != null:
		problem = CampaignState.problem(regions)
	if not problem.is_empty():
		SaveStore.last_error = Text.label(problem)
		return null
	return CampaignState.restore(state, chunks, regions)


func save(reason: String = "save_done") -> bool:
	var saved: Dictionary = CampaignState.capture(campaign)
	var game_version: String = str(ProjectSettings.get_setting("application/config/version"))
	var meta: Dictionary = {
		"schema_version": SimState.SCHEMA,
		"game_version": game_version,
		"name": slot,
		"seed": sim.world_seed,
		"day": sim.calendar.day(),
		"played_seconds": int(played_seconds),
	}
	var payload: Dictionary = {"meta.json": SaveStore.json_bytes(meta), "sim.bin": var_to_bytes(saved.sim),
		"chunks.bin": var_to_bytes(saved.chunks), "regions.bin": var_to_bytes(saved.regions), "templates.json": SaveStore.json_bytes(sim.god.offered)}
	var ok: bool = SaveStore.write(slot, payload)
	if hud != null:
		hud.flash(Text.label(reason) if ok else SaveStore.last_error, not ok)
	return ok


func _process(delta: float) -> void:
	if sim == null:
		return
	played_seconds += delta
	var day: int = sim.calendar.day()
	if driver != null and driver.resting:
		_last_dawn_day = day
		return
	if day != _last_dawn_day and sim.calendar.hour() >= Balance.number("time.dawn_hour"):
		if _last_dawn_day >= 0:
			save("save_autosaved")
		_last_dawn_day = day
