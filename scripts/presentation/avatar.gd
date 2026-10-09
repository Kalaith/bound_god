extends CharacterBody3D
## The god's avatar: walks, sprints, jumps one block and climbs one-block steps
## by itself. It is bound: after moving it is pushed back inside the presence
## zone of its shrine (`zone_center`, `zone_radius`). Movement never waits on
## the simulation or the UI, except for modal screens that take focus.
const Balance = preload("res://scripts/core/balance.gd")

var zone_center := Vector3.ZERO
var zone_radius: float = 1000.0
var camera_yaw: float = 0.0
var input_enabled: bool = true
## Debug captures drive the avatar with a fixed stick and jump.
var autopilot := Vector2.ZERO
var autopilot_jump: bool = false
## A faint wisp while the god is dormant: it may not build.
var dormant: bool = false
var _body: MeshInstance3D
var _head: MeshInstance3D
var _glow: OmniLight3D
var _material := StandardMaterial3D.new()
var _bob: float = 0.0
var _walk: float
var _sprint: float
var _jump: float
var _gravity: float


func _ready() -> void:
	collision_layer = 1
	collision_mask = 2
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	_walk = Balance.number("avatar.walk_speed")
	_sprint = Balance.number("avatar.sprint_speed")
	_jump = Balance.number("avatar.jump_velocity")
	_gravity = Balance.number("avatar.gravity")
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.7
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.85
	add_child(collider)
	_material.albedo_color = Color(0.78, 0.72, 0.98, 0.78)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_material.emission = Color("8f78e8")
	_material.emission_energy_multiplier = 0.25
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.3
	body_mesh.height = 1.25
	_body = MeshInstance3D.new()
	_body.mesh = body_mesh
	_body.material_override = _material
	_body.position.y = 0.68
	add_child(_body)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	_head = MeshInstance3D.new()
	_head.mesh = head_mesh
	_head.material_override = _material
	_head.position.y = 1.5
	add_child(_head)
	_glow = OmniLight3D.new()
	_glow.light_color = Color("cbb8ff")
	_glow.light_energy = 0.5
	_glow.omni_range = 4.0
	_glow.position.y = 2.3
	add_child(_glow)


func set_dormant(value: bool) -> void:
	dormant = value
	_material.albedo_color.a = 0.3 if value else 0.78
	_glow.light_energy = 0.3 if value else 0.9


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if autopilot != Vector2.ZERO:
		input = autopilot
	var direction: Vector3 = Basis(Vector3.UP, camera_yaw) * Vector3(input.x, 0.0, input.y)
	var speed: float = _sprint if input_enabled and Input.is_action_pressed("sprint") else _walk
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if is_on_floor():
		if (input_enabled and Input.is_action_just_pressed("jump")) or autopilot_jump:
			autopilot_jump = false
			velocity.y = _jump
	else:
		velocity.y -= _gravity * delta
	if direction.length() > 0.1:
		_step_up(direction * speed * delta)
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 12.0, 1.0))
	move_and_slide()
	_stay_bound()
	_bob += delta * (8.0 if direction.length() > 0.1 and is_on_floor() else 1.5)
	_body.position.y = 0.68 + sin(_bob) * 0.03
	_head.position.y = 1.5 + sin(_bob) * 0.035
	if global_position.y < -10.0:
		global_position = zone_center + Vector3(0, 4, 0)
		velocity = Vector3.ZERO


## Climb a one-block step without jumping when the way up is clear.
func _step_up(motion: Vector3) -> void:
	if not is_on_floor():
		return
	var probe: Vector3 = motion.normalized() * 0.3
	if not test_move(global_transform, probe):
		return
	var raised: Transform3D = global_transform.translated(Vector3(0, 1.05, 0))
	if test_move(global_transform, Vector3(0, 1.05, 0)) or test_move(raised, probe):
		return
	global_position.y += 1.05


## The binding: the avatar cannot leave the presence zone.
func _stay_bound() -> void:
	var flat := Vector2(global_position.x - zone_center.x, global_position.z - zone_center.z)
	var limit: float = maxf(zone_radius - 0.4, 1.0)
	if flat.length() > limit:
		flat = flat.normalized() * limit
		global_position.x = zone_center.x + flat.x
		global_position.z = zone_center.z + flat.y
		var outward := Vector3(flat.x, 0.0, flat.y).normalized()
		var push: float = velocity.dot(outward)
		if push > 0.0:
			velocity -= outward * push


func is_inside_zone() -> bool:
	var flat := Vector2(global_position.x - zone_center.x, global_position.z - zone_center.z)
	return flat.length() <= zone_radius + 0.01
