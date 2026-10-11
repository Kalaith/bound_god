extends RefCounted
## Debug-only captures of the sect's alchemy (M20b): `alchemy_herbs` (spirit
## herbs, ginseng in the tree's shade and thunder root on scorched earth),
## `alchemy_lotus` (frost lotus by winter water) and `alchemy_garden` (a herb
## garden and a ginseng house with herbs in their beds). The buildings are
## `halls_<design id>` captures.
const Registry = preload("res://scripts/world/block_registry.gd")
const Herbs = preload("res://scripts/sim/herbs.gd")
const CaptureArchitecture = preload("res://scripts/presentation/capture_architecture.gd")


static func _days(sim: RefCounted, days: int) -> void:
	for day in range(days):
		sim.calendar.tick += sim.calendar.ticks_per_day
		sim.tree_growth.daily(sim)
		sim.herbs.daily(sim)


static func _middle(sim: RefCounted, block: int) -> Vector3:
	var middle := Vector3.ZERO
	var count: int = 0
	for cell in sim.herbs.plants:
		if block < 0 or sim.voxels.get_block(cell) == block:
			middle += Vector3(cell)
			count += 1
	return middle / maxf(count, 1.0)


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	main.driver.set_speed(0)
	sim.tree_growth.maturity = 12.0
	var tree: Vector3i = sim.features.sacred_tree
	match scenario:
		"alchemy_herbs":
			# Heaven's lightning has scorched a patch beside the tree.
			for dz in range(3):
				for dx in range(4):
					var x: int = tree.x + 9 + dx
					var z: int = tree.z + 4 + dz
					sim.set_block(Vector3i(x, sim.voxels.top_solid_y(x, z), z), Registry.id("scorched_earth"), 0, "capture")
			_days(sim, 10)
			main.world_view.remesh_now()
			CaptureArchitecture._look(main, Vector3(tree.x + 8.0, tree.y + 1.0, tree.z + 5.0), 14.0, -0.55, 30.0)
		"alchemy_lotus":
			sim.calendar.tick = (3 * sim.calendar.days_per_season + 1) * sim.calendar.ticks_per_day + 11 * sim.calendar.ticks_per_hour()
			_days(sim, 5)
			sim.weather.kind = "clear"
			sim.weather.until_tick = sim.calendar.tick + 100000
			main.weather_view.settle_now(0.85)
			main.world_view.remesh_now()
			# Close on one lotus: they bloom scattered along the bank.
			var lotus: Vector3 = _middle(sim, Herbs.block_id("frost_lotus"))
			for cell in sim.herbs.plants:
				if sim.voxels.get_block(cell) == Herbs.block_id("frost_lotus"):
					lotus = Vector3(cell)
					break
			CaptureArchitecture._look(main, lotus, 5.0, -0.6, 20.0)
		"alchemy_garden":
			var middle := Vector3.ZERO
			for id in ["herb_garden", "ginseng_house"]:
				var choice: Dictionary = CaptureArchitecture._stamp(sim, id)
				middle += Vector3(choice.get("origin", tree)) / 2.0
			_days(sim, 4)
			main.world_view.remesh_now()
			CaptureArchitecture._look(main, middle + Vector3(3.0, 1.0, 2.0), 15.0, -0.7, 25.0)
	var kinds: Dictionary = {}
	for cell in sim.herbs.plants:
		var name: String = Registry.block_name(sim.voxels.get_block(cell))
		kinds[name] = int(kinds.get(name, 0)) + 1
	print("ALCHEMY %s herbs %s" % [scenario, str(kinds)])
	shot.shoot_after(90)
