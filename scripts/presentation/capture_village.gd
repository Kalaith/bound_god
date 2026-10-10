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


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
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
