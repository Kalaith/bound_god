extends RefCounted
## Routes between settlements (M21): pilgrims, messengers and traders walk
## between linked settlements, too many and too far to simulate one by one,
## and wear the way between their camps. A branch and its parent are
## linked, and so is a settlement whose people pray at another's shrine.
## Each day every link adds its traffic to the wear of each column on its
## route (a navigation path between the camps, kept and found again every
## few days), so a well-used route turns to path by the ordinary wear rules
## (paths.gd) and the tree's roots can follow it. While the valley passes
## abstractly the wear is held at what the traffic would keep it at, and the
## paths are laid when it materialises. Runs the same in both fidelities.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

## "a:b" (settlement ids, a < b) -> {cells: Array of Vector2i, day: int found, worn: bool}
var routes: Dictionary = {}


## Links between settlements with people in both, and the traffic each
## carries a day: "a:b" -> steps.
static func links(sim: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	var present: Dictionary = {}
	for agent in sim.agents:
		if agent.is_present() and agent.settlement_id >= 0:
			present[agent.settlement_id] = true
	if sim.sects != null:
		for id in sim.sects.ids():
			var sect: Dictionary = sim.sects.entries[id]
			var parent: Dictionary = sim.sects.get_sect(int(sect.get("parent", -1)))
			if not parent.is_empty():
				_add(result, present, int(sect.settlement_id), int(parent.settlement_id), Balance.number("routes.per_link"))
	if sim.faith != null:
		for agent in sim.agents:
			if not agent.is_present() or agent.is_child or not agent.faith.get("knows", false):
				continue
			var shrine: Dictionary = sim.faith.get_shrine(int(agent.faith.shrine_id))
			if not shrine.is_empty():
				_add(result, present, agent.settlement_id, int(shrine.settlement_id), Balance.number("routes.per_pilgrim"))
	var most: float = Balance.number("routes.most")
	for key in result:
		result[key] = minf(float(result[key]), most)
	return result


static func _add(result: Dictionary, present: Dictionary, a: int, b: int, steps: float) -> void:
	if a == b or a < 0 or b < 0 or not present.has(a) or not present.has(b):
		return
	var key: String = "%d:%d" % [mini(a, b), maxi(a, b)]
	result[key] = float(result.get(key, 0.0)) + steps


## Daily: every link wears its route. `abstract` holds the wear at what the
## traffic keeps it at instead of adding a day's steps (no paths are laid
## while abstract; `materialise` lays them).
func daily(sim: RefCounted, abstract: bool = false) -> void:
	var traffic: Dictionary = links(sim)
	var keys: Array = traffic.keys()
	keys.sort()
	var keep: float = Balance.number("paths.wear_keep")
	for key in keys:
		var route: Dictionary = _route(sim, key)
		var steps: float = float(traffic[key])
		for column in route.get("cells", []):
			if abstract:
				sim.paths.wear[column] = maxf(float(sim.paths.wear.get(column, 0.0)), steps / (1.0 - keep))
			else:
				sim.paths.add_steps(column, steps)
		if not abstract:
			_note_worn(sim, key, route)


## The route for a link, found again when it is old or missing.
func _route(sim: RefCounted, key: String) -> Dictionary:
	var route: Dictionary = routes.get(key, {})
	var day: int = sim.calendar.day()
	if not route.is_empty() and day - int(route.day) < Balance.integer("routes.refind_days"):
		return route
	var ends: PackedStringArray = key.split(":")
	var a: Dictionary = sim.settlements.get_settlement(int(ends[0]))
	var b: Dictionary = sim.settlements.get_settlement(int(ends[1]))
	var cells: Array = []
	if not a.is_empty() and not b.is_empty():
		var from: Vector3i = sim.nav.nearest_walkable(a.camp, 4)
		var to: Vector3i = sim.nav.nearest_walkable(b.camp, 4)
		if from.x >= 0 and to.x >= 0:
			for cell in sim.nav.find_path(from, to):
				var column := Vector2i(cell.x, cell.z)
				if cells.is_empty() or cells.back() != column:
					cells.append(column)
	route = {"cells": cells, "day": day, "worn": bool(route.get("worn", false))}
	routes[key] = route
	return route


## A route is worn through once nearly all its grass has turned to path.
func _note_worn(sim: RefCounted, key: String, route: Dictionary) -> void:
	if bool(route.worn) or route.cells.is_empty():
		return
	var grass: int = Registry.id("grass")
	var path: int = Registry.id("path")
	var open: int = 0
	var worn: int = 0
	for column in route.cells:
		var top: int = sim.voxels.top_solid_y(column.x, column.y)
		var block: int = sim.voxels.get_xyz(column.x, top, column.y) if top >= 0 else 0
		if block == path:
			worn += 1
			open += 1
		elif block == grass:
			open += 1
	if open == 0 or float(worn) / open < 0.9:
		return
	route.worn = true
	var ends: PackedStringArray = key.split(":")
	var a: String = str(sim.settlements.get_settlement(int(ends[0])).get("name", ""))
	var b: String = str(sim.settlements.get_settlement(int(ends[1])).get("name", ""))
	sim.chronicle_event("route_worn", int(ends[0]), {"from": a, "to": b}, "cause_route_traffic|%d" % route.cells.size())


func to_dict() -> Dictionary:
	return {"routes": routes.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	routes = data.get("routes", {})
