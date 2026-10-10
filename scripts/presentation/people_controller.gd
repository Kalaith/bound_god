extends Node
## Selecting and following people: the inspect key picks the person under
## the crosshair (or the mouse when it is free), opens the inspector, and
## Follow turns the overlook camera on them, still bound to the zone.
const Text = preload("res://scripts/core/text.gd")
const Balance = preload("res://scripts/core/balance.gd")

var sim: RefCounted
var views: Node3D
var inspector: Control
var camera_rig: Node3D
var hud: Control
var main: Node3D


func _ready() -> void:
	inspector.closed.connect(close)
	inspector.person_chosen.connect(select)
	inspector.follow_toggled.connect(func(on: bool) -> void:
		if on and not camera_rig.overlook:
			camera_rig.toggle_overlook())
	inspector.pin_toggled.connect(func(id: int) -> void:
		var result: Dictionary = sim.apply_command({"type": "follow", "agent": id})
		if not result.ok:
			hud.flash(Text.format(str(result.reason), {"most": Balance.integer("cultivation.followed_most")}), true))


func select(id: int) -> void:
	if id < 0 or id >= sim.agents.size():
		return
	views.selected = id
	inspector.inspect(id)


func close() -> void:
	views.selected = -1
	inspector.hide()
	inspector.following = false
	main.restore_overlook_center()


func _unhandled_input(event: InputEvent) -> void:
	if not main.accepts_world_input():
		return
	if event.is_action_pressed("inspect") or (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and inspector.visible):
		var viewport: Viewport = get_viewport()
		var screen: Vector2 = viewport.get_visible_rect().size * 0.5
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			screen = viewport.get_mouse_position()
		var id: int = person_at(screen)
		if id >= 0:
			select(id)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.is_action_pressed("inspect"):
			if inspector.visible:
				close()
			else:
				hud.flash(Text.label("inspect_nobody"), true)
		viewport.set_input_as_handled()


## The person nearest a screen point, with a wider margin from the overlook,
## where people are small; -1 when nobody is close.
func person_at(screen: Vector2) -> int:
	if camera_rig.overlook:
		return views.pick(camera_rig.camera, screen, 200.0, 1.0)
	return views.pick(camera_rig.camera, screen, 70.0)


## The person under the crosshair, for the HUD prompt; -1 for nobody.
func aimed() -> int:
	return person_at(get_viewport().get_visible_rect().size * 0.5)


func _process(_delta: float) -> void:
	if sim == null or not inspector.visible or not inspector.following or views.selected < 0:
		return
	var agent: RefCounted = sim.agents[views.selected]
	if not agent.is_present():
		close()
		return
	# The god's gaze still cannot leave its presence.
	var center: Vector3 = sim.zone_center()
	var offset := Vector2(agent.position.x - center.x, agent.position.z - center.z)
	var limit: float = sim.zone_radius()
	if offset.length() > limit:
		offset = offset.normalized() * limit
	camera_rig.overlook_center = Vector3(center.x + offset.x, agent.position.y, center.z + offset.y)
