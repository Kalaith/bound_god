extends RefCounted
## Debug-only captures of regions (M22), in two phases because stepping into
## another region rebuilds the scene: first the marsh's people raise an
## altar and the god steps through to it; then, in the rebuilt scene,
## `region_arrival` looks over the marsh settlement, `region_menu` opens
## the shrine menu there, listing the shrines of every region, and
## `region_lands` the lands panel.
const Registry = preload("res://scripts/world/block_registry.gd")
const Session = preload("res://scripts/presentation/session.gd")
const CaptureArchitecture = preload("res://scripts/presentation/capture_architecture.gd")


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var campaign: RefCounted = main.campaign
	if Session.mode != "region":
		var home: RefCounted = campaign.active_sim()
		home.faith.current(home).favour = 60.0
		var marsh: RefCounted = campaign.sim_of(1)
		var settlement: Dictionary = marsh.settlements.entries[1]
		var cell: Vector3i = marsh.nav.surface(settlement.camp.x - 3, settlement.camp.z + 2)
		marsh.set_block(cell, Registry.id("altar"), 0, "npc:0")
		var shrine: Dictionary = marsh.faith.get_shrine(int(marsh.faith.by_cell[cell]))
		shrine.state = "active"
		shrine.support = 2.0
		shrine.favour = 20.0
		for agent in marsh.agents:
			agent.faith.knows = true
			agent.faith.devotion = 72.0
		var result: Dictionary = campaign.transfer(1, int(shrine.id))
		print("REGION stepped through: %s" % str(result))
		main.step_into_region()
		return
	var sim: RefCounted = main.sim
	main.world_view.remesh_now()
	var shrine: Dictionary = sim.faith.current(sim)
	match scenario:
		"region_arrival":
			CaptureArchitecture._look(main, Vector3(sim.settlements.entries[1].center) + Vector3(0.5, 1.0, 0.5), 30.0, -0.7, 0.0)
		"region_menu":
			main.faith._process(0.0)
			main.faith.try_open_menu()
		"region_lands":
			main.open_lands()
	print("REGION %s active=%d shrine=%s people=%d" % [scenario, campaign.active, str(shrine.get("name", "")), sim.present_count()])
	shot.shoot_after(90)
