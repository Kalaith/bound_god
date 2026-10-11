extends RefCounted
## Debug-only captures of branches (M21): `branch_site` (an elder's branch on
## the first founding ground, its cutting by the camp and the route worn to
## it), `branch_menu` (the shrine menu's transfer rows: the branch's cutting
## with the journey's cost, and the cooldown after a journey) and
## `branch_panel` (the branch's settlement panel naming its parent and school).
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Branches = preload("res://scripts/sim/branches.gd")
const EffectsApply = preload("res://scripts/sim/effects_apply.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const CaptureArchitecture = preload("res://scripts/presentation/capture_architecture.gd")


## Tree Hollow's people take up the Way and found a sect; its first elder
## carries a cutting to the first ground, a disciple follows. Returns the
## branch's settlement id.
static func _branch(sim: RefCounted) -> int:
	var hollow: Array = []
	for agent in sim.agents:
		if agent.is_present() and agent.settlement_id == 1 and not agent.is_child:
			agent.cultivation = CultivationState.fresh(0.5, "none", 0.6)
			agent.cultivation.realm = 1
			agent.cultivation.techniques = ["tree_breath"]
			agent.faith.knows = true
			agent.faith.devotion = 75.0
			hollow.append(agent)
	var master: RefCounted = hollow[0]
	for i in range(1, hollow.size()):
		hollow[i].cultivation.teacher = master.id
		master.cultivation.students.append(hollow[i].id)
	sim.sects.found(sim, master)
	var parent: Dictionary = sim.sects.in_settlement(1)
	var founder: RefCounted = hollow[1]
	founder.cultivation.realm = 2
	founder.carrying = {"resource": "wood", "amount": 1.0}
	var camp: Vector3i = sim.nav.nearest_walkable(sim.features.grounds[0].center, 4)
	founder.cell = camp
	founder.position = Movement.center(camp)
	EffectsApply._settle(sim, founder, 0, Branches.Cause.AMBITION)
	var place: int = sim.settlements.on_ground(0)
	if hollow.size() > 2:
		hollow[2].cultivation.teacher = founder.id
		hollow[2].cell = camp
		EffectsApply._settle(sim, hollow[2], 0, Branches.Cause.AMBITION)
	for day in range(8):
		sim.routes.daily(sim)
		sim.paths.daily(sim)
	var branch: Dictionary = sim.sects.in_settlement(place)
	branch.doctrine.mercy = 0.85
	branch.school = "healing"
	parent["last_branch_tick"] = sim.calendar.tick
	return place


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	main.driver.set_speed(0)
	var place: int = _branch(sim)
	var cutting: Dictionary = Branches.cutting_of(sim, place)
	main.world_view.remesh_now()
	match scenario:
		"branch_site":
			CaptureArchitecture._look(main, Vector3(cutting.cell) + Vector3(0.5, 0.8, 0.5), 5.5, -0.45, 0.0)
		"branch_menu":
			cutting.state = "active"
			cutting.support = 1.6
			sim.faith.current(sim).favour = 40.0
			var tree: Vector3i = sim.features.sacred_tree
			main.avatar.global_position = Vector3(tree) + Vector3(1.5, 0.2, 5.5)
			main.camera_rig.yaw = 0.0
			main.faith._process(0.0)
			main.faith.try_open_menu()
		"branch_panel":
			CaptureArchitecture._look(main, Vector3(cutting.cell) + Vector3(0.5, 0.5, 0.5), 18.0, -0.9, 0.0)
			main.settlement_panel.open(place)
	print("BRANCH %s settlement=%d cutting=%s sects=%d" % [scenario, place, str(cutting.get("cell", "")), sim.sects.entries.size()])
	shot.shoot_after(90)
