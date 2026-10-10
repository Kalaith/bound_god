extends Node3D
## Warm light at the lanterns nearest the camera: a small pool of point
## lights moved to whichever lanterns are closest, brighter after dusk.
## Reads the sim's lantern list; never changes it.

const POOL: int = 12
const RANGE: float = 7.0

var sim: RefCounted
var camera: Camera3D
var _lights: Array[OmniLight3D] = []
var _left: float = 0.0


func _ready() -> void:
	for i in range(POOL):
		var light := OmniLight3D.new()
		light.light_color = Color("ffcf7a")
		light.omni_range = RANGE
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_lights.append(light)


func _process(delta: float) -> void:
	_left -= delta
	if sim == null or camera == null or _left > 0.0:
		return
	_left = 0.4
	var eye: Vector3 = camera.global_position
	var ranked: Array = []
	for cell in sim.lanterns:
		var at := Vector3(cell.x + 0.5, cell.y + 0.6, cell.z + 0.5)
		ranked.append([at.distance_squared_to(eye), cell.y, cell.z, cell.x, at])
	ranked.sort()
	var night: bool = not sim.calendar.is_daylight()
	for i in range(POOL):
		var light: OmniLight3D = _lights[i]
		light.visible = i < ranked.size()
		if light.visible:
			light.position = ranked[i][4]
			light.light_energy = 1.6 if night else 0.35
