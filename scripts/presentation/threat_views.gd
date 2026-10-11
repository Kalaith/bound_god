extends Node3D
## Wolves and raiders drawn from simple shapes: a low grey body and head for
## a wolf, a dark hooded figure for a raider. Positions follow the sim.

var sim: RefCounted
var driver: Node
var views: Dictionary = {}
var _wolf_material := StandardMaterial3D.new()
var _raider_material := StandardMaterial3D.new()
var _hood_material := StandardMaterial3D.new()


func _ready() -> void:
	_wolf_material.albedo_color = Color("6f7378")
	_raider_material.albedo_color = Color("5a2a2a")
	_hood_material.albedo_color = Color("2b2324")


func _make(kind: String) -> Node3D:
	var root := Node3D.new()
	if kind == "wolf":
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 0.45, 1.0)
		body.mesh = box
		body.position.y = 0.45
		body.material_override = _wolf_material
		root.add_child(body)
		var head := MeshInstance3D.new()
		var skull := BoxMesh.new()
		skull.size = Vector3(0.32, 0.32, 0.4)
		head.mesh = skull
		head.position = Vector3(0, 0.72, 0.6)
		head.material_override = _wolf_material
		root.add_child(head)
	else:
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = 1.2
		body.mesh = capsule
		body.position.y = 0.6
		body.material_override = _raider_material
		root.add_child(body)
		var hood := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 0.26
		cone.height = 0.5
		hood.mesh = cone
		hood.position.y = 1.45
		hood.material_override = _hood_material
		root.add_child(hood)
	return root


func _process(_delta: float) -> void:
	if sim == null or sim.threats == null:
		return
	var alpha: float = driver.alpha if driver != null else 1.0
	var seen: Dictionary = {}
	for id in sim.threats.ids():
		var entry: Dictionary = sim.threats.entries[id]
		# An outlaw is drawn as the person they are (agent views), not as their stand-in.
		if entry.has("agent"):
			continue
		seen[id] = true
		var view: Node3D = views.get(id)
		if view == null:
			view = _make(str(entry.kind))
			add_child(view)
			views[id] = view
		var target: Vector3 = entry.previous_position.lerp(entry.position, alpha)
		var motion: Vector3 = target - view.position
		view.position = target
		if Vector2(motion.x, motion.z).length() > 0.002:
			view.rotation.y = atan2(motion.x, motion.z)
	for id in views.keys():
		if not seen.has(id):
			views[id].queue_free()
			views.erase(id)
