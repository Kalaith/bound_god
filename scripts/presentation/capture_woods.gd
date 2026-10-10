extends RefCounted
## Debug-only capture of the woods: `woods_grove` shows, beside the nearest
## home tree, saplings set in the grass, a tree just grown from one, and the
## home tree with its top logs cut and its hanging crown half fallen.
const Registry = preload("res://scripts/world/block_registry.gd")
const Woods = preload("res://scripts/sim/woods.gd")


static func arrange(main: Node3D, shot: Node, _scenario: String) -> void:
	var sim: RefCounted = main.sim
	var tree: Vector3i = sim.features.sacred_tree
	sim.run_ticks(12)
	var home: int = -1
	for id in sim.sites.ids_sorted():
		var site: Dictionary = sim.sites.get_site(id)
		if site.kind == "tree" and (home < 0 or Vector3(site.cells[0]).distance_to(Vector3(tree)) < Vector3(sim.sites.get_site(home).cells[0]).distance_to(Vector3(tree))):
			home = id
	var trunk: Vector3i = sim.sites.get_site(home).cells[0]
	# Cut the top two logs, then let a few hours pass for the crown to thin.
	var logs: Array = sim.sites.get_site(home).cells.duplicate()
	logs.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y > b.y)
	for index in range(2):
		sim.set_block(logs[index], 0, 0, "god")
	var hanging: int = sim.woods.falling.size()
	for _hour in range(3):
		sim.woods.hourly(sim)
	# Saplings in a row on open grass nearby, and one grown into a tree.
	var planted: Array = []
	for ring in range(3, 9):
		for dx in range(-ring, ring + 1):
			var cell: Vector3i = sim.nav.surface(trunk.x + dx, trunk.z + ring)
			if cell.x >= 0 and Woods.room_for_tree(sim, cell):
				sim.set_block(cell, Registry.id("sapling"), 0, "god")
				planted.append(cell)
			if planted.size() >= 4:
				break
		if planted.size() >= 4:
			break
	var grown: int = sim.woods.grow(sim, planted[0]) if not planted.is_empty() else -1
	print("WOODS home tree %s: %d leaves left hanging, %d still falling; %d saplings, grown tree %d" % [
		str(trunk), hanging, sim.woods.falling.size(), sim.woods.saplings.size(), grown])
	# The overlook always centres on the shrine, so stand south of the tree and look north.
	main.avatar.global_position = Vector3(trunk) + Vector3(1.5, 0.2, 15.5)
	main.camera_rig.yaw = 0.0
	main.camera_rig.pitch = -0.22
	main.camera_rig.distance = 10.0
	main.world_view.remesh_now()
	shot.shoot_after(120)
