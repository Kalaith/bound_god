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
const DesignTool = preload("res://scripts/presentation/design_tool.gd")
const LibraryScreen = preload("res://scripts/presentation/ui/template_library_screen.gd")
const SimDriver = preload("res://scripts/presentation/sim_driver.gd")
const AgentViews = preload("res://scripts/presentation/agent_views.gd")
const Inspector = preload("res://scripts/presentation/ui/inspector.gd")
const PeopleController = preload("res://scripts/presentation/people_controller.gd")
const ConstructionView = preload("res://scripts/presentation/construction_view.gd")
const StoresPanel = preload("res://scripts/presentation/ui/stores_panel.gd")
const SettlementPanel = preload("res://scripts/presentation/ui/settlement_panel.gd")
const FaithController = preload("res://scripts/presentation/faith_controller.gd")

var rig: Node3D
var sim: RefCounted
var world_view: Node3D
var avatar: CharacterBody3D
var camera_rig: Node3D
var builder: Node3D
var overlays: Node3D
var hud: Control
var design_tool: Node3D
var library_screen: Control
var driver: Node
var agent_views: Node3D
var inspector: Control
var people: Node
var construction_view: Node3D
var stores_panel: Control
var settlement_panel: Control
var faith: Node
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
	driver = SimDriver.new()
	driver.sim = sim
	add_child(driver)
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
	design_tool = DesignTool.new()
	design_tool.sim = sim
	design_tool.builder = builder
	add_child(design_tool)
	design_tool.message.connect(hud.flash)
	design_tool.captured.connect(_open_library)
	library_screen = LibraryScreen.new()
	ui_layer.add_child(library_screen)
	library_screen.closed.connect(_close_library)
	library_screen.capture_requested.connect(func() -> void:
		_close_library()
		design_tool.begin())
	agent_views = AgentViews.new()
	agent_views.sim = sim
	agent_views.driver = driver
	add_child(agent_views)
	inspector = Inspector.new()
	inspector.sim = sim
	ui_layer.add_child(inspector)
	construction_view = ConstructionView.new()
	construction_view.sim = sim
	add_child(construction_view)
	stores_panel = StoresPanel.new()
	stores_panel.sim = sim
	ui_layer.add_child(stores_panel)
	stores_panel.closed.connect(_close_stores)
	stores_panel.transfer.connect(func(id: int, resource: String, amount: int) -> void:
		var result: Dictionary = sim.apply_command({"type": "transfer", "settlement": id, "resource": resource, "amount": amount})
		hud.flash(Text.label(result.reason), not result.ok))
	settlement_panel = SettlementPanel.new()
	settlement_panel.sim = sim
	ui_layer.add_child(settlement_panel)
	settlement_panel.closed.connect(func() -> void: settlement_panel.hide())
	library_screen.offer_requested.connect(_offer)
	people = PeopleController.new()
	people.sim = sim
	people.views = agent_views
	people.inspector = inspector
	people.camera_rig = camera_rig
	people.hud = hud
	people.main = self
	add_child(people)
	faith = FaithController.new()
	faith.sim = sim
	faith.main = self
	add_child(faith)
	_sync_zone()
	_loading.hide()
	if capture_request.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		driver.set_speed(0)
		CaptureScenes.arrange(self, capture_request)


func _sync_zone() -> void:
	var center: Vector3 = sim.zone_center()
	var radius: float = sim.zone_radius()
	avatar.zone_center = center
	avatar.zone_radius = radius
	if inspector == null or not inspector.following:
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


func _clock_text() -> String:
	var calendar: RefCounted = sim.calendar
	var text: String = Text.format("hud_day", {"day": calendar.day(), "season": Text.label("season_" + calendar.season_name()), "clock": calendar.clock_text()})
	text += "  " + Text.label("hud_speed_%d" % driver.speed_index)
	if driver.busy:
		text += "  " + Text.label("hud_busy")
	return text


func _hud_state() -> Dictionary:
	return {
		"clock": _clock_text(),
		"stock": sim.god.divine_stock,
		"hotbar": builder.hotbar,
		"selected": builder.selected,
		"shrine": faith.shrine_line(),
		"prayers": faith.prayer_lines(),
		"hint": design_tool.hint() if design_tool.active else Text.label("design_hint"),
		"hotbar_visible": not design_tool.active and not library_screen.visible,
		"crosshair": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not capture_request.is_empty(),
	}


func _unhandled_input(event: InputEvent) -> void:
	if library_screen != null and (library_screen.visible or stores_panel.visible or faith.menu.visible):
		return
	if event.is_action_pressed("design_tool"):
		design_tool.finish()
		_open_library()
		get_viewport().set_input_as_handled()
		return
	if design_tool != null and design_tool.active and event.is_action_pressed("toggle_settings"):
		design_tool.finish()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("speed_pause"):
		driver.set_speed(0 if driver.speed_index != 0 else 1)
	elif event.is_action_pressed("speed_up"):
		driver.set_speed(driver.speed_index + 1)
	elif event.is_action_pressed("speed_down"):
		driver.set_speed(driver.speed_index - 1)
	elif event.is_action_pressed("interact"):
		if not faith.try_open_menu():
			_open_stores()
	elif event.is_action_pressed("toggle_settlement"):
		if settlement_panel.visible:
			settlement_panel.hide()
		else:
			settlement_panel.open(sim.settlements.at_cell(Vector3i(sim.zone_center())))
	elif event.is_action_pressed("toggle_settings") and inspector.visible:
		people.close()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("toggle_settings"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("overlook"):
		camera_rig.toggle_overlook()
	elif event.is_action_pressed("toggle_fullscreen"):
		var full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


## Modal screens take the world's input; the inspector does not.
func accepts_world_input() -> bool:
	return library_screen != null and not library_screen.visible and not stores_panel.visible and not faith.menu.visible


func _offer(design: RefCounted) -> void:
	var result: Dictionary = sim.apply_command({"type": "offer_template", "template": design.to_dict()})
	library_screen._notice.text = Text.label(result.reason)
	library_screen.offered = sim.god.offered
	library_screen._refresh()


## Interact beside a settlement's pile or chest opens its stores.
func _open_stores() -> void:
	var here := Vector3i(avatar.global_position.floor())
	for id in sim.settlements.ids():
		var near: bool = Vector3(sim.settlements.entries[id].pile).distance_to(Vector3(here)) <= 4.5
		for chest in sim.settlements.chest_cells(sim, id):
			near = near or Vector3(chest).distance_to(Vector3(here)) <= 4.5
		if near:
			builder.enabled = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			stores_panel.open(id)
			return
	hud.flash(Text.label("stores_none_near"), true)


func open_stores_for(id: int) -> void:
	if not sim.settlements.entries.has(id):
		hud.flash(Text.label("stores_none_near"), true)
		return
	builder.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stores_panel.open(id)


func open_requests() -> void:
	hud.flash(Text.label("requests_none_yet"), true)


func rest(days: float) -> void:
	driver.rest(days)


func _close_stores() -> void:
	stores_panel.hide()
	builder.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func restore_overlook_center() -> void:
	camera_rig.overlook_center = sim.zone_center()


func _open_library(design: RefCounted = null) -> void:
	builder.enabled = false
	avatar.input_enabled = false
	camera_rig.set_process_unhandled_input(false)
	camera_rig.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	library_screen.offered = sim.god.offered
	library_screen.open(design)


func _close_library() -> void:
	library_screen.hide()
	builder.enabled = true
	avatar.input_enabled = true
	camera_rig.set_process_unhandled_input(true)
	camera_rig.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
