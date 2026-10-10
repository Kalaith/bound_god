extends RefCounted
## Debug-only verification scenarios for `-- --capture=<scenario>`: each sets
## up a shot (and sometimes a scripted test that prints its result), then asks
## the Capture node to save the frame. Never used in normal play.
const Capture = preload("res://scripts/presentation/capture.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Template = preload("res://scripts/building/template.gd")
const TextForCapture = preload("res://scripts/core/text.gd")
const Data = preload("res://scripts/core/data.gd")
const CapturePeople = preload("res://scripts/presentation/capture_people.gd")
const CaptureStores = preload("res://scripts/presentation/capture_stores.gd")
const CaptureSettlement = preload("res://scripts/presentation/capture_settlement.gd")
const CaptureFaith = preload("res://scripts/presentation/capture_faith.gd")
const CaptureTime = preload("res://scripts/presentation/capture_time.gd")
const CaptureVillage = preload("res://scripts/presentation/capture_village.gd")
const CaptureFood = preload("res://scripts/presentation/capture_food.gd")
const CaptureInput = preload("res://scripts/presentation/capture_input.gd")


static func arrange(main: Node3D, request: Dictionary) -> void:
	var shot: Node = Capture.new()
	shot.configure(request)
	main.add_child(shot)
	var scenario: String = str(request.scenario)
	var camera_rig: Node3D = main.camera_rig
	var avatar: Node3D = main.avatar
	var sim: RefCounted = main.sim
	if not request.has("load"):
		sim.calendar.tick = sim.calendar.ticks_per_day * 10 / 24
	if scenario.begins_with("time_"):
		CaptureTime.arrange(main, shot, scenario)
		return
	if scenario.begins_with("faith_"):
		CaptureFaith.arrange(main, shot, scenario)
		return
	if scenario.begins_with("settlement_"):
		CaptureSettlement.arrange(main, shot, scenario)
		return
	if scenario.begins_with("people_"):
		CapturePeople.arrange(main, shot, scenario)
		return
	if scenario.begins_with("stores_"):
		CaptureStores.arrange(main, shot, scenario)
		return
	if scenario.begins_with("village_"):
		CaptureVillage.arrange(main, shot, scenario)
		return
	if scenario.begins_with("input_"):
		CaptureInput.arrange(main, shot, scenario)
		return
	if scenario.begins_with("food_"):
		CaptureFood.arrange(main, shot, scenario)
		return
	match scenario:
		"design_library", "design_box", "design_invalid":
			_design_test(main, shot, scenario)
			return
		"valley_overview":
			camera_rig.overlook = true
			camera_rig._overlook_distance = 120.0
			camera_rig._overlook_pitch = -0.75
			camera_rig._overlook_yaw = deg_to_rad(-135.0)
			camera_rig.overlook_center = Vector3(80, 14, 80)
			avatar.zone_radius = 1000.0
		"valley_ridge":
			var ruin: Dictionary = sim.features.ruin
			avatar.zone_radius = 1000.0
			avatar.global_position = Vector3(ruin.altar) + Vector3(-6, 1, -10)
			camera_rig.yaw = deg_to_rad(200.0)
		"walk_test":
			_walk_test(main, shot)
			return
		"build_test":
			_build_test(main, shot)
			return
		"zone_edge":
			_zone_edge(main, shot)
			return
		_:
			camera_rig.yaw = deg_to_rad(180.0)
			camera_rig.pitch = -0.12
	shot.shoot_after()


static func _design_test(main: Node3D, shot: Node, scenario: String) -> void:
	var sim: RefCounted = main.sim
	var origin: Vector3i = sim.features.sacred_tree + Vector3i(-7, 0, 5)
	var design: RefCounted = Template.from_starter(Data.starter("miner_hut"))
	# Prepare a level patch, then place the cottage through player commands.
	for z in range(-2, 8):
		for x in range(-2, 8):
			for y in range(-1, 8):
				sim.set_block(origin + Vector3i(x, y, z), Registry.id("dirt") if y == -1 else 0, 0, "capture_setup")
	sim.god.add_stock("wood", 200)
	sim.god.add_stock("stone", 200)
	sim.god.add_stock("thatch", 200)
	var worst: int = 0
	var placed: int = 0
	for block in design.placement(0):
		var start: int = Time.get_ticks_usec()
		var result: Dictionary = sim.apply_command({"type": "edit_block", "cell": origin + block[0], "id": block[1], "meta": block[2]})
		worst = maxi(worst, Time.get_ticks_usec() - start)
		if result.ok:
			placed += 1
	main.world_view.remesh_now()
	main.avatar.global_position = Vector3(origin) + Vector3(2, 0.1, -3)
	main.camera_rig.yaw = PI
	main.camera_rig.pitch = -0.2
	main.library_screen.library.root = "user://verification_capture_m3"
	main.design_tool.begin()
	main.design_tool.mark(origin)
	if scenario == "design_box":
		main.design_tool.set_process(false)
		main.design_tool.show_box(origin, origin + design.size - Vector3i.ONE)
	else:
		main.design_tool.mark(origin + design.size - Vector3i.ONE)
		if scenario == "design_invalid":
			main.library_screen._notice.text = TextForCapture.label("template_blocks")
	print("DESIGN placed=%d functions=%s capacity=%s worst_command_ms=%.2f" % [placed, design.functions, design.capacity, worst / 1000.0])
	shot.shoot_after(60)


## Walk over a one-block step into a two-block wall, then jump at it.
static func _walk_test(main: Node3D, shot: Node) -> void:
	var sim: RefCounted = main.sim
	var avatar: Node3D = main.avatar
	var tree: Vector3i = sim.features.sacred_tree
	var ground: int = tree.y
	var start := Vector3(tree.x + 0.5, ground + 0.1, tree.z + 4.5)
	avatar.global_position = start
	for dx in range(-3, 4):
		sim.voxels.set_block(Vector3i(tree.x + dx, ground, tree.z + 8), 3)
		for dz in range(9, 12):
			sim.voxels.set_block(Vector3i(tree.x + dx, ground, tree.z + dz), 3)
		for dy in range(3):
			sim.voxels.set_block(Vector3i(tree.x + dx, ground + dy, tree.z + 12), 3)
	main.world_view.remesh_now()
	main.camera_rig.yaw = PI
	main.camera_rig.pitch = -0.35
	avatar.autopilot = Vector2(0, -1)
	var highest: float = start.y
	for frame in range(180):
		await main.get_tree().physics_frame
		highest = maxf(highest, avatar.global_position.y)
	var stepped: bool = highest >= ground + 1.0
	var blocked: bool = avatar.global_position.z < tree.z + 12.0
	avatar.autopilot_jump = true
	for frame in range(60):
		await main.get_tree().physics_frame
	print("WALK step_climbed=%s wall_blocked=%s final=%s fps=%d" % [stepped, blocked, avatar.global_position, Engine.get_frames_per_second()])
	avatar.autopilot = Vector2.ZERO
	shot.shoot_after(10)


## Place and break through the real build controller, timing the re-mesh.
static func _build_test(main: Node3D, shot: Node) -> void:
	var sim: RefCounted = main.sim
	var builder: Node3D = main.builder
	var tree: Vector3i = sim.features.sacred_tree
	main.avatar.global_position = Vector3(tree.x + 0.5, tree.y + 0.1, tree.z + 6.5)
	main.camera_rig.yaw = PI
	main.camera_rig.pitch = -0.55
	sim.god.add_stock("wood", 40)
	sim.god.add_stock("thatch", 10)
	var Registry = preload("res://scripts/world/block_registry.gd")
	sim.apply_command({"type": "set_hotbar", "slots": [Registry.id("planks"), 0, Registry.id("thatch"), 0, 0, 0, 0, 0, 0]})
	for frame in range(10):
		await main.get_tree().process_frame
	var placed: int = 0
	var times: Array = []
	for index in range(6):
		builder.select(0 if index % 2 == 0 else 2)
		await main.get_tree().process_frame
		var before: int = Time.get_ticks_usec()
		var cell: Vector3i = builder.place_cell
		builder._act(false)
		times.append((Time.get_ticks_usec() - before) / 1000.0)
		if sim.voxels.get_block(cell) != 0:
			placed += 1
	await main.get_tree().process_frame
	var target_before: Vector3i = builder.target.cell
	var stock_before: int = sim.god.stock("wood")
	builder._act(true)
	var broke: bool = sim.voxels.get_block(target_before) == 0
	print("BUILD placed=%d broke=%s wood_back=%d remesh_ms=%s" % [placed, broke, sim.god.stock("wood") - stock_before, times])
	sim.god.divine_stock.clear()
	builder.select(0)
	await main.get_tree().process_frame
	print("BUILD no_stock_problem=%s" % builder.place_problem)
	shot.shoot_after(20)


## Walk straight out of the zone: the binding must hold.
static func _zone_edge(main: Node3D, shot: Node) -> void:
	var avatar: Node3D = main.avatar
	var center: Vector3 = main.sim.zone_center()
	var radius: float = main.sim.zone_radius()
	avatar.global_position = center + Vector3(radius - 6.0, 0.5, 0)
	avatar.global_position.y = main.sim.voxels.top_solid_y(int(avatar.global_position.x), int(avatar.global_position.z)) + 1.1
	main.camera_rig.yaw = -PI * 0.5
	main.camera_rig.pitch = -0.1
	avatar.autopilot = Vector2(0, -1)
	var farthest: float = 0.0
	for frame in range(240):
		await main.get_tree().physics_frame
		farthest = maxf(farthest, Vector2(avatar.global_position.x - center.x, avatar.global_position.z - center.z).length())
	print("ZONE radius=%.1f farthest=%.2f bound=%s" % [radius, farthest, farthest <= radius + 0.01])
	shot.shoot_after(10)
