extends Node3D
## The valley scene: builds the simulation from the session, the views that
## present it, and routes player input into commands.
const EnvironmentRig = preload("res://scripts/presentation/environment_rig.gd")
const Capture = preload("res://scripts/presentation/capture.gd")
const Session = preload("res://scripts/presentation/session.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const SaveStore = preload("res://scripts/core/save_store.gd")
const WorldView = preload("res://scripts/presentation/world_view.gd")
const Avatar = preload("res://scripts/presentation/avatar.gd")
const CameraRig = preload("res://scripts/presentation/camera_rig.gd")
const BuildController = preload("res://scripts/presentation/build_controller.gd")
const Overlays = preload("res://scripts/presentation/overlays.gd")
const QiOverlay = preload("res://scripts/presentation/qi_overlay.gd")
const Hud = preload("res://scripts/presentation/ui/hud.gd")
const Text = preload("res://scripts/core/text.gd")
const CaptureScenes = preload("res://scripts/presentation/capture_scenes.gd")
const DesignTool = preload("res://scripts/presentation/design_tool.gd")
const BlueprintTool = preload("res://scripts/presentation/blueprint_tool.gd")
const LibraryScreen = preload("res://scripts/presentation/ui/template_library_screen.gd")
const SimDriver = preload("res://scripts/presentation/sim_driver.gd")
const AgentViews = preload("res://scripts/presentation/agent_views.gd")
const Inspector = preload("res://scripts/presentation/ui/inspector.gd")
const PeopleController = preload("res://scripts/presentation/people_controller.gd")
const ConstructionView = preload("res://scripts/presentation/construction_view.gd")
const InteractController = preload("res://scripts/presentation/interact_controller.gd")
const InventoryScreen = preload("res://scripts/presentation/ui/inventory_screen.gd")
const SettlementPanel = preload("res://scripts/presentation/ui/settlement_panel.gd")
const FaithController = preload("res://scripts/presentation/faith_controller.gd")
const RequestsPanel = preload("res://scripts/presentation/ui/requests_panel.gd")
const ThreatViews = preload("res://scripts/presentation/threat_views.gd")
const TribulationViews = preload("res://scripts/presentation/tribulation_views.gd")
const TreeMarks = preload("res://scripts/presentation/tree_marks.gd")
const TreeScreen = preload("res://scripts/presentation/ui/tree_screen.gd")
const LanternLights = preload("res://scripts/presentation/lantern_lights.gd")
const SacredAura = preload("res://scripts/presentation/sacred_aura.gd")
const WorldIO = preload("res://scripts/presentation/world_io.gd")
const RestOverlay = preload("res://scripts/presentation/ui/rest_overlay.gd")
const ChronicleScreen = preload("res://scripts/presentation/ui/chronicle_screen.gd")
const AudioDirector = preload("res://scripts/presentation/audio_director.gd")
const PauseMenu = preload("res://scripts/presentation/ui/pause_menu.gd")
const SettingsScreen = preload("res://scripts/presentation/ui/settings_screen.gd")
const SettingsStore = preload("res://scripts/core/settings_store.gd")
const Prompts = preload("res://scripts/presentation/ui/prompts.gd")
const TITLE_SCENE: String = "res://scenes/title.tscn"

var rig: Node3D
var sim: RefCounted
var world_view: Node3D
var avatar: CharacterBody3D
var camera_rig: Node3D
var builder: Node3D
var overlays: Node3D
var qi_overlay: MeshInstance3D
var tree_screen: Control
var hud: Control
var design_tool: Node3D
var blueprint_tool: Node3D
var library_screen: Control
var driver: Node
var agent_views: Node3D
var inspector: Control
var people: Node
var construction_view: Node3D
var interaction: Node
var inventory: Control
var settlement_panel: Control
var faith: Node
var requests_panel: Control
var world_io: Node
var rest_overlay: Control
var chronicle_screen: Control
var pause_menu: Control
var settings_screen: Control
## The prompt shown now: {id, text} or {}.
var _prompt_now: Dictionary = {}
var _show_guide: bool = true
var _guide_left: float = 0.0
var ui_layer := CanvasLayer.new()
var capture_request: Dictionary = {}
## Set by a capture that frames its own shot: the overlook stays where it put it.
var camera_hold: bool = false
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
	if capture_request.has("load"):
		Session.mode = "load"
		Session.slot = capture_request.load
	await get_tree().process_frame
	_start()


func _start() -> void:
	var started: int = Time.get_ticks_msec()
	if Session.mode == "load":
		sim = WorldIO.load_slot(Session.slot)
		if sim == null:
			_loading.text = Text.format("save_load_failed", {"error": SaveStore.last_error})
			return
	else:
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
	qi_overlay = QiOverlay.new()
	qi_overlay.sim = sim
	add_child(qi_overlay)
	var aura: Node3D = SacredAura.new()
	aura.base = sim.features.sacred_tree
	add_child(aura)
	avatar = Avatar.new()
	add_child(avatar)
	var tree: Vector3i = sim.features.sacred_tree
	avatar.global_position = Vector3(tree.x + 0.5, tree.y + 0.2, tree.z + 4.5)
	if Session.mode == "load" and sim.god.active_shrine_id != 1:
		var shrine: Dictionary = sim.faith.current(sim)
		if not shrine.is_empty():
			avatar.global_position = Vector3(sim.faith.shrine_access(sim, int(shrine.id), shrine.cell)) + Vector3(0.5, 0.2, 0.5)
	camera_rig = CameraRig.new()
	camera_rig.target = avatar
	add_child(camera_rig)
	camera_rig.camera.current = true
	rig.attach_paper(camera_rig.camera)
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
	blueprint_tool = BlueprintTool.new()
	blueprint_tool.sim = sim
	blueprint_tool.builder = builder
	add_child(blueprint_tool)
	blueprint_tool.message.connect(hud.flash)
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
	var threat_views: Node3D = ThreatViews.new()
	threat_views.sim = sim
	threat_views.driver = driver
	add_child(threat_views)
	var trial_views: Node3D = TribulationViews.new()
	trial_views.sim = sim
	trial_views.driver = driver
	trial_views.hud = hud
	add_child(trial_views)
	var marks: Node3D = TreeMarks.new()
	marks.sim = sim
	add_child(marks)
	var lantern_lights: Node3D = LanternLights.new()
	lantern_lights.sim = sim
	lantern_lights.camera = camera_rig.camera
	add_child(lantern_lights)
	inspector = Inspector.new()
	inspector.sim = sim
	ui_layer.add_child(inspector)
	construction_view = ConstructionView.new()
	construction_view.sim = sim
	add_child(construction_view)
	interaction = InteractController.new()
	interaction.main = self
	interaction.sim = sim
	add_child(interaction)
	inventory = InventoryScreen.new()
	inventory.sim = sim
	ui_layer.add_child(inventory)
	inventory.closed.connect(func() -> void:
		inventory.hide()
		resume_world_input())
	inventory.hotbar_changed.connect(func(slots: Array, selected: int) -> void:
		sim.apply_command({"type": "set_hotbar", "slots": slots})
		builder.select(selected))
	settlement_panel = SettlementPanel.new()
	settlement_panel.sim = sim
	ui_layer.add_child(settlement_panel)
	settlement_panel.closed.connect(func() -> void:
		settlement_panel.hide()
		resume_world_input())
	library_screen.offer_requested.connect(_offer)
	library_screen.blueprint_requested.connect(func(design: RefCounted) -> void:
		_close_library()
		blueprint_tool.begin(design))
	people = PeopleController.new()
	people.sim = sim
	people.views = agent_views
	people.inspector = inspector
	people.camera_rig = camera_rig
	people.hud = hud
	people.main = self
	add_child(people)
	requests_panel = RequestsPanel.new()
	requests_panel.sim = sim
	ui_layer.add_child(requests_panel)
	requests_panel.closed.connect(func() -> void:
		requests_panel.hide()
		builder.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	faith = FaithController.new()
	faith.sim = sim
	faith.main = self
	add_child(faith)
	requests_panel.command.connect(faith.send)
	world_io = WorldIO.new()
	world_io.sim = sim
	world_io.hud = hud
	world_io.slot = Session.slot
	world_io.driver = driver
	add_child(world_io)
	rest_overlay = RestOverlay.new()
	rest_overlay.sim = sim
	rest_overlay.driver = driver
	ui_layer.add_child(rest_overlay)
	rest_overlay.finished.connect(func() -> void:
		builder.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	chronicle_screen = ChronicleScreen.new()
	chronicle_screen.sim = sim
	ui_layer.add_child(chronicle_screen)
	chronicle_screen.closed.connect(func() -> void:
		chronicle_screen.hide()
		builder.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	tree_screen = TreeScreen.new()
	tree_screen.sim = sim
	ui_layer.add_child(tree_screen)
	tree_screen.closed.connect(func() -> void:
		tree_screen.hide()
		builder.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	if sim.god.dormant:
		avatar.set_dormant(true)
	var preferences: RefCounted = SettingsStore.new()
	preferences.load_settings()
	_apply_settings(preferences)
	var audio: Node = AudioDirector.new()
	audio.sim = sim
	add_child(audio)
	pause_menu = PauseMenu.new()
	ui_layer.add_child(pause_menu)
	pause_menu.resume.connect(_close_pause)
	pause_menu.save.connect(func() -> void: world_io.save())
	pause_menu.title.connect(func() -> void:
		world_io.save()
		get_tree().change_scene_to_file(TITLE_SCENE))
	pause_menu.settings.connect(_open_settings)
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
	if (inspector == null or not inspector.following) and not camera_hold:
		camera_rig.overlook_center = center
	var key: String = "%s/%.2f" % [center, radius]
	if key != _zone_key:
		_zone_key = key
		overlays.set_zone(center, radius)
		overlays.draw_ring(sim.voxels, center, radius)


func _process(_delta: float) -> void:
	if sim == null or avatar == null:
		return
	rig.set_hour(sim.calendar.hour())
	avatar.camera_yaw = camera_rig.yaw
	overlays.update_avatar(avatar.global_position)
	_sync_zone()
	_guide_left -= _delta
	if _guide_left <= 0.0:
		_guide_left = 1.0
		_prompt_now = Prompts.current(sim, library_screen.library, _show_guide)
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
		"hotbar": builder.hotbar(),
		"selected": builder.selected,
		"shrine": faith.shrine_line(),
		"prayers": faith.prayer_lines(),
		"hint": design_tool.hint() if design_tool.active else (blueprint_tool.hint() if blueprint_tool.active else Text.label("hud_controls")),
		"prompt": _prompt() if accepts_world_input() else "",
		"guide": _prompt_now.get("text", ""),
		"hotbar_visible": not design_tool.active and not blueprint_tool.active and not library_screen.visible,
		"crosshair": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not capture_request.is_empty(),
	}


## Someone under the crosshair is inspected before a block is used.
func _prompt() -> String:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not inspector.visible:
		var id: int = people.aimed()
		if id >= 0:
			return Text.format("inspect_prompt", {"name": sim.agents[id].full_name()})
	return interaction.prompt()


func _unhandled_input(event: InputEvent) -> void:
	if library_screen != null and modal_open():
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
	if blueprint_tool != null and blueprint_tool.active and event.is_action_pressed("toggle_settings"):
		blueprint_tool.finish()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("speed_pause"):
		driver.set_speed(0 if driver.speed_index != 0 else 1)
	elif event.is_action_pressed("speed_up"):
		driver.set_speed(driver.speed_index + 1)
	elif event.is_action_pressed("speed_down"):
		driver.set_speed(driver.speed_index - 1)
	elif event.is_action_pressed("interact"):
		interaction.use()
	elif event.is_action_pressed("inventory"):
		pause_world_input()
		inventory.open(builder.selected)
	elif event.is_action_pressed("quick_save"):
		world_io.save()
	elif event.is_action_pressed("toggle_tree"):
		builder.enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		tree_screen.open()
	elif event.is_action_pressed("toggle_qi"):
		qi_overlay.toggle()
		if qi_overlay.visible:
			hud.flash(Text.label("hud_qi_overlay"))
	elif event.is_action_pressed("dismiss_prompt") and not _prompt_now.is_empty():
		sim.apply_command({"type": "dismiss_prompt", "prompt": str(_prompt_now.id)})
		_prompt_now = {}
		_guide_left = 0.0
	elif event.is_action_pressed("toggle_chronicle"):
		builder.enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		chronicle_screen.open()
	elif event.is_action_pressed("toggle_settlement"):
		# The panel scrolls and has buttons, so the mouse is freed while it is open.
		pause_world_input()
		settlement_panel.open(sim.settlements.at_cell(Vector3i(sim.zone_center())))
	elif event.is_action_pressed("toggle_settings") and inspector.visible:
		people.close()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("toggle_settings"):
		builder.enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		pause_menu.open()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("overlook"):
		camera_rig.toggle_overlook()
	elif event.is_action_pressed("toggle_fullscreen"):
		var full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _close_pause() -> void:
	pause_menu.hide()
	builder.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_settings() -> void:
	if settings_screen == null:
		var store: RefCounted = SettingsStore.new()
		store.load_settings()
		settings_screen = SettingsScreen.new()
		settings_screen.store = store
		ui_layer.add_child(settings_screen)
		settings_screen.close_requested.connect(func() -> void: settings_screen.hide())
		settings_screen.changed.connect(func() -> void:
			store.apply_all(get_tree())
			_apply_settings(store))
	settings_screen.show()


## Look settings reach the camera and graphics the environment; the rest the
## store applies itself.
func _apply_settings(store: RefCounted) -> void:
	rig.apply_graphics(store.values)
	camera_rig.look_sensitivity = float(store.values.get("look_sensitivity", camera_rig.look_sensitivity))
	camera_rig.invert_look = bool(store.values.get("invert_look", camera_rig.invert_look))
	_show_guide = bool(store.values.get("show_guide", true))
	_guide_left = 0.0


## Screens that take the world's input while open.
func modal_open() -> bool:
	if settings_screen != null and settings_screen.visible:
		return true
	if interaction.is_open() or inventory.visible:
		return true
	for screen in [library_screen, faith.menu, requests_panel, rest_overlay, chronicle_screen, pause_menu, settlement_panel, tree_screen]:
		if screen.visible:
			return true
	return false


## Modal screens take the world's input; the inspector does not.
func accepts_world_input() -> bool:
	return library_screen != null and not modal_open()


func _offer(design: RefCounted) -> void:
	var result: Dictionary = sim.apply_command({"type": "offer_template", "template": design.to_dict()})
	library_screen._notice.text = Text.label(result.reason)
	library_screen.offered = sim.god.offered
	library_screen._refresh()


## The shrine menu's Stores: the settlement's nearest chest in the presence.
func open_stores_for(id: int) -> void:
	interaction.open_settlement_chest(id)


## Screens opened from the world free the mouse and stop building.
func pause_world_input() -> void:
	builder.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume_world_input() -> void:
	builder.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func open_requests() -> void:
	builder.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	requests_panel.open()


func rest(days: float) -> void:
	world_io.save("save_autosaved")
	builder.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rest_overlay.begin(days)


## Years pass in meditation behind the same veil.
func meditate(years: float) -> void:
	world_io.save("save_autosaved")
	builder.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rest_overlay.begin_meditation(years)


func restore_overlook_center() -> void:
	camera_rig.overlook_center = sim.zone_center()


func open_library() -> void:
	_open_library()


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
