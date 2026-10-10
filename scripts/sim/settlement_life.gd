extends RefCounted
## The slow life of settlements: job boards every 10 ticks, and each day
## culture weights drift, settlements grow, stalled sites are abandoned and
## finished buildings remember their layout so they can be repaired.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const JobBoard = preload("res://scripts/sim/job_board.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Construction = preload("res://scripts/sim/construction.gd")
const Standing = preload("res://scripts/sim/standing.gd")

## settlement id -> job board
var boards: Dictionary = {}
## settlement id -> {work type -> samples} of what respected people did today
var samples: Dictionary = {}
## structure id -> {template_id, settlement_id, layout: Array of [cell, block, meta], built_tick}
var layouts: Dictionary = {}
## "settlement:template" -> tick until which a failed site search is not retried
var no_site_until: Dictionary = {}
## While the valley passes abstractly no block is touched: structure id ->
## blocks decay has taken, applied when the valley materialises.
var pending_decay: Dictionary = {}


func board(id: int) -> Dictionary:
	return boards.get(id, {})


func refresh_jobs(sim: RefCounted) -> void:
	for id in sim.settlements.ids():
		var settlement: Dictionary = sim.settlements.entries[id]
		boards[id] = JobBoard.refresh(sim, settlement)
		_sample(sim, settlement)


## The three most respected residents set an example by what they do.
func _sample(sim: RefCounted, settlement: Dictionary) -> void:
	var respect: Array = []
	for agent_id in settlement.residents:
		var score: float = 0.0
		for other_id in settlement.residents:
			if other_id != agent_id:
				score += sim.agents[other_id].beliefs.opinion_of(agent_id)
		if sim.agents[agent_id].has_trait("leader"):
			score *= 2.0
		respect.append([agent_id, score])
	respect.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1] > b[1]
		return a[0] < b[0])
	var tally: Dictionary = samples.get(settlement.id, {})
	for i in range(mini(3, respect.size())):
		var goal: Dictionary = sim.agents[respect[i][0]].current_goal()
		var work: String = Goals.work_type(goal) if not goal.is_empty() else ""
		if not work.is_empty():
			tally[work] = int(tally.get(work, 0)) + 1
	samples[settlement.id] = tally


func daily(sim: RefCounted) -> void:
	for id in sim.settlements.ids():
		var settlement: Dictionary = sim.settlements.entries[id]
		_grow(sim, settlement)
		_drift(sim, settlement)
	samples.clear()
	Standing.daily(sim)
	_make_do(sim)
	_abandon(sim)
	_decay(sim)
	_overgrow(sim)


func _grow(sim: RefCounted, settlement: Dictionary) -> void:
	var count: int = 0
	for entry in sim.structures.built():
		if Vector2(entry.anchor.x - settlement.center.x, entry.anchor.z - settlement.center.z).length() <= float(settlement.radius):
			count += 1
	settlement.radius = minf(Balance.number("settlements.start_radius") + count * Balance.number("settlements.radius_per_structure"),
		Balance.number("settlements.max_radius"))


## Each weight moves toward what the settlement needs and toward what its
## respected members spent the day doing.
func _drift(sim: RefCounted, settlement: Dictionary) -> void:
	var board_now: Dictionary = boards.get(settlement.id, {})
	var residents: int = maxi(settlement.residents.size(), 1)
	var demand: float = 0.0
	for resource in board_now.get("gather_demand", {}):
		demand = maxf(demand, float(board_now.gather_demand[resource]))
	var pull: Dictionary = {
		"build": 1.0 + minf(float(board_now.get("housing_deficit", 0)) / residents, 1.0) * 0.6 + (0.2 if not board_now.get("builds", []).is_empty() else 0.0),
		"gather": 0.7 + demand * 0.8,
		"haul": 0.8 + minf(board_now.get("items", []).size() / 4.0, 1.0) * 0.5,
		"defend": 0.8 + (0.6 if not board_now.get("threats", []).is_empty() else 0.0),
		"scout": 0.9,
		"farm": 0.8 + (0.4 if not board_now.get("fields", []).is_empty() else 0.0) + (0.5 if Standing.fear_of_winter(sim, settlement.id) else 0.0),
	}
	var tally: Dictionary = samples.get(settlement.id, {})
	var total: int = 0
	for work in tally:
		total += int(tally[work])
	var low: float = Balance.number("settlements.culture_min")
	var high: float = Balance.number("settlements.culture_max")
	for work in Goals.WORK_TYPES:
		var weight: float = float(settlement.culture.get(work, 1.0))
		weight += (float(pull[work]) - weight) * Balance.number("settlements.culture_need_drift")
		if total > 0:
			var example: float = low + (high - low) * float(tally.get(work, 0)) / total
			weight += (example - weight) * Balance.number("settlements.culture_example_drift")
		settlement.culture[work] = clampf(weight, low, high)


## Builders who wait a day for stone nobody has or knows where to find raise
## the rest of the walls in planks. Only plain walling changes: a hearth or
## an altar is still stone, so the building keeps its function.
func _make_do(sim: RefCounted) -> void:
	var day: int = sim.calendar.ticks_per_day
	for id in sim.construction.ids():
		var site: Dictionary = sim.construction.get_site(id)
		var settlement_id: int = int(site.settlement_id)
		if not sim.construction.missing(id).has("stone") or sim.calendar.tick - int(site.last_progress_tick) < day:
			continue
		if sim.settlements.amount(settlement_id, "stone") > 0 or _stone_known(sim, settlement_id):
			continue
		if Construction.in_timber(site.order, int(site.cursor)) > 0:
			site["made_do"] = true
			sim.chronicle_event("site_made_do", settlement_id, {"design": sim.template_name(site.template_id)}, "cause_no_stone", [int(site.founder)])


## Whether anyone in the settlement has stone to hand or knows a place for it
## within a short walk.
func _stone_known(sim: RefCounted, settlement_id: int) -> bool:
	for item_id in sim.items:
		var item: Dictionary = sim.items[item_id]
		if item.resource == "stone" and sim.settlements.at_cell(item.cell) == settlement_id:
			return true
	for agent_id in sim.settlements.entries[settlement_id].residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present() and Construction.knows_stone_near(sim, agent):
			return true
	return false


func _abandon(sim: RefCounted) -> void:
	var limit: int = sim.calendar.ticks_for_days(Balance.number("construction.abandon_days"))
	for id in sim.construction.ids():
		var site: Dictionary = sim.construction.get_site(id)
		if sim.calendar.tick - int(site.last_progress_tick) < limit:
			continue
		for resource in site.delivered:
			sim.drop_item(site.origin, resource, float(site.delivered[resource]))
		sim.chronicle_event("site_abandoned", int(site.settlement_id), {"design": sim.template_name(site.template_id)}, "cause_stalled", [int(site.founder)])
		sim.construction.release(id)


## Buildings nobody lives in or mends lose a block now and then. A hall, a
## garden or a storehouse is nobody's home: it is kept up while people live
## in its settlement.
func _decay(sim: RefCounted) -> void:
	var now: int = sim.calendar.tick
	var limit: int = sim.calendar.ticks_for_days(Balance.number("decay.unattended_days"))
	var keys: Array = layouts.keys()
	keys.sort()
	for id in keys:
		var record: Dictionary = layouts[id]
		var entry: Dictionary = sim.structures.entries.get(id, {})
		if not entry.is_empty() and (not entry.residents.is_empty() or _common_and_kept(sim, entry)):
			record["attended_tick"] = now
			continue
		if now - int(record.get("attended_tick", record.built_tick)) < limit:
			continue
		if sim.rng.randf() >= Balance.number("decay.block_loss_chance"):
			continue
		var standing: Array = []
		for part in record.layout:
			if part[1] != 0 and sim.voxels.get_block(part[0]) == part[1]:
				standing.append(part)
		# A building fallen to nothing is no longer remembered.
		if standing.is_empty():
			layouts.erase(id)
			continue
		if sim.meditating:
			pending_decay[id] = int(pending_decay.get(id, 0)) + 1
		else:
			var part: Array = standing[sim.rng.randi_range(0, standing.size() - 1)]
			sim.set_block(part[0], 0, 0, "decay")
		if not record.get("decaying", false):
			record["decaying"] = true
			sim.chronicle_event("structure_decaying", int(record.settlement_id), {"design": sim.template_name(record.template_id)}, "cause_unattended")


static func _common_and_kept(sim: RefCounted, entry: Dictionary) -> bool:
	if entry.functions.has("dwelling"):
		return false
	var id: int = sim.settlements.at_cell(entry.anchor)
	if id < 0:
		return false
	for agent_id in sim.settlements.entries[id].residents:
		if sim.agents[agent_id].is_present():
			return true
	return false


## The decay the abstract years took, all at once: blocks of each building
## gone, chosen as the daily decay would have chosen them.
func apply_pending_decay(sim: RefCounted) -> void:
	var batch: Array = []
	var ids: Array = pending_decay.keys()
	ids.sort()
	for id in ids:
		var record: Dictionary = layouts.get(id, {})
		if record.is_empty():
			continue
		var standing: Array = []
		for part in record.layout:
			if part[1] != 0 and sim.voxels.get_block(part[0]) == part[1]:
				standing.append(part)
		for _i in range(mini(int(pending_decay[id]), standing.size())):
			var index: int = sim.rng.randi_range(0, standing.size() - 1)
			batch.append([standing[index][0], 0, 0])
			standing.remove_at(index)
	pending_decay.clear()
	sim.set_blocks(batch, "decay")


## A settlement with nobody left is taken back by the grass.
func _overgrow(sim: RefCounted) -> void:
	# While abstract nothing grows over; the grass waits for the valley's return.
	if sim.meditating:
		return
	var grass: int = Registry.id("tall_grass")
	var turf: int = Registry.id("grass")
	for id in sim.settlements.ids():
		var settlement: Dictionary = sim.settlements.entries[id]
		var empty: bool = true
		for agent_id in settlement.residents:
			empty = empty and not sim.agents[agent_id].is_present()
		if not empty:
			settlement["empty_since"] = -1
			continue
		if int(settlement.get("empty_since", -1)) < 0:
			settlement["empty_since"] = sim.calendar.tick
		if sim.calendar.tick - int(settlement.empty_since) < sim.calendar.ticks_for_days(Balance.number("decay.abandoned_days")):
			continue
		if not settlement.get("abandoned", false):
			settlement["abandoned"] = true
			sim.chronicle_event("settlement_abandoned", id, {"place": settlement.name}, "cause_nobody_left")
		for _i in range(6):
			var x: int = settlement.center.x + sim.rng.randi_range(-int(settlement.radius), int(settlement.radius))
			var z: int = settlement.center.z + sim.rng.randi_range(-int(settlement.radius), int(settlement.radius))
			var top: int = sim.voxels.top_solid_y(x, z)
			var cell := Vector3i(x, top + 1, z)
			if top >= 0 and sim.voxels.get_block(cell - Vector3i(0, 1, 0)) == turf and sim.voxels.get_block(cell) == 0 and not sim.is_occupied(cell):
				sim.set_block(cell, grass, 0, "growth")


## A finished site's design is remembered against the structure it became.
func remember(sim: RefCounted, structure_id: int, site: Dictionary, layout: Array) -> void:
	layouts[structure_id] = {"template_id": site.template_id, "settlement_id": site.settlement_id, "layout": layout, "built_tick": sim.calendar.tick}


## Remembered buildings with blocks missing from their layout.
func repairs_for(sim: RefCounted, settlement_id: int) -> Array:
	var result: Array = []
	var keys: Array = layouts.keys()
	keys.sort()
	for id in keys:
		var record: Dictionary = layouts[id]
		if int(record.settlement_id) != settlement_id:
			continue
		if not missing_blocks(sim, id).is_empty():
			result.append(id)
	return result


func missing_blocks(sim: RefCounted, id: int) -> Array:
	var result: Array = []
	for entry in layouts.get(id, {}).get("layout", []):
		if entry[1] != 0 and sim.voxels.get_block(entry[0]) != entry[1] and sim.voxels.get_block(entry[0]) == 0:
			result.append(entry)
	return result


func to_dict() -> Dictionary:
	return {"layouts": layouts.duplicate(true), "samples": samples.duplicate(true), "no_site_until": no_site_until.duplicate(), "pending_decay": pending_decay.duplicate(),
		"boards": boards.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	layouts = data.layouts
	samples = data.samples
	no_site_until = data.no_site_until
	pending_decay = data.get("pending_decay", {})
	boards = data.boards
