extends Node3D
## The sky's weather as it is seen (M20): rain streaks and snowflakes falling
## round the camera, a sky and mist greyed by cloud, distant flashes in a
## thunderstorm, and snow that settles on the ground and roofs through a
## snowy winter and melts away after it. Reads the sim; changes nothing.

const Style = preload("res://scripts/presentation/ui/style.gd")
const RAIN_COLOUR := Color(0.78, 0.82, 0.88, 0.45)
const SNOW_COLOUR := Color(0.97, 0.97, 1.0, 0.9)
## Greying of the sky by kind of weather.
const DIM: Dictionary = {"clear": 0.0, "overcast": 0.45, "rain": 0.65, "thunderstorm": 0.95, "snow": 0.55}
## Snow settling and melting, per in-game hour.
const SETTLE_PER_HOUR: float = 0.12
const MELT_PER_HOUR: float = 0.25

var sim: RefCounted
var camera: Camera3D
var rig: Node3D
var world_view: Node3D
## How heavily rain and snow are falling as shown (eases toward the sky's).
var rain: float = 0.0
var snow: float = 0.0
var dim: float = 0.0
## How deep the shown snow lies (0 to 1).
var cover: float = 0.0
var _flash: float = 0.0
var _next_flash: float = 3.0
var _last_tick: int = -1
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 2024
	_rain = _particles(1600, 0.7, Vector3(0, -20.0, 0), 16.0, Vector3(22, 1, 22), _streak(), 0.0)
	_snow = _particles(1400, 9.0, Vector3(0, -0.3, 0), 1.4, Vector3(26, 1, 26), _flake(), 0.6)
	add_child(_rain)
	add_child(_snow)


func _particles(count: int, lifetime: float, gravity: Vector3, speed: float, box: Vector3, mesh: Mesh, drift: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = lifetime
	# The air is already full of rain or snow when it starts to fall.
	particles.preprocess = lifetime
	particles.emitting = false
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = box
	process.gravity = gravity
	process.direction = Vector3(0, -1, 0)
	process.initial_velocity_min = speed * 0.85
	process.initial_velocity_max = speed * 1.15
	if drift > 0.0:
		process.turbulence_enabled = true
		process.turbulence_noise_strength = drift
		process.turbulence_noise_scale = 3.0
	particles.process_material = process
	particles.draw_pass_1 = mesh
	return particles


static func _unlit(colour: Color, billboard: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = colour
	material.no_depth_test = false
	if billboard:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return material


func _streak() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.55, 0.025)
	mesh.material = _unlit(RAIN_COLOUR, false)
	return mesh


func _flake() -> Mesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.11, 0.11)
	mesh.material = _unlit(SNOW_COLOUR, true)
	return mesh


func _process(delta: float) -> void:
	if sim == null or sim.weather == null:
		return
	var kind: String = sim.weather.kind
	var blend: float = clampf(delta * 0.6, 0.0, 1.0)
	rain = lerpf(rain, 1.0 if kind in ["rain", "thunderstorm"] else 0.0, blend)
	snow = lerpf(snow, 1.0 if kind == "snow" else 0.0, blend)
	dim = lerpf(dim, float(DIM.get(kind, 0.0)), blend)
	_settle(kind)
	if camera != null:
		var at: Vector3 = camera.global_position + Vector3(0, 14.0, 0)
		_rain.global_position = at
		_snow.global_position = at
	_rain.emitting = rain > 0.05
	_rain.amount_ratio = clampf(rain, 0.0, 1.0)
	_snow.emitting = snow > 0.05
	_snow.amount_ratio = clampf(snow, 0.0, 1.0)
	_lightning(kind, delta)
	if rig != null:
		rig.set_weather(dim, 0.0 if Style.reduce_motion else _flash)


## Snow lies deeper while it falls in winter and melts once winter is past.
func _settle(kind: String) -> void:
	var tick: int = sim.calendar.tick
	if _last_tick < 0 or tick < _last_tick:
		_last_tick = tick
		return
	var hours: float = float(tick - _last_tick) / sim.calendar.ticks_per_hour()
	_last_tick = tick
	if hours <= 0.0:
		return
	var was: float = cover
	if kind == "snow":
		cover = minf(cover + SETTLE_PER_HOUR * hours, 1.0)
	elif not sim.calendar.is_winter():
		cover = maxf(cover - MELT_PER_HOUR * hours, 0.0)
	if world_view != null and not is_equal_approx(was, cover):
		world_view.set_snow(cover)


## Now and then a thunderstorm lights the whole sky for a moment.
func _lightning(kind: String, delta: float) -> void:
	_flash = maxf(_flash - delta * 4.0, 0.0)
	if kind != "thunderstorm":
		return
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = _rng.randf_range(3.0, 9.0)
		_flash = 1.0


## For captures: show a sky at once, without easing in.
func settle_now(snow_lying: float) -> void:
	var kind: String = sim.weather.kind
	rain = 1.0 if kind in ["rain", "thunderstorm"] else 0.0
	snow = 1.0 if kind == "snow" else 0.0
	dim = float(DIM.get(kind, 0.0))
	cover = snow_lying
	if world_view != null:
		world_view.set_snow(cover)
	_last_tick = sim.calendar.tick
