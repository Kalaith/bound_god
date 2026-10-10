extends RefCounted
## Work plans: gathering, hauling, building, repairing, and marking out a
## new site. Each reads the person's beliefs and the visible job board.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const JobBoard = preload("res://scripts/sim/job_board.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const FunctionRules = preload("res://scripts/building/function_rules.gd")

const Kind = Goals.Kind
const Op = Plans.Op
const T = Plans.T
const GATHER_IDS: Array[String] = ["gather_nearest", "gather_next", "gather_farther"]
const FUNCTIONS: Array[String] = FunctionRules.FUNCTIONS


static func _store(agent: RefCounted) -> Dictionary:
	return Plans.go_to(Plans.target(T.STORE, agent.settlement_id))


static func plans(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> Array:
	match int(goal.kind):
		Kind.GATHER:
			return _gather(sim, agent, int(goal.target))
		Kind.HAUL:
			return _haul(sim, agent)
		Kind.BUILD:
			return _build(sim, agent, int(goal.target))
		Kind.REPAIR:
			return _repair(sim, agent, int(goal.target))
		Kind.DEFEND:
			return [H.option("drive_off", 1.0, [Plans.step(Op.ATTACK, {"threat": int(goal.target)})])]
		Kind.SCOUT:
			return [H.option("look_around", 1.0, [Plans.go_cell(frontier_cell(sim, agent)), Plans.step(Op.SCOUT, {"ticks": 12})])]
		Kind.GARDEN:
			return _garden(sim, agent, int(goal.target))
		Kind.FOUND_HOME:
			return [H.option("mark_home", 1.0, [Plans.step(Op.MARK_SITE, {"function": "dwelling", "purpose": "home"})])]
		Kind.PROPOSE_PROJECT:
			var function: String = FUNCTIONS[int(goal.target)]
			return [H.option("mark_project", 1.0, [Plans.step(Op.MARK_SITE, {"function": function, "purpose": function})])]
	return []


## Plant a berry in an empty planter of the garden: one already carried,
## one from the stores, or one picked from a bush on the way.
static func _garden(sim: RefCounted, agent: RefCounted, garden_id: int) -> Array:
	var board: Dictionary = sim.settlement_life.board(agent.settlement_id)
	var result: Array = []
	# A basket holds about three bushes' worth; pick them, then store it all.
	var picking: Array = []
	for entry in board.get("ripe", []):
		if int(entry[0]) == garden_id and picking.size() < 6:
			var site: int = int(entry[1])
			picking.append_array([Plans.go_to(Plans.target(T.SITE, site)), Plans.step(Op.HARVEST, {"site": site})])
	if not picking.is_empty():
		result.append(H.option("pick_the_garden", 1.1, H.free_hands(agent, "berries") + picking + [_store(agent), Plans.step(Op.DEPOSIT)]))
	var plot: Vector3i = Vector3i(-1, -1, -1)
	for entry in board.get("plots", []):
		if int(entry[0]) == garden_id:
			plot = entry[1]
			break
	if plot.x < 0:
		return result
	var stand: Vector3i = plot_stand(sim, plot, agent.cell)
	if stand.x < 0:
		return result
	var plant: Array = [Plans.go_cell(stand), Plans.step(Op.PLANT, {"cell": plot})]
	if agent.carried("berries") >= 1.0:
		result.append(H.option("plant_a_berry", 1.2, plant))
	if agent.beliefs.believes_stock("berries"):
		result.append(H.option("fetch_a_berry_to_plant", 1.0, H.free_hands(agent, "berries") + [_store(agent),
			Plans.step(Op.TAKE_STOCK, {"resource": "berries", "amount": 1})] + plant))
	var bushes: Array = H.known_sites(sim, agent, "bush")
	if not bushes.is_empty():
		result.append(H.option("pick_a_berry_to_plant", 0.7, H.free_hands(agent, "berries") + [Plans.go_to(Plans.target(T.SITE, bushes[0])),
			Plans.step(Op.HARVEST, {"site": bushes[0], "once": 1})] + plant))
	return result


## A walkable cell within reach of a plot, nearest `from`: off the planters
## if possible (a fenced garden is worked from outside its fence), otherwise
## on another planter, never on the plot itself.
static func plot_stand(sim: RefCounted, plot: Vector3i, from: Vector3i) -> Vector3i:
	var reach: float = Balance.number("agents.reach")
	var best: Vector3i = Vector3i(-1, -1, -1)
	var best_score: float = INF
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			for dy in [-1, 0, 1]:
				var cell: Vector3i = plot + Vector3i(dx, dy, dz)
				if cell == plot or not sim.nav.is_walkable(cell) or Vector3(cell).distance_to(Vector3(plot)) > reach:
					continue
				var on_planter: bool = Registry.component(sim.voxels.get_block(cell + Vector3i.DOWN)) == "planter"
				var score: float = Vector3(cell).distance_to(Vector3(from)) + (100.0 if on_planter else 0.0)
				if score < best_score:
					best = cell
					best_score = score
	return best


## Somewhere toward the edge of what the settlement knows, turning with
## time so scouts cover different ground.
static func frontier_cell(sim: RefCounted, agent: RefCounted) -> Vector3i:
	var settlement: Dictionary = sim.settlements.get_settlement(agent.settlement_id)
	var center: Vector3i = settlement.get("center", agent.cell)
	var turn: int = agent.id * 3 + sim.calendar.tick / 240
	var angle: float = float(posmod(turn, 8)) * TAU / 8.0
	var distance: float = float(settlement.get("radius", 20.0)) + 6.0 + float(posmod(turn, 3)) * 5.0
	var target: Vector3i = center + Vector3i(roundi(cos(angle) * distance), 0, roundi(sin(angle) * distance))
	target.x = clampi(target.x, 4, sim.voxels.size.x - 5)
	target.z = clampi(target.z, 4, sim.voxels.size.z - 5)
	var cell: Vector3i = sim.nav.surface(target.x, target.z)
	return cell if cell.x >= 0 else agent.cell


static func _gather(sim: RefCounted, agent: RefCounted, index: int) -> Array:
	var resource: String = JobBoard.RESOURCES[index]
	var result: Array = []
	var sites: Array = H.known_sites(sim, agent, JobBoard.SITE_KIND[resource])
	for i in range(sites.size()):
		result.append(H.option(GATHER_IDS[i], 1.0 - i * 0.1, H.free_hands(agent, resource) + [
			Plans.go_to(Plans.target(T.SITE, sites[i])),
			Plans.step(Op.HARVEST, {"site": sites[i]}),
			_store(agent),
			Plans.step(Op.DEPOSIT),
		]))
	return result


static func _haul(sim: RefCounted, agent: RefCounted) -> Array:
	var board: Dictionary = sim.settlement_life.board(agent.settlement_id)
	var items: Array = board.get("items", []).filter(func(id: int) -> bool: return sim.items.has(id))
	items.sort_custom(func(a: int, b: int) -> bool:
		var da: float = H.distance(sim.items[a].cell, agent.cell)
		var db: float = H.distance(sim.items[b].cell, agent.cell)
		if da != db:
			return da < db
		return a < b)
	var result: Array = []
	if not agent.carrying.is_empty():
		result.append(H.option("store_carried", 1.2, [_store(agent), Plans.step(Op.DEPOSIT)]))
	for i in range(mini(items.size(), 2)):
		result.append(H.option("haul_item" if i == 0 else "haul_other", 1.0 - i * 0.1, H.free_hands(agent, sim.items[items[i]].resource) + [
			Plans.go_cell(sim.items[items[i]].cell),
			Plans.step(Op.PICK_UP, {"item": items[i]}),
			_store(agent),
			Plans.step(Op.DEPOSIT),
		]))
	return result


static func _build(sim: RefCounted, agent: RefCounted, site_id: int) -> Array:
	var site: Dictionary = sim.construction.get_site(site_id)
	if site.is_empty():
		return []
	var to_site := Plans.go_to(Plans.target(T.CONSTRUCTION, site_id))
	var place := Plans.step(Op.PLACE_BLOCK, {"site": site_id})
	var deliver := Plans.step(Op.DELIVER, {"site": site_id})
	var result: Array = []
	if sim.construction.ready_to_build(site_id):
		result.append(H.option("construct", 1.2, [to_site, place]))
	var missing: Dictionary = sim.construction.missing(site_id)
	if not agent.carrying.is_empty() and missing.has(agent.carrying.resource):
		result.append(H.option("deliver_carried", 1.1, [to_site, deliver, place]))
	var resources: Array = missing.keys()
	resources.sort()
	for resource in resources:
		if agent.beliefs.believes_stock(resource):
			var amount: int = mini(int(missing[resource]), int(Balance.number("agents.carry_capacity")))
			result.append(H.option("fetch_from_stores", 1.0, H.free_hands(agent, resource) + [_store(agent),
				Plans.step(Op.TAKE_STOCK, {"resource": resource, "amount": amount}), to_site, deliver, place]))
			break
	var board: Dictionary = sim.settlement_life.board(agent.settlement_id)
	for item_id in board.get("loose", []):
		var item: Dictionary = sim.items.get(item_id, {})
		if not item.is_empty() and missing.has(item.resource):
			result.append(H.option("fetch_loose", 0.8, H.free_hands(agent, item.resource) + [Plans.go_cell(item.cell), Plans.step(Op.PICK_UP, {"item": item_id}), to_site, deliver, place]))
			break
	return result


static func _repair(sim: RefCounted, agent: RefCounted, structure_id: int) -> Array:
	var missing: Array = sim.settlement_life.missing_blocks(sim, structure_id)
	if missing.is_empty():
		return []
	var resource: String = Registry.resource(missing[0][1])
	var go := Plans.go_to(Plans.target(T.STRUCTURE, structure_id))
	var mend := Plans.step(Op.REPAIR_BLOCK, {"structure": structure_id})
	var result: Array = []
	if agent.carried(resource) >= 1.0:
		result.append(H.option("repair_carried", 1.1, [go, mend]))
	if agent.beliefs.believes_stock(resource):
		result.append(H.option("repair_from_stores", 1.0, H.free_hands(agent, resource) + [_store(agent),
			Plans.step(Op.TAKE_STOCK, {"resource": resource, "amount": mini(missing.size(), 6)}), go, mend]))
	return result
