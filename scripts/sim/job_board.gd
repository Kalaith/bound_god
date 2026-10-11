extends RefCounted
## A settlement's job board, refreshed every 10 ticks: building sites and
## what they lack, repairs, how much each resource is wanted, loose items to
## haul and threats near home. Nothing on it is assigned; people read it.
const Crafts = preload("res://scripts/sim/crafts.gd")
const Alchemy = preload("res://scripts/sim/alchemy.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Food = preload("res://scripts/sim/food.gd")
const Crops = preload("res://scripts/sim/crops.gd")
const Woods = preload("res://scripts/sim/woods.gd")

const RESOURCES: Array[String] = ["wood", "stone", "thatch", "berries", "ore", "herb", "ginseng", "thunder_root", "frost_lotus"]
const SITE_KIND: Dictionary = {"wood": "tree", "stone": "rock", "thatch": "grass", "berries": "bush", "ore": "ore", "herb": "herb",
	"ginseng": "ginseng", "thunder_root": "thunder_root", "frost_lotus": "frost_lotus"}
## Stock a settlement likes to keep before anyone needs it: base + per resident.
const RESERVE: Dictionary = {"wood": [12, 2], "stone": [8, 1], "thatch": [8, 1], "berries": [6, 4], "ore": [0, 0], "herb": [0, 0],
	"ginseng": [0, 0], "thunder_root": [0, 0], "frost_lotus": [0, 0]}


static func refresh(sim: RefCounted, settlement: Dictionary) -> Dictionary:
	var id: int = int(settlement.id)
	var board: Dictionary = {"builds": [], "repairs": [], "gather_demand": {}, "items": [], "loose": [], "threats": []}
	var stock: Dictionary = sim.settlements.stock_of(id)
	var site_need: Dictionary = {}
	for site_id in sim.construction.in_settlement(id):
		var missing: Dictionary = sim.construction.missing(site_id)
		board.builds.append({"site": site_id, "ready": sim.construction.ready_to_build(site_id), "missing": missing})
		for resource in missing:
			site_need[resource] = int(site_need.get(resource, 0)) + int(missing[resource])
	var loose: Dictionary = {}
	# Loose goods are worth hauling only when a chest has room for them (a
	# granary bin has room only for grain).
	var room: Dictionary = {}
	for item_id in _sorted(sim.items.keys()):
		var item: Dictionary = sim.items[item_id]
		if _distance(item.cell, settlement.center) <= float(settlement.radius):
			board.loose.append(item_id)
			if not room.has(item.resource):
				room[item.resource] = sim.settlements.room_for(sim, id, item.resource) > 0
			if room[item.resource]:
				board.items.append(item_id)
			loose[item.resource] = float(loose.get(item.resource, 0.0)) + float(item.amount)
	var residents: int = settlement.residents.size()
	board["alchemy"] = Alchemy.workshops(sim, id)
	board["smithies"] = Crafts.stations(sim, id, "smithy")
	# Herbs for the preparations still to refine, ore for the anvil's tools.
	var crafts: Dictionary = Alchemy.herbs_wanted(sim, id) if not board.alchemy.is_empty() else {}
	if not board.smithies.is_empty():
		crafts["ore"] = Crafts.tools_short(sim, id)
	# Before winter, people want food put by for the months without berries.
	var autumn: bool = sim.calendar.season() == int(Balance.number("settlements.autumn_season"))
	for resource in RESOURCES:
		var reserve: Array = RESERVE[resource]
		var per_person: float = Balance.number("settlements.autumn_berries_per_person") if autumn and resource == "berries" else float(reserve[1])
		var wanted: float = float(reserve[0]) + per_person * residents + float(site_need.get(resource, 0)) + float(crafts.get(resource, 0))
		var have: float = float(stock.get(resource, 0)) + float(loose.get(resource, 0.0))
		# Berries stand for food: grain and meals in the chests count toward them.
		if resource == "berries":
			have = (Food.worth(stock) + Food.worth(loose)) / Food.value("berries")
		if wanted > 0.0:
			board.gather_demand[resource] = clampf((wanted - have) / wanted, 0.0, 1.0)
	if sim.settlement_life != null:
		board.repairs = sim.settlement_life.repairs_for(sim, id)
	for threat in sim.threats_list():
		if _distance(threat.cell, settlement.center) <= float(settlement.radius) + 8.0:
			board.threats.append(threat.id)
	board["housing_deficit"] = housing_deficit(sim, id)
	board["plots"] = plots(sim, id)
	board["ripe"] = ripe(sim, id)
	board["fields"] = fields(sim, id)
	board["kitchens"] = kitchens(sim, id)
	# Where the woods near home are thin, open ground at the edge to plant.
	board["woods_thin"] = Woods.thinness(sim, settlement)
	board["groves"] = Woods.grove_spots(sim, settlement) if float(board.woods_thin) > 0.0 else []
	return board


## The settlement's kitchens by structure id, in id order.
static func kitchens(sim: RefCounted, id: int) -> Array:
	var result: Array = []
	for entry in sim.settlements.structures_in(sim, id):
		if entry.functions.has("kitchen"):
			result.append(int(entry.id))
	return result


## Fields with work in them, by structure id: {id, ripe, tend, sow}, each a
## few crop cells in a stable order. Sowing is listed only while a crop sown
## now would ripen before winter.
static func fields(sim: RefCounted, id: int) -> Array:
	var result: Array = []
	var most: int = Balance.integer("farming.board_cells")
	var sowing: bool = Crops.can_sow(sim, Crops.staple())
	for entry in sim.settlements.structures_in(sim, id):
		if not entry.functions.has("field"):
			continue
		var cells: Array = entry.components.get("farmland", []).duplicate()
		cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return [a.y, a.z, a.x] < [b.y, b.z, b.x])
		var work: Dictionary = {"id": int(entry.id), "ripe": [], "tend": [], "sow": [], "size": cells.size()}
		for ground in cells:
			var cell: Vector3i = ground + Vector3i.UP
			if sim.crops.is_ripe(sim, cell):
				if work.ripe.size() < most:
					work.ripe.append(cell)
			elif sim.crops.needs_tending(sim, cell):
				if work.tend.size() < most:
					work.tend.append(cell)
			elif sowing and work.sow.size() < most and Crops.open_plot(sim, cell):
				work.sow.append(cell)
		if not work.ripe.is_empty() or not work.tend.is_empty() or not work.sow.is_empty():
			result.append(work)
	return result


## Garden bushes worth picking: [garden id, bush site id], a few at most.
static func ripe(sim: RefCounted, id: int) -> Array:
	var result: Array = []
	var least: int = Balance.integer("world.garden_pick_at")
	for entry in sim.settlements.structures_in(sim, id):
		if not entry.functions.has("garden"):
			continue
		var cells: Array = entry.components.get("planter", []).duplicate()
		cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return [a.y, a.z, a.x] < [b.y, b.z, b.x])
		for planter in cells:
			var site: int = int(sim.sites.by_cell.get(planter + Vector3i.UP, -1))
			if site >= 0 and sim.voxels.block_meta(planter + Vector3i.UP) >= least:
				result.append([int(entry.id), site])
				if result.size() >= 6:
					return result
	return result


## Empty planters in the settlement's gardens: [garden id, cell above], a
## few at most, in a stable order.
static func plots(sim: RefCounted, id: int) -> Array:
	var result: Array = []
	for entry in sim.settlements.structures_in(sim, id):
		if not entry.functions.has("garden"):
			continue
		var cells: Array = entry.components.get("planter", []).duplicate()
		cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return [a.y, a.z, a.x] < [b.y, b.z, b.x])
		for planter in cells:
			var above: Vector3i = planter + Vector3i.UP
			if sim.voxels.get_block(above) == 0 and not sim.is_reserved_cell(above):
				result.append([int(entry.id), above])
				if result.size() >= 6:
					return result
	return result


## People in the settlement without a bed of their own.
static func housing_deficit(sim: RefCounted, id: int) -> int:
	var count: int = 0
	for agent_id in sim.settlements.entries[id].residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present() and agent.home < 0:
			count += 1
	return count


static func _sorted(keys: Array) -> Array:
	keys.sort()
	return keys


static func _distance(a: Vector3i, b: Vector3i) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
