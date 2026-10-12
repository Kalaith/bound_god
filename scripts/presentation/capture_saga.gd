extends RefCounted
## Debug-only captures of the campaign's shape (M23): `saga_screen` (the
## Saga: ages, deeds, numbers), `saga_epilogue` (Close the book),
## `saga_chronicle` (the chronicle under its ages), `saga_ward` (the warding
## formation's edge round the tree) and `saga_realm` (the hidden realm, in
## two phases: the realm opens and the god steps through to its root heart,
## then the rebuilt scene looks over it).
const Ages = preload("res://scripts/sim/ages.gd")
const Deeds = preload("res://scripts/sim/deeds.gd")
const Session = preload("res://scripts/presentation/session.gd")
const CaptureArchitecture = preload("res://scripts/presentation/capture_architecture.gd")


## A few turns of history so the saga has something to tell.
static func _history(main: Node3D) -> void:
	var sim: RefCounted = main.sim
	var campaign: RefCounted = main.campaign
	for entry in [["sect_founded", {"sect": "sect_name|sect_adj_patient|sect_noun_root"}], ["sect_master", {"name": "Wenna Elmstead"}],
			["tree_grew", {"phase": "phase_spirit_root"}], ["raid_turned_back", {"band": "the Crow band"}]]:
		sim.chronicle.add(sim.calendar.tick, sim.calendar.day(), str(entry[0]), "Tree Hollow", entry[1], "")
		sim.calendar.tick += sim.calendar.ticks_per_day * 3
	Ages.daily(campaign)
	Deeds.daily(campaign)


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var campaign: RefCounted = main.campaign
	if scenario == "saga_realm":
		_realm(main, shot)
		return
	match scenario:
		"saga_screen":
			_history(main)
			main.open_saga()
		"saga_epilogue":
			_history(main)
			main.open_epilogue(false)
		"saga_chronicle":
			_history(main)
			main.chronicle_screen.open()
		"saga_ward":
			sim.tree_growth.unlocks.append("warding_formation")
			var tree: Vector3i = sim.features.sacred_tree
			CaptureArchitecture._look(main, Vector3(tree) + Vector3(1.0, 0.0, 1.0), 46.0, -0.95, 0.0)
	print("SAGA %s ages=%d deeds=%d" % [scenario, campaign.ages.size(), campaign.deeds.size()])
	shot.shoot_after(90)


static func _realm(main: Node3D, shot: Node) -> void:
	var campaign: RefCounted = main.campaign
	if Session.mode != "region":
		var home: RefCounted = campaign.active_sim()
		home.tree_growth.unlocks.append("root_realm")
		campaign.sync()
		var realm: RefCounted = campaign.sim_of(campaign.realm)
		var heart: Dictionary = realm.faith.shrines.values()[0]
		heart.state = "active"
		heart.support = 1.0
		home.faith.current(home).favour = 60.0
		print("SAGA realm step: %s" % str(campaign.transfer(campaign.realm, int(heart.id))))
		main.step_into_region()
		return
	var sim: RefCounted = main.sim
	main.world_view.remesh_now()
	var spring: Vector3i = sim.features.wells[0].cell
	CaptureArchitecture._look(main, Vector3(spring) + Vector3(0.5, 0.0, 0.5), 34.0, -0.62, 30.0)
	print("SAGA realm region=%d" % campaign.active)
	shot.shoot_after(90)
