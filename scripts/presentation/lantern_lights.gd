extends Node3D
## Warm light at the lanterns nearest the camera: a small pool of point
## lights moved to whichever lanterns are closest, brighter after dusk.
## Reads the sim's lantern list; never changes it.

const POOL: int = 12
const RANGE: float = 7.0

var sim: RefCounted
var camera: Camera3D
var _lights: Array[OmniLight3D] = []
## A glowing lamp over each lit post, so the lantern itself shines.
var _lamps: Array[MeshInstance3D] = []
var _left: float = 0.0


func _ready() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("ffd98a")
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.3, 0.34)
	for i in range(POOL):
		var light := OmniLight3D.new()
		light.light_color = Color("ffcf7a")
		light.omni_range = RANGE
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_lights.append(light)
		var lamp := MeshInstance3D.new()
		lamp.mesh = box
		lamp.material_override = glow
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.visible = false
		add_child(lamp)
		_lamps.append(lamp)


func _process(delta: float) -> void:
	_left -= delta
	if sim == null or camera == null or _left > 0.0:
		return
	_left = 0.4
	var eye: Vector3 = camera.global_position
	var ranked: Array = []
	for cell in sim.lanterns:
		var at := Vector3(cell.x + 0.5, cell.y + 0.8, cell.z + 0.5)
		ranked.append([at.distance_squared_to(eye), cell.y, cell.z, cell.x, at])
	ranked.sort()
	var night: bool = not sim.calendar.is_daylight()
	for i in range(POOL):
		var light: OmniLight3D = _lights[i]
		light.visible = i < ranked.size()
		_lamps[i].visible = light.visible
		if light.visible:
			_lamps[i].position = ranked[i][4]
			light.position = ranked[i][4] + Vector3(0.0, 0.6, 0.0)
			light.light_energy = 1.6 if night else 0.35
