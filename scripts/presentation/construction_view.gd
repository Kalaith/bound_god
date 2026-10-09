extends Node3D
## Ghost blocks for every block a building site still has to place, the
## stores piles at each settlement's centre, and loose materials lying about.
## Rebuilt only when the sites, stock or items change.
const AgentView = preload("res://scripts/presentation/agent_view.gd")

var sim: RefCounted
var _ghosts := MultiMeshInstance3D.new()
var _piles := MultiMeshInstance3D.new()
var _items := MultiMeshInstance3D.new()
var _key: String = ""


func _ready() -> void:
	var ghost_material := StandardMaterial3D.new()
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.albedo_color = Color(0.95, 0.85, 0.55, 0.22)
	ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghosts.multimesh = _multimesh(Vector3(0.98, 0.98, 0.98), false)
	_ghosts.material_override = ghost_material
	_ghosts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ghosts)
	var crate := StandardMaterial3D.new()
	crate.albedo_color = Color("8a6a43")
	_piles.multimesh = _multimesh(Vector3(0.8, 0.5, 0.8), false)
	_piles.material_override = crate
	add_child(_piles)
	var loose := StandardMaterial3D.new()
	loose.vertex_color_use_as_albedo = true
	_items.multimesh = _multimesh(Vector3(0.3, 0.2, 0.3), true)
	_items.material_override = loose
	add_child(_items)


static func _multimesh(size: Vector3, colored: bool) -> MultiMesh:
	var box := BoxMesh.new()
	box.size = size
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = colored
	multimesh.mesh = box
	return multimesh


func _process(_delta: float) -> void:
	if sim == null:
		return
	var key: String = str(sim.construction.next_id)
	for id in sim.construction.ids():
		key += ":%d/%d" % [id, sim.construction.get_site(id).cursor]
	for id in sim.settlements.ids():
		key += "|%d" % sim.settlements.total(id)
	key += "#%d" % sim.items.size()
	if key == _key:
		return
	_key = key
	_rebuild()


func _rebuild() -> void:
	var cells: Array = []
	for id in sim.construction.ids():
		var site: Dictionary = sim.construction.get_site(id)
		for i in range(int(site.cursor), site.order.size()):
			var entry: Array = site.order[i]
			if entry[1] != 0:
				cells.append(entry[0])
	var ghosts: MultiMesh = _ghosts.multimesh
	ghosts.instance_count = cells.size()
	for i in range(cells.size()):
		ghosts.set_instance_transform(i, Transform3D(Basis(), Vector3(cells[i]) + Vector3(0.5, 0.5, 0.5)))
	var piles: MultiMesh = _piles.multimesh
	var ids: Array = sim.settlements.ids()
	piles.instance_count = ids.size()
	for i in range(ids.size()):
		var settlement: Dictionary = sim.settlements.entries[ids[i]]
		var height: float = clampf(0.3 + sim.settlements.total(ids[i]) / 40.0, 0.3, 2.0)
		var basis := Basis.from_scale(Vector3(1.0, height, 1.0))
		piles.set_instance_transform(i, Transform3D(basis, Vector3(settlement.pile) + Vector3(0.5, 0.25 * height, 0.5)))
	var items: MultiMesh = _items.multimesh
	var keys: Array = sim.items.keys()
	items.instance_count = keys.size()
	for i in range(keys.size()):
		var item: Dictionary = sim.items[keys[i]]
		items.set_instance_transform(i, Transform3D(Basis(), Vector3(item.cell) + Vector3(0.5, 0.1, 0.5)))
		items.set_instance_color(i, AgentView.RESOURCE_COLORS.get(item.resource, Color.WHITE))
