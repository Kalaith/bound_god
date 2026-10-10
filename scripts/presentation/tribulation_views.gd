extends Node3D
## Heaven's trials made visible: an ink-dark cloud gathering over a
## cultivator who has called Heaven (pale while it waits, heavy in the
## storm), jagged lightning with a flash of light where it falls, and a toast
## when a storm breaks. When someone the god has pinned faces Heaven, time
## drops back to normal speed so the god can watch. Reads the sim only.
const Text = preload("res://scripts/core/text.gd")

const CLOUD_HEIGHT: float = 11.0
const BOLT_COLOUR := Color(0.92, 1.0, 0.96)

var sim: RefCounted
var driver: Node
var hud: Control
## trial id -> cloud node
var _clouds: Dictionary = {}
var _cloud_material := StandardMaterial3D.new()
var _bolt_material := StandardMaterial3D.new()


func _ready() -> void:
	_cloud_material.albedo_color = Color(0.2, 0.21, 0.25, 0.75)
	_cloud_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cloud_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cloud_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bolt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_material.albedo_color = BOLT_COLOUR
	_bolt_material.vertex_color_use_as_albedo = true
	_bolt_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _process(delta: float) -> void:
	if sim == null or sim.tribulations == null:
		return
	for event in sim.tribulations.take_events():
		match str(event.kind):
			"strike":
				_bolt(Vector3(event.cell) + Vector3(0.5, 0.0, 0.5), int(event.trial))
			"storm":
				_storm_began(int(event.trial))
	var live: Dictionary = {}
	for id in sim.tribulations.entries:
		var trial: Dictionary = sim.tribulations.entries[id]
		if trial.state == "done":
			continue
		live[id] = true
		var agent: RefCounted = sim.agents[int(trial.agent)]
		var cloud: Node3D = _clouds.get(id)
		if cloud == null:
			cloud = _make_cloud(int(id))
			_clouds[id] = cloud
			add_child(cloud)
		var storm: bool = trial.state == "storm"
		var target := Vector3(agent.position.x, agent.position.y + CLOUD_HEIGHT, agent.position.z)
		cloud.position = cloud.position.lerp(target, minf(delta * 2.0, 1.0)) if cloud.visible else target
		cloud.visible = true
		var size: float = 1.6 if storm else 0.8
		cloud.scale = cloud.scale.lerp(Vector3.ONE * size, minf(delta * 0.8, 1.0))
		cloud.rotation.y += delta * (0.4 if storm else 0.1)
	for id in _clouds.keys():
		if not live.has(id):
			var cloud: Node3D = _clouds[id]
			var tween: Tween = create_tween()
			tween.tween_property(cloud, "scale", Vector3.ONE * 0.05, 1.5)
			tween.tween_callback(cloud.queue_free)
			_clouds.erase(id)


## A heap of soft dark puffs, like ink dropped in water.
func _make_cloud(id: int) -> Node3D:
	var root := Node3D.new()
	root.visible = false
	root.scale = Vector3.ONE * 0.3
	var puffs: int = 7
	for i in range(puffs):
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var radius: float = 1.4 + fposmod(float(id * 13 + i * 7) * 0.37, 1.0) * 1.3
		sphere.radius = radius
		sphere.height = radius * 1.1
		puff.mesh = sphere
		puff.material_override = _cloud_material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle: float = float(i) * TAU / puffs + float(id)
		puff.position = Vector3(cos(angle) * 2.2, fposmod(float(i) * 0.61, 1.0) * 0.8, sin(angle) * 2.2) if i > 0 else Vector3.ZERO
		root.add_child(puff)
	return root


## A jagged bolt from the cloud to where it falls, a white flash, then gone.
func _bolt(ground: Vector3, trial_id: int) -> void:
	var cloud: Node3D = _clouds.get(trial_id)
	var top: Vector3 = cloud.position if cloud != null else ground + Vector3(0, CLOUD_HEIGHT, 0)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3] = [top]
	var segments: int = 9
	for i in range(1, segments):
		var t: float = float(i) / segments
		var jitter := Vector3(sin(t * 37.0 + ground.x) * 0.9, 0.0, cos(t * 29.0 + ground.z) * 0.9) * (1.0 - t * 0.6)
		points.append(top.lerp(ground, t) + jitter)
	points.append(ground)
	# Two crossed ribbons, so the bolt reads from any side.
	for side in [Vector3(0.18, 0, 0), Vector3(0, 0, 0.18)]:
		for i in range(points.size() - 1):
			var a: Vector3 = points[i]
			var b: Vector3 = points[i + 1]
			for corner in [a - side, a + side, b + side, a - side, b + side, b - side]:
				mesh.surface_set_color(BOLT_COLOUR)
				mesh.surface_add_vertex(corner)
	mesh.surface_end()
	var bolt := MeshInstance3D.new()
	bolt.mesh = mesh
	bolt.material_override = _bolt_material.duplicate()
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bolt)
	var flash := OmniLight3D.new()
	flash.light_color = BOLT_COLOUR
	flash.light_energy = 6.0
	flash.omni_range = 14.0
	flash.position = ground + Vector3(0, 1.5, 0)
	add_child(flash)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(bolt.material_override, "albedo_color:a", 0.0, 0.35)
	tween.tween_property(flash, "light_energy", 0.0, 0.4)
	tween.chain().tween_callback(func() -> void:
		bolt.queue_free()
		flash.queue_free())


func _storm_began(trial_id: int) -> void:
	var trial: Dictionary = sim.tribulations.entries.get(trial_id, {})
	if trial.is_empty():
		return
	var agent: RefCounted = sim.agents[int(trial.agent)]
	if hud != null:
		hud.flash(Text.format("toast_trial", {"name": agent.full_name()}))
	if driver != null and sim.god.followed.has(agent.id) and driver.speed_index > 1:
		driver.set_speed(1)
