extends Node3D
## Keeps one AgentView per present person in step with the simulation, and
## draws the selected person's ring, path and strongest relations.
const AgentView = preload("res://scripts/presentation/agent_view.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")

var sim: RefCounted
var driver: Node
var selected: int = -1
var views: Dictionary = {}
var _ring := MeshInstance3D.new()
var _ring_material := StandardMaterial3D.new()
var _lines := MeshInstance3D.new()
var _lines_mesh := ImmediateMesh.new()
var _lines_material := StandardMaterial3D.new()
var _time: float = 0.0


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.66
	_ring.mesh = torus
	_ring.scale = Vector3(1, 0.1, 1)
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.albedo_color = Style.GOLD
	_ring_material.no_depth_test = true
	_ring.material_override = _ring_material
	add_child(_ring)
	_lines.mesh = _lines_mesh
	_lines_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lines_material.vertex_color_use_as_albedo = true
	_lines_material.no_depth_test = true
	_lines.material_override = _lines_material
	add_child(_lines)


func _process(delta: float) -> void:
	if sim == null:
		return
	_time += delta
	var alpha: float = driver.alpha if driver != null else 1.0
	for agent in sim.agents:
		var view: Node3D = views.get(agent.id)
		if not agent.is_present():
			if view != null:
				view.queue_free()
				views.erase(agent.id)
			continue
		if view == null:
			view = AgentView.new()
			add_child(view)
			view.setup(agent)
			views[agent.id] = view
		view.refresh(agent, alpha, delta, agent.id == selected)
	_draw_selection()


func _draw_selection() -> void:
	_lines_mesh.clear_surfaces()
	var view: Node3D = views.get(selected)
	if view == null:
		_ring.hide()
		return
	var agent: RefCounted = sim.agents[selected]
	_ring.show()
	_ring.position = view.position + Vector3(0, 0.05, 0)
	var pulse: float = 1.0 + sin(_time * 4.0) * 0.08
	_ring.scale = Vector3(pulse, 0.1, pulse)
	_lines_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var previous: Vector3 = view.position + Vector3(0, 0.15, 0)
	for cell in agent.path:
		var point := Vector3(cell.x + 0.5, cell.y + 0.15, cell.z + 0.5)
		_lines_mesh.surface_set_color(Color(Style.GOLD, 0.8))
		_lines_mesh.surface_add_vertex(previous)
		_lines_mesh.surface_set_color(Color(Style.GOLD, 0.8))
		_lines_mesh.surface_add_vertex(point)
		previous = point
	for other in agent.beliefs.relations:
		var opinion: float = agent.beliefs.opinion_of(other)
		var other_view: Node3D = views.get(other)
		if absf(opinion) < 25.0 or other_view == null:
			continue
		var color: Color = Style.GOOD if opinion > 0.0 else Style.BAD
		color.a = clampf(absf(opinion) / 100.0 + 0.3, 0.3, 1.0)
		_lines_mesh.surface_set_color(color)
		_lines_mesh.surface_add_vertex(view.position + Vector3(0, 1.0, 0))
		_lines_mesh.surface_set_color(color)
		_lines_mesh.surface_add_vertex(other_view.position + Vector3(0, 1.0, 0))
	# An empty surface is not allowed; close with a degenerate segment.
	_lines_mesh.surface_add_vertex(previous)
	_lines_mesh.surface_add_vertex(previous)
	_lines_mesh.surface_end()


## The person nearest a screen point within a zoom-aware radius, or -1.
## Close people get a wider margin; `min_scale` keeps far ones from
## shrinking below a share of `reach` (the overlook keeps the full reach).
func pick(camera: Camera3D, screen: Vector2, reach: float, min_scale: float = 0.6) -> int:
	var best: int = -1
	var best_distance: float = INF
	for id in views:
		var view: Node3D = views[id]
		var point: Vector3 = view.position + Vector3(0, 0.9, 0)
		if camera.is_position_behind(point):
			continue
		var distance_to_camera: float = camera.global_position.distance_to(point)
		var radius: float = reach * clampf(12.0 / maxf(distance_to_camera, 1.0), min_scale, 3.0)
		var d: float = camera.unproject_position(point).distance_to(screen)
		if d <= radius and d < best_distance:
			best = id
			best_distance = d
	return best
