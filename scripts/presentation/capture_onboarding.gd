extends RefCounted
## Debug-only captures of contextual prompts: `onboarding_hungry` (a
## traveller beside empty chests turns the first-steps line into a prompt),
## and the M25 prompts `onboarding_lands`, `onboarding_realm`, `onboarding_saga`
## (their moment set by hand, every other prompt put away).
const Personality = preload("res://scripts/agents/personality.gd")
const Prompts = preload("res://scripts/presentation/ui/prompts.gd")


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
		"onboarding_lands":
			sim.traders.append({"region": 1, "region_name": "", "goods": [], "technique": "", "sect": "", "friendly": true})
			_only(sim, "prompt_lands")
		"onboarding_realm":
			sim.sanctuary["realm"] = true
			_only(sim, "prompt_realm")
		"onboarding_saga":
			sim.chronicle.add(sim.calendar.tick, 30, "age_began", "", {"age": "age_first"})
			_only(sim, "prompt_saga")
	shot.shoot_after(90)


## Puts away every prompt that would show now but `id`, and the guide.
static func _only(sim: RefCounted, id: String) -> void:
	for prompt in Prompts.contextual(sim):
		if str(prompt.id) != id:
			sim.god.prompts_dismissed.append(prompt.id)
	if not sim.god.prompts_dismissed.has("prompt_no_favour"):
		sim.god.prompts_dismissed.append("prompt_no_favour")
	sim.god.prompts_dismissed.append("prompt_cold")
