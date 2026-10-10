extends Node3D
## What the tree's history looks like on the tree: spirit fruit glowing among
## the sacred leaves (one for each that hangs there now) and lightning scars
## streaked down the bark on the side the lightning fell. Rebuilt whenever
## the tree's record changes. Reads the sim only.
const FRUIT_COLOUR := Color(1.0, 0.72, 0.48)
const SCAR_COLOUR := Color(0.12, 0.1, 0.09, 0.85)

var sim: RefCounted
var _fruit_shown: int = -1
var _scars_shown: int = -1
var _fruit_root := Node3D.new()
var _scar_root := Node3D.new()
var _fruit_material := StandardMaterial3D.new()
var _scar_material := StandardMaterial3D.new()


func _ready() -> void:
	_fruit_material.albedo_color = FRUIT_COLOUR
	_fruit_material.emission_enabled = true
	_fruit_material.emission = FRUIT_COLOUR
	_fruit_material.emission_energy_multiplier = 1.4
	_scar_material.albedo_color = SCAR_COLOUR
	_scar_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(_fruit_root)
	add_child(_scar_root)


func _process(_delta: float) -> void:
	if sim == null or sim.tree_growth == null:
		return
	var growth: RefCounted = sim.tree_growth
	if int(growth.fruit) != _fruit_shown:
		_fruit_shown = int(growth.fruit)
		_build_fruit(_fruit_shown)
	if growth.scars.size() != _scars_shown:
		_scars_shown = growth.scars.size()
		_build_scars(growth.scars)
	var pulse: float = 1.2 + sin(Time.get_ticks_msec() / 600.0) * 0.4
	_fruit_material.emission_energy_multiplier = pulse


## Fruit hang just under the crown's rim, spread round it.
func _build_fruit(count: int) -> void:
	for child in _fruit_root.get_children():
		child.queue_free()
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	if tree.x < 0:
		return
	var sphere := SphereMesh.new()
	sphere.radius = 0.28
	sphere.height = 0.5
	for i in range(count):
		var angle: float = float(i) * 2.39996 + 0.6
		var fruit := MeshInstance3D.new()
		fruit.mesh = sphere
		fruit.material_override = _fruit_material
		fruit.position = Vector3(tree.x + 1.0 + cos(angle) * 4.2, tree.y + 6.4 + float(i % 2) * 0.5, tree.z + 1.0 + sin(angle) * 4.2)
		_fruit_root.add_child(fruit)


## A dark jagged streak on the bark face that looks toward the lightning.
func _build_scars(scars: Array) -> void:
	for child in _scar_root.get_children():
		child.queue_free()
	for scar in scars:
		var cell: Vector3i = scar.cell
		var side: Vector3i = scar.side
		var normal := Vector3(signf(side.x), 0.0, signf(side.z))
		if absf(normal.x) > 0.0 and absf(normal.z) > 0.0:
			normal.z = 0.0
		var quad := QuadMesh.new()
		quad.size = Vector2(0.22, 1.6)
		var streak := MeshInstance3D.new()
		streak.mesh = quad
		streak.material_override = _scar_material
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var center := Vector3(cell) + Vector3(0.5, 0.5, 0.5) + normal * 0.505
		_scar_root.add_child(streak)
		streak.look_at_from_position(center, center - normal, Vector3.UP)
		streak.rotate_object_local(Vector3.FORWARD, 0.18 * (1.0 if int(scar.tick) % 2 == 0 else -1.0))
