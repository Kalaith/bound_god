extends Node3D
## World overlays: the presence boundary (a shimmering wall that brightens as
## the avatar nears it, plus a faint ring on the ground) and helpers for
## construction ghosts and selection markers added in later milestones.

const BOUNDARY_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;
uniform vec3 avatar_position;
uniform vec4 tint : source_color = vec4(0.72, 0.62, 1.0, 1.0);
uniform float near_range = 7.0;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float near = 1.0 - clamp(distance(world_position.xz, avatar_position.xz) / near_range, 0.0, 1.0);
	float height = 1.0 - clamp(abs(world_position.y - avatar_position.y - 1.0) / 7.0, 0.0, 1.0);
	float around = atan(world_position.z - avatar_position.z, world_position.x - avatar_position.x);
	float lattice = max(pow(abs(sin(world_position.y * 2.2 - TIME * 1.4)), 24.0), pow(abs(sin((world_position.x + world_position.z) * 1.6 + TIME * 0.6)), 24.0));
	float glow = 0.12 + 0.88 * lattice;
	float alpha = near * near * height * glow;
	ALBEDO = tint.rgb * alpha * 0.55;
}
"""

var wall := MeshInstance3D.new()
var ring := MeshInstance3D.new()
var _wall_material := ShaderMaterial.new()
var _ring_material := StandardMaterial3D.new()
var _radius: float = -1.0


func _ready() -> void:
	var shader := Shader.new()
	shader.code = BOUNDARY_SHADER
	_wall_material.shader = shader
	wall.material_override = _wall_material
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.albedo_color = Color(0.75, 0.65, 1.0, 0.35)
	_ring_material.no_depth_test = false
	ring.material_override = _ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


func set_zone(center: Vector3, radius: float) -> void:
	# The 30-high wall spans from 6 below the shrine to 24 above it.
	wall.global_position = Vector3(center.x, center.y + 9.0, center.z)
	ring.global_position = Vector3(center.x, 0.0, center.z)
	if is_equal_approx(radius, _radius):
		return
	_radius = radius
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 30.0
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	cylinder.radial_segments = maxi(48, int(radius * 4.0))
	cylinder.rings = 1
	wall.mesh = cylinder


## A dotted line on the terrain along the boundary, so it reads from above.
func draw_ring(world: RefCounted, center: Vector3, radius: float) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var segments: int = maxi(64, int(radius * 6.0))
	for index in range(segments):
		if index % 2 == 1:
			continue
		var a: float = index * TAU / segments
		var b: float = (index + 1) * TAU / segments
		var pa := Vector2(center.x, center.z) + Vector2.from_angle(a) * radius
		var pb := Vector2(center.x, center.z) + Vector2.from_angle(b) * radius
		var ya: float = world.top_solid_y(int(pa.x), int(pa.y)) + 1.08
		var yb: float = world.top_solid_y(int(pb.x), int(pb.y)) + 1.08
		mesh.surface_add_vertex(Vector3(pa.x - center.x, ya, pa.y - center.z))
		mesh.surface_add_vertex(Vector3(pb.x - center.x, yb, pb.y - center.z))
	mesh.surface_end()
	ring.mesh = mesh


func update_avatar(position: Vector3) -> void:
	_wall_material.set_shader_parameter("avatar_position", position)
