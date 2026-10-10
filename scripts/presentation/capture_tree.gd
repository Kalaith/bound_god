extends RefCounted
## Debug-only captures of the tree's growth: `tree_screen` (the tree screen
## after two lightning trials beneath it) and `tree_fruit` (spirit fruit on
## the boughs and lightning scars on the bark).
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")


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
	main.world_view.remesh_now()
	var camera_rig: Node3D = main.camera_rig
	camera_rig.overlook = true
	camera_rig.overlook_center = Vector3(tree) + Vector3(1.0, 4.0, 1.0)
	camera_rig._overlook_distance = 16.0
	camera_rig._overlook_pitch = -0.12
	camera_rig._overlook_yaw = deg_to_rad(110.0 if scenario == "tree_fruit" else 20.0)
	if scenario == "tree_screen":
		main.tree_screen.open()
	print("TREE insight=%s fruit=%d scars=%d phase=%s" % [str(sim.tree_growth.insights), sim.tree_growth.fruit, sim.tree_growth.scars.size(), sim.tree_growth.phase_id()])
	shot.shoot_after(90)
