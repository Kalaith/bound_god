extends RefCounted
## Deterministic valley generation from the world seed. Writes blocks into a
## VoxelWorld and returns resource sites and fixed features; draws randomness
## only from the RandomNumberGenerator it is given.
const Balance = preload("res://scripts/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Template = preload("res://scripts/building/template.gd")

var world: RefCounted
var rng: RandomNumberGenerator
var heights := PackedInt32Array()
var sites: Array = []
var features: Dictionary = {}
## Columns kept clear of vegetation: Vector2i -> true.
var reserved: Dictionary = {}
var _height_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _forest_noise := FastNoiseLite.new()
var _rock_noise := FastNoiseLite.new()
var _b: Dictionary = {}


func _init(target: RefCounted, random: RandomNumberGenerator) -> void:
	world = target
	rng = random
	# A copy: a region overrides terrain numbers for its own world only.
	_b = Balance.dict("world").duplicate(true)


func _id(name: String) -> int:
	return Registry.id(name)


func _site(kind: String, cells: Array, amount: int) -> void:
	sites.append({"id": sites.size() + 1, "kind": kind, "cells": cells, "amount": amount})


func _top(x: int, z: int) -> int:
	return heights[x + z * world.size.x]


## The full prototype valley.
func valley() -> Dictionary:
	_height_noise.seed = rng.randi()
	_height_noise.frequency = 0.018
	_detail_noise.seed = rng.randi()
	_detail_noise.frequency = 0.07
	_forest_noise.seed = rng.randi()
	_forest_noise.frequency = 0.035
	_rock_noise.seed = rng.randi()
	_rock_noise.frequency = 0.12
	_heights()
	_flatten_features()
	_columns()
	_sacred_tree()
	_ruin()
	_hamlet()
	_vegetation()
	_founding_grounds()
	return {"sites": sites, "features": features}


## A neighbouring region's world from its archetype (M22).
func region(archetype: Dictionary) -> Dictionary:
	return load("res://scripts/world/world_gen_region.gd").generate(self, archetype)


## A flat test field for headless scenarios: grass at `ground` over dirt.
func flat(ground: int) -> Dictionary:
	heights.resize(world.size.x * world.size.z)
	for z in range(world.size.z):
		for x in range(world.size.x):
			heights[x + z * world.size.x] = ground
			world.fill(Vector3i(x, 0, z), _id("bedrock"))
			for y in range(1, ground - 1):
				world.fill(Vector3i(x, y, z), _id("stone"))
			world.fill(Vector3i(x, ground - 1, z), _id("dirt"))
			world.fill(Vector3i(x, ground, z), _id("grass"))
	features = {"sacred_tree": Vector3i(world.size.x / 2, ground + 1, world.size.z / 2), "grounds": []}
	return {"sites": sites, "features": features}


func _heights() -> void:
	var size: Vector3i = world.size
	heights.resize(size.x * size.z)
	var base: float = float(_b.base_height)
	var rim_width: float = float(_b.rim_width)
	var water: int = int(_b.water_level)
	for z in range(size.z):
		for x in range(size.x):
			var h: float = base + _height_noise.get_noise_2d(x, z) * 3.2 + _detail_noise.get_noise_2d(x, z) * 0.9
			var edge: float = float(mini(mini(x, z), mini(size.x - 1 - x, size.z - 1 - z)))
			if edge < rim_width:
				h += pow((rim_width - edge) / rim_width, 1.7) * float(_b.rim_height)
			var along: float = (x + z) * 0.5
			h += smoothstep(float(_b.ridge_start), float(_b.ridge_full), along) * float(_b.ridge_height)
			# The river runs beside the valley's long axis, never between tree and ridge.
			var bend: float = sin(along * 0.06) * 9.0
			var across: float = absf(x - z - float(_b.river_offset) + bend) / sqrt(2.0)
			var half: float = float(_b.river_half_width)
			if edge > 3.0:
				if across < half:
					h = float(water - 2)
				elif across < half + 4.0:
					h = lerpf(float(water - 1), h, (across - half) / 4.0)
			heights[x + z * size.x] = clampi(roundi(h), 2, size.y - 6)


func _flatten(center: Vector2i, radius: int, height: int, blend: int = 4) -> void:
	for z in range(center.y - radius - blend, center.y + radius + blend + 1):
		for x in range(center.x - radius - blend, center.x + radius + blend + 1):
			if x < 0 or z < 0 or x >= world.size.x or z >= world.size.z:
				continue
			var distance: float = Vector2(x - center.x, z - center.y).length()
			var index: int = x + z * world.size.x
			if distance <= radius:
				heights[index] = height
			elif distance <= radius + blend:
				var t: float = (distance - radius) / float(blend)
				heights[index] = roundi(lerpf(float(height), float(heights[index]), t))


func _flatten_features() -> void:
	var tree := Vector2i(int(_b.sacred_tree[0]), int(_b.sacred_tree[1]))
	var water: int = int(_b.water_level)
	_flatten(tree, int(_b.meadow_radius), maxi(_top(tree.x, tree.y), water + 2), 6)
	var ruin := Vector2i(int(_b.ridge_ruin[0]), int(_b.ridge_ruin[1]))
	_flatten(ruin, 4, _top(ruin.x, ruin.y), 3)
	var hamlet := Vector2i(int(_b.ridge_hamlet[0]), int(_b.ridge_hamlet[1]))
	_flatten(hamlet, 9, _top(hamlet.x, hamlet.y), 4)


func _columns() -> void:
	var size: Vector3i = world.size
	var water: int = int(_b.water_level)
	var ridge_from: float = float(_b.ridge_start)
	var ids: Dictionary = {}
	for name in ["bedrock", "stone", "dirt", "grass", "sand", "gravel", "ore", "water"]:
		ids[name] = _id(name)
	var stride_y: int = world.stride_y
	for z in range(size.z):
		for x in range(size.x):
			var top: int = _top(x, z)
			var along: float = (x + z) * 0.5
			var rocky: float = _rock_noise.get_noise_2d(x, z)
			var surface: int = ids.grass
			var under: int = ids.dirt
			if top <= water:
				surface = ids.sand
				under = ids.sand
			elif top >= 30:
				surface = ids.stone
				under = ids.stone
			elif along > ridge_from + 8.0 and rocky > 0.35:
				surface = ids.gravel if rocky < 0.5 else ids.stone
				under = ids.stone
			var index: int = x + z * size.x
			world.blocks[index] = ids.bedrock
			for y in range(1, top + 1):
				var block: int = ids.stone
				if y == top:
					block = surface
				elif y >= top - 3:
					block = under
				elif along > ridge_from + 6.0 and y >= top - 7 and _rock_noise.get_noise_3d(x * 2.0, y * 3.0, z * 2.0) > 0.55:
					block = ids.ore
				world.blocks[index + y * stride_y] = block
			for y in range(top + 1, water + 1):
				world.blocks[index + y * stride_y] = ids.water


func _sacred_tree() -> void:
	var tx: int = int(_b.sacred_tree[0])
	var tz: int = int(_b.sacred_tree[1])
	var top: int = _top(tx, tz)
	var bark: int = _id("sacred_tree")
	var crown: int = _id("sacred_leaves")
	for y in range(top + 1, top + 10):
		for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			world.fill(Vector3i(tx + offset.x, y, tz + offset.y), bark)
	var middle := Vector3(tx + 0.5, top + 11, tz + 0.5)
	for y in range(top + 7, top + 15):
		for z in range(tz - 6, tz + 8):
			for x in range(tx - 6, tx + 8):
				var cell := Vector3i(x, y, z)
				var offset := Vector3(x + 0.5, y + 0.5, z + 0.5) - middle
				offset.y *= 1.5
				if offset.length() < 5.6 + _detail_noise.get_noise_3d(x * 3.0, y * 3.0, z * 3.0) * 0.8 and world.get_block(cell) == 0:
					world.fill(cell, crown)
	# The meadow round the tree stays open; home trees and stone ring its edge.
	var clear: float = float(_b.meadow_radius) + 0.5
	for z in range(tz - 12, tz + 14):
		for x in range(tx - 12, tx + 14):
			if Vector2(x - tx - 0.5, z - tz - 0.5).length() <= clear:
				reserved[Vector2i(x, z)] = true
	features["sacred_tree"] = Vector3i(tx, top + 1, tz)
	features["sacred_tree_cells"] = [Vector3i(tx, top + 1, tz), Vector3i(tx + 1, top + 1, tz), Vector3i(tx, top + 1, tz + 1), Vector3i(tx + 1, top + 1, tz + 1)]


func _stamp(template: RefCounted, origin: Vector3i, rotation: int) -> Array:
	var placed: Array = []
	for entry in template.placement(rotation):
		var cell: Vector3i = origin + entry[0]
		world.fill(cell, entry[1])
		if entry[2] != 0:
			world.meta[world.index_of(cell)] = entry[2]
		placed.append(cell)
	return placed


func _ruin() -> void:
	var template: RefCounted = Template.from_starter(Data.starter("ridge_altar"))
	var center := Vector2i(int(_b.ridge_ruin[0]), int(_b.ridge_ruin[1]))
	var origin := Vector3i(center.x - 2, _top(center.x, center.y) + 1, center.y - 2)
	_stamp(template, origin, 0)
	# The old altar lies broken: rubble where it stood and gaps in the ring.
	var altar := origin + Vector3i(2, 0, 2)
	world.fill(altar, _id("cobble"))
	var ring: Array = []
	for entry in template.placement(0):
		if entry[1] == _id("cut_stone") and entry[0].y == 1:
			ring.append(origin + entry[0])
	for _i in range(2):
		var pick: int = rng.randi_range(0, ring.size() - 1)
		world.fill(ring[pick], 0)
		ring.remove_at(pick)
	for z in range(center.y - 6, center.y + 7):
		for x in range(center.x - 6, center.x + 7):
			reserved[Vector2i(x, z)] = true
	features["ruin"] = {"origin": origin, "template": "ridge_altar", "rotation": 0, "altar": altar}


func _hamlet() -> void:
	var center := Vector2i(int(_b.ridge_hamlet[0]), int(_b.ridge_hamlet[1]))
	var ground: int = _top(center.x, center.y)
	var hut: RefCounted = Template.from_starter(Data.starter("miner_hut"))
	var lean: RefCounted = Template.from_starter(Data.starter("lean_to"))
	# Two huts face the square from the north and west; the lean-to sits east.
	var buildings: Array = [
		[hut, Vector3i(center.x - 2, ground + 1, center.y + 3), 2],
		[hut, Vector3i(center.x - 8, ground + 1, center.y - 2), 3],
		[lean, Vector3i(center.x + 4, ground + 1, center.y - 1), 1],
	]
	var placed: Array = []
	for entry in buildings:
		var template: RefCounted = entry[0]
		var origin: Vector3i = entry[1]
		_stamp(template, origin, entry[2])
		placed.append({"template": template.id, "origin": origin, "rotation": entry[2]})
	# Two storage chests stand on the square, where the miners keep their goods.
	var chests: Array = []
	for offset in [Vector2i(1, -3), Vector2i(2, -3), Vector2i(1, -4), Vector2i(2, -4), Vector2i(-1, -3), Vector2i(0, -4)]:
		if chests.size() >= 2:
			break
		var cell := Vector3i(center.x + offset.x, ground + 1, center.y + offset.y)
		if world.get_block(cell) == 0 and world.get_block(cell + Vector3i.DOWN) != 0:
			world.fill(cell, _id("storage_chest"))
			chests.append(cell)
	for z in range(center.y - 11, center.y + 12):
		for x in range(center.x - 11, center.x + 12):
			reserved[Vector2i(x, z)] = true
	features["hamlet"] = {"center": Vector3i(center.x, ground + 1, center.y), "buildings": placed, "chests": chests}


func _ground_ok(x: int, z: int) -> bool:
	if x < 3 or z < 3 or x >= world.size.x - 3 or z >= world.size.z - 3 or reserved.has(Vector2i(x, z)):
		return false
	var top: int = _top(x, z)
	return world.get_xyz(x, top, z) == _id("grass") and world.get_xyz(x, top + 1, z) == 0 and top < 28


func _vegetation() -> void:
	var tree_center := Vector2(float(_b.sacred_tree[0]), float(_b.sacred_tree[1]))
	var spacing: float = float(_b.tree_spacing)
	var size: Vector3i = world.size
	var steps_x: int = int(size.x / spacing)
	var steps_z: int = int(size.z / spacing)
	for gz in range(steps_z):
		for gx in range(steps_x):
			var x: int = int((gx + rng.randf()) * spacing)
			var z: int = int((gz + rng.randf()) * spacing)
			var woods: bool = _forest_noise.get_noise_2d(x, z) > float(_b.forest_threshold)
			if rng.randf() > (0.85 if woods else 0.1):
				continue
			if Vector2(x, z).distance_to(tree_center) < 18.0 or not _ground_ok(x, z):
				continue
			_tree(x, z)
	# A ring of berry bushes keeps the first travellers fed near the tree.
	for index in range(12):
		var angle: float = index * TAU / 12.0 + rng.randf() * 0.3
		var distance: float = 13.0 + rng.randf() * 5.0
		var at: Vector2 = tree_center + Vector2.from_angle(angle) * distance
		var placed: bool = false
		for attempt in range(6):
			var x: int = int(at.x) + attempt % 3 - 1
			var z: int = int(at.y) + attempt / 3
			if _bush_ok(x, z):
				_bush(x, z)
				placed = true
				break
		if not placed:
			continue
	_home_grove(tree_center)
	# Bushes in the hamlet's hollows: the miners have always picked here.
	var hamlet := Vector2(float(_b.ridge_hamlet[0]), float(_b.ridge_hamlet[1]))
	for index in range(10):
		var at: Vector2 = hamlet + Vector2.from_angle(index * TAU / 10.0 + rng.randf() * 0.4) * (13.0 + rng.randf() * 6.0)
		for attempt in range(6):
			var x: int = int(at.x) + attempt % 3 - 1
			var z: int = int(at.y) + attempt / 3
			if _bush_ok(x, z):
				_bush(x, z)
				break
	_scatter(float(_b.bush_spacing) * 1.3, 0.55, _bush_ok, _bush)
	_scatter(float(_b.grass_spacing), 0.55, _ground_ok, _grass_patch)
	_scatter(float(_b.rock_spacing), 0.6, _ground_ok, _boulder)
	_ore_outcrops()
	_quarries()


## How far from the tree the first wood and stone stand: inside the circle
## the tree always holds, so a new god can gather from the start.
func _home_distance() -> float:
	return rng.randf_range(float(_b.home_reach[0]), float(_b.home_reach[1]))


## A few trees just past the meadow, spread round the tree.
func _home_grove(tree_center: Vector2) -> void:
	var count: int = int(_b.home_trees)
	for index in range(count):
		var base: float = index * TAU / count + rng.randf() * 0.5
		for attempt in range(8):
			var at: Vector2 = tree_center + Vector2.from_angle(base + attempt * 0.3) * _home_distance()
			var x: int = int(at.x)
			var z: int = int(at.y)
			if _ground_ok(x, z) and _clearing(x, z):
				_tree(x, z)
				break


## No log, bush or stone in the 3x3 around the column.
func _clearing(x: int, z: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var top: int = _top(x + dx, z + dz)
			if world.get_xyz(x + dx, top + 1, z + dz) != 0:
				return false
	return true


func _bush_ok(x: int, z: int) -> bool:
	if x < 3 or z < 3 or x >= world.size.x - 3 or z >= world.size.z - 3:
		return false
	var tree := Vector2i(int(_b.sacred_tree[0]), int(_b.sacred_tree[1]))
	if reserved.has(Vector2i(x, z)) and Vector2(x - tree.x, z - tree.y).length() < 10.0:
		return false
	var top: int = _top(x, z)
	return world.get_xyz(x, top, z) == _id("grass") and world.get_xyz(x, top + 1, z) == 0 and top < 28


func _scatter(spacing: float, chance: float, accept: Callable, place: Callable) -> void:
	for gz in range(int(world.size.z / spacing)):
		for gx in range(int(world.size.x / spacing)):
			var x: int = int((gx + rng.randf()) * spacing)
			var z: int = int((gz + rng.randf()) * spacing)
			if rng.randf() < chance and accept.call(x, z):
				place.call(x, z)


func _tree(x: int, z: int) -> void:
	var top: int = _top(x, z)
	var height: int = 4 + rng.randi_range(0, 1)
	var logs: Array = []
	for y in range(top + 1, top + 1 + height):
		world.fill(Vector3i(x, y, z), _id("log"))
		logs.append(Vector3i(x, y, z))
	var leaves: Array = []
	for cell in crown_cells(Vector3i(x, top + 1, z), height):
		if world.get_block(cell) == 0:
			world.fill(cell, _id("leaves"))
			leaves.append(cell)
	reserved[Vector2i(x, z)] = true
	sites.append({"id": sites.size() + 1, "kind": "tree", "cells": logs, "leaves": leaves, "amount": logs.size() * Registry.yields[_id("log")]})


## The leaf cells of a tree whose trunk rises `height` logs from `base`:
## two wide layers round the top logs and a narrow one above. Trees grown
## from saplings share the shape.
static func crown_cells(base: Vector3i, height: int) -> Array:
	var cells: Array = []
	for dy in range(height - 2, height + 1):
		var radius: int = 1 if dy == height else 2
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) == 2 and absi(dz) == 2:
					continue
				cells.append(base + Vector3i(dx, dy, dz))
	return cells


func _bush(x: int, z: int) -> void:
	var cell := Vector3i(x, _top(x, z) + 1, z)
	var berries: int = int(_b.bush_max_berries)
	world.fill(cell, _id("berry_bush"))
	world.meta[world.index_of(cell)] = berries
	reserved[Vector2i(x, z)] = true
	_site("bush", [cell], berries)


func _grass_patch(x: int, z: int) -> void:
	var cells: Array = []
	for _i in range(7):
		var cx: int = x + rng.randi_range(-2, 2)
		var cz: int = z + rng.randi_range(-2, 2)
		if not _ground_ok(cx, cz):
			continue
		var cell := Vector3i(cx, _top(cx, cz) + 1, cz)
		if world.get_block(cell) == 0:
			world.fill(cell, _id("tall_grass"))
			cells.append(cell)
	if cells.size() >= 3:
		_site("grass", cells, cells.size() * Registry.yields[_id("tall_grass")])
	else:
		for cell in cells:
			world.fill(cell, 0)


func _boulder(x: int, z: int) -> void:
	var cells: Array = []
	var top: int = _top(x, z)
	for offset in [Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 2, 0), Vector3i(1, 1, 1)]:
		if offset != Vector3i(0, 1, 0) and rng.randf() < 0.35:
			continue
		var cell := Vector3i(x + offset.x, top + offset.y, z + offset.z)
		if world.get_block(cell) == 0 and world.get_block(cell - Vector3i(0, 1, 0)) != 0:
			world.fill(cell, _id("stone"))
			cells.append(cell)
	reserved[Vector2i(x, z)] = true
	if not cells.is_empty():
		_site("rock", cells, cells.size())


func _ore_outcrops() -> void:
	var ruin := Vector2(float(_b.ridge_ruin[0]), float(_b.ridge_ruin[1]))
	var placed: int = 0
	var attempts: int = 0
	while placed < 7 and attempts < 400:
		attempts += 1
		var at: Vector2 = ruin + Vector2(rng.randf_range(-26.0, 22.0), rng.randf_range(-26.0, 22.0))
		var x: int = int(at.x)
		var z: int = int(at.y)
		if x < 4 or z < 4 or x >= world.size.x - 4 or z >= world.size.z - 4 or reserved.has(Vector2i(x, z)):
			continue
		if (x + z) * 0.5 < float(_b.ridge_start) + 6.0:
			continue
		var top: int = _top(x, z)
		if world.get_xyz(x, top + 1, z) != 0 or world.get_xyz(x, top, z) == _id("water"):
			continue
		var cells: Array = []
		for offset in [Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 1, 0)]:
			var cell := Vector3i(x + offset.x, _top(x + offset.x, z + offset.z) + offset.y, z + offset.z)
			if offset.y == 1 and world.get_block(cell) != 0:
				continue
			world.fill(cell, _id("ore"))
			cells.append(cell)
		reserved[Vector2i(x, z)] = true
		_site("ore", cells, cells.size())
		placed += 1


## Bare stone faces that people can quarry, block by block: a few outcrops
## within reach of the sacred tree, the rest wherever the ridge shows stone.
func _quarries() -> void:
	var tree := Vector2(float(_b.sacred_tree[0]), float(_b.sacred_tree[1]))
	var count: int = int(_b.home_outcrops)
	for index in range(count):
		var base: float = index * TAU / count + 1.0 + rng.randf() * 0.4
		for attempt in range(8):
			var at: Vector2 = tree + Vector2.from_angle(base + attempt * 0.35) * _home_distance()
			if _outcrop(int(at.x), int(at.y)):
				break
	var placed: int = 0
	for attempt in range(400):
		if placed >= 14:
			return
		var x: int = rng.randi_range(8, world.size.x - 9)
		var z: int = rng.randi_range(8, world.size.z - 9)
		if reserved.has(Vector2i(x, z)):
			continue
		var top: int = _top(x, z)
		if world.get_xyz(x, top, z) != _id("stone"):
			continue
		var cells: Array = []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var cell := Vector3i(x + dx, _top(x + dx, z + dz), z + dz)
				if world.get_block(cell) == _id("stone") and world.get_block(cell + Vector3i.UP) == 0:
					cells.append(cell)
		if cells.size() >= 5:
			for cell in cells:
				reserved[Vector2i(cell.x, cell.z)] = true
			_site("rock", cells, cells.size())
			placed += 1


## A low knuckle of stone pushed up through the meadow; false when the
## ground would not take it.
func _outcrop(x: int, z: int) -> bool:
	if not _ground_ok(x, z):
		return false
	var cells: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cx: int = x + dx
			var cz: int = z + dz
			if not _ground_ok(cx, cz):
				continue
			var top: int = _top(cx, cz)
			var cell := Vector3i(cx, top + 1, cz)
			world.fill(cell, _id("stone"))
			cells.append(cell)
			if absi(dx) + absi(dz) <= 1:
				world.fill(cell + Vector3i.UP, _id("stone"))
				cells.append(cell + Vector3i.UP)
	for cell in cells:
		reserved[Vector2i(cell.x, cell.z)] = true
	if cells.size() >= 4:
		_site("rock", cells, cells.size())
		return true
	return false


## Open, level land well away from the tree and the hamlet where a second
## settlement could be founded, named by its direction from the tree. Read
## from the finished terrain without drawing randomness or changing a block.
func _founding_grounds() -> void:
	var tree := Vector2(float(_b.sacred_tree[0]), float(_b.sacred_tree[1]))
	var hamlet := Vector2(float(_b.ridge_hamlet[0]), float(_b.ridge_hamlet[1]))
	var ruin := Vector2(float(_b.ridge_ruin[0]), float(_b.ridge_ruin[1]))
	var reach: Array = _b.ground_distance
	var radius: int = int(_b.ground_radius)
	var candidates: Array = []
	for z in range(radius + 8, world.size.z - radius - 8, 3):
		for x in range(radius + 8, world.size.x - radius - 8, 3):
			var at := Vector2(x, z)
			var from_tree: float = at.distance_to(tree)
			if from_tree < float(reach[0]) or from_tree > float(reach[1]) or at.distance_to(hamlet) < 36.0 or at.distance_to(ruin) < 30.0:
				continue
			var spread: int = _level(x, z, radius)
			if spread < 0 or spread > int(_b.ground_flatness):
				continue
			candidates.append([spread, absf(from_tree - (float(reach[0]) + float(reach[1])) * 0.5), z, x])
	candidates.sort()
	var names: Array = ["east", "south_east", "south", "south_west", "west", "north_west", "north", "north_east"]
	var taken: Dictionary = {}
	var grounds: Array = []
	for entry in candidates:
		if grounds.size() >= int(_b.ground_count):
			break
		var at := Vector2(int(entry[3]), int(entry[2]))
		var direction: int = posmod(roundi((at - tree).angle() / (TAU / 8.0)), 8)
		var apart: bool = not taken.has(direction)
		for ground in grounds:
			apart = apart and at.distance_to(Vector2(ground.center.x, ground.center.z)) >= float(_b.ground_spacing)
		if not apart:
			continue
		taken[direction] = true
		grounds.append({"name": "place_ground_" + names[direction], "center": Vector3i(int(at.x), _top(int(at.x), int(at.y)) + 1, int(at.y))})
		_ground_larder(int(at.x), int(at.y))
	features["grounds"] = grounds


## What lets a few settlers live on new land: a ring of berry bushes and a
## knuckle of stone a short walk from where they will camp.
func _ground_larder(x: int, z: int) -> void:
	var count: int = int(_b.ground_bushes)
	for index in range(count):
		var at: Vector2 = Vector2(x, z) + Vector2.from_angle(index * TAU / count + 0.4) * float(_b.ground_bush_ring)
		if _bush_ok(int(at.x), int(at.y)) and not reserved.has(Vector2i(int(at.x), int(at.y))):
			_bush(int(at.x), int(at.y))
	for attempt in range(8):
		var at: Vector2 = Vector2(x, z) + Vector2.from_angle(attempt * TAU / 8.0 + 1.1) * float(_b.ground_bush_ring + 4)
		if _outcrop(int(at.x), int(at.y)):
			return


## How uneven the land is within `radius` of a column, or -1 where it is not
## open grass (water, rock, trees, buildings).
func _level(x: int, z: int, radius: int) -> int:
	var low: int = 1 << 20
	var high: int = -1
	for dz in range(-radius, radius + 1, 2):
		for dx in range(-radius, radius + 1, 2):
			var top: int = _top(x + dx, z + dz)
			if world.get_xyz(x + dx, top, z + dz) != _id("grass") or reserved.has(Vector2i(x + dx, z + dz)):
				return -1
			low = mini(low, top)
			high = maxi(high, top)
	return high - low
