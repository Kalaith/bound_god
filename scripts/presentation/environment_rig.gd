extends Node3D
## Sky, sun and atmosphere for the valley, tuned to read like ink and soft
## pastel on paper: a cream horizon under faded blue, warm mist that thickens
## with distance and pools in the low ground, gentle light and pale shadows.
## The sun follows the calendar hour; graphics toggles (SSAO, glow, shadows)
## come from the settings store.

const DAY_TOP := Color("aebfc5")
const DAY_HORIZON := Color("ebe2cc")
const NIGHT_TOP := Color("161b28")
const NIGHT_HORIZON := Color("343947")
const DUSK := Color("e2ae86")
const DAY_MIST := Color("e2d9c4")
const NIGHT_MIST := Color("2c3240")
const SUN := Color("fbeedb")
const INK_PAPER = preload("res://assets/shaders/ink_paper.gdshader")

var environment := Environment.new()
var sky_material := ProceduralSkyMaterial.new()
var sun := DirectionalLight3D.new()
var moon := DirectionalLight3D.new()
var world_environment := WorldEnvironment.new()
## The ink-and-paper overlay, carried in front of the camera.
var paper := MeshInstance3D.new()
var _hour: float = 10.0
## How much the weather greys the sky (0 clear, 1 storm) and a lightning flash.
var _dim: float = 0.0
var _flash: float = 0.0


func _ready() -> void:
	sky_material.sky_top_color = DAY_TOP
	sky_material.sky_horizon_color = DAY_HORIZON
	sky_material.sky_curve = 0.12
	sky_material.ground_bottom_color = Color("b9b19c")
	sky_material.ground_horizon_color = DAY_HORIZON
	sky_material.sun_angle_max = 12.0
	sky_material.sun_curve = 0.3
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.75
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.95
	environment.tonemap_white = 2.2
	environment.ssao_enabled = true
	environment.ssao_radius = 1.4
	environment.ssao_intensity = 1.1
	environment.ssao_power = 1.2
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 0.95
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.fog_enabled = true
	environment.fog_light_color = DAY_MIST
	environment.fog_light_energy = 1.0
	environment.fog_density = 0.0028
	environment.fog_aerial_perspective = 0.15
	environment.fog_sky_affect = 0.35
	environment.fog_height = 11.0
	environment.fog_height_density = 0.0
	environment.volumetric_fog_enabled = false
	environment.volumetric_fog_density = 0.04
	environment.volumetric_fog_albedo = Color("d8d2c4")
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.9
	environment.adjustment_contrast = 1.08
	environment.adjustment_brightness = 1.02
	world_environment.environment = environment
	add_child(world_environment)
	sun.light_energy = 1.1
	sun.light_color = SUN
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.85
	sun.shadow_blur = 1.6
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.04
	add_child(sun)
	moon.light_energy = 0.0
	moon.light_color = Color("a9b6dc")
	moon.shadow_enabled = false
	add_child(moon)
	set_hour(_hour)


## Hangs the ink-and-paper overlay on the camera: a full-screen quad drawn last.
func attach_paper(camera: Camera3D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var material := ShaderMaterial.new()
	material.shader = INK_PAPER
	material.render_priority = Material.RENDER_PRIORITY_MAX
	paper.mesh = quad
	paper.material_override = material
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	paper.extra_cull_margin = 16384.0
	paper.position = Vector3(0, 0, -1.0)
	camera.add_child(paper)


func apply_graphics(values: Dictionary) -> void:
	paper.visible = bool(values.get("ink", true))
	environment.ssao_enabled = bool(values.get("ssao", true))
	environment.glow_enabled = bool(values.get("glow", true))
	sun.shadow_enabled = bool(values.get("shadows", true))


## The weather view greys the sky and mist and lights it with flashes.
func set_weather(dim: float, flash: float) -> void:
	_dim = clampf(dim, 0.0, 1.0)
	_flash = clampf(flash, 0.0, 1.0)
	set_hour(_hour)


## Veil of Fog thickens the air where the god hides people.
func set_veil(active: bool) -> void:
	environment.volumetric_fog_enabled = active


func set_hour(hour: float) -> void:
	_hour = hour
	# Sun rises at 6, peaks at 13, sets at 20; below the horizon at night.
	var day_t: float = clampf((hour - 6.0) / 14.0, 0.0, 1.0)
	var elevation: float = sin(day_t * PI)
	var daylight: float = clampf(elevation * 1.6, 0.0, 1.0)
	var night: bool = hour < 5.5 or hour > 20.5
	sun.rotation = Vector3(-deg_to_rad(8.0 + elevation * 58.0), deg_to_rad(-60.0 + day_t * 140.0), 0.0)
	sun.light_energy = 1.1 * daylight
	sun.visible = daylight > 0.01
	var dusk: float = 1.0 - absf(elevation * 2.0 - 0.6)
	sun.light_color = SUN.lerp(Color("f4b98a"), clampf(dusk * 0.6, 0.0, 0.7) if elevation < 0.45 else 0.0)
	moon.rotation = Vector3(-deg_to_rad(50.0), deg_to_rad(30.0), 0.0)
	moon.light_energy = 0.0 if not night else 0.25
	var t: float = daylight
	var glow: float = clampf(dusk, 0.0, 1.0) * 0.45 * t
	sky_material.sky_top_color = NIGHT_TOP.lerp(DAY_TOP, t)
	sky_material.sky_horizon_color = NIGHT_HORIZON.lerp(DAY_HORIZON, t).lerp(DUSK, glow)
	sky_material.ground_horizon_color = sky_material.sky_horizon_color
	sky_material.ground_bottom_color = sky_material.sky_horizon_color.darkened(0.15)
	environment.ambient_light_energy = lerpf(0.3, 0.5, t)
	environment.fog_light_color = NIGHT_MIST.lerp(DAY_MIST, t).lerp(DUSK, glow * 0.6)
	_apply_weather(t)


## Cloud mutes the sun and greys the sky toward the mist; a flash lights all.
func _apply_weather(daylight: float) -> void:
	if _dim <= 0.0 and _flash <= 0.0:
		environment.fog_density = 0.0028
		return
	# Storm cloud is heavier and darker than a rain sky.
	var grey := Color("9ea3a6").darkened(maxf(_dim - 0.6, 0.0) * 1.1).lerp(Color("3b4048"), 1.0 - daylight)
	sun.light_energy *= 1.0 - 0.75 * _dim
	environment.ambient_light_energy *= 1.0 - 0.35 * maxf(_dim - 0.6, 0.0) / 0.4
	sky_material.sky_top_color = sky_material.sky_top_color.lerp(grey, _dim * 0.8)
	sky_material.sky_horizon_color = sky_material.sky_horizon_color.lerp(grey.lightened(0.15), _dim * 0.7)
	sky_material.ground_horizon_color = sky_material.sky_horizon_color
	environment.fog_light_color = environment.fog_light_color.lerp(grey, _dim * 0.6)
	environment.fog_density = 0.0028 * (1.0 + 2.5 * _dim)
	environment.ambient_light_energy += _flash * 1.2
	sky_material.sky_top_color = sky_material.sky_top_color.lerp(Color("e8eef5"), _flash * 0.8)
