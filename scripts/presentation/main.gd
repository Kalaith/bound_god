extends Node3D
## The valley scene. M0: an empty lit 3D scene that proves the renderer and
## the capture path work.
const EnvironmentRig = preload("res://scripts/presentation/environment_rig.gd")
const Capture = preload("res://scripts/presentation/capture.gd")
const Session = preload("res://scripts/presentation/session.gd")

var rig: Node3D
var camera := Camera3D.new()


func _ready() -> void:
	rig = EnvironmentRig.new()
	add_child(rig)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(64, 64)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("5d8a4a")
	ground.material_override = material
	add_child(ground)
	camera.position = Vector3(0, 6, 14)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	add_child(camera)
	var request: Dictionary = Capture.request()
	if not request.is_empty():
		var shot: Node = Capture.new()
		shot.configure(request)
		add_child(shot)
		shot.shoot_after()
