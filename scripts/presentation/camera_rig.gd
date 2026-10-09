extends Node3D
## Over-the-shoulder spring-arm camera that orbits with the mouse or right
## stick, plus an overlook mode: an elevated orbit around the active shrine,
## still clamped to the presence zone, with longer build reach.
const Balance = preload("res://scripts/core/balance.gd")

var target: Node3D
var yaw: float = 0.0
var pitch: float = -0.25
var distance: float = 5.0
var overlook: bool = false
var overlook_center := Vector3.ZERO
var overlook_radius: float = 30.0
var look_sensitivity: float = 0.5
var invert_look: bool = false
var mouse_look: bool = true
var input_enabled: bool = true
var arm := SpringArm3D.new()
var camera := Camera3D.new()
var _blend: float = 0.0
var _overlook_yaw: float = 0.0
var _overlook_pitch: float = -0.9
var _overlook_distance: float = 34.0


func _ready() -> void:
	arm.collision_mask = 2
	arm.margin = 0.3
	arm.spring_length = distance
	add_child(arm)
	camera.fov = 70.0
	camera.near = 0.08
	camera.far = 600.0
	arm.add_child(camera)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and mouse_look:
		var scale: float = 0.0012 + look_sensitivity * 0.004
		var vertical: float = -1.0 if invert_look else 1.0
		if overlook:
			_overlook_yaw -= event.relative.x * scale
			_overlook_pitch = clampf(_overlook_pitch - event.relative.y * scale * vertical, -1.45, -0.35)
		else:
			yaw -= event.relative.x * scale
			pitch = clampf(pitch - event.relative.y * scale * vertical, -1.35, 0.9)
	if event.is_action_pressed("zoom_in"):
		_zoom(-1.0)
	elif event.is_action_pressed("zoom_out"):
		_zoom(1.0)
	elif event is InputEventMouseButton and event.pressed and Input.is_key_pressed(KEY_CTRL):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0)


func _zoom(direction: float) -> void:
	if overlook:
		_overlook_distance = clampf(_overlook_distance + direction * 4.0, 14.0, 70.0)
	else:
		distance = clampf(distance + direction * 0.75, 2.0, 10.0)


func toggle_overlook() -> void:
	overlook = not overlook
	if overlook:
		_overlook_yaw = yaw


func _process(delta: float) -> void:
	if target == null:
		return
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if not input_enabled:
		stick = Vector2.ZERO
	var speed: float = (1.2 + look_sensitivity * 2.4) * delta
	var vertical: float = -1.0 if invert_look else 1.0
	if overlook:
		_overlook_yaw -= stick.x * speed
		_overlook_pitch = clampf(_overlook_pitch - stick.y * speed * vertical, -1.45, -0.35)
	else:
		yaw -= stick.x * speed
		pitch = clampf(pitch - stick.y * speed * vertical, -1.35, 0.9)
	_blend = move_toward(_blend, 1.0 if overlook else 0.0, delta * 2.5)
	var t: float = smoothstep(0.0, 1.0, _blend)
	var shoulder: Vector3 = target.global_position + Vector3(0, 1.55, 0) + Basis(Vector3.UP, yaw) * Vector3(0.55, 0, 0)
	# The overlook pivot sits over the shrine, never outside the zone.
	var pivot: Vector3 = overlook_center + Vector3(0, 2.0, 0)
	global_position = shoulder.lerp(pivot, t)
	rotation = Vector3(lerpf(pitch, _overlook_pitch, t), lerp_angle(yaw, _overlook_yaw, t), 0.0)
	arm.spring_length = lerpf(distance, _overlook_distance, t)
	arm.collision_mask = 0 if t > 0.5 else 2


## The point and direction the crosshair looks along.
func aim_ray() -> Array:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = viewport_size * 0.5
	return [camera.project_ray_origin(center), camera.project_ray_normal(center)]


func reach() -> float:
	return Balance.number("avatar.overlook_reach") if overlook else Balance.number("avatar.reach")
