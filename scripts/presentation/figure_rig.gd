extends Node3D
## A jointed figure in the woodblock manner: legs, a jacket with its sash and
## collar, kimono sleeves, a head with hair or a hat. Villagers and the avatar
## share it; the avatar is a spirit in a long robe with no legs showing.
## Faces +Z. `pose()` eases every joint toward the pose for an activity.
const Meshes = preload("res://scripts/presentation/figure_meshes.gd")
const Poses = preload("res://scripts/presentation/figure_poses.gd")
const SHADER = preload("res://assets/shaders/figure.gdshader")

const HIP_HEIGHT: float = 0.66
## Hair styles: cropped, topknot, bun, straw hat, headband, low tail.
const STYLES: int = 6

static var _material: ShaderMaterial

var pose_root := Node3D.new()
var hips := Node3D.new()
var torso := Node3D.new()
var head := Node3D.new()
var leg_l := Node3D.new()
var leg_r := Node3D.new()
var arm_l := Node3D.new()
var arm_r := Node3D.new()
var cargo := MeshInstance3D.new()
var spirit: bool = false
var elder: bool = false
var stride: float = 0.0
var _parts: Array[MeshInstance3D] = []
var _fade: float = 1.0


## `colours` holds jacket, trim, sash, trousers, skin, hair, accent and straw.
func build(colours: Dictionary, style: int, as_spirit: bool) -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	spirit = as_spirit
	add_child(pose_root)
	pose_root.add_child(hips)
	hips.position.y = HIP_HEIGHT
	hips.add_child(torso)
	# The legs always join the hips so the tree frees them; a spirit's stay bare.
	for leg in [leg_l, leg_r]:
		var side: float = 1.0 if leg == leg_l else -1.0
		leg.position = Vector3(0.095 * side, 0, 0)
		hips.add_child(leg)
		if not spirit:
			_part(leg, "leg", colours.trousers, Vector3.ZERO)
			_part(leg, "foot", colours.straw, Vector3(0, -0.62, 0.035), Vector3(0.9, 0.5, 1.5))
	_part(torso, "robe" if spirit else "jacket", colours.jacket, Vector3.ZERO)
	# A darker border at the hem and cuffs, as a printed robe has.
	_part(torso, "robe_hem" if spirit else "hem", colours.trim, Vector3.ZERO)
	_part(torso, "robe_sash" if spirit else "sash", colours.sash, Vector3(0, 0.02, 0))
	var collar: MeshInstance3D = _part(torso, "collar", colours.accent, Vector3(0, 0.49, 0.012))
	collar.rotation.x = 0.35
	for arm in [arm_l, arm_r]:
		var side: float = 1.0 if arm == arm_l else -1.0
		arm.position = Vector3(0.215 * side, 0.43, 0)
		torso.add_child(arm)
		_part(arm, "wide_sleeve" if spirit else "sleeve", colours.jacket, Vector3.ZERO)
		_part(arm, "wide_cuff" if spirit else "cuff", colours.trim, Vector3.ZERO)
		_part(arm, "hand", colours.skin, Vector3(0, -0.39, 0.01))
	head.position.y = 0.52
	torso.add_child(head)
	_part(head, "head", colours.skin, Vector3(0, 0.165, 0), Vector3(1.0, 1.06, 0.96))
	for side in [-1.0, 1.0]:
		_part(head, "eye", colours.hair, Vector3(0.058 * side, 0.15, 0.148), Vector3(1.0, 1.3, 0.6))
	_hair(colours, style)
	cargo.mesh = Meshes.get_mesh("cargo")
	cargo.material_override = _material
	cargo.position = Vector3(0, 0.12, 0.27)
	cargo.hide()
	torso.add_child(cargo)
	_parts.append(cargo)


func _hair(colours: Dictionary, style: int) -> void:
	var cap: MeshInstance3D = _part(head, "hair_cap", colours.hair, Vector3(0, 0.185, -0.014), Vector3(1.0, 1.0, 1.02))
	cap.rotation.x = -0.52
	if spirit:
		_part(head, "hair_fall", colours.hair, Vector3(0, 0.22, -0.11), Vector3(1.1, 1.0, 1.0))
		_part(head, "bun", colours.hair, Vector3(0, 0.36, -0.03), Vector3(1.1, 0.9, 1.1))
		var halo: MeshInstance3D = _part(head, "halo", colours.accent, Vector3(0, 0.2, -0.2))
		halo.rotation.x = PI * 0.5
		halo.set_instance_shader_parameter("glow", 0.9)
		return
	match style % STYLES:
		1:
			_part(head, "bun", colours.hair, Vector3(0, 0.355, -0.02), Vector3(0.9, 1.2, 1.4))
		2:
			_part(head, "bun", colours.hair, Vector3(0, 0.2, -0.19), Vector3(1.3, 1.2, 1.1))
		3:
			_part(head, "kasa", colours.straw, Vector3(0, 0.3, 0))
		4:
			var band: MeshInstance3D = _part(head, "headband", colours.accent, Vector3(0, 0.2, 0), Vector3(1.0, 1.0, 1.0))
			band.rotation.x = -0.15
		5:
			_part(head, "bun", colours.hair, Vector3(0, 0.1, -0.18), Vector3(0.8, 1.6, 0.9))


func _part(parent: Node3D, key: String, colour: Color, at: Vector3, size := Vector3.ONE) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = Meshes.get_mesh(key)
	part.material_override = _material
	part.position = at
	part.scale = size
	part.set_instance_shader_parameter("tint", colour)
	parent.add_child(part)
	_parts.append(part)
	return part


func set_fade(value: float) -> void:
	if is_equal_approx(value, _fade):
		return
	_fade = value
	for part in _parts:
		part.set_instance_shader_parameter("fade", value)


func set_glow(value: float) -> void:
	for part in _parts:
		if part.mesh != Meshes.get_mesh("halo"):
			part.set_instance_shader_parameter("glow", value)


func set_cargo(colour: Variant) -> void:
	cargo.visible = colour != null
	if cargo.visible:
		cargo.set_instance_shader_parameter("tint", colour)


## Ease toward the pose for `activity`; `speed` is ground speed in m/s.
func pose(activity: String, time: float, speed: float, delta: float) -> void:
	stride += speed * delta * 6.0
	var target: Dictionary = Poses.target(activity, time, stride, speed, spirit, cargo.visible)
	if elder and not activity in ["sleeping", "relaxing"]:
		target.torso_x = float(target.get("torso_x", 0.0)) + 0.16
		target.head_x = float(target.get("head_x", 0.0)) - 0.1
	var blend: float = minf(delta * 9.0, 1.0)
	pose_root.rotation.x = lerp_angle(pose_root.rotation.x, target.get("lie", 0.0), blend)
	pose_root.position = pose_root.position.lerp(target.get("root", Vector3.ZERO), blend)
	hips.position.y = HIP_HEIGHT + float(target.get("bob", 0.0))
	torso.rotation = torso.rotation.lerp(Vector3(target.get("torso_x", 0.0), target.get("torso_y", 0.0), target.get("torso_z", 0.0)), blend)
	head.rotation = head.rotation.lerp(Vector3(target.get("head_x", 0.0), target.get("head_y", 0.0), 0.0), blend)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, target.get("leg_l", 0.0), blend)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, target.get("leg_r", 0.0), blend)
	arm_l.rotation = arm_l.rotation.lerp(Vector3(target.get("arm_l_x", 0.0), 0.0, target.get("arm_l_z", 0.08)), blend)
	arm_r.rotation = arm_r.rotation.lerp(Vector3(target.get("arm_r_x", 0.0), 0.0, -float(target.get("arm_r_z", 0.08))), blend)
