extends RefCounted
## Debug-only close-ups of the figures: `figures_avatar` turns the god's
## avatar three-quarters to the camera; `figures_lineup` stands loose rigs in
## a row, one per pose, child, elder and spirit, so every pose can be checked
## in one frame.
const AgentView = preload("res://scripts/presentation/agent_view.gd")
const FigureRig = preload("res://scripts/presentation/figure_rig.gd")
const Avatar = preload("res://scripts/presentation/avatar.gd")
## activity, ground speed, look, child or elder or spirit.
const LINEUP: Array = [
	["idle", 0.0, 0, ""], ["walking", 1.4, 1, ""], ["hauling", 1.2, 2, ""], ["building", 0.0, 3, ""],
	["sowing", 0.0, 4, ""], ["praying", 0.0, 5, "elder"], ["talking", 0.0, 6, "child"], ["relaxing", 0.0, 7, ""],
	["sleeping", 0.0, 8, ""], ["idle", 0.0, 0, "spirit"],
]


static func arrange(main: Node3D, shot: Node, scenario: String) -> void:
	var rig: Node3D = main.camera_rig
	if scenario == "figures_avatar":
		main.avatar.rotation.y = deg_to_rad(150.0)
		rig.yaw = deg_to_rad(10.0)
		rig.pitch = -0.12
		rig.distance = 3.2
		shot.shoot_after(60)
		return
	_lineup(main, shot)


static func _lineup(main: Node3D, shot: Node) -> void:
	var sim: RefCounted = main.sim
	# In a row across the meadow, looking back at where the avatar first stands
	# with the sacred tree behind it.
	var start: Vector3 = main.avatar.global_position
	var origin := Vector3i(floori(start.x) - 6, floori(start.y), floori(start.z) + 5)
	var rigs: Array = []
	for index in range(LINEUP.size()):
		var entry: Array = LINEUP[index]
		var rig := FigureRig.new()
		var look: int = int(entry[2])
		var colours: Dictionary = Avatar.COLOURS.duplicate()
		if entry[3] != "spirit":
			var jacket: Color = AgentView.JACKETS[look % AgentView.JACKETS.size()]
			colours = {"jacket": jacket, "trim": jacket.darkened(0.38), "sash": AgentView.SASHES[look % AgentView.SASHES.size()],
				"trousers": AgentView.TROUSERS[look % AgentView.TROUSERS.size()], "skin": AgentView.SKINS[look % AgentView.SKINS.size()],
				"hair": AgentView.GREY_HAIR if entry[3] == "elder" else AgentView.HAIRS[look % AgentView.HAIRS.size()],
				"accent": AgentView.COLLAR, "straw": AgentView.STRAW}
		rig.build(colours, look, entry[3] == "spirit")
		rig.elder = entry[3] == "elder"
		if entry[3] == "child":
			rig.scale = Vector3.ONE * 0.7
			rig.head.scale = Vector3.ONE * 1.22
		var x: int = origin.x + int(index * 1.3)
		var ground: int = sim.voxels.top_solid_y(x, origin.z) + 1
		rig.position = Vector3(origin.x + index * 1.3 + 0.5, ground if absi(ground - origin.y) < 3 else origin.y, origin.z + 0.5)
		rig.rotation.y = PI
		rig.set_cargo(AgentView.RESOURCE_COLORS.wood if entry[0] == "hauling" else null)
		main.add_child(rig)
		rigs.append(rig)
	var clock: Array = [0.0]
	main.get_tree().process_frame.connect(func() -> void:
		var delta: float = 1.0 / 60.0
		clock[0] += delta
		for index in range(rigs.size()):
			rigs[index].pose(LINEUP[index][0], clock[0] + index * 0.7, LINEUP[index][1], delta))
	main.avatar.global_position = Vector3(origin.x + LINEUP.size() * 0.65, start.y, start.z)
	main.avatar.zone_radius = 1000.0
	main.avatar._figure.hide()
	main.camera_rig.yaw = PI
	main.camera_rig.pitch = -0.1
	main.camera_rig.distance = 2.5
	print("FIGURES lineup of %d at %s" % [rigs.size(), str(origin)])
	shot.shoot_after(90)
