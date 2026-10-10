extends RefCounted
## Debug-only captures of cultivation: `cultivation_meditation` (people
## seated in the tree's qi with motes gathering), `cultivation_inspector`
## (the Cultivation tab of a pinned cultivator), `cultivation_qi` (the qi
## overlay from above) and `cultivation_sect` (a founded sect in the
## settlement panel).
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")
const Movement = preload("res://scripts/sim/movement.gd")


static func _seat(sim: RefCounted, count: int) -> Array:
	var camp: Vector3i = sim.settlements.entries[1].camp
	while sim.present_count() < count + 5:
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), sim.nav.nearest_walkable(camp, 4), 1, "")
	var seated: Array = []
	for agent in sim.agents:
		if agent.settlement_id != 1 or seated.size() >= count:
			continue
		agent.cultivation = CultivationState.fresh(0.6, "wood", 0.9)
		agent.cultivation.realm = 1
		agent.cultivation.progress = 120.0
		agent.cultivation.techniques = ["tree_breath"]
		var spot: Vector3i = DeliberationCultivation.spot(sim, agent)
		agent.cell = spot
		agent.position = Movement.center(spot)
		agent.previous_position = agent.position
		agent.activity = "cultivating"
		agent.intention = {}
		seated.append(agent)
	return seated


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var tree: Vector3i = sim.features.sacred_tree
	var seated: Array = _seat(sim, 4)
	var camera_rig: Node3D = main.camera_rig
	camera_rig.overlook = true
	camera_rig.overlook_center = Vector3(tree) + Vector3(1.0, 1.0, 1.0)
	camera_rig._overlook_distance = 14.0
	camera_rig._overlook_pitch = -0.45
	camera_rig._overlook_yaw = deg_to_rad(160.0)
	match scenario:
		"cultivation_inspector":
			seated[0].cultivation.teacher = seated[1].id
			seated[1].cultivation.students = [seated[0].id, seated[2].id]
			sim.apply_command({"type": "follow", "agent": seated[0].id})
			main.people.select(seated[0].id)
			main.inspector._tabs.current_tab = main.inspector.TABS.find("cultivation")
		"cultivation_qi":
			camera_rig._overlook_distance = 60.0
			camera_rig._overlook_pitch = -1.05
			main.qi_overlay.toggle()
		"cultivation_sect":
			for i in range(1, seated.size()):
				seated[i].cultivation.teacher = seated[0].id
				seated[0].cultivation.students.append(seated[i].id)
			print("SECT founded=%d" % sim.sects.found(sim, seated[0]))
			main.settlement_panel.open(1)
	shot.shoot_after(120)
