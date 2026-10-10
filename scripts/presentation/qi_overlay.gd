extends MeshInstance3D
## The tree's qi drawn on the ground: a jade wash over every other column
## inside the presence, deeper where qi is denser. Read from the sim; built
## when shown and when the presence moves.
const STEP: int = 2
const TINT := Color(0.55, 0.92, 0.78)

var sim: RefCounted
var _material := StandardMaterial3D.new()
var _built_for: Vector4 = Vector4.INF


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hide()


func toggle() -> void:
	visible = not visible
	if visible:
		rebuild()


func rebuild() -> void:
	var center: Vector3 = sim.zone_center()
	var radius: float = sim.zone_radius()
	var key := Vector4(center.x, center.y, center.z, radius)
	if key == _built_for and mesh != null:
		return
	_built_for = key
	var built := ImmediateMesh.new()
	built.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var reach: int = int(radius)
	for dz in range(-reach, reach + 1, STEP):
		for dx in range(-reach, reach + 1, STEP):
			if Vector2(dx, dz).length() > radius:
				continue
			var x: int = int(center.x) + dx
			var z: int = int(center.z) + dz
			var top: int = sim.voxels.top_solid_y(x, z)
			if top < 0:
				continue
			var qi: float = sim.qi.density(sim, Vector3i(x, top + 1, z))
			var colour := Color(TINT, clampf(qi * 0.55, 0.04, 0.55))
			var y: float = top + 1.06
			var a := Vector3(x + 0.15, y, z + 0.15)
			var b := Vector3(x + STEP - 0.15, y, z + 0.15)
			var c := Vector3(x + STEP - 0.15, y, z + STEP - 0.15)
			var d := Vector3(x + 0.15, y, z + STEP - 0.15)
			for corner in [a, b, c, a, c, d]:
				built.surface_set_color(colour)
				built.surface_add_vertex(corner)
	built.surface_end()
	mesh = built


func _process(_delta: float) -> void:
	if visible and sim != null:
		rebuild()
