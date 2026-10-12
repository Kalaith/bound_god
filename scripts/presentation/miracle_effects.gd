extends Node3D
## Each miracle's own sign where it is worked (M24), from the faith event's
## miracle id: a burst of particles shaped and coloured for it (green motes
## rising for Bless Growth, embers for Kindle, a grey bank for the Veil, pale
## sparks for Mend, a dome for the Shield, a gold column for Defy Heaven, blue
## motes for Nurture, a clear ripple for Calm the Sky, gold in the crown for
## Ripen Fruit, a halo for Bless Cultivation). The ring flash (overlays.gd)
## stays. Reads the simulation only; each effect frees itself.
const Style = preload("res://scripts/presentation/ui/style.gd")

## miracle id -> [colour, amount, lifetime, rise speed, spread radius share, shape]
const SIGNS: Dictionary = {
	"bless_growth": [Color(0.55, 0.9, 0.5), 90, 2.4, 1.6, 0.8, "ground"],
	"kindle": [Color(1.0, 0.62, 0.25), 60, 1.6, 2.4, 0.5, "ground"],
	"veil_of_fog": [Color(0.75, 0.78, 0.8, 0.5), 120, 5.0, 0.3, 0.9, "bank"],
	"mend": [Color(0.95, 0.95, 0.85), 70, 1.8, 1.0, 0.7, "ground"],
	"bless_cultivation": [Color(0.75, 1.0, 0.92), 40, 2.2, 0.6, 0.15, "halo"],
	"shield_trial": [Color(0.6, 0.85, 1.0, 0.6), 160, 3.0, 0.0, 0.6, "dome"],
	"defy_heaven": [Color(1.0, 0.85, 0.35), 200, 2.8, 6.0, 0.1, "column"],
	"nurture": [Color(0.5, 0.75, 1.0), 80, 3.0, 0.8, 1.0, "ring"],
	"calm_sky": [Color(0.85, 0.95, 1.0, 0.6), 140, 3.0, 0.2, 0.5, "ring"],
	"ripen_fruit": [Color(1.0, 0.85, 0.4), 70, 2.6, -0.4, 0.4, "crown"],
}

var sim: RefCounted
var _seen: int = -1
var _soft_texture: GradientTexture2D = null


## A soft round dab, white at the heart and fading out: every mote's shape.
func _soft() -> GradientTexture2D:
	if _soft_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		_soft_texture = GradientTexture2D.new()
		_soft_texture.gradient = gradient
		_soft_texture.fill = GradientTexture2D.FILL_RADIAL
		_soft_texture.fill_from = Vector2(0.5, 0.5)
		_soft_texture.fill_to = Vector2(1.0, 0.5)
		_soft_texture.width = 64
		_soft_texture.height = 64
	return _soft_texture


func _process(_delta: float) -> void:
	if sim == null or sim.faith == null:
		return
	for event in sim.faith.events:
		if int(event.uid) <= _seen:
			continue
		_seen = int(event.uid)
		if SIGNS.has(str(event.id)) and not Style.reduce_motion:
			_sign(str(event.id), Vector3(event.cell) + Vector3(0.5, 0.2, 0.5), float(event.radius))


## The particles for one miracle at `at`, spread over its radius.
func _sign(id: String, at: Vector3, radius: float) -> void:
	var sign: Array = SIGNS[id]
	var spread: float = maxf(radius * float(sign[4]), 1.0)
	var particles := GPUParticles3D.new()
	particles.amount = int(sign[1])
	particles.lifetime = float(sign[2])
	particles.one_shot = true
	particles.explosiveness = 0.7
	particles.visibility_aabb = AABB(Vector3(-spread - 4, -4, -spread - 4), Vector3(spread * 2 + 8, 30, spread * 2 + 8))
	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3.ZERO
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = absf(float(sign[3])) * 0.6
	process.initial_velocity_max = absf(float(sign[3]))
	if float(sign[3]) < 0.0:
		process.direction = Vector3.DOWN
	process.scale_min = 0.6
	process.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(sign[0], 0.0))
	fade.add_point(0.15, Color(sign[0]))
	fade.set_color(fade.get_point_count() - 1, Color(sign[0], 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	match str(sign[5]):
		"ground", "bank":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			process.emission_box_extents = Vector3(spread, 0.3 if str(sign[5]) == "ground" else 1.5, spread)
		"ring":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			process.emission_ring_axis = Vector3.UP
			process.emission_ring_radius = spread
			process.emission_ring_inner_radius = spread * 0.85
			process.emission_ring_height = 0.2
		"dome":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
			process.emission_sphere_radius = spread
		"column", "halo":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			process.emission_sphere_radius = spread
		"crown":
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			process.emission_sphere_radius = 5.0
			at += Vector3(0.5, 10.0, 0.5)
	particles.process_material = process
	var mote := QuadMesh.new()
	mote.size = Vector2(0.18, 0.18) if str(sign[5]) != "bank" else Vector2(2.4, 1.2)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_texture = _soft()
	mote.material = material
	particles.draw_pass_1 = mote
	particles.position = at
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(float(sign[2]) + 1.0).timeout.connect(particles.queue_free)
