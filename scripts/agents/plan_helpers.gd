extends RefCounted
## Helpers shared by the plan library files: nearest places, known sites,
## friends nearby and wandering, all read from beliefs and visible state.
const Balance = preload("res://scripts/core/balance.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Homes = preload("res://scripts/sim/homes.gd")


static func distance(a: Vector3i, b: Vector3i) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length() + absf(a.y - b.y)


## Nearest structure matching `wanted` that the person has not recently failed
## to use, or -1. Ties break on id.
static func nearest_structure(sim: RefCounted, agent: RefCounted, wanted: Callable) -> int:
	var now: int = sim.calendar.tick
	var window: int = Balance.integer("agents.failure_memory_ticks")
	var best: int = -1
	var best_distance: float = INF
	for id in agent.beliefs.structures:
		# People only head for places they believe in; a vanished one fails on arrival.
		var entry: Dictionary = sim.structures.entries.get(id, {})
		if entry.is_empty() or not wanted.call(entry) or agent.beliefs.recently_failed("structure:%d" % entry.id, now, window):
			continue
		var d: float = distance(entry.anchor, agent.cell)
		if d < best_distance or (d == best_distance and entry.id < best):
			best = entry.id
			best_distance = d
	return best


static func free_beds(sim: RefCounted, entry: Dictionary) -> int:
	return Homes.free_beds(sim, entry)


## Up to three believed sites of a kind with no recent failure, nearest first.
static func known_sites(sim: RefCounted, agent: RefCounted, kind: String) -> Array:
	var now: int = sim.calendar.tick
	var window: int = Balance.integer("agents.failure_memory_ticks")
	var result: Array = []
	for id in agent.beliefs.known_sites(kind, agent.cell):
		if not agent.beliefs.recently_failed("site:%d" % id, now, window):
			result.append(id)
			if result.size() >= 3:
				break
	return result


## The closest awake adult this person likes at least `min_opinion`.
static func friend_nearby(sim: RefCounted, agent: RefCounted, min_opinion: float) -> int:
	var best: int = -1
	var best_distance: float = INF
	for other in sim.agents:
		if other.id == agent.id or not other.available_to_talk() or other.is_child:
			continue
		if agent.beliefs.opinion_of(other.id) < min_opinion:
			continue
		var d: float = distance(other.cell, agent.cell)
		if d < best_distance:
			best = other.id
			best_distance = d
	return best


## A walkable cell on a ring round `center`, its own for each person (by id,
## without the rng), so a crowd spreads round a tree instead of standing in
## one spot.
static func ring_cell(sim: RefCounted, center: Vector3, id: int, inner: float, outer: float) -> Vector3i:
	var angle: float = float(id) * 2.39996
	var radius: float = inner + fposmod(float(id) * 0.618034, 1.0) * (outer - inner)
	var target := Vector3i(floori(center.x + cos(angle) * radius), roundi(center.y), floori(center.z + sin(angle) * radius))
	return sim.nav.nearest_walkable(target, 2)


## A nearby cell to wander to, varied by id and time without the rng.
static func wander_cell(sim: RefCounted, agent: RefCounted) -> Vector3i:
	var seed: int = agent.id * 31 + sim.calendar.tick / 60
	var dx: int = posmod(seed * 7919, 9) - 4
	var dz: int = posmod(seed * 104729, 9) - 4
	var target: Vector3i = agent.cell + Vector3i(dx * 2, 0, dz * 2)
	var settlement: Dictionary = sim.settlements.get_settlement(agent.settlement_id)
	if not settlement.is_empty() and distance(target, settlement.center) > float(settlement.radius):
		target = agent.cell + (settlement.center - agent.cell) / 3
	var cell: Vector3i = sim.nav.nearest_walkable(target, 3)
	return agent.cell if cell.x < 0 else cell


## Steps that put a carried load in the stores first, when a plan needs
## hands free for `resource` (or for anything, with ""). Empty when not needed.
static func free_hands(agent: RefCounted, resource: String = "") -> Array:
	if agent.carrying.is_empty() or agent.settlement_id < 0:
		return []
	if not resource.is_empty() and agent.carrying.resource == resource:
		return []
	return [Plans.go_to(Plans.target(Plans.T.STORE, agent.settlement_id)), Plans.step(Plans.Op.DEPOSIT)]


## The nearest loose pile of a resource lying about the person's home, or -1.
static func loose_item(sim: RefCounted, agent: RefCounted, resource: String) -> int:
	var settlement: Dictionary = sim.settlements.get_settlement(agent.settlement_id)
	if settlement.is_empty():
		return -1
	var best: int = -1
	var best_distance: float = INF
	for id in sim.items:
		var item: Dictionary = sim.items[id]
		if item.resource != resource or float(item.amount) < 1.0:
			continue
		if distance(item.cell, settlement.center) > float(settlement.radius):
			continue
		var d: float = distance(item.cell, agent.cell)
		if d < best_distance or (d == best_distance and int(id) < best):
			best = int(id)
			best_distance = d
	return best


static func option(id: String, preference: float, steps: Array) -> Dictionary:
	return Plans.option(id, preference, steps)
