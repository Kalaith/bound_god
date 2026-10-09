extends Node3D
## The valley scene. M1: generate the valley from the session seed, mesh it,
## and let the avatar walk it under a moving sun.
const EnvironmentRig = preload("res://scripts/presentation/environment_rig.gd")
const Capture = preload("res://scripts/presentation/capture.gd")
const Session = preload("res://scripts/presentation/session.gd")
const VoxelWorld = preload("res://scripts/world/voxel_world.gd")
const WorldGen = preload("res://scripts/world/world_gen.gd")
const WorldView = preload("res://scripts/presentation/world_view.gd")
const Avatar = preload("res://scripts/presentation/avatar.gd")
const CameraRig = preload("res://scripts/presentation/camera_rig.gd")
const Balance = preload("res://scripts/core/balance.gd")

var rig: Node3D
var world: RefCounted
var features: Dictionary = {}
var world_view: Node3D
var avatar: CharacterBody3D
var camera_rig: Node3D
var hour: float = 9.0
var capture_request: Dictionary = {}
var _loading: Label


func _ready() -> void:
	rig = EnvironmentRig.new()
	add_child(rig)
	var layer := CanvasLayer.new()
	add_child(layer)
	_loading = Label.new()
	_loading.text = "The valley rises from the seed…"
	_loading.add_theme_font_size_override("font_size", 28)
	_loading.position = Vector2(80, 80)
	layer.add_child(_loading)
	capture_request = Capture.request()
	await get_tree().process_frame
	_build_world()


func _build_world() -> void:
	var size: Array = Balance.list("world.size")
	world = VoxelWorld.new(Vector3i(int(size[0]), int(size[1]), int(size[2])))
	var rng := RandomNumberGenerator.new()
	rng.seed = Session.seed
	var started: int = Time.get_ticks_msec()
	features = WorldGen.new(world, rng).valley().features
	var generated: int = Time.get_ticks_msec()
	world_view = WorldView.new()
	add_child(world_view)
	world_view.build_all(world)
	print("valley: generated in %d ms, meshed in %d ms" % [generated - started, Time.get_ticks_msec() - generated])
	var tree: Vector3i = features.sacred_tree
	avatar = Avatar.new()
	add_child(avatar)
	avatar.global_position = Vector3(tree.x + 0.5, tree.y + 0.2, tree.z + 4.5)
	avatar.zone_center = Vector3(tree.x + 1.0, tree.y, tree.z + 1.0)
	avatar.zone_radius = 30.0
	camera_rig = CameraRig.new()
	camera_rig.target = avatar
	camera_rig.overlook_center = avatar.zone_center
	add_child(camera_rig)
	camera_rig.camera.current = true
	_loading.hide()
	if capture_request.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_arrange_capture()


func _process(delta: float) -> void:
	hour = fmod(hour + delta * 24.0 / 120.0, 24.0)
	rig.set_hour(hour)
	if avatar != null:
		avatar.camera_yaw = camera_rig.yaw
	if not capture_request.is_empty() and Engine.get_process_frames() % 30 == 0:
		var vp: RID = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		print("FRAME fps=%d process=%.2fms physics=%.2fms render_cpu=%.2fms render_gpu=%.2fms" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp)])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_settings"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("overlook"):
		camera_rig.toggle_overlook()
	elif event.is_action_pressed("toggle_fullscreen"):
		var full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _arrange_capture() -> void:
	var shot: Node = Capture.new()
	shot.configure(capture_request)
	add_child(shot)
	hour = 10.0
	match str(capture_request.scenario):
		"valley_overview":
			camera_rig.overlook = true
			camera_rig._overlook_distance = 120.0
			camera_rig._overlook_pitch = -0.75
			camera_rig._overlook_yaw = deg_to_rad(-135.0)
			camera_rig.overlook_center = Vector3(80, 14, 80)
		"valley_ridge":
			var ruin: Dictionary = features.ruin
			avatar.zone_radius = 1000.0
			avatar.global_position = Vector3(ruin.altar) + Vector3(-6, 1, -10)
			camera_rig.yaw = deg_to_rad(200.0)
		"walk_test":
			_walk_test(shot)
			return
		_:
			camera_rig.yaw = deg_to_rad(180.0)
			camera_rig.pitch = -0.12
	shot.shoot_after()


## Scripted check: walk forward over a one-block step into a two-block wall,
## then jump at it. Prints what happened and the frame rate.
func _walk_test(shot: Node) -> void:
	var tree: Vector3i = features.sacred_tree
	var ground: int = tree.y
	var start := Vector3(tree.x + 0.5, ground + 0.1, tree.z + 4.5)
	avatar.global_position = start
	for dx in range(-3, 4):
		world.set_block(Vector3i(tree.x + dx, ground, tree.z + 8), 3)
		for dy in range(3):
			world.set_block(Vector3i(tree.x + dx, ground + dy, tree.z + 12), 3)
		for dz in range(9, 12):
			world.set_block(Vector3i(tree.x + dx, ground, tree.z + dz), 3)
	world_view.remesh_now()
	camera_rig.yaw = PI
	camera_rig.pitch = -0.35
	avatar.autopilot = Vector2(0, -1)
	var highest: float = start.y
	for frame in range(180):
		await get_tree().physics_frame
		highest = maxf(highest, avatar.global_position.y)
	var stepped: bool = highest >= ground + 1.0
	var blocked: bool = avatar.global_position.z < tree.z + 12.0
	avatar.autopilot_jump = true
	for frame in range(60):
		await get_tree().physics_frame
	print("WALK step_climbed=%s wall_blocked=%s final=%s fps=%d" % [stepped, blocked, avatar.global_position, Engine.get_frames_per_second()])
	avatar.autopilot = Vector2.ZERO
	shot.shoot_after(10)
