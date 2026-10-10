extends RefCounted
## Debug-only captures of Heaven's trials: `trial_storm` (a storm over a
## cultivator beside the tree, lightning falling, the inspector showing the
## trial) and `trial_warning` (the cloud gathering, the prompt and prayer).
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Movement = preload("res://scripts/sim/movement.gd")


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var tree: Vector3i = sim.features.sacred_tree
	var agent: RefCounted = sim.agents[0]
	agent.cultivation = CultivationState.fresh(0.7, "wood", 0.9)
	agent.cultivation.realm = 1
	agent.cultivation.progress = CultivationState.needed(agent.cultivation)
	agent.cultivation.techniques = ["tree_breath"]
	var site: Vector3i = sim.nav.nearest_walkable(tree + Vector3i(7, 0, 4), 3)
	agent.cell = site
	agent.position = Movement.center(site)
	agent.previous_position = agent.position
	agent.activity = "facing_heaven"
	agent.intention = {}
	agent.next_deliberation = sim.calendar.tick + 100000
	sim.apply_command({"type": "follow", "agent": agent.id})
	var id: int = sim.tribulations.announce(sim, agent, site)
	var trial: Dictionary = sim.tribulations.entries[id]
	var camera_rig: Node3D = main.camera_rig
	camera_rig.overlook = true
	camera_rig.overlook_center = Vector3(site) + Vector3(0.5, 6.0, 0.5)
	camera_rig._overlook_distance = 26.0
	camera_rig._overlook_pitch = -0.18
	camera_rig._overlook_yaw = deg_to_rad(110.0)
	if scenario == "trial_storm":
		# Strike every few ticks from now, so the shot lands just after one.
		trial.start_tick = sim.calendar.tick + 1
		var strikes: Array = []
		for i in range(12):
			strikes.append(sim.calendar.tick + 2 + i * 4)
		trial.strikes = strikes
		trial.end_tick = sim.calendar.tick + 200
		main.people.select(agent.id)
		main.inspector._tabs.current_tab = main.inspector.TABS.find("cultivation")
		for _i in range(42):
			await main.get_tree().process_frame
			sim.tribulations.step(sim)
			sim.calendar.tick += 1
			agent.activity = "facing_heaven"
		main.world_view.remesh_now()
		shot.shoot_after(1)
		return
	shot.shoot_after(90)
