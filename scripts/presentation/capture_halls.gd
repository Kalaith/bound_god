extends RefCounted
## Debug-only captures of the sect's halls (M19b): `halls_<design id>` (one
## design stamped where a founder would put it), `halls_compound` (several
## stamped round the settlement) and `halls_renovation` (a village hall with
## a lectern and benches added: `halls_renovation_before` shows it first).
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const SiteFinder = preload("res://scripts/building/site_finder.gd")
const Renovations = preload("res://scripts/sim/renovations.gd")
const CaptureArchitecture = preload("res://scripts/presentation/capture_architecture.gd")

const COMPOUND: Array[String] = ["scripture_pavilion", "lecture_hall", "hall_of_ancestors", "mountain_gate", "bell_pavilion",
	"precept_stele", "jade_array", "seclusion_cell"]


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	main.driver.set_speed(0)
	match scenario:
		"halls_compound":
			var middle := Vector3.ZERO
			var count: int = 0
			for id in COMPOUND:
				var choice: Dictionary = CaptureArchitecture._stamp(sim, id)
				if not choice.is_empty():
					middle += Vector3(choice.origin)
					count += 1
			main.world_view.remesh_now()
			CaptureArchitecture._look(main, middle / maxf(count, 1.0) + Vector3(3.0, 1.0, 3.0), 40.0, -0.7, 30.0)
			print("HALLS compound=%d %s" % [count, str(_functions(sim))])
		"halls_renovation", "halls_renovation_before":
			var choice: Dictionary = CaptureArchitecture._stamp(sim, "village_hall")
			if scenario == "halls_renovation":
				var option: Dictionary = Renovations.option(sim, 1, "lecture_hall")
				for entry in option.get("order", []):
					sim.set_block(entry[0], entry[1], entry[2], "capture")
			_strip_roof(sim, choice)
			main.world_view.remesh_now()
			CaptureArchitecture._look(main, Vector3(choice.get("origin", Vector3i.ZERO)) + Vector3(3.5, 0.0, 3.0), 13.0, -1.05, 20.0)
			print("HALLS renovation %s" % str(_functions(sim)))
		_:
			var id: String = scenario.trim_prefix("halls_")
			var cutaway: bool = id.ends_with("_open")
			id = id.trim_suffix("_open")
			var choice: Dictionary = CaptureArchitecture._stamp(sim, id)
			if cutaway:
				_strip_roof(sim, choice)
			main.world_view.remesh_now()
			var size: Vector3i = Template.from_starter(Data.starter(id)).rotated_size(int(choice.get("rotation", 0))) if not Data.starter(id).is_empty() else Vector3i.ONE
			var at: Vector3 = Vector3(choice.get("origin", Vector3i.ZERO)) + Vector3(size.x * 0.5, 1.0, size.z * 0.5)
			CaptureArchitecture._look(main, at, 11.0 + size.x, -1.05 if cutaway else -0.55, 25.0)
			print("HALLS %s at %s: %s" % [id, str(choice.get("origin", "none")), str(_functions(sim))])
	shot.shoot_after(60)


## Lifts the top layer of a stamped design off for the camera (the
## structure is probed again, but the picture is only of the walls).
static func _strip_roof(sim: RefCounted, choice: Dictionary) -> void:
	var top: int = -1
	for entry in choice.get("order", []):
		top = maxi(top, int(entry[0].y))
	var batch: Array = []
	for entry in choice.get("order", []):
		if int(entry[0].y) == top and int(entry[1]) != 0:
			batch.append([entry[0], 0, 0])
	sim.set_blocks(batch, "capture")


static func _functions(sim: RefCounted) -> Array:
	var result: Array = []
	for entry in sim.structures.built():
		for function in entry.functions:
			if not result.has(function):
				result.append(function)
	return result
