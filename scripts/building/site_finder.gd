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
## `enough` > 0 stops the spiral once that many candidates are found (the
## nearest rings hold the best of them; used where time matters more).
static func find(sim: RefCounted, template: RefCounted, settlement: Dictionary, enough: int = 0) -> Dictionary:
	var center: Vector3i = settlement.center
	var radius: int = mini(Balance.integer("construction.site_search_radius"), int(settlement.radius))
	# Columns other buildings or sites already hold, and ground heights, are
	# gathered once: per-candidate scans made this the slowest thing in the sim.
	var blocked: Dictionary = {}
	for entry in sim.structures.built():
		for cell in entry.cells:
			blocked[Vector2i(cell.x, cell.z)] = true
	for cell in sim.construction.reserved:
		blocked[Vector2i(cell.x, cell.z)] = true
	var context: Dictionary = {"blocked": blocked, "tops": {}, "footprints": {}}
	var candidates: Array = []
	for offset in _spiral(radius):
		if enough > 0 and candidates.size() >= enough:
			break
		for rotation in range(4):
			var scored: Dictionary = _score(sim, template, Vector2i(center.x, center.z) + offset, rotation, settlement, context)
			if not scored.is_empty():
				candidates.append(scored)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.score != b.score:
			return a.score < b.score
		if a.origin != b.origin:
			return sim.voxels.index_of(a.origin) < sim.voxels.index_of(b.origin)
		return a.rotation < b.rotation)
	var camp: Vector3i = settlement.camp
	for i in range(mini(candidates.size(), 4)):
		var choice: Dictionary = candidates[i]
		var door_out: Vector3i = sim.nav.nearest_walkable(choice.outside, 1)
		if door_out.x >= 0 and (door_out == camp or not sim.nav.find_path(door_out, camp).is_empty()):
			choice["order"] = _order(sim, template, choice)
			return choice
	return {}


static func _top(world: RefCounted, context: Dictionary, x: int, z: int) -> int:
	var key := Vector2i(x, z)
	if not context.tops.has(key):
		context.tops[key] = _ground(world, x, z)
	return context.tops[key]


## Whether a footprint of `size` at `corner` is buildable, shared by the
## rotations with the same footprint: {} when it is not, else
## {origin, tops, low, high}.
static func _footprint(sim: RefCounted, corner: Vector2i, size: Vector3i, settlement: Dictionary, context: Dictionary) -> Dictionary:
	var key := Vector4i(corner.x, corner.y, size.x, size.z)
	if context.footprints.has(key):
		return context.footprints[key]
	var result: Dictionary = {}
	context.footprints[key] = result
	var world: RefCounted = sim.voxels
	var spacing: int = Balance.integer("construction.site_spacing")
	var tree: Vector3i = sim.features.sacred_tree
	var low: int = 999
	var high: int = -1
	var tops: Dictionary = {}
	for z in range(corner.y, corner.y + size.z):
		for x in range(corner.x, corner.x + size.x):
			if x < 2 or z < 2 or x >= world.size.x - 2 or z >= world.size.z - 2:
				return result
			if Vector2(x - settlement.center.x, z - settlement.center.z).length() > float(settlement.radius):
				return result
			if Vector2(x - tree.x, z - tree.z).length() < 6.0:
				return result
			var top: int = _top(world, context, x, z)
			if top < 0:
				return result
			tops[Vector2i(x, z)] = top
			low = mini(low, top)
			high = maxi(high, top)
	if high - low > Balance.integer("construction.max_height_variation"):
		return result
	var origin := Vector3i(corner.x, high + 1, corner.y)
	if origin.y + size.y >= world.size.y - 1:
		return result
	for z in range(corner.y - spacing, corner.y + size.z + spacing):
		for x in range(corner.x - spacing, corner.x + size.x + spacing):
			if context.blocked.has(Vector2i(x, z)):
				return result
	var grass: int = Registry.id("tall_grass")
	for column in tops:
		for y in range(origin.y, origin.y + size.y):
			var block: int = world.get_xyz(column.x, y, column.y)
			if block != 0 and block != grass:
				return result
	result.merge({"origin": origin, "tops": tops, "low": low, "high": high})
	return result


static func _score(sim: RefCounted, template: RefCounted, corner: Vector2i, rotation: int, settlement: Dictionary, context: Dictionary) -> Dictionary:
	var size: Vector3i = template.rotated_size(rotation)
	var footprint: Dictionary = _footprint(sim, corner, size, settlement, context)
	if footprint.is_empty():
		return {}
	var origin: Vector3i = footprint.origin
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
	var out_distance: float = Vector2(outside.x - settlement.center.x, outside.z - settlement.center.z).length()
	var door_distance: float = Vector2(origin.x + door.x - settlement.center.x, origin.z + door.z - settlement.center.z).length()
	var distance: float = Vector2(corner.x - settlement.center.x, corner.y - settlement.center.z).length()
	var score: float = float(footprint.high - footprint.low) * 3.0 + distance * 0.25 + (out_distance - door_distance) * 2.0
	return {"origin": origin, "rotation": rotation, "score": score, "outside": outside, "tops": footprint.tops}


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
