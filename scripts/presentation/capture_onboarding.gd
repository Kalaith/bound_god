extends RefCounted
## Debug-only captures of contextual prompts: `onboarding_hungry` (a
## traveller beside empty chests turns the first-steps line into a prompt).
const Personality = preload("res://scripts/agents/personality.gd")


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var tree: Vector3i = sim.features.sacred_tree
	main.avatar.global_position = Vector3(tree.x + 0.5, tree.y + 0.1, tree.z + 7.5)
	main.camera_rig.yaw = PI
	main.camera_rig.pitch = -0.4
	match scenario:
		"onboarding_hungry":
			for agent in sim.agents:
				if agent.settlement_id == 1:
					agent.needs[Personality.Need.FOOD] = 12.0
					agent.carrying = {}
	shot.shoot_after(90)
