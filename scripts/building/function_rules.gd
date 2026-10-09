extends RefCounted
## Rules consume actual components. Names and imported claims never confer use.
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const RoomProbe = preload("res://scripts/world/room_probe.gd")
const Balance = preload("res://scripts/core/balance.gd")


static func evaluate(world: RefCounted, cells: Dictionary) -> Dictionary:
	var components: Dictionary = {}
	for cell in cells:
		var kind: String = Registry.component(world.get_block(cell))
		if not kind.is_empty():
			if not components.has(kind):
				components[kind] = []
			components[kind].append(cell)
	var functions: Array = []
	var capacity: Dictionary = {}
	for rule in Data.function_rules():
		var valid: bool = true
		for kind in rule.requires:
			if components.get(kind, []).size() < int(rule.requires[kind]):
				valid = false
		if not rule.requires_any.is_empty():
			var any: bool = false
			for kind in rule.requires_any:
				any = any or components.has(kind)
			valid = valid and any
		for kind in rule.roofed:
			for cell in components.get(kind, []):
				valid = valid and world.is_roofed(cell, int(rule.roof_reach))
		var floor_count: int = 0
		if rule.has("min_roofed_floor"):
			for cell in cells:
				# Furniture is permeable to the probe, so the cell above a bed is not floor.
				var below: Vector3i = cell + Vector3i.DOWN
				if RoomProbe.permeable(world, cell) and world.is_solid(below) and not RoomProbe.permeable(world, below) and world.is_roofed(cell, int(rule.roof_reach)):
					floor_count += 1
			valid = valid and floor_count >= int(rule.min_roofed_floor)
		if rule.has("sky_or_tree_within"):
			var sacred: bool = false
			for altar in components.get("altar", []):
				sacred = sacred or _near_sky(world, altar, int(rule.sky_or_tree_within))
			valid = valid and sacred
		if not valid:
			continue
		functions.append(rule.id)
		for key in rule.capacity:
			var source: String = rule.capacity[key]
			var count: int = floor_count if source == "roofed_floor" else components.get(source, []).size()
			if key == "stock":
				count *= int(Balance.number("settlements.chest_capacity"))
			if key == "workers":
				count = mini(count, 1)
			capacity[key] = count
	return {"functions": functions, "capacity": capacity, "components": components}


static func _near_sky(world: RefCounted, altar: Vector3i, reach: int) -> bool:
	for z in range(-reach, reach + 1):
		for x in range(-reach, reach + 1):
			for y in range(-reach, reach + 1):
				if x * x + y * y + z * z > reach * reach:
					continue
				var cell: Vector3i = altar + Vector3i(x, y, z)
				if world.get_block(cell) == Registry.id("sacred_tree"):
					return true
				if world.in_bounds(cell) and world.get_block(cell) == 0 and world.sees_sky(cell):
					return true
	return world.sees_sky(altar)
