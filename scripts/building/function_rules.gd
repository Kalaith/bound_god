extends RefCounted
## Rules consume actual components. Names and imported claims never confer use.
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const RoomProbe = preload("res://scripts/world/room_probe.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Qi = preload("res://scripts/sim/qi.gd")

## Every function a structure can have, in a fixed order: goal targets and
## saved proposals refer to a function by its index here, so only append.
const FUNCTIONS: Array[String] = ["dwelling", "storehouse", "workshop", "shrine", "shelter", "hall", "garden", "field", "kitchen", "granary",
	"meditation_hall", "tribulation_ground", "library", "meditation_room", "tribulation_chamber", "infirmary", "spirit_array", "sect_gate",
	"ancestral_hall", "precept_stele", "bell_tower", "lecture_hall", "alchemy_room", "smithy",
	"herbal_workshop", "alchemy_hall", "pill_pavilion", "herb_garden"]


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
		# A meditation room holds one mat: more and it is a hall.
		for kind in rule.get("at_most", {}):
			valid = valid and components.get(kind, []).size() <= int(rule.at_most[kind])
		if not rule.requires_any.is_empty():
			var any: bool = false
			for kind in rule.requires_any:
				any = any or components.has(kind)
			valid = valid and any
		for kind in rule.roofed:
			for cell in components.get(kind, []):
				valid = valid and world.is_roofed(cell, int(rule.roof_reach))
		# A field grows under the open sky: nothing solid over any of its ground.
		for kind in rule.get("open_sky", []):
			for cell in components.get(kind, []):
				valid = valid and world.sees_sky(cell)
		var floor_count: int = 0
		if rule.has("min_roofed_floor"):
			for cell in cells:
				# Furniture is permeable to the probe, so the cell above a bed is not floor.
				var below: Vector3i = cell + Vector3i.DOWN
				if RoomProbe.permeable(world, cell) and world.is_solid(below) and not RoomProbe.permeable(world, below) and world.is_roofed(cell, int(rule.roof_reach)):
					floor_count += 1
			valid = valid and floor_count >= int(rule.min_roofed_floor)
		# Blocks that must be part of it, by name (a trial ground's stone platform).
		for name in rule.get("requires_blocks", {}):
			var count: int = 0
			var wanted: int = Registry.id(str(name))
			for cell in cells:
				count += 1 if world.get_block(cell) == wanted else 0
			valid = valid and count >= int(rule.requires_blocks[name])
		# A meditation hall stands where the tree's qi is dense enough.
		if rule.has("qi_at_least"):
			var at: Array = components.get(rule.requires.keys()[0], []) if not rule.requires.is_empty() else []
			valid = valid and not at.is_empty() and tree_qi(world, at[0]) >= float(rule.qi_at_least)
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
			if key == "grain":
				count *= int(Balance.number("settlements.bin_capacity"))
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


## The tree's qi at a cell. Function rules see only blocks, so this uses the
## tree's place, which world generation fixes at the middle of the map;
## nurtured spots, which pass in a season, do not make a hall. A design on
## its own (a world no bigger than a design) always meets it: where it may
## stand is the site finder's question.
static func tree_qi(world: RefCounted, cell: Vector3i) -> float:
	var limits: Array = Data.template_limits().max_size
	if world.size.x <= int(limits[0]) and world.size.z <= int(limits[2]):
		return 1.0
	var centre := Vector2(world.size.x / 2 + 1.0, world.size.z / 2 + 1.0)
	return Qi.curve_at(Vector2(cell.x + 0.5, cell.z + 0.5).distance_to(centre))
