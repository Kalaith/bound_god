extends RefCounted
## Where relics lie (M21). A great cultivator's relic is laid at the living
## shrine of the settlement they die in when that is a branch's (a cutting or
## altar away from the tree), otherwise at the tree, as before. Relics steady
## trials faced near the shrine they lie at. When a branch's shrine falls or
## its settlement empties, its relics lie in the ruins (`lost`) until a
## believer who knows the place carries them to a shrine of their own (goal
## RECOVER_RELIC), chronicled with where they came from.
## A relic is {name, realm, tick, shrine: shrine id, lost: bool, carried: agent id or -1};
## older relics without `shrine` lie at the tree.
const Balance = preload("res://scripts/core/balance.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const Mind = preload("res://scripts/agents/mind.gd")


## The sacred tree's shrine id, or -1.
static func tree_shrine(sim: RefCounted) -> int:
	if sim.faith == null:
		return -1
	for id in sim.faith.ids():
		if str(sim.faith.shrines[id].kind) == "tree":
			return id
	return -1


static func shrine_of(sim: RefCounted, relic: Dictionary) -> int:
	return int(relic.get("shrine", tree_shrine(sim)))


## Whether a relic lies at a shrine now (not lost in ruins, not in someone's hands).
static func lies(relic: Dictionary) -> bool:
	return not bool(relic.get("lost", false)) and int(relic.get("carried", -1)) < 0


## Relics lying at a shrine.
static func at(sim: RefCounted, shrine_id: int) -> Array:
	var result: Array = []
	if sim.tree_growth == null:
		return result
	for relic in sim.tree_growth.relics:
		if lies(relic) and shrine_of(sim, relic) == shrine_id:
			result.append(relic)
	return result


## Where someone dying here leaves their relic: their settlement's living
## shrine when it is not the tree's, else the tree.
static func shrine_for(sim: RefCounted, agent: RefCounted) -> int:
	var tree: int = tree_shrine(sim)
	var tree_settlement: int = int(sim.faith.shrines[tree].settlement_id) if tree >= 0 else -1
	if agent.settlement_id >= 0 and agent.settlement_id != tree_settlement:
		for id in sim.settlements.get_settlement(agent.settlement_id).get("shrine_ids", []):
			var shrine: Dictionary = sim.faith.get_shrine(int(id))
			if not shrine.is_empty() and str(shrine.state) != "fallen" and str(shrine.kind) != "tree":
				return int(id)
	return tree


## How many relics steady a trial faced at `cell` beyond the tree: those lying
## at a living branch shrine within reach of it.
static func branch_count(sim: RefCounted, cell: Vector3i) -> int:
	if sim.faith == null:
		return 0
	var reach: float = Balance.number("branches.relic_reach")
	var count: int = 0
	for id in sim.faith.ids():
		var shrine: Dictionary = sim.faith.shrines[id]
		if str(shrine.kind) == "tree" or str(shrine.state) == "fallen":
			continue
		if Vector2(cell.x - shrine.cell.x, cell.z - shrine.cell.z).length() <= reach:
			count += at(sim, int(id)).size()
	return count


## A shrine whose relics are left in ruins: fallen, or nobody lives there.
static func _abandoned(sim: RefCounted, shrine: Dictionary) -> bool:
	if str(shrine.state) == "fallen":
		return true
	for agent_id in sim.settlements.get_settlement(int(shrine.settlement_id)).get("residents", []):
		if sim.agents[agent_id].is_present():
			return false
	return true


## Daily: relics at a fallen or emptied branch shrine are left in its ruins.
static func daily(sim: RefCounted) -> void:
	if sim.tree_growth == null or sim.faith == null:
		return
	var tree: int = tree_shrine(sim)
	var left: Dictionary = {}
	for relic in sim.tree_growth.relics:
		var id: int = shrine_of(sim, relic)
		if id == tree or not lies(relic):
			continue
		var shrine: Dictionary = sim.faith.get_shrine(id)
		if shrine.is_empty() or _abandoned(sim, shrine):
			relic["lost"] = true
			left[id] = int(left.get(id, 0)) + 1
	var ids: Array = left.keys()
	ids.sort()
	for id in ids:
		var shrine: Dictionary = sim.faith.get_shrine(id)
		var cause: String = "cause_shrine_fell" if not shrine.is_empty() and str(shrine.state) == "fallen" else "cause_nobody_left"
		sim.chronicle_event("relics_lost", int(shrine.get("settlement_id", -1)), {"shrine": str(shrine.get("name", "")), "count": left[id]}, cause)


## Shrines whose relics lie in ruins, in id order.
static func ruins(sim: RefCounted) -> Array:
	var result: Array = []
	if sim.tree_growth == null:
		return result
	for relic in sim.tree_growth.relics:
		var id: int = shrine_of(sim, relic)
		if bool(relic.get("lost", false)) and int(relic.get("carried", -1)) < 0 and not result.has(id):
			result.append(id)
	result.sort()
	return result


## A believer weighs carrying relics home from ruins they know of, to a
## living shrine of their own: {utility, from, to} or {}.
static func recovery(sim: RefCounted, agent: RefCounted) -> Dictionary:
	if agent.is_child or not agent.faith.get("knows", false) or not FaithState.is_believer(agent.faith) or Schedule.is_sleep_time(sim, agent):
		return {}
	var home: int = shrine_home(sim, agent)
	if home < 0:
		return {}
	for id in ruins(sim):
		if not agent.beliefs.places.has("shrine:%d" % id) or id == home:
			continue
		# Someone else is already on the way.
		if not sim.pursuers(_key(id)).is_empty() and not sim.pursuers(_key(id)).has(agent.id):
			continue
		var utility: float = Balance.number("branches.recover_pull") * (0.5 + float(agent.faith.devotion) / 100.0) * agent.capacity()
		return {"utility": utility, "from": id, "to": home}
	return {}


static func _key(shrine_id: int) -> int:
	return (int(preload("res://scripts/agents/goals.gd").Kind.RECOVER_RELIC) << 32) | (shrine_id & 0xffffffff)


## The living shrine a person would lay relics at: their settlement's, or the tree.
static func shrine_home(sim: RefCounted, agent: RefCounted) -> int:
	for id in sim.settlements.get_settlement(agent.settlement_id).get("shrine_ids", []):
		var shrine: Dictionary = sim.faith.get_shrine(int(id))
		if not shrine.is_empty() and str(shrine.state) != "fallen":
			return int(id)
	return tree_shrine(sim)


## The bearer takes up every relic lying in the ruins of shrine `from`.
static func take(sim: RefCounted, agent: RefCounted, from: int) -> int:
	var count: int = 0
	for relic in sim.tree_growth.relics:
		if bool(relic.get("lost", false)) and int(relic.get("carried", -1)) < 0 and shrine_of(sim, relic) == from:
			relic["carried"] = agent.id
			count += 1
	return count


## The bearer lays what they carry at shrine `to`.
static func lay(sim: RefCounted, agent: RefCounted, to: int) -> int:
	var count: int = 0
	var from: String = ""
	for relic in sim.tree_growth.relics:
		if int(relic.get("carried", -1)) != agent.id:
			continue
		from = str(sim.faith.get_shrine(shrine_of(sim, relic)).get("name", ""))
		relic["shrine"] = to
		relic["lost"] = false
		relic["carried"] = -1
		count += 1
	if count > 0:
		var shrine: Dictionary = sim.faith.get_shrine(to)
		Mind.add(agent, "carried_relics", sim.calendar.ticks_per_day)
		sim.chronicle_event("relics_carried", int(shrine.settlement_id), {"name": agent.full_name(), "count": count, "shrine": str(shrine.name)},
			"cause_relics_from|%s" % from, [agent.id])
	return count


## Someone who dies or leaves while carrying relics drops them where they are:
## they stay lost, at the ruin they came from.
static func drop(sim: RefCounted, agent: RefCounted) -> void:
	if sim.tree_growth == null:
		return
	for relic in sim.tree_growth.relics:
		if int(relic.get("carried", -1)) == agent.id:
			relic["carried"] = -1


## While abstract: a believer of a living shrine who knows each ruin carries
## its relics home now and then.
static func abstract_day(sim: RefCounted) -> void:
	for id in ruins(sim):
		for agent in sim.agents:
			if not agent.is_present() or agent.is_child or not agent.beliefs.places.has("shrine:%d" % id) or not FaithState.is_believer(agent.faith):
				continue
			var home: int = shrine_home(sim, agent)
			if home < 0 or home == id or sim.rng.randf() >= Balance.number("branches.abstract_recover"):
				break
			if take(sim, agent, id) > 0:
				lay(sim, agent, home)
			break
