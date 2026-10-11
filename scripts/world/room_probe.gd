extends RefCounted
## Bounded room discovery. Doors close a room even though people pass them.
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const DIRECTIONS: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
## Furniture: components a room holds and the probe passes through.
const FURNITURE: Array[String] = ["bed", "chest", "hearth", "workbench", "altar", "table", "bench", "lantern", "granary_bin", "mat",
	"scripture", "lectern", "incense", "medicine", "tablet", "bell", "array", "mortar", "rack", "cauldron"]
## Components a structure is found from: furniture that gives a room its use,
## and planters and farmland, whose connected beds make a garden or a field
## under the open sky.
const ANCHORS: Array[String] = ["bed", "chest", "altar", "hearth", "workbench", "table", "planter", "farmland", "granary_bin", "mat", "formation",
	"scripture", "lectern", "incense", "medicine", "tablet", "bell", "array", "jade", "stele", "banner", "mortar", "rack", "cauldron", "herb_bed"]
## Components that stand on a cut-stone platform under the sky: a trial
## ground's formation stones, an array's jade, a stele, a gate's banners.
const PLATFORM: Array[String] = ["formation", "jade", "stele", "banner"]
## Bed components: probed as connected beds, not as rooms.
const BEDS: Array[String] = ["planter", "farmland", "herb_bed"]


## An open column straight up from the seed, as tall as a room may be: the
## flood would climb it past the limit, so the room is open without flooding
## the whole box around it (most anchors stand outdoors).
static func _open_above(world: RefCounted, seed: Vector3i, height: int) -> bool:
	for dy in range(1, height + 1):
		var cell: Vector3i = seed + Vector3i(0, dy, 0)
		if not world.in_bounds(cell):
			return true
		if not permeable(world, cell):
			return false
	return true


static func permeable(world: RefCounted, cell: Vector3i) -> bool:
	var block: int = world.get_block(cell)
	var component: String = Registry.component(block)
	return component != "door" and (block == 0 or component in FURNITURE)


static func probe(world: RefCounted, seed: Vector3i) -> Dictionary:
	if Registry.component(world.get_block(seed)) in BEDS:
		return beds(world, seed)
	if Registry.component(world.get_block(seed)) in PLATFORM:
		return platform(world, seed)
	var limits: Array = Data.template_limits().max_size
	var limit := Vector3i(int(limits[0]), int(limits[1]), int(limits[2]))
	var maximum: int = limit.x * limit.y * limit.z
	var queue: Array[Vector3i] = [seed]
	var inside: Dictionary = {seed: true}
	var shell: Dictionary = {}
	var low: Vector3i = seed
	var high: Vector3i = seed
	var cursor: int = 0
	var closed: bool = not _open_above(world, seed, limit.y)
	while closed and cursor < queue.size():
		var cell: Vector3i = queue[cursor]
		cursor += 1
		for direction in DIRECTIONS:
			var other: Vector3i = cell + direction
			if not permeable(world, other):
				shell[other] = true
				continue
			if inside.has(other):
				continue
			low = Vector3i(mini(low.x, other.x), mini(low.y, other.y), mini(low.z, other.z))
			high = Vector3i(maxi(high.x, other.x), maxi(high.y, other.y), maxi(high.z, other.z))
			var span: Vector3i = high - low + Vector3i.ONE
			if not world.in_bounds(other) or inside.size() >= maximum or span.x > limit.x or span.y > limit.y or span.z > limit.z:
				closed = false
				break
			inside[other] = true
			queue.append(other)
		if not closed:
			break
	if not closed:
		# An open lean-to has a connected roofed floor, not an arbitrary box
		# that might borrow a door or bed from a neighbouring building.
		inside = {seed: true}
		shell = {}
		queue = [seed]
		cursor = 0
		while cursor < queue.size() and inside.size() < maximum:
			var cell: Vector3i = queue[cursor]
			cursor += 1
			for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
				var other: Vector3i = cell + direction
				if absi(other.x - seed.x) >= limit.x or absi(other.z - seed.z) >= limit.z:
					continue
				if not permeable(world, other):
					shell[other] = true
				elif not inside.has(other) and world.in_bounds(other) and world.is_roofed(other, int(Data.function_rules()[0].roof_reach)) and world.is_solid(other + Vector3i.DOWN):
					inside[other] = true
					queue.append(other)
	var cells: Dictionary = inside.duplicate()
	cells.merge(shell)
	# Everything the probe looked at lies in this box, and the rules look no
	# further than the columns above it: an edit outside cannot change it.
	var reads: Array = [low.x - 1, low.z - 1, high.x + 1, high.z + 1, low.y - 1]
	for cell in cells:
		_widen(reads, cell)
	return {"closed": closed, "inside": inside, "cells": cells, "reads": reads}


## Grow a read box [min x, min z, max x, max z, min y] to hold a cell and its neighbours.
static func _widen(reads: Array, cell: Vector3i) -> void:
	reads[0] = mini(reads[0], cell.x - 1)
	reads[1] = mini(reads[1], cell.z - 1)
	reads[2] = maxi(reads[2], cell.x + 1)
	reads[3] = maxi(reads[3], cell.z + 1)
	reads[4] = mini(reads[4], cell.y - 1)


## A garden or a field: the planters (or farmland) joined side by side (or a
## step up or down) to the seed. Its inside is the beds and the cell above
## each, where a bush or a crop grows, so no bed of it seeds a second one.
static func beds(world: RefCounted, seed: Vector3i) -> Dictionary:
	var kind: String = Registry.component(world.get_block(seed))
	var limits: Array = Data.template_limits().max_size
	var limit := Vector3i(int(limits[0]), int(limits[1]), int(limits[2]))
	var planters: Dictionary = {seed: true}
	var queue: Array[Vector3i] = [seed]
	var cursor: int = 0
	while cursor < queue.size():
		var cell: Vector3i = queue[cursor]
		cursor += 1
		for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			for dy in [0, 1, -1]:
				var other: Vector3i = cell + direction + Vector3i(0, dy, 0)
				if planters.has(other) or Registry.component(world.get_block(other)) != kind:
					continue
				if absi(other.x - seed.x) >= limit.x or absi(other.z - seed.z) >= limit.z:
					continue
				planters[other] = true
				queue.append(other)
	var inside: Dictionary = planters.duplicate()
	var reads: Array = [seed.x, seed.z, seed.x, seed.z, seed.y]
	for cell in planters:
		inside[cell + Vector3i.UP] = true
		_widen(reads, cell + Vector3i.DOWN)
	return {"closed": false, "inside": inside, "cells": inside.duplicate(), "reads": reads}


## A platform (a trial ground, an array, a stele, a gate): the cut stone
## joined side by side under its seed, and what stands on it. Its inside is the platform and
## the cell above each stone of it.
static func platform(world: RefCounted, seed: Vector3i) -> Dictionary:
	var stone: int = Registry.id("cut_stone")
	var base: Vector3i = seed + Vector3i.DOWN
	var reads: Array = [seed.x - 1, seed.z - 1, seed.x + 1, seed.z + 1, seed.y - 2]
	if world.get_block(base) != stone:
		return {"closed": false, "inside": {seed: true}, "cells": {seed: true}, "reads": reads}
	var limits: Array = Data.template_limits().max_size
	var floor: Dictionary = {base: true}
	var queue: Array[Vector3i] = [base]
	var cursor: int = 0
	while cursor < queue.size():
		var cell: Vector3i = queue[cursor]
		cursor += 1
		for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var other: Vector3i = cell + direction
			if floor.has(other) or world.get_block(other) != stone:
				continue
			if absi(other.x - base.x) >= int(limits[0]) or absi(other.z - base.z) >= int(limits[2]):
				continue
			floor[other] = true
			queue.append(other)
	var inside: Dictionary = floor.duplicate()
	for cell in floor:
		inside[cell + Vector3i.UP] = true
		_widen(reads, cell)
	return {"closed": false, "inside": inside, "cells": inside.duplicate(), "reads": reads}
