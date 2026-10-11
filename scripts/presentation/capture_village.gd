extends RefCounted
## Debug-only captures of the village buildings (M13): `village_day` and
## `village_night` (a hall, a garden, a store shed, a timber cottage and
## lanterns raised beside the tree), `village_panel` (the settlement panel's
## standing checklist), `village_library` (what each building does) and
## `village_requests` (a village asked to found a settlement).
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Perception = preload("res://scripts/sim/perception.gd")
const CaptureArchitecture = preload("res://scripts/presentation/capture_architecture.gd")
const CaptureHalls = preload("res://scripts/presentation/capture_halls.gd")


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	if scenario == "village_beds":
		_beds(main, shot)
		return
	var tree: Vector3i = sim.features.sacred_tree
	sim.run_ticks(12)
	_stamp(sim, "village_hall", tree.x - 15, tree.z + 6)
	_stamp(sim, "garden_patch", tree.x - 6, tree.z + 9)
	_stamp(sim, "store_shed", tree.x + 3, tree.z + 9)
	_stamp(sim, "timber_cottage", tree.x + 10, tree.z + 8)
	for offset in [Vector2i(-8, 7), Vector2i(1, 7), Vector2i(9, 6), Vector2i(-16, 4)]:
		var cell: Vector3i = sim.nav.surface(tree.x + offset.x, tree.z + offset.y)
		if cell.x >= 0:
			sim.set_block(cell, Registry.id("lantern"), 0, "god")
	var hour: float = 22.5 if scenario == "village_night" else 15.0
	sim.calendar.tick = sim.calendar.ticks_per_day * (sim.calendar.day() - 1) + int(hour / 24.0 * sim.calendar.ticks_per_day)
	main.world_view.remesh_now()
	var camera_rig: Node3D = main.camera_rig
	camera_rig.overlook = true
	camera_rig._overlook_distance = 30.0
	camera_rig._overlook_pitch = -0.62
	camera_rig._overlook_yaw = deg_to_rad(0.0)
	match scenario:
		"village_panel":
			main.settlement_panel.open(1)
		"village_library":
			main.open_library()
			main.library_screen._help = true
			main.library_screen._refresh()
		"village_requests":
			sim.settlements.entries[1].standing = "village"
			for agent in sim.agents:
				agent.faith.knows = true
				agent.faith.devotion = 80.0
				Perception.note_ground(sim, agent, 0)
				Perception.note_ground(sim, agent, 1)
			main.open_requests()
	var functions: Array = []
	for entry in sim.structures.built():
		functions.append(",".join(entry.functions))
	print("VILLAGE %s structures=%s lanterns=%d lit=%s" % [scenario, functions, sim.lanterns.size(), sim.is_lit(sim.nav.surface(tree.x - 8, tree.z + 8))])
	shot.shoot_after(120)


## Two people asleep in a timber cottage, its thatch lifted for the camera,
## each lying on their own bed.
static func _beds(main: Node3D, shot: Node) -> void:
	var sim: RefCounted = main.sim
	var choice: Dictionary = CaptureArchitecture._stamp(sim, "timber_cottage")
	var home: int = -1
	for entry in choice.get("order", []):
		if int(entry[1]) == Registry.id("bed"):
			home = sim.structure_id_at(entry[0])
	var sleepers: Array = []
	if home >= 0:
		var entry: Dictionary = sim.structures.entries[home]
		var access: Vector3i = sim.structure_access(home, entry.anchor)
		# Whoever the probe already housed here sleeps here; strangers fill
		# any bed left.
		for agent in sim.agents:
			if not agent.is_present() or (agent.home != home and entry.residents.size() >= int(entry.capacity.get("beds", 0))):
				continue
			sim.set_home(agent, home)
			agent.inside = home
			agent.activity = "sleeping"
			agent.cell = access
			agent.position = Vector3(access) + Vector3(0.5, 0.0, 0.5)
			agent.previous_position = agent.position
			sleepers.append(agent.id)
	main.driver.set_speed(0)
	# Lift the thatch for the camera, then put back the house the edit lost
	# (only the picture is opened up; the sleepers stay where they lay).
	if home >= 0:
		var kept: Dictionary = sim.structures.entries[home].duplicate(true)
		CaptureHalls._strip_roof(sim, choice)
		sim.structures.entries[home] = kept
		for id in sleepers:
			sim.agents[id].home = home
			sim.agents[id].inside = home
			sim.agents[id].activity = "sleeping"
	main.world_view.remesh_now()
	var at: Vector3 = Vector3(choice.get("origin", Vector3i.ZERO)) + Vector3(2.5, 0.6, 2.5)
	CaptureArchitecture._look(main, at, 3.5, -1.15, 20.0)
	print("VILLAGE beds home=%d sleepers=%s beds=%s" % [home, str(sleepers), str(sim.structures.entries.get(home, {}).get("components", {}).get("bed", []))])
	shot.shoot_after(90)
	main.get_tree().create_timer(1.0).timeout.connect(func() -> void:
		for id in sleepers:
			print("VILLAGE sleeper %d lies at %s" % [id, str(main.agent_views.views[id].position)]))


## Raises a valley design on levelled ground, as a god's hands could.
static func _stamp(sim: RefCounted, id: String, x: int, z: int) -> void:
	var design: RefCounted = Template.from_starter(Data.starter(id))
	var top: int = 0
	for dz in range(design.size.z):
		for dx in range(design.size.x):
			top = maxi(top, sim.voxels.top_solid_y(x + dx, z + dz))
	for dz in range(-1, design.size.z + 1):
		for dx in range(-1, design.size.x + 1):
			for y in range(top - 3, top + design.size.y + 3):
				var cell := Vector3i(x + dx, y, z + dz)
				var ground: bool = y <= top
				var want: int = Registry.id("grass") if y == top else (Registry.id("dirt") if ground else 0)
				if sim.voxels.get_block(cell) != want and Registry.component(sim.voxels.get_block(cell)) != "sacred_tree":
					sim.set_block(cell, want, 0, "god")
	for block in design.placement(0):
		sim.set_block(Vector3i(x, top + 1, z) + block[0], block[1], block[2], "god")
