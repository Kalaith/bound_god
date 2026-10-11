extends CharacterBody3D
## The god's avatar: walks, sprints, jumps one block and climbs one-block steps
## by itself. It is bound: after moving it is pushed back inside the presence
## zone of its shrine (`zone_center`, `zone_radius`). Movement never waits on
## the simulation or the UI, except for modal screens that take focus.
const Balance = preload("res://scripts/core/balance.gd")
const FigureRig = preload("res://scripts/presentation/figure_rig.gd")
## A spirit in pale robes: jade-white silk bordered in jade, a gold sash,
## ink-black hair and a faint gold halo.
const COLOURS: Dictionary = {"jacket": Color("dbe8df"), "trim": Color("6fa594"), "sash": Color("c9a24a"), "trousers": Color("dbe8df"),
	"skin": Color("f3e6d6"), "hair": Color("26221f"), "accent": Color("e8c66a"), "straw": Color("e8c66a")}
const GLOW: float = 0.06

var zone_center := Vector3.ZERO
var zone_radius: float = 1000.0
## Where else the avatar may stand (the sim's presence check), when set.
var reach: Callable = Callable()
var _on_roots: bool = false
var _last_rooted := Vector2.ZERO
var camera_yaw: float = 0.0
var input_enabled: bool = true
## Debug captures drive the avatar with a fixed stick and jump.
var autopilot := Vector2.ZERO
var autopilot_jump: bool = false
## A faint wisp while the god is dormant: it may not build.
var dormant: bool = false
var _figure := FigureRig.new()
var _glow: OmniLight3D
var _bob: float = 0.0
var _time: float = 0.0
var _speed: float = 0.0
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
	# The rig faces +Z; the avatar walks toward -Z.
	_figure.rotation.y = PI
	_figure.scale = Vector3.ONE * 1.08
	_figure.build(COLOURS, 0, true)
	_figure.set_glow(GLOW)
	add_child(_figure)
	_glow = OmniLight3D.new()
	_glow.light_color = Color("cfeee2")
	_glow.light_energy = 0.5
	_glow.omni_range = 4.0
	_glow.position.y = 2.3
	add_child(_glow)


func set_dormant(value: bool) -> void:
	dormant = value
	_figure.set_fade(0.35 if value else 1.0)
	_figure.set_glow(0.05 if value else GLOW)
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
	# The god hovers a hand's breadth above the ground, breathing slowly.
	_bob += delta * 1.5
	_time += delta
	_figure.position.y = 0.08 + sin(_bob) * 0.03
	var ground := Vector2(velocity.x, velocity.z).length()
	_speed = lerpf(_speed, ground, minf(delta * 8.0, 1.0))
	_figure.pose("walking" if _speed > 0.2 else "idle", _time, _speed, delta)
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

## The binding: the avatar cannot leave the presence zone. Beyond the
## shrine's circle it may walk only where `reach` holds (the tree's roots
## along the paths), and is stopped at the last step that did.
func _stay_bound() -> void:
	var flat := Vector2(global_position.x - zone_center.x, global_position.z - zone_center.z)
	var limit: float = maxf(zone_radius - 0.4, 1.0)
	if flat.length() <= limit:
		_on_roots = false
		return
	if reach.is_valid() and reach.call(global_position):
		_on_roots = true
		_last_rooted = Vector2(global_position.x, global_position.z)
		return
	if _on_roots:
		global_position.x = _last_rooted.x
		global_position.z = _last_rooted.y
		velocity.x = 0.0
		velocity.z = 0.0
		return
	flat = flat.normalized() * limit
	global_position.x = zone_center.x + flat.x
	global_position.z = zone_center.z + flat.y
	var outward := Vector3(flat.x, 0.0, flat.y).normalized()
	var push: float = velocity.dot(outward)
	if push > 0.0:
		velocity -= outward * push


func is_inside_zone() -> bool:
	var flat := Vector2(global_position.x - zone_center.x, global_position.z - zone_center.z)
	return flat.length() <= zone_radius + 0.01 or (reach.is_valid() and reach.call(global_position))
