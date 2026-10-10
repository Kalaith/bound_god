extends RefCounted
## Social plans: conversations of each kind, helping someone who asked,
## mental breaks, and moving to another settlement or leaving the valley.
const Balance = preload("res://scripts/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")

const Kind = Goals.Kind
const Op = Plans.Op
const T = Plans.T
const Topic = Plans.Topic


static func _to(id: int) -> Dictionary:
	return Plans.go_to(Plans.target(T.AGENT, id))


static func plans(sim: RefCounted, agent: RefCounted, goal: Dictionary) -> Array:
	var target: int = int(goal.target)
	match int(goal.kind):
		Kind.CHAT:
			var lashing: bool = not agent.mental_break.is_empty() and int(agent.mental_break.kind) == Goals.BreakKind.LASH_OUT
			if lashing:
				return [H.option("pick_a_fight", 1.0, [_to(target), Plans.step(Op.TALK, {"with": target, "topic": Topic.INSULT})])]
			return [H.option("chat", 1.0, [_to(target), Plans.step(Op.TALK, {"with": target, "topic": Topic.SMALL_TALK})])]
		Kind.COMFORT:
			return [H.option("comfort", 1.0, [_to(target), Plans.step(Op.TALK, {"with": target, "topic": Topic.COMFORT})])]
		Kind.COURT:
			return [H.option("court", 1.0, [_to(target), Plans.step(Op.TALK, {"with": target, "topic": Topic.FLIRT})])]
		Kind.RECONCILE:
			return [H.option("make_peace", 1.0, [_to(target), Plans.step(Op.TALK, {"with": target, "topic": Topic.RECONCILE})])]
		Kind.HELP:
			return _help(sim, agent, target, int(goal.extra))
		Kind.BREAK:
			return _break(sim, agent, target)
		Kind.MIGRATE:
			return _migrate(sim, agent, target, int(goal.extra) == 1)
	return []


static func _help(sim: RefCounted, agent: RefCounted, requester: int, need: int) -> Array:
	var result: Array = []
	match need:
		Goals.HelpNeed.FOOD:
			var give := Plans.step(Op.GIVE, {"to": requester})
			if agent.carried("berries") >= 1.0:
				result.append(H.option("hand_over_food", 1.2, [_to(requester), give]))
			if agent.beliefs.believes_stock("berries"):
				result.append(H.option("fetch_food", 1.0, H.free_hands(agent, "berries") + [Plans.go_to(Plans.target(T.STORE, agent.settlement_id)),
					Plans.step(Op.TAKE_STOCK, {"resource": "berries", "amount": 2}), _to(requester), give]))
			var bushes: Array = H.known_sites(sim, agent, "bush")
			if not bushes.is_empty():
				result.append(H.option("forage_for_friend", 0.6, H.free_hands(agent, "berries") + [Plans.go_to(Plans.target(T.SITE, bushes[0])),
					Plans.step(Op.HARVEST, {"site": bushes[0], "once": 1}), _to(requester), give]))
		Goals.HelpNeed.CARE:
			result.append(H.option("tend_wounds", 1.0, [_to(requester), Plans.step(Op.TREAT, {"to": requester})]))
		Goals.HelpNeed.DEFENCE:
			result.append(H.option("defend_friend", 1.0, [Plans.step(Op.ATTACK, {"threat": -1, "near": requester})]))
	return result


static func _break(sim: RefCounted, agent: RefCounted, kind: int) -> Array:
	var ticks: int = Balance.integer("mood.break_ticks")
	match kind:
		Goals.BreakKind.BINGE:
			if agent.settlement_id >= 0 and sim.settlements.amount(agent.settlement_id, "berries") > 0:
				return [H.option("binge", 1.0, H.free_hands(agent, "berries") + [Plans.go_to(Plans.target(T.STORE, agent.settlement_id)),
					Plans.step(Op.TAKE_STOCK, {"resource": "berries", "amount": 4}), Plans.step(Op.BREAK, {"ticks": ticks})])]
			return [H.option("sulk", 1.0, [Plans.step(Op.BREAK, {"ticks": ticks})])]
		Goals.BreakKind.WANDER:
			return [H.option("wander_off", 1.0, [Plans.go_cell(H.wander_cell(sim, agent)), Plans.step(Op.BREAK, {"ticks": ticks})])]
	return [H.option("sulk", 1.0, [Plans.step(Op.BREAK, {"ticks": ticks})])]


static func _migrate(sim: RefCounted, agent: RefCounted, settlement_id: int, departing: bool) -> Array:
	var settlement: Dictionary = sim.settlements.get_settlement(settlement_id)
	var result: Array = []
	if not settlement.is_empty():
		result.append(H.option("move_there", 1.0, [Plans.go_cell(settlement.camp), Plans.step(Op.JOIN, {"settlement": settlement_id})]))
	var edge: Vector3i = valley_edge(sim, agent) if departing else Vector3i(-1, -1, -1)
	if edge.x >= 0:
		result.append(H.option("leave_the_valley", 0.2, [Plans.go_cell(edge), Plans.step(Op.LEAVE)]))
	return result


## The nearest walkable cell near the valley's rim, where people leave it.
static func valley_edge(sim: RefCounted, agent: RefCounted) -> Vector3i:
	var size: Vector3i = sim.voxels.size
	var candidates: Array = [Vector2i(agent.cell.x, 18), Vector2i(agent.cell.x, size.z - 19), Vector2i(18, agent.cell.z), Vector2i(size.x - 19, agent.cell.z)]
	var best := Vector3i(-1, -1, -1)
	var best_distance: float = INF
	for column in candidates:
		var cell: Vector3i = sim.nav.surface(column.x, column.y)
		if cell.x >= 0 and H.distance(cell, agent.cell) < best_distance:
			best = cell
			best_distance = H.distance(cell, agent.cell)
	return best
