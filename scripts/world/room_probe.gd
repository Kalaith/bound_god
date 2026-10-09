extends RefCounted
## Bounded room discovery. Doors close a room even though people pass them.
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const DIRECTIONS: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]


static func permeable(world: RefCounted, cell: Vector3i) -> bool:
	var block: int = world.get_block(cell)
	var component: String = Registry.component(block)
	return component != "door" and (block == 0 or component in ["bed", "chest", "hearth", "workbench", "altar"])


static func probe(world: RefCounted, seed: Vector3i) -> Dictionary:
	var limits: Array = Data.template_limits().max_size
	var limit := Vector3i(int(limits[0]), int(limits[1]), int(limits[2]))
	var maximum: int = limit.x * limit.y * limit.z
	var queue: Array[Vector3i] = [seed]
	var inside: Dictionary = {seed: true}
	var shell: Dictionary = {}
	var low: Vector3i = seed
	var high: Vector3i = seed
	var cursor: int = 0
	var closed: bool = true
	while cursor < queue.size():
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
	return {"closed": closed, "inside": inside, "cells": cells}
