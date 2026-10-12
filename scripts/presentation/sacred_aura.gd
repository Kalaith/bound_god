extends Node3D
## The sacred tree's presence: a straw rope with paper streamers bound round
## its trunk, pale motes rising slowly through the crown and the odd leaf
## drifting down. Decoration only; it reads where the tree stands and never
## touches the sim.

const Style = preload("res://scripts/presentation/ui/style.gd")
const ROPE := Color("cdb27a")
const PAPER := Color("f3eee2")
const MOTE := Color("d9fff0")
const LEAF := Color("8fc4b5")

## The tree's base cell (the trunk is two by two from here).
var base := Vector3i.ZERO
## The world, to show the warding formation's edge once the tree has it (M23).
var sim: RefCounted = null
var _ward: MeshInstance3D
## The drifting motes and leaves, stilled when motion is reduced.
var _drift: Array = []
var _ward_check: float = 0.0


func _ready() -> void:
	var trunk := Vector3(base.x + 1.0, base.y, base.z + 1.0)
	_rope(trunk + Vector3(0, 2.6, 0))
	_motes(trunk + Vector3(0, 10.0, 0))
	_leaves(trunk + Vector3(0, 9.0, 0))
	_ward_ring(trunk)


## The warding formation's edge: a faint gold line on the ground.
func _ward_ring(trunk: Vector3) -> void:
	var reach: float = float(load("res://scripts/core/data.gd").tree_growth().warding.reach)
	var torus := TorusMesh.new()
	torus.inner_radius = reach - 0.12
	torus.outer_radius = reach + 0.12
	torus.rings = 96
	torus.ring_segments = 4
	_ward = MeshInstance3D.new()
	_ward.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.95, 0.82, 0.45, 0.55)
	_ward.material_override = material
	_ward.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ward.position = Vector3(trunk.x, trunk.y + 0.15, trunk.z)
	_ward.scale = Vector3(1.0, 0.2, 1.0)
	_ward.visible = false
	add_child(_ward)


func _process(delta: float) -> void:
	_ward_check -= delta
	if _ward_check > 0.0 or sim == null or _ward == null:
		return
	_ward_check = 1.0
	for particles in _drift:
		particles.emitting = not Style.reduce_motion
	_ward.visible = sim.tree_growth != null and sim.tree_growth.has_unlock("warding_formation")


func _rope(center: Vector3) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 1.4
	torus.outer_radius = 1.62
	torus.rings = 24
	torus.ring_segments = 8
	var rope := MeshInstance3D.new()
	rope.mesh = torus
	rope.material_override = _lit(ROPE)
	rope.position = center
	add_child(rope)
	# Zigzag paper streamers hang from the rope on each face of the trunk.
	var strip := BoxMesh.new()
	strip.size = Vector3(0.16, 0.2, 0.03)
	var paper: Material = _lit(PAPER)
	for side in range(4):
		var facing: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, side * PI * 0.5)
		for step in range(3):
			var piece := MeshInstance3D.new()
			piece.mesh = strip
			piece.material_override = paper
			piece.position = center + facing * 1.52 + Vector3(0.07 * (1 - 2 * (step % 2)), -0.18 - step * 0.19, 0)
			piece.rotation.y = side * PI * 0.5
			add_child(piece)


func _motes(center: Vector3) -> void:
	var motes := GPUParticles3D.new()
	_drift.append(motes)
	motes.amount = 70
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.visibility_aabb = AABB(Vector3(-10, -12, -10), Vector3(20, 24, 20))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 6.5
	process.direction = Vector3.UP
	process.spread = 30.0
	process.initial_velocity_min = 0.08
	process.initial_velocity_max = 0.25
	process.gravity = Vector3(0, 0.03, 0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.turbulence_noise_scale = 4.0
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.color_ramp = _fade_ramp(MOTE)
	motes.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.4, 1.4, 1.4)
	quad.material = material
	motes.draw_pass_1 = quad
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.position = center
	add_child(motes)


func _leaves(center: Vector3) -> void:
	var leaves := GPUParticles3D.new()
	_drift.append(leaves)
	leaves.amount = 10
	leaves.lifetime = 12.0
	leaves.preprocess = 12.0
	leaves.visibility_aabb = AABB(Vector3(-10, -12, -10), Vector3(20, 16, 20))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(5.5, 1.5, 5.5)
	process.gravity = Vector3(0, -0.22, 0)
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.1
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 1.2
	process.turbulence_noise_scale = 3.0
	process.angular_velocity_min = -60.0
	process.angular_velocity_max = 60.0
	process.color_ramp = _fade_ramp(LEAF)
	leaves.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.1)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	quad.material = material
	leaves.draw_pass_1 = quad
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	leaves.position = center
	add_child(leaves)


## Fades a particle in and out so none pops.
func _fade_ramp(color: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	gradient.colors = PackedColorArray([Color(color, 0.0), color, color, Color(color, 0.0)])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _lit(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	return material
