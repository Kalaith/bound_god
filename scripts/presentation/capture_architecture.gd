extends RefCounted
## Debug-only captures of sect architecture: `arch_hall` (a meditation hall
## with cultivators on its mats, and a tribulation ground beyond),
## `arch_ground` (a tribulation ground), `arch_blueprint` (a cottage the god
## has laid as a proposal), `arch_library` (the design library with Lay
## blueprint) and `arch_paths` (the ways six days of life have worn).
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const SiteFinder = preload("res://scripts/building/site_finder.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Movement = preload("res://scripts/sim/movement.gd")


static func _stamp(sim: RefCounted, id: String) -> Dictionary:
	var template: RefCounted = Template.from_starter(Data.starter(id))
	var choice: Dictionary = SiteFinder.find(sim, template, sim.settlements.entries[1])
	if choice.is_empty():
		return {}
	for entry in choice.order:
		sim.set_block(entry[0], entry[1], entry[2], "capture")
	return choice


## Looks at `at` from the side away from the sacred tree (turned by `turn`
## degrees), so the trunk never stands between the camera and the subject.
static func _look(main: Node3D, at: Vector3, distance: float, pitch: float, turn: float) -> void:
	var camera_rig: Node3D = main.camera_rig
	var tree: Vector3i = main.sim.features.get("sacred_tree", Vector3i(80, 12, 80))
	main.camera_hold = true
	camera_rig.overlook = true
	camera_rig.overlook_center = at
	camera_rig._overlook_distance = distance
	camera_rig._overlook_pitch = pitch
	camera_rig._overlook_yaw = atan2(at.x - tree.x - 1.0, at.z - tree.z - 1.0) + deg_to_rad(turn)
	main.avatar.zone_radius = 1000.0


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	main.driver.set_speed(0)
	for id in ["meditation_hall", "trial_ground", "timber_cottage"]:
		sim.apply_command({"type": "offer_template", "template": Template.from_starter(Data.starter(id)).to_dict()})
	match scenario:
		"arch_paths":
			sim.run_ticks(sim.calendar.ticks_per_day * 6)
			main.world_view.remesh_now()
			var worn: Array = []
			for column in sim.paths.wear:
				var top: int = sim.voxels.top_solid_y(column.x, column.y)
				if sim.voxels.get_block(Vector3i(column.x, top, column.y)) == Data.block_id("path"):
					worn.append(Vector3(column.x, top, column.y))
			var middle := Vector3.ZERO
			for at in worn:
				middle += at / maxf(worn.size(), 1.0)
			_look(main, middle if not worn.is_empty() else Vector3(sim.settlements.entries[1].camp), 24.0, -0.95, 0.0)
			print("ARCH paths=%d" % worn.size())
		"arch_hall":
			var hall: Dictionary = _stamp(sim, "meditation_hall")
			var ground: Dictionary = _stamp(sim, "trial_ground")
			main.world_view.remesh_now()
			var entry: Dictionary = {}
			for built in sim.structures.built():
				if built.functions.has("meditation_hall"):
					entry = built
			var mats: Array = entry.get("components", {}).get("mat", [])
			for i in range(mini(mats.size(), 3)):
				var agent: RefCounted = sim.agents[i]
				agent.cultivation = CultivationState.fresh(0.6, "wood", 0.8)
				agent.cell = mats[i]
				agent.position = Movement.center(mats[i])
				agent.previous_position = agent.position
				agent.intention = {}
				agent.activity = "cultivating"
			var middle: Vector3 = Vector3(hall.get("origin", Vector3i.ZERO)) + Vector3(3.5, 1.0, 3.0)
			_look(main, middle, 18.0, -0.75, 35.0)
			print("ARCH hall=%s ground=%s mats=%d functions=%s" % [str(hall.get("origin", "none")), str(ground.get("origin", "none")), mats.size(), str(entry.get("functions", []))])
		"arch_ground":
			var ground: Dictionary = _stamp(sim, "trial_ground")
			main.world_view.remesh_now()
			_look(main, Vector3(ground.get("origin", Vector3i.ZERO)) + Vector3(2.5, 1.0, 2.5), 14.0, -0.6, 25.0)
			print("ARCH ground=%s" % str(ground.get("origin", "none")))
		"arch_blueprint", "arch_library":
			var template: RefCounted = Template.from_starter(Data.starter("timber_cottage"))
			var settlement: Dictionary = sim.settlements.entries[1]
			var laid: Dictionary = {}
			for ring in range(6, 20, 2):
				for k in range(8):
					var corner := Vector3i(settlement.center.x + roundi(cos(k * PI / 4.0) * ring), 0, settlement.center.z + roundi(sin(k * PI / 4.0) * ring))
					if laid.is_empty() and sim.apply_command({"type": "lay_blueprint", "template": template.id, "origin": corner, "rotation": 1}).ok:
						laid = sim.god.blueprints.back()
			print("ARCH blueprint=%s" % str(laid))
			_look(main, Vector3(laid.get("origin", Vector3i.ZERO)) + Vector3(2.5, 1.0, 2.5), 16.0, -0.6, 20.0)
			if scenario == "arch_library":
				# A design of the player's own, offered, can be laid as a blueprint.
				main._open_library()
				if main.library_screen.selected != null:
					main._offer(main.library_screen.selected)
	shot.shoot_after(60)
