extends RefCounted
## The turned shapes people and the avatar are built from, made once and
## shared: each is a profile (radius, height) spun round the vertical axis and
## squashed front to back, so a robe has a hem, a waist and shoulders rather
## than being a capsule. A repeated profile point makes a crisp fold.

const SEGMENTS: int = 12
static var _cache: Dictionary = {}


static func get_mesh(key: String) -> Mesh:
	if _cache.is_empty():
		_build()
	return _cache[key]


static func _build() -> void:
	# Villager jacket over the hips: hem, waist, chest, sloping shoulders.
	_cache["jacket"] = lathe([Vector2(0, -0.3), Vector2(0.25, -0.3), Vector2(0.25, -0.3), Vector2(0.23, -0.12),
		Vector2(0.2, 0.06), Vector2(0.21, 0.24), Vector2(0.225, 0.37), Vector2(0.2, 0.46), Vector2(0.13, 0.51),
		Vector2(0.06, 0.53), Vector2(0, 0.535)], 0.74)
	# The avatar's robe falls to the ground and flares like a bell.
	_cache["robe"] = lathe([Vector2(0, -0.62), Vector2(0.33, -0.62), Vector2(0.33, -0.62), Vector2(0.27, -0.4),
		Vector2(0.21, -0.1), Vector2(0.19, 0.06), Vector2(0.205, 0.24), Vector2(0.22, 0.37), Vector2(0.2, 0.46),
		Vector2(0.13, 0.51), Vector2(0.06, 0.53), Vector2(0, 0.535)], 0.78)
	_cache["hem"] = band(0.254, -0.305, -0.25, 0.74)
	_cache["robe_hem"] = band(0.335, -0.625, -0.56, 0.78)
	_cache["cuff"] = band(0.104, -0.345, -0.3, 0.9)
	_cache["wide_cuff"] = band(0.154, -0.375, -0.33, 0.8)
	_cache["sash"] = band(0.214, 0.0, 0.11, 0.74)
	_cache["robe_sash"] = band(0.204, 0.0, 0.12, 0.78)
	_cache["collar"] = band(0.085, 0.0, 0.05, 0.9)
	# Trouser leg from the hip joint down to the ankle.
	_cache["leg"] = lathe([Vector2(0, 0.02), Vector2(0.085, 0.02), Vector2(0.09, -0.16), Vector2(0.072, -0.42),
		Vector2(0.062, -0.58), Vector2(0, -0.6)], 1.0)
	# A kimono sleeve widening to its cuff; the hand peeks out below.
	_cache["sleeve"] = lathe([Vector2(0, 0.04), Vector2(0.07, 0.04), Vector2(0.085, -0.14), Vector2(0.1, -0.34),
		Vector2(0.1, -0.34), Vector2(0, -0.35)], 0.9)
	_cache["wide_sleeve"] = lathe([Vector2(0, 0.04), Vector2(0.075, 0.04), Vector2(0.1, -0.14), Vector2(0.15, -0.36),
		Vector2(0.15, -0.36), Vector2(0, -0.37)], 0.8)
	# Hair cap: the top and back of the head, open at the face.
	var cap: Array = []
	for step in range(8):
		var angle: float = lerpf(-0.25, PI * 0.5, float(step) / 7.0)
		cap.append(Vector2(cos(angle) * 0.178, sin(angle) * 0.178))
	cap.insert(0, Vector2(0, cap[0].y))
	_cache["hair_cap"] = lathe(cap, 1.0)
	# Long hair down the avatar's back.
	_cache["hair_fall"] = lathe([Vector2(0, 0.05), Vector2(0.1, 0.0), Vector2(0.12, -0.2), Vector2(0.09, -0.42),
		Vector2(0.03, -0.5), Vector2(0, -0.5)], 0.45)
	# Straw kasa: a shallow cone with a crisp brim.
	_cache["kasa"] = lathe([Vector2(0, -0.02), Vector2(0.32, -0.02), Vector2(0.32, -0.02), Vector2(0.32, 0.0),
		Vector2(0.32, 0.0), Vector2(0.03, 0.15), Vector2(0, 0.155)], 1.0)
	_cache["headband"] = band(0.18, 0.0, 0.04, 1.0)
	_cache["head"] = sphere(0.165, 10, 1.0)
	_cache["bun"] = sphere(0.06, 6, 1.0)
	_cache["hand"] = sphere(0.048, 6, 1.0)
	_cache["foot"] = sphere(0.07, 6, 1.0)
	_cache["eye"] = sphere(0.017, 4, 1.0)
	_cache["cargo"] = box(Vector3(0.24, 0.22, 0.2))
	var halo := TorusMesh.new()
	halo.inner_radius = 0.245
	halo.outer_radius = 0.265
	halo.rings = 24
	halo.ring_segments = 6
	_cache["halo"] = halo


## A short open-topped tube shown as a solid ring: sashes, collars, bands.
static func band(radius: float, bottom: float, top: float, depth: float) -> ArrayMesh:
	return lathe([Vector2(0, bottom), Vector2(radius, bottom), Vector2(radius, bottom), Vector2(radius, top),
		Vector2(radius, top), Vector2(0, top)], depth)


static func sphere(radius: float, rings: int, depth: float) -> ArrayMesh:
	var profile: Array = []
	for step in range(rings + 1):
		var angle: float = lerpf(-PI * 0.5, PI * 0.5, float(step) / float(rings))
		profile.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	profile[0].x = 0.0
	profile[rings].x = 0.0
	return lathe(profile, depth)


static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Spin a profile of (radius, height) points round Y. `depth` squashes Z.
static func lathe(points: Array, depth: float) -> ArrayMesh:
	var count: int = points.size()
	var normals2: Array[Vector2] = []
	for index in range(count):
		var sum := Vector2.ZERO
		if index > 0:
			sum += _segment_normal(points[index - 1], points[index])
		if index < count - 1:
			sum += _segment_normal(points[index], points[index + 1])
		normals2.append(sum.normalized() if sum.length() > 0.0001 else Vector2(0, 1))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for index in range(count):
		for segment in range(SEGMENTS + 1):
			var angle: float = TAU * float(segment) / float(SEGMENTS)
			var direction := Vector2(sin(angle), cos(angle))
			var point: Vector2 = points[index]
			var normal: Vector2 = normals2[index]
			vertices.append(Vector3(direction.x * point.x, point.y, direction.y * point.x * depth))
			normals.append(Vector3(direction.x * normal.x, normal.y, direction.y * normal.x / depth).normalized())
	var stride: int = SEGMENTS + 1
	for index in range(count - 1):
		for segment in range(SEGMENTS):
			var a: int = index * stride + segment
			var b: int = a + stride
			indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Outward normal of one profile segment; a zero-length segment adds nothing.
static func _segment_normal(from: Vector2, to: Vector2) -> Vector2:
	var along: Vector2 = to - from
	if along.length() < 0.00001:
		return Vector2.ZERO
	return Vector2(along.y, -along.x).normalized()
