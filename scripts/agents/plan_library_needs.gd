extends RefCounted
## Plans for bodily needs: eating, sleeping, shelter, safety, care and rest.
## Each goal ends with a cheap plan that always applies.
const Balance = preload("res://scripts/core/balance.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const Registry = preload("res://scripts/world/block_registry.gd")

const Op = Plans.Op
const T = Plans.T


static func _store(agent: RefCounted) -> Dictionary:
	return Plans.target(T.STORE, agent.settlement_id)


static func _structure(id: int) -> Dictionary:
	return Plans.go_to(Plans.target(T.STRUCTURE, id))


static func eat(sim: RefCounted, agent: RefCounted) -> Array:
	var plans: Array = []
	if agent.carried("berries") >= 1.0:
		plans.append(H.option("eat_carried", 1.3, [Plans.step(Op.EAT)]))
	if agent.settlement_id >= 0 and agent.beliefs.believes_stock("berries", 1):
		plans.append(H.option("raw_stores", 0.7, H.free_hands(agent, "berries") + [
			Plans.go_to(_store(agent)),
			Plans.step(Op.TAKE_STOCK, {"resource": "berries", "amount": 1}),
			Plans.step(Op.EAT),
		]))
	var loose: int = H.loose_item(sim, agent, "berries")
	if loose >= 0:
		plans.append(H.option("eat_loose", 0.6, H.free_hands(agent, "berries") + [
			Plans.go_cell(sim.items[loose].cell),
			Plans.step(Op.PICK_UP, {"item": loose}),
			Plans.step(Op.EAT),
		]))
	var bushes: Array = H.known_sites(sim, agent, "bush")
	if not bushes.is_empty():
		plans.append(H.option("forage", 0.45, [
			Plans.go_to(Plans.target(T.SITE, bushes[0])),
			Plans.step(Op.FORAGE, {"site": bushes[0]}),
		]))
	var friend: int = H.friend_nearby(sim, agent, 25.0)
	if friend >= 0:
		plans.append(H.option("ask_friend_for_food", 0.2, [
			Plans.step(Op.SEND, {"to": friend, "kind": "request_help", "need": 0}),
			Plans.step(Op.WAIT_FOR_HELP, {"ticks": Balance.integer("agents.help_wait_ticks")}),
			Plans.step(Op.EAT),
		]))
	return plans


static func sleep(sim: RefCounted, agent: RefCounted) -> Array:
	var plans: Array = []
	var home: Dictionary = sim.structures.entries.get(agent.home, {})
	if not home.is_empty() and home.functions.has("dwelling"):
		plans.append(H.option("own_bed", 1.0, [_structure(home.id), Plans.step(Op.SLEEP, {"structure": home.id})]))
	if agent.partner >= 0:
		var partner_home: int = sim.agents[agent.partner].home
		var entry: Dictionary = sim.structures.entries.get(partner_home, {})
		if partner_home != agent.home and not entry.is_empty() and H.free_beds(entry) > 0:
			plans.append(H.option("partner_bed", 1.5, [_structure(partner_home), Plans.step(Op.SLEEP, {"structure": partner_home})]))
	if home.is_empty():
		var bed: int = H.nearest_structure(sim, agent, func(s: Dictionary) -> bool:
			return s.functions.has("dwelling") and H.free_beds(s) > 0)
		if bed >= 0:
			plans.append(H.option("free_bed", 0.8, [_structure(bed), Plans.step(Op.SLEEP, {"structure": bed})]))
	var shelter: int = H.nearest_structure(sim, agent, func(s: Dictionary) -> bool:
		return s.functions.has("shelter") and s.closed)
	if shelter >= 0:
		plans.append(H.option("sleep_in_shelter", 0.5, [_structure(shelter), Plans.step(Op.SLEEP, {"structure": -1})]))
	var canopy: Vector3i = covered_cell(sim, agent)
	if canopy.x >= 0:
		plans.append(H.option("sleep_under_trees", 0.3, [Plans.go_cell(canopy), Plans.step(Op.SLEEP, {"structure": -1})]))
	plans.append(H.option("sleep_rough", 0.15, [Plans.step(Op.SLEEP, {"structure": -1})]))
	return plans


static func shelter(sim: RefCounted, agent: RefCounted) -> Array:
	var plans: Array = []
	var home: Dictionary = sim.structures.entries.get(agent.home, {})
	if not home.is_empty():
		plans.append(H.option("go_home", 1.0, [_structure(home.id), Plans.step(Op.SHELTER, {"ticks": 90})]))
	var roof: int = H.nearest_structure(sim, agent, func(s: Dictionary) -> bool:
		return (s.functions.has("shelter") or s.functions.has("dwelling")) and s.id != agent.home)
	if roof >= 0:
		plans.append(H.option("shelter_structure", 0.8, [_structure(roof), Plans.step(Op.SHELTER, {"ticks": 90})]))
	var canopy: Vector3i = covered_cell(sim, agent)
	if canopy.x >= 0:
		plans.append(H.option("under_trees", 0.4, [Plans.go_cell(canopy), Plans.step(Op.SHELTER, {"ticks": 60})]))
	plans.append(H.option("endure", 0.1, [Plans.step(Op.SHELTER, {"ticks": 30})]))
	return plans


## The nearest walkable cell under a known tree's canopy, or (-1,-1,-1).
static func covered_cell(sim: RefCounted, agent: RefCounted) -> Vector3i:
	var bases: Array = []
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	if tree.x >= 0 and H.distance(tree, agent.cell) < 40.0:
		bases.append(tree + Vector3i(-1, 0, 2))
	for id in agent.beliefs.known_sites("tree", agent.cell):
		bases.append(agent.beliefs.sites[id].cell + Vector3i(1, 0, 1))
		if bases.size() >= 4:
			break
	var best := Vector3i(-1, -1, -1)
	var best_distance: float = INF
	for base in bases:
		var cell: Vector3i = sim.nav.nearest_walkable(base, 2)
		if cell.x < 0 or not sim.is_under_canopy(cell):
			continue
		var d: float = H.distance(cell, agent.cell)
		if d < best_distance:
			best = cell
			best_distance = d
	return best


static func _flee_cell(sim: RefCounted, agent: RefCounted) -> Vector3i:
	var threat: Array = agent.beliefs.nearest_threat(agent.cell)
	if threat.is_empty():
		return Vector3i(-1, -1, -1)
	var from: Vector3i = threat[0].cell
	var away := Vector3i(signi(agent.cell.x - from.x) * 8, 0, signi(agent.cell.z - from.z) * 8)
	return sim.nav.nearest_walkable(agent.cell + away, 4)


static func flee(sim: RefCounted, agent: RefCounted) -> Array:
	var plans: Array = []
	var threat: Array = agent.beliefs.nearest_threat(agent.cell)
	var safe: int = H.nearest_structure(sim, agent, func(s: Dictionary) -> bool:
		return s.closed and (s.functions.has("dwelling") or s.functions.has("shelter")) \
			and (threat.is_empty() or H.distance(s.anchor, threat[0].cell) > 4.0))
	if safe >= 0:
		plans.append(H.option("shelter_indoors", 1.0, [_structure(safe), Plans.step(Op.HIDE, {"ticks": 40})]))
	var cell: Vector3i = _flee_cell(sim, agent)
	if cell.x >= 0:
		plans.append(H.option("run_away", 0.6, [Plans.go_cell(cell), Plans.step(Op.HIDE, {"ticks": 25})]))
	plans.append(H.option("freeze", 0.1, [Plans.step(Op.HIDE, {"ticks": 15})]))
	return plans


static func care(sim: RefCounted, agent: RefCounted) -> Array:
	var plans: Array = []
	var bed: int = agent.home if sim.structures.entries.has(agent.home) else H.nearest_structure(sim, agent, func(s: Dictionary) -> bool:
		return int(s.capacity.get("beds", 0)) > 0)
	if bed >= 0:
		plans.append(H.option("bed_rest", 0.6, [_structure(bed), Plans.step(Op.RECOVER, {"ticks": 150})]))
	var friend: int = H.friend_nearby(sim, agent, 20.0)
	if friend >= 0:
		plans.append(H.option("ask_for_care", 0.4, [
			Plans.step(Op.SEND, {"to": friend, "kind": "request_help", "need": 1}),
			Plans.step(Op.WAIT_FOR_HELP, {"ticks": Balance.integer("agents.help_wait_ticks")}),
		]))
	plans.append(H.option("rest_here", 0.1, [Plans.step(Op.RECOVER, {"ticks": 90})]))
	return plans


static func relax(sim: RefCounted, agent: RefCounted) -> Array:
	var plans: Array = []
	var hall: int = H.nearest_structure(sim, agent, func(s: Dictionary) -> bool: return s.functions.has("hall"))
	if hall >= 0 and H.distance(sim.structures.entries[hall].anchor, agent.cell) < 40.0:
		plans.append(H.option("gather_in_the_hall", 0.8, [_structure(hall), Plans.step(Op.RELAX, {"ticks": 60})]))
	var tree: Vector3i = sim.features.get("sacred_tree", Vector3i(-1, -1, -1))
	if tree.x >= 0 and H.distance(tree, agent.cell) < 30.0:
		var spot: Vector3i = sim.nav.nearest_walkable(tree + Vector3i(2, 0, -1), 3)
		if spot.x >= 0:
			plans.append(H.option("sit_by_the_tree", 0.5, [Plans.go_cell(spot), Plans.step(Op.RELAX, {"ticks": 50})]))
	plans.append(H.option("stroll", 0.3, [Plans.go_cell(H.wander_cell(sim, agent)), Plans.step(Op.RELAX, {"ticks": 40})]))
	return plans
