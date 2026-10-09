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
