extends RefCounted
## Debug-only captures of faith: `faith_menu` lets the travellers believe and
## pray for a day, then opens the shrine menu beside the tree;
## `faith_miracle` works Bless Growth among them and catches its flash.


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	for agent in sim.agents:
		if agent.settlement_id == 1:
			agent.faith.knows = true
			agent.faith.saw_god = true
			agent.faith.devotion = 55.0
			agent.needs[0] = 30.0
	if scenario == "faith_ridge":
		_ridge(main, shot)
		return
	if scenario == "faith_raid":
		_raid(main, shot)
		return
	sim.run_ticks(sim.calendar.ticks_per_hour() * 20)
	main.world_view.remesh_now()
	var tree: Vector3i = sim.features.sacred_tree
	main.avatar.global_position = Vector3(tree) + Vector3(1.5, 0.2, 5.5)
	main.camera_rig.yaw = 0.0
	main.camera_rig.pitch = -0.2
	main.faith._process(0.0)
	if scenario == "faith_miracle":
		var at := Vector3i(main.avatar.global_position.floor())
		var result: Dictionary = sim.apply_command({"type": "cast_miracle", "miracle": "bless_growth", "cell": at})
		print("FAITH miracle=%s" % str(result))
		main.world_view.remesh_now()
		shot.shoot_after(25)
		return
	main.faith.try_open_menu()
	var shrine: Dictionary = sim.faith.current(sim)
	print("FAITH prayers=%d favour=%.1f support=%.2f renown=%d" % [shrine.prayers.size(), shrine.favour, shrine.support, sim.god.renown])
	shot.shoot_after(40)


## Followers carry the name until the ridge altar wakes; the god steps
## through and looks at the ridge with the shrine menu open.
static func _ridge(main: Node3D, shot: Node) -> void:
	var sim: RefCounted = main.sim
	for agent in sim.agents:
		if agent.settlement_id == 1:
			agent.faith.devotion = 72.0
	sim.faith.shrines[1].favour = 60.0
	for day in range(15):
		var open: bool = false
		for id in sim.requests.ids():
			open = open or sim.requests.requests[id].state == "open"
		if not open:
			sim.apply_command({"type": "post_request", "kind": "carry_name", "target": 2, "boon": 10})
		sim.run_ticks(sim.calendar.ticks_per_day)
		if sim.faith.shrines[2].state == "active":
			break
	sim.run_ticks(sim.calendar.ticks_per_hour() * 4)
	var result: Dictionary = sim.apply_command({"type": "transfer_shrine", "shrine": 2})
	# Once to follow the god through, once to report where the avatar now stands.
	main.faith._process(0.0)
	main.faith._process(0.0)
	main.world_view.remesh_now()
	main.camera_rig.yaw = PI * 0.75
	main.camera_rig.pitch = -0.25
	print("FAITH ridge day=%d state=%s transfer=%s" % [sim.calendar.day(), sim.faith.shrines[2].state, result.reason])
	main.faith.try_open_menu()
	shot.shoot_after(60)


## A wealthy ridge with a living altar on raid day: the band at the stores.
static func _raid(main: Node3D, shot: Node) -> void:
	var sim: RefCounted = main.sim
	sim.set_block(sim.features.ruin.altar, preload("res://scripts/world/block_registry.gd").id("altar"), 0, "capture")
	sim.faith.shrines[2].state = "active"
	for chest in sim.settlements.chest_cells(sim, 2):
		for resource in ["berries", "stone", "wood", "ore"]:
			sim.settlements.chest_add(chest, resource, 10)
	sim.calendar.tick = sim.calendar.ticks_per_day * 11
	var raiders: int = 0
	for _hour in range(24 * 14):
		sim.run_ticks(sim.calendar.ticks_per_hour())
		raiders = 0
		for id in sim.threats.ids():
			if sim.threats.entries[id].kind == "raider" and sim.threats.entries[id].state in ["loot", "altar"]:
				raiders += 1
		if raiders > 0:
			break
	# Debug shot only: show it by daylight, with the god standing at the ridge.
	sim.calendar.tick = (sim.calendar.tick / sim.calendar.ticks_per_day) * sim.calendar.ticks_per_day + sim.calendar.ticks_per_hour() * 13
	sim.god.dormant = false
	sim.god.active_shrine_id = 2
	main.avatar.set_dormant(false)
	main.faith._process(0.0)
	var camp: Vector3i = sim.settlements.entries[2].camp
	main.avatar.global_position = Vector3(sim.features.ruin.altar) + Vector3(1.5, 0.2, -2.5)
	main.camera_rig.overlook = true
	main.camera_rig.overlook_center = Vector3(camp)
	main.camera_rig._overlook_distance = 22.0
	main.camera_rig._overlook_pitch = -0.7
	main.world_view.remesh_now()
	print("FAITH raid day=%d raiders_at_stores=%d" % [sim.calendar.day(), raiders])
	shot.shoot_after(40)
