extends Node
## The exported build's smoke test (M25), the one check that runs in a
## release build: `TheBoundGod.exe -- --smoke` boots past the title, raises a
## new world from seed 7, lets it run a few seconds, saves to its own slot
## (never the player's), loads that slot back, compares, deletes the slot and
## quits: exit 0 and "SMOKE ok" when all of it held.
const WorldIO = preload("res://scripts/presentation/world_io.gd")
const SaveStore = preload("res://scripts/core/save_store.gd")

const SLOT: String = "smoke_test"

var main: Node3D
var _frames: int = 0


static func requested() -> bool:
	return OS.get_cmdline_user_args().has("--smoke")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 180:
		_finish(_run())


func _run() -> String:
	var sim: RefCounted = main.sim
	if sim.present_count() == 0:
		return "the new world has nobody in it"
	main.world_io.slot = SLOT
	if not main.world_io.save():
		return "saving failed: " + SaveStore.last_error
	var back: RefCounted = WorldIO.load_slot(SLOT)
	if back == null:
		return "loading failed: " + SaveStore.last_error
	var again: RefCounted = back.active_sim()
	if again.calendar.tick != sim.calendar.tick or again.present_count() != sim.present_count() or back.regions.size() != main.campaign.regions.size():
		return "the loaded world differs (tick %d/%d, people %d/%d)" % [again.calendar.tick, sim.calendar.tick, again.present_count(), sim.present_count()]
	return ""


func _finish(problem: String) -> void:
	var folder: String = SaveStore.folder(SLOT)
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder + file)
	DirAccess.remove_absolute(folder)
	print("SMOKE ok: %d people, day %d, %d frames" % [main.sim.present_count(), main.sim.calendar.day(), _frames] if problem.is_empty() else "SMOKE FAIL: " + problem)
	get_tree().quit(0 if problem.is_empty() else 1)
