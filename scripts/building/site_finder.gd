extends RefCounted
## Where a settlement could raise a copy of a design: candidate origins on a
## spiral from the centre (a fixed order), every rotation, scored by
## flatness, distance to the centre and an entrance facing home. Rejects
## overlaps, uneven ground (more than one block), water and cells other
## sites or buildings hold, and requires a path from the door to the stores.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

const SIDES: Array[Vector3i] = [Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]


static func _spiral(radius: int) -> Array:
	var result: Array = [Vector2i.ZERO]
	for ring in range(2, radius + 1, 2):
		for i in range(-ring, ring, 2):
			result.append(Vector2i(i, -ring))
			result.append(Vector2i(ring, i))
			result.append(Vector2i(-i, ring))
			result.append(Vector2i(-ring, -i))
	return result


## {origin, rotation, order} for the best site, or {} when there is none.
static func find(sim: RefCounted, template: RefCounted, settlement: Dictionary) -> Dictionary:
	var center: Vector3i = settlement.center
	var radius: int = mini(Balance.integer("construction.site_search_radius"), int(settlement.radius))
	var candidates: Array = []
	var built: Dictionary = {}
	for entry in sim.structures.built():
		built.merge(entry.cells)
	for offset in _spiral(radius):
		for rotation in range(4):
			var scored: Dictionary = _score(sim, template, Vector2i(center.x, center.z) + offset, rotation, settlement, built)
			if not scored.is_empty():
				candidates.append(scored)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.score != b.score:
			return a.score < b.score
		if a.origin != b.origin:
			return sim.voxels.index_of(a.origin) < sim.voxels.index_of(b.origin)
		return a.rotation < b.rotation)
	var pile: Vector3i = settlement.pile
	for i in range(mini(candidates.size(), 4)):
		var choice: Dictionary = candidates[i]
		var door_out: Vector3i = sim.nav.nearest_walkable(choice.outside, 1)
		if door_out.x >= 0 and (door_out == pile or not sim.nav.find_path(door_out, pile).is_empty()):
			choice["order"] = _order(sim, template, choice)
			return choice
	return {}


static func _score(sim: RefCounted, template: RefCounted, corner: Vector2i, rotation: int, settlement: Dictionary, built: Dictionary) -> Dictionary:
	var size: Vector3i = template.rotated_size(rotation)
	var world: RefCounted = sim.voxels
	var low: int = 999
	var high: int = -1
	var tops: Dictionary = {}
	var spacing: int = Balance.integer("construction.site_spacing")
	var tree: Vector3i = sim.features.sacred_tree
	for z in range(corner.y, corner.y + size.z):
		for x in range(corner.x, corner.x + size.x):
			if x < 2 or z < 2 or x >= world.size.x - 2 or z >= world.size.z - 2:
				return {}
			if Vector2(x - settlement.center.x, z - settlement.center.z).length() > float(settlement.radius):
				return {}
			if Vector2(x - tree.x, z - tree.z).length() < 6.0:
				return {}
			var top: int = _ground(world, x, z)
			if top < 0:
				return {}
			tops[Vector2i(x, z)] = top
			low = mini(low, top)
			high = maxi(high, top)
	if high - low > Balance.integer("construction.max_height_variation"):
		return {}
	var origin := Vector3i(corner.x, high + 1, corner.y)
	if origin.y + size.y >= world.size.y - 1:
		return {}
	for z in range(corner.y - spacing, corner.y + size.z + spacing):
		for x in range(corner.x - spacing, corner.x + size.x + spacing):
			var inner: bool = x >= corner.x and x < corner.x + size.x and z >= corner.y and z < corner.y + size.z
			for y in range(origin.y - 1, origin.y + (size.y if inner else 2)):
				var cell := Vector3i(x, y, z)
				if sim.construction.is_reserved(cell) or built.has(cell):
					return {}
				if inner and y >= origin.y:
					var block: int = world.get_block(cell)
					if block != 0 and block != Registry.id("tall_grass"):
						return {}
	# The door must open onto the outside, onto ground a person can walk on.
	var door: Vector3i = template.rotate_local(template.entrance, rotation)
	var outside: Vector3i = Vector3i(-1, -1, -1)
	for side in SIDES:
		var probe: Vector3i = door + side
		if probe.x < 0 or probe.z < 0 or probe.x >= size.x or probe.z >= size.z:
			outside = origin + probe
			break
	if outside.x < 0:
		return {}
	var facing: float = Vector2(outside.x - settlement.center.x, outside.z - settlement.center.z).length() \
		- Vector2(origin.x + door.x - settlement.center.x, origin.z + door.z - settlement.center.z).length()
	var distance: float = Vector2(corner.x - settlement.center.x, corner.y - settlement.center.z).length()
	var score: float = float(high - low) * 3.0 + distance * 0.25 + facing * 2.0
	return {"origin": origin, "rotation": rotation, "score": score, "outside": outside, "tops": tops}


## The surface height of a column if it is buildable ground, or -1.
static func _ground(world: RefCounted, x: int, z: int) -> int:
	var top: int = world.top_solid_y(x, z)
	if top < 0:
		return -1
	var block: int = world.get_block(Vector3i(x, top, z))
	if Registry.opaque[block] == 0 or Registry.component(block) != "" or block == Registry.id("log"):
		return -1
	if world.get_block(Vector3i(x, top + 1, z)) == Registry.id("water"):
		return -1
	return top


## Foundation first, then clearing, then the design bottom-up.
static func _order(sim: RefCounted, template: RefCounted, choice: Dictionary) -> Array:
	var order: Array = []
	var origin: Vector3i = choice.origin
	var cobble: int = Registry.id("cobble")
	var keys: Array = choice.tops.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	for column in keys:
		for y in range(int(choice.tops[column]) + 1, origin.y):
			order.append([Vector3i(column.x, y, column.y), cobble, 0])
	var size: Vector3i = template.rotated_size(choice.rotation)
	var grass: int = Registry.id("tall_grass")
	for y in range(origin.y, origin.y + size.y):
		for column in keys:
			var cell := Vector3i(column.x, y, column.y)
			if sim.voxels.get_block(cell) == grass:
				order.append([cell, 0, 0])
	for entry in template.placement(choice.rotation):
		order.append([origin + entry[0], entry[1], entry[2]])
	return order
