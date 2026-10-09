extends Node3D
## The valley scene: builds the simulation from the session, the views that
## present it, and routes player input into commands.
const EnvironmentRig = preload("res://scripts/presentation/environment_rig.gd")
const Capture = preload("res://scripts/presentation/capture.gd")
const Session = preload("res://scripts/presentation/session.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const WorldView = preload("res://scripts/presentation/world_view.gd")
const Avatar = preload("res://scripts/presentation/avatar.gd")
const CameraRig = preload("res://scripts/presentation/camera_rig.gd")
const BuildController = preload("res://scripts/presentation/build_controller.gd")
const Overlays = preload("res://scripts/presentation/overlays.gd")
const Hud = preload("res://scripts/presentation/ui/hud.gd")
const Text = preload("res://scripts/core/text.gd")
const CaptureScenes = preload("res://scripts/presentation/capture_scenes.gd")

var rig: Node3D
var sim: RefCounted
var world_view: Node3D
var avatar: CharacterBody3D
var camera_rig: Node3D
var builder: Node3D
var overlays: Node3D
var hud: Control
var ui_layer := CanvasLayer.new()
var capture_request: Dictionary = {}
var _loading: Label
var _zone_key: String = ""


func _ready() -> void:
	rig = EnvironmentRig.new()
	add_child(rig)
	add_child(ui_layer)
	_loading = Label.new()
	_loading.text = Text.label("loading_world")
	_loading.add_theme_font_size_override("font_size", 30)
	_loading.position = Vector2(80, 80)
	ui_layer.add_child(_loading)
	capture_request = Capture.request()
	await get_tree().process_frame
	_start()


func _start() -> void:
	var started: int = Time.get_ticks_msec()
	sim = Sim.create(Session.seed)
	var generated: int = Time.get_ticks_msec()
	world_view = WorldView.new()
	add_child(world_view)
	world_view.build_all(sim.voxels)
	print("valley: generated in %d ms, meshed in %d ms" % [generated - started, Time.get_ticks_msec() - generated])
	overlays = Overlays.new()
	add_child(overlays)
	avatar = Avatar.new()
	add_child(avatar)
	var tree: Vector3i = sim.features.sacred_tree
	avatar.global_position = Vector3(tree.x + 0.5, tree.y + 0.2, tree.z + 4.5)
	camera_rig = CameraRig.new()
	camera_rig.target = avatar
	add_child(camera_rig)
	camera_rig.camera.current = true
	builder = BuildController.new()
	builder.sim = sim
	builder.world_view = world_view
	builder.camera_rig = camera_rig
	builder.avatar = avatar
	add_child(builder)
	hud = Hud.new()
	ui_layer.add_child(hud)
	builder.message.connect(hud.flash)
	_sync_zone()
	_loading.hide()
	if capture_request.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		CaptureScenes.arrange(self, capture_request)


func _sync_zone() -> void:
	var center: Vector3 = sim.zone_center()
	var radius: float = sim.zone_radius()
	avatar.zone_center = center
	avatar.zone_radius = radius
	camera_rig.overlook_center = center
	var key: String = "%s/%.2f" % [center, radius]
	if key != _zone_key:
		_zone_key = key
		overlays.set_zone(center, radius)
		overlays.draw_ring(sim.voxels, center, radius)


func _process(_delta: float) -> void:
	if sim == null:
		return
	rig.set_hour(sim.calendar.hour())
	avatar.camera_yaw = camera_rig.yaw
	overlays.update_avatar(avatar.global_position)
	_sync_zone()
	hud.refresh(_hud_state())


func _hud_state() -> Dictionary:
	var calendar: RefCounted = sim.calendar
	return {
		"clock": Text.format("hud_day", {"day": calendar.day(), "season": Text.label("season_" + calendar.season_name()), "clock": calendar.clock_text()}),
		"stock": sim.god.divine_stock,
		"hotbar": builder.hotbar,
		"selected": builder.selected,
		"shrine": "",
		"prayers": [],
		"crosshair": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not capture_request.is_empty(),
	}


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_settings"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("overlook"):
		camera_rig.toggle_overlook()
	elif event.is_action_pressed("toggle_fullscreen"):
		var full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
