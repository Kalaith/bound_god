extends RefCounted
## Debug-only captures of the tree's growth: `tree_screen` (the tree screen
## after two lightning trials beneath it), `tree_fruit` (spirit fruit on
## the boughs and lightning scars on the bark), `tree_lessons` (the screen
## once it has learned from winters, droughts, teaching and a death, with
## what is still locked) and `tree_roots` (its roots' reach marked along a
## worn path beyond the presence ring).
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const TreeAbilities = preload("res://scripts/sim/tree_abilities.gd")


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var tree: Vector3i = sim.features.sacred_tree
	for i in range(2):
		var agent: RefCounted = sim.agents[i]
		var trial: Dictionary = {"id": i + 1, "agent": agent.id, "kind": "lightning", "severity": 0.55 + 0.2 * i, "shield": 0.0,
			"defy": false, "site": tree + Vector3i(5 - i * 9, 0, 3), "sanctuary": true, "outcome": "passed" if i == 0 else "injured", "state": "done"}
		sim.tree_growth.on_trial(sim, trial, agent)
		sim.calendar.tick += sim.calendar.ticks_per_day
	for _day in range(8):
		sim.calendar.tick += sim.calendar.ticks_per_day
		sim.tree_growth.daily(sim)
	if scenario in ["tree_lessons", "tree_roots"]:
		_lessons(sim)
	if scenario == "tree_roots":
		_worn_path(sim, tree)
	main.world_view.remesh_now()
	var camera_rig: Node3D = main.camera_rig
	camera_rig.overlook = true
	camera_rig.overlook_center = Vector3(tree) + Vector3(1.0, 4.0, 1.0)
	camera_rig._overlook_distance = 16.0
	camera_rig._overlook_pitch = -0.12
	camera_rig._overlook_yaw = deg_to_rad(110.0 if scenario == "tree_fruit" else 20.0)
	if scenario == "tree_roots":
		main.camera_hold = true
		camera_rig.overlook_center = Vector3(tree) + Vector3(22.0, 2.0, 12.0)
		camera_rig._overlook_distance = 34.0
		camera_rig._overlook_pitch = -0.75
	if scenario in ["tree_screen", "tree_lessons"]:
		main.tree_screen.open()
	print("TREE insight=%s fruit=%d scars=%d phase=%s unlocks=%s rooted=%d" % [str(sim.tree_growth.insights), sim.tree_growth.fruit, sim.tree_growth.scars.size(),
		sim.tree_growth.phase_id(), str(sim.tree_growth.unlocks), sim.tree_growth.rooted_paths.size()])
	shot.shoot_after(90)


## Two droughts, three winters, teaching and two deaths beneath it, and
## the years to reach the Heaven-Touched Tree.
static func _lessons(sim: RefCounted) -> void:
	var growth: RefCounted = sim.tree_growth
	var first: RefCounted = sim.agents[0]
	for i in range(2):
		growth.lesson(sim, "drought")
	for i in range(3):
		growth.lesson(sim, "winter")
	for i in range(12):
		growth.lesson(sim, "teaching", first.full_name())
	growth.lesson(sim, "death", sim.agents[1].full_name())
	growth.maturity = 101.0
	growth.daily(sim)


## A path worn from beside the tree out east, past the ring.
static func _worn_path(sim: RefCounted, tree: Vector3i) -> void:
	var path: int = Registry.id("path")
	for x in range(tree.x + 6, tree.x + 44):
		var z: int = tree.z + 6 + (x - tree.x) / 4
		var top: int = sim.voxels.top_solid_y(x, z)
		if top < 0 or sim.voxels.get_xyz(x, top, z) != Registry.id("grass"):
			continue
		sim.set_block(Vector3i(x, top, z), path, 0, "capture")
		sim.paths.wear[Vector2i(x, z)] = 40.0
	TreeAbilities.refresh_roots(sim)
