extends RefCounted
## Renovations (M19b): a standing building with one function takes on
## another when the components it lacks are added to free floor inside it
## (shelves and a lectern turn a storehouse into a library as well). The
## catalog is `renovations` in templates.json. A renovation is known to anyone
## who knows a design with the function it gives, is preferred to a new
## building while a fitting one stands, and is raised as an ordinary site
## whose order holds only the added blocks. Nothing is taken away.
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const RoomProbe = preload("res://scripts/world/room_probe.gd")

## Site template ids for renovations start with this.
const PREFIX: String = "renovate:"
const SIDES: Array[Vector3i] = [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]


static func catalog() -> Array:
	return Data.file("templates").get("renovations", [])


static func by_id(id: String) -> Dictionary:
	for entry in catalog():
		if str(entry.id) == id:
			return entry
	return {}


static func is_renovation(template_id: String) -> bool:
	return template_id.begins_with(PREFIX)


static func name_of(template_id: String) -> String:
	return str(by_id(template_id.trim_prefix(PREFIX)).get("name", template_id))


## The first renovation that would give a settlement `function`: a standing
## building there with the function it starts from, room inside for what it
## lacks, and nobody already at work on it. {renovation, structure, order} or {}.
static func option(sim: RefCounted, settlement_id: int, function: String) -> Dictionary:
	for renovation in catalog():
		if str(renovation.gives) != function:
			continue
		for entry in sim.structures.built():
			if not entry.functions.has(str(renovation.on)) or entry.functions.has(function) or not entry.closed:
				continue
			if sim.settlements.at_cell(entry.anchor) != settlement_id or not _fits(entry, renovation):
				continue
			var order: Array = place(sim, entry, renovation)
			if not order.is_empty():
				return {"renovation": renovation, "structure": int(entry.id), "order": order}
	return {}


## Whether a building has what a renovation builds on beyond its function
## (a home of two beds or more for an infirmary).
static func _fits(entry: Dictionary, renovation: Dictionary) -> bool:
	for component in renovation.get("needs", {}):
		if entry.components.get(component, []).size() < int(renovation.needs[component]):
			return false
	return true


## Where the added blocks go: free, roofed floor inside against a wall, not by
## a door, chosen so every other floor cell stays reachable and every piece of
## furniture keeps a cell beside it. [cell, block, 0] entries, or [] if they
## do not fit.
static func place(sim: RefCounted, entry: Dictionary, renovation: Dictionary) -> Array:
	var floor: Dictionary = {}
	for cell in entry.inside:
		if sim.voxels.get_block(cell) == 0 and sim.nav.is_walkable(cell):
			floor[cell] = true
	var wanted: Array = []
	for name in renovation.adds:
		for _i in range(int(renovation.adds[name])):
			wanted.append(Registry.id(str(name)))
	var cells: Array = floor.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return sim.voxels.index_of(a) < sim.voxels.index_of(b))
	var taken: Dictionary = {}
	var order: Array = []
	for cell in cells:
		if order.size() == wanted.size():
			break
		if sim.construction.is_reserved(cell) or sim.is_occupied(cell) or not sim.voxels.is_roofed(cell, 4):
			continue
		if not _against_wall(sim, cell) or _by_door(sim, cell):
			continue
		taken[cell] = true
		if _still_open(sim, entry, floor, taken):
			order.append([cell, wanted[order.size()], 0])
		else:
			taken.erase(cell)
	return order if order.size() == wanted.size() else []


static func _against_wall(sim: RefCounted, cell: Vector3i) -> bool:
	for side in SIDES:
		if not RoomProbe.permeable(sim.voxels, cell + side):
			return true
	return false


static func _by_door(sim: RefCounted, cell: Vector3i) -> bool:
	for side in SIDES:
		for dy in [0, 1]:
			if Registry.component(sim.voxels.get_block(cell + side + Vector3i(0, dy, 0))) == "door":
				return true
	return false


## The floor left free is all one piece, and every component has free floor
## beside it.
static func _still_open(sim: RefCounted, entry: Dictionary, floor: Dictionary, taken: Dictionary) -> bool:
	var free: Array = floor.keys().filter(func(c: Vector3i) -> bool: return not taken.has(c))
	if free.is_empty():
		return false
	var seen: Dictionary = {free[0]: true}
	var queue: Array = [free[0]]
	while not queue.is_empty():
		var cell: Vector3i = queue.pop_back()
		for side in SIDES:
			for dy in [-1, 0, 1]:
				var other: Vector3i = cell + side + Vector3i(0, dy, 0)
				if floor.has(other) and not taken.has(other) and not seen.has(other):
					seen[other] = true
					queue.append(other)
	if seen.size() != free.size():
		return false
	for kind in entry.components:
		for part in entry.components[kind]:
			if kind == "door":
				continue
			var reachable: bool = false
			for side in SIDES:
				for dy in [-1, 0]:
					var beside: Vector3i = part + side + Vector3i(0, dy, 0)
					reachable = reachable or (floor.has(beside) and not taken.has(beside))
			reachable = reachable or (floor.has(part) and not taken.has(part))
			if not reachable:
				return false
	return true


## Whether someone in a settlement knows a design with the function: they
## then know what such a room needs.
static func known(sim: RefCounted, agent: RefCounted, function: String) -> bool:
	for id in agent.beliefs.known_templates:
		var template: RefCounted = sim.template(id)
		if template != null and template.functions.has(function):
			return true
	return false


## A finished renovation: chronicled, and the building keeps its design.
static func complete(sim: RefCounted, site: Dictionary) -> void:
	var renovation: Dictionary = by_id(str(site.template_id).trim_prefix(PREFIX))
	var founder: RefCounted = sim.agents[int(site.founder)] if int(site.founder) >= 0 else null
	var entry: Dictionary = sim.structures.containing(site.order[0][0]) if not site.order.is_empty() else {}
	var gives: String = str(renovation.get("gives", ""))
	var done: bool = not entry.is_empty() and entry.functions.has(gives)
	sim.chronicle_event("renovated" if done else "renovation_fell_short", int(site.settlement_id),
		{"name": founder.full_name() if founder != null else "", "from": "function_" + str(renovation.get("on", "")), "to": "function_" + gives},
		str(site.get("cause", "cause_npc")), [founder.id] if founder != null else [])
