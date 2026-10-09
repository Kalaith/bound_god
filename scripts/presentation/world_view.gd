extends Node3D
## Chunk meshes and collision for the voxel grid. The first build meshes every
## chunk on WorkerThreadPool tasks; afterwards dirty chunks re-mesh on the main
## thread, at most `per_frame` a frame, so block edits show within a frame.
const Mesher = preload("res://scripts/world/chunk_mesher.gd")

const WORLD_LAYER: int = 2

var world: RefCounted
var per_frame: int = 4
var chunk_nodes: Dictionary = {}
var _queue: Array = []
var _queued: Dictionary = {}
var _results: Dictionary = {}
var _mutex := Mutex.new()
var _materials: Array = []


func _ready() -> void:
	var atlas: Texture2D = load("res://assets/blocks_atlas.png")
	var opaque := StandardMaterial3D.new()
	opaque.albedo_texture = atlas
	opaque.vertex_color_use_as_albedo = true
	opaque.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	opaque.roughness = 1.0
	var cutout: StandardMaterial3D = opaque.duplicate()
	cutout.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	cutout.alpha_scissor_threshold = 0.3
	cutout.cull_mode = BaseMaterial3D.CULL_DISABLED
	var water: StandardMaterial3D = opaque.duplicate()
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.albedo_color = Color(1, 1, 1, 0.72)
	water.roughness = 0.15
	water.metallic_specular = 0.8
	water.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials = [opaque, cutout, water]


## Mesh every chunk using worker threads; blocks until done.
func build_all(target: RefCounted) -> void:
	world = target
	Mesher.prepare()
	var all: Array = []
	for cy in range(world.chunks.y):
		for cz in range(world.chunks.z):
			for cx in range(world.chunks.x):
				all.append(Vector3i(cx, cy, cz))
	_results.clear()
	var task: int = WorkerThreadPool.add_group_task(func(index: int) -> void:
		var data: Dictionary = Mesher.build(world, all[index])
		_mutex.lock()
		_results[all[index]] = data
		_mutex.unlock(), all.size(), -1, true, "chunk meshing")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for chunk in all:
		_apply(chunk, _results[chunk])
	_results.clear()
	world.take_dirty_chunks()


func _process(_delta: float) -> void:
	if world == null:
		return
	for chunk in world.take_dirty_chunks():
		if not _queued.has(chunk):
			_queued[chunk] = true
			_queue.append(chunk)
	var count: int = 0
	while not _queue.is_empty() and count < per_frame:
		var chunk: Vector3i = _queue.pop_front()
		_queued.erase(chunk)
		_apply(chunk, Mesher.build(world, chunk))
		count += 1


## Re-mesh right now (used after the player's own edits so they feel instant).
func remesh_now() -> void:
	for chunk in world.take_dirty_chunks():
		_queued.erase(chunk)
		_queue.erase(chunk)
		_apply(chunk, Mesher.build(world, chunk))


func _apply(chunk: Vector3i, data: Dictionary) -> void:
	var holder: Node3D = chunk_nodes.get(chunk)
	if holder == null:
		holder = Node3D.new()
		holder.name = "Chunk_%d_%d_%d" % [chunk.x, chunk.y, chunk.z]
		add_child(holder)
		chunk_nodes[chunk] = holder
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	var mesh := ArrayMesh.new()
	var surfaces: Array = data.surfaces
	for index in range(surfaces.size()):
		var surface: Dictionary = surfaces[index]
		if surface.indices.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface.verts
		arrays[Mesh.ARRAY_NORMAL] = surface.normals
		arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
		arrays[Mesh.ARRAY_COLOR] = surface.colors
		arrays[Mesh.ARRAY_INDEX] = surface.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _materials[index])
	if mesh.get_surface_count() > 0:
		var view := MeshInstance3D.new()
		view.mesh = mesh
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(view)
	var faces: PackedVector3Array = data.collision
	if not faces.is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var owner_shape := CollisionShape3D.new()
		owner_shape.shape = shape
		body.add_child(owner_shape)
		holder.add_child(body)
