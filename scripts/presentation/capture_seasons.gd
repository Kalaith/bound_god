extends RefCounted
## Debug-only captures of the sky and herbs (M20): `seasons_rain`,
## `seasons_storm` and `seasons_snow` (the village under each, with the
## weather in the clock line) and `seasons_herbs` (spirit herbs grown and
## ripened in the tree's deep qi).
const CaptureArchitecture = preload("res://scripts/presentation/capture_architecture.gd")
const Herbs = preload("res://scripts/sim/herbs.gd")

const SKIES: Dictionary = {"seasons_rain": "rain", "seasons_storm": "thunderstorm", "seasons_snow": "snow"}


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	main.driver.set_speed(0)
	var tree: Vector3i = sim.features.sacred_tree
	match scenario:
		"seasons_herbs":
			sim.tree_growth.maturity = 12.0
			for day in range(8):
				sim.calendar.tick += sim.calendar.ticks_per_day
				sim.tree_growth.daily(sim)
				sim.herbs.daily(sim)
			main.world_view.remesh_now()
			var middle := Vector3.ZERO
			for cell in sim.herbs.plants:
				middle += Vector3(cell)
			middle /= maxf(sim.herbs.count(), 1.0)
			CaptureArchitecture._look(main, middle, 16.0, -0.6, 35.0)
			print("SEASONS herbs=%d ripe=%d" % [sim.herbs.count(), _ripe(sim)])
		_:
			if scenario == "seasons_snow":
				sim.calendar.tick = (3 * sim.calendar.days_per_season + 2) * sim.calendar.ticks_per_day + 11 * sim.calendar.ticks_per_hour()
			sim.weather.kind = str(SKIES.get(scenario, "clear"))
			sim.weather.until_tick = sim.calendar.tick + 100000
			main.weather_view.settle_now(0.85 if scenario == "seasons_snow" else 0.0)
			CaptureArchitecture._look(main, Vector3(tree.x + 6.0, tree.y + 2.0, tree.z + 6.0), 30.0, -0.45, 20.0)
			print("SEASONS sky=%s" % sim.weather.kind)
	shot.shoot_after(90)


static func _ripe(sim: RefCounted) -> int:
	var count: int = 0
	for cell in sim.herbs.plants:
		if sim.voxels.block_meta(cell) >= Herbs.RIPE:
			count += 1
	return count
