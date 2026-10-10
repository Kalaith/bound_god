extends RefCounted
## Debug-only captures of fields and meals (M14): `food_fields` (two fields
## with crops at every stage, a granary and a cookhouse beside the tree),
## `food_site` (a field laid out as a construction site) and `food_panel`
## (the settlement panel's food days in an autumn short of food).
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Crops = preload("res://scripts/sim/crops.gd")
const SiteFinder = preload("res://scripts/building/site_finder.gd")
const CaptureVillage = preload("res://scripts/presentation/capture_village.gd")


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var tree: Vector3i = sim.features.sacred_tree
	sim.run_ticks(12)
	CaptureVillage._stamp(sim, "field_plot", tree.x - 9, tree.z + 8)
	CaptureVillage._stamp(sim, "field_plot", tree.x - 2, tree.z + 8)
	CaptureVillage._stamp(sim, "granary", tree.x + 6, tree.z + 8)
	CaptureVillage._stamp(sim, "cookhouse", tree.x + 12, tree.z + 8)
	var crop: Dictionary = Crops.staple()
	for entry in sim.structures.built():
		if not entry.functions.has("field"):
			continue
		var cells: Array = entry.components.get("farmland", []).duplicate()
		cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return [a.z, a.x] < [b.z, b.x])
		for index in range(cells.size()):
			var cell: Vector3i = cells[index] + Vector3i.UP
			sim.crops.sow(sim, cell, crop, "god")
			# One row at each stage, from the sprout to the ripe ear.
			var stage: int = index * int(crop.stages) / cells.size()
			sim.set_block(cell, Registry.id(crop.block), stage, "god")
	var hour: float = 15.0
	sim.calendar.tick = sim.calendar.ticks_per_day * (sim.calendar.day() - 1) + int(hour / 24.0 * sim.calendar.ticks_per_day)
	var camera_rig: Node3D = main.camera_rig
	camera_rig.overlook = true
	camera_rig._overlook_distance = 22.0
	camera_rig._overlook_pitch = -0.7
	camera_rig._overlook_yaw = deg_to_rad(0.0)
	camera_rig.overlook_center = Vector3(tree.x + 3, tree.y + 1, tree.z + 10)
	main.avatar.zone_radius = 1000.0
	match scenario:
		"food_site":
			var settlement: Dictionary = sim.settlements.entries[1]
			var template: RefCounted = sim.template("field_plot")
			var found: Dictionary = SiteFinder.find(sim, template, settlement)
			if not found.is_empty():
				var id: int = sim.construction.create("field_plot", found.origin, found.rotation, 1, 0, "field", found.order, sim.calendar.tick)
				for _i in range(8):
					sim.construction.advance(id, sim.calendar.tick)
					var entry: Array = sim.construction.get_site(id).order[sim.construction.get_site(id).cursor - 1]
					sim.set_block(entry[0], entry[1], entry[2], "npc:0")
				camera_rig.overlook_center = Vector3(found.origin) + Vector3(3, 0, 2)
			print("FOOD site at %s" % str(found.get("origin", "none")))
		"food_panel":
			sim.calendar.tick += sim.calendar.ticks_per_day * 21
			var camp: Vector3i = sim.settlements.entries[1].camp
			var chest: Vector3i = sim.nav.surface(camp.x + 2, camp.z - 2)
			sim.set_block(chest, Registry.id("storage_chest"), 0, "god")
			for resource in ["grain", "berries", "meal", "seed"]:
				sim.settlements.chest_add(chest, resource, {"grain": 14, "berries": 12, "meal": 4, "seed": 9}[resource])
			main.settlement_panel.open(1)
	main.world_view.remesh_now()
	var functions: Array = []
	for entry in sim.structures.built():
		functions.append(",".join(entry.functions))
	print("FOOD %s structures=%s crops=%d" % [scenario, functions, sim.crops.plots.size()])
	shot.shoot_after(120)
