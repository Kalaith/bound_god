extends Node3D
## Sky, sun and atmosphere for the valley. The sun follows the calendar hour;
## graphics toggles (SSAO, glow, shadows) come from the settings store.

var environment := Environment.new()
var sky_material := ProceduralSkyMaterial.new()
var sun := DirectionalLight3D.new()
var moon := DirectionalLight3D.new()
var world_environment := WorldEnvironment.new()
var _hour: float = 10.0


func _ready() -> void:
	sky_material.sky_top_color = Color("4f7fb8")
	sky_material.sky_horizon_color = Color("bcd2e0")
	sky_material.ground_bottom_color = Color("2a3326")
	sky_material.ground_horizon_color = Color("8ea3a0")
	sky_material.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 1.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.6
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.1
	environment.fog_enabled = true
	environment.fog_light_color = Color("aebfcc")
	environment.fog_density = 0.0016
	environment.fog_aerial_perspective = 0.4
	environment.volumetric_fog_enabled = false
	environment.volumetric_fog_density = 0.04
	environment.volumetric_fog_albedo = Color("c8ccd8")
	world_environment.environment = environment
	add_child(world_environment)
	sun.light_energy = 1.25
	sun.light_color = Color("fff1d8")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.04
	add_child(sun)
	moon.light_energy = 0.0
	moon.light_color = Color("9fb4ff")
	moon.shadow_enabled = false
	add_child(moon)
	set_hour(_hour)


func apply_graphics(values: Dictionary) -> void:
	environment.ssao_enabled = bool(values.get("ssao", true))
	environment.glow_enabled = bool(values.get("glow", true))
	sun.shadow_enabled = bool(values.get("shadows", true))


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
	sun.rotation = Vector3(-deg_to_rad(8.0 + elevation * 62.0), deg_to_rad(-60.0 + day_t * 140.0), 0.0)
	sun.light_energy = 1.05 * daylight
	sun.visible = daylight > 0.01
	var dusk: float = 1.0 - absf(elevation * 2.0 - 0.6)
	sun.light_color = Color("fff1d8").lerp(Color("ffb46b"), clampf(dusk * 0.6, 0.0, 0.7) if elevation < 0.45 else 0.0)
	moon.rotation = Vector3(-deg_to_rad(50.0), deg_to_rad(30.0), 0.0)
	moon.light_energy = 0.0 if not night else 0.22
	var day_top := Color("4f7fb8")
	var night_top := Color("0a1024")
	var t: float = daylight
	sky_material.sky_top_color = night_top.lerp(day_top, t)
	sky_material.sky_horizon_color = Color("1b2238").lerp(Color("bcd2e0"), t).lerp(Color("e3a46a"), clampf(dusk, 0.0, 1.0) * 0.5 * t)
	sky_material.ground_horizon_color = sky_material.sky_horizon_color.darkened(0.25)
	environment.ambient_light_energy = lerpf(0.2, 0.45, t)
	environment.fog_light_color = Color("2b3348").lerp(Color("aebfcc"), t)
