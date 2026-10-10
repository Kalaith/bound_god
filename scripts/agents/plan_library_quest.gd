extends RefCounted
## Plans for the god's requests and for restoring shrines: travelling to a
## place and telling its people of the god, bringing materials, repairing a
## fallen altar from its old layout, and setting up a new altar.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const JobBoard = preload("res://scripts/sim/job_board.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")

const Op = Plans.Op
const T = Plans.T
const Topic = Plans.Topic


static func plans(sim: RefCounted, agent: RefCounted, goal: Dictionary, request: Dictionary) -> Array:
	if int(goal.kind) == Goals.Kind.RESTORE_SHRINE:
		return restore(sim, agent, int(goal.target))
	if int(goal.kind) == Goals.Kind.PREACH:
		var listener: int = int(goal.target)
		return [H.option("tell_the_story", 1.0, [Plans.go_to(Plans.target(T.AGENT, listener)), Plans.step(Op.TALK, {"with": listener, "topic": Topic.STORY})])]
	if request.is_empty():
		return []
	match str(request.kind):
		"carry_name":
			return _carry_name(sim, agent, int(request.target))
		"bring":
			return _bring(sim, agent, request)
		"restore_shrine":
			return restore(sim, agent, int(request.target))
		"raise_shrine":
			return _raise(sim, agent, int(request.target))
	return []


## Someone in `settlement_id` the person could tell of the god, or -1.
static func listener_in(sim: RefCounted, agent: RefCounted, settlement_id: int, reach: float) -> int:
	var best: int = -1
	var best_distance: float = INF
	for other in sim.agents:
		if other.id == agent.id or not other.available_to_talk() or other.settlement_id != settlement_id:
			continue
		if FaithState.stage(other.faith) >= FaithState.stage(agent.faith):
			continue
		var d: float = H.distance(other.cell, agent.cell)
		if d < reach and d < best_distance:
			best = other.id
			best_distance = d
	return best


static func _carry_name(sim: RefCounted, agent: RefCounted, settlement_id: int) -> Array:
	var settlement: Dictionary = sim.settlements.get_settlement(settlement_id)
	if settlement.is_empty():
		return []
	var there: bool = Vector2(agent.cell.x - settlement.center.x, agent.cell.z - settlement.center.z).length() <= float(settlement.radius)
	if not there:
		return [H.option("travel_there", 1.0, [Plans.go_cell(settlement.camp), Plans.step(Op.WAIT, {"ticks": 5})])]
	var listener: int = listener_in(sim, agent, settlement_id, 40.0)
	var result: Array = []
	if listener >= 0:
		result.append(H.option("tell_the_story", 1.0, [Plans.go_to(Plans.target(T.AGENT, listener)), Plans.step(Op.TALK, {"with": listener, "topic": Topic.STORY})]))
	var around: Vector3i = sim.nav.nearest_walkable(settlement.center + Vector3i(posmod(sim.calendar.tick / 30, 7) - 3, 0, posmod(sim.calendar.tick / 47, 7) - 3), 4)
	if around.x >= 0:
		result.append(H.option("seek_listeners", 0.5, [Plans.go_cell(around), Plans.step(Op.WAIT, {"ticks": 20})]))
	return result


static func _bring(sim: RefCounted, agent: RefCounted, request: Dictionary) -> Array:
	var resource: String = request.resource
	var shrine: Dictionary = sim.faith.get_shrine(int(request.shrine_id))
	var store := Plans.go_to(Plans.target(T.STORE, int(shrine.get("settlement_id", agent.settlement_id))))
	var result: Array = []
	if agent.carried(resource) >= 1.0:
		result.append(H.option("deliver_offering", 1.2, [store, Plans.step(Op.DEPOSIT)]))
	var sites: Array = H.known_sites(sim, agent, JobBoard.SITE_KIND.get(resource, ""))
	if not sites.is_empty():
		result.append(H.option("gather_offering", 1.0, H.free_hands(agent, resource) + [Plans.go_to(Plans.target(T.SITE, sites[0])),
			Plans.step(Op.HARVEST, {"site": sites[0]}), store, Plans.step(Op.DEPOSIT)]))
	return result


## Bring stone and put the shrine's old blocks back, the altar first.
static func restore(sim: RefCounted, agent: RefCounted, shrine_id: int) -> Array:
	var shrine: Dictionary = sim.faith.get_shrine(shrine_id)
	if shrine.is_empty():
		return []
	var go := Plans.go_to(Plans.target(T.SHRINE, shrine_id))
	var mend := Plans.step(Op.REPAIR_BLOCK, {"shrine": shrine_id})
	var result: Array = []
	if agent.carried("stone") >= 1.0:
		result.append(H.option("restore_altar", 1.2, [go, mend]))
	if agent.beliefs.believes_stock("stone"):
		result.append(H.option("fetch_stone_for_altar", 1.0, H.free_hands(agent, "stone") + [Plans.go_to(Plans.target(T.STORE, agent.settlement_id)),
			Plans.step(Op.TAKE_STOCK, {"resource": "stone", "amount": 6}), go, mend]))
	var rocks: Array = H.known_sites(sim, agent, "rock")
	if not rocks.is_empty():
		result.append(H.option("quarry_for_altar", 0.8, H.free_hands(agent, "stone") + [Plans.go_to(Plans.target(T.SITE, rocks[0])),
			Plans.step(Op.HARVEST, {"site": rocks[0]}), go, mend]))
	return result


## Set up a simple altar under the open sky at the heart of a settlement.
static func _raise(sim: RefCounted, agent: RefCounted, settlement_id: int) -> Array:
	var settlement: Dictionary = sim.settlements.get_settlement(settlement_id)
	if settlement.is_empty():
		return []
	var spot: Vector3i = sim.nav.nearest_walkable(settlement.camp + Vector3i(3, 0, 3), 4)
	if spot.x < 0:
		return []
	var place := Plans.step(Op.REPAIR_BLOCK, {"altar_at": spot})
	var result: Array = []
	if agent.carried("stone") >= 1.0:
		result.append(H.option("set_up_altar", 1.2, [Plans.go_cell(spot + Vector3i(1, 0, 0)), place]))
	var rocks: Array = H.known_sites(sim, agent, "rock")
	if not rocks.is_empty():
		result.append(H.option("quarry_for_altar", 0.8, H.free_hands(agent, "stone") + [Plans.go_to(Plans.target(T.SITE, rocks[0])),
			Plans.step(Op.HARVEST, {"site": rocks[0], "once": 1}), Plans.go_cell(spot + Vector3i(1, 0, 0)), place]))
	return result
