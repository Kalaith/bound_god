extends RefCounted
## The slow life of settlements: job boards every 10 ticks, and each day
## culture weights drift, settlements grow, stalled sites are abandoned and
## finished buildings remember their layout so they can be repaired.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const JobBoard = preload("res://scripts/sim/job_board.gd")

## settlement id -> job board
var boards: Dictionary = {}
## settlement id -> {work type -> samples} of what respected people did today
var samples: Dictionary = {}
## structure id -> {template_id, settlement_id, layout: Array of [cell, block, meta], built_tick}
var layouts: Dictionary = {}


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
	_abandon(sim)


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
	return {"layouts": layouts.duplicate(true), "samples": samples.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	layouts = data.layouts
	samples = data.samples
	boards.clear()
