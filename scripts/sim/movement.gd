extends RefCounted
## Follows the path with a fractional move budget so motion is smooth at any
## tick rate; `position` lerps between cells for the presentation.
const Balance = preload("res://scripts/core/balance.gd")


static func center(cell: Vector3i) -> Vector3:
	return Vector3(cell.x + 0.5, cell.y, cell.z + 0.5)


## Whoever loses the floor under them, or finds a block where they stand,
## settles onto the nearest place a person can stand.
static func settle(sim: RefCounted, agent: RefCounted) -> void:
	if sim.nav.is_walkable(agent.cell):
		return
	var cell: Vector3i = sim.nav.nearest_walkable(agent.cell, 4)
	if cell.x >= 0:
		agent.cell = cell
		agent.path.clear()
		agent.position = center(cell)


static func advance(sim: RefCounted, agent: RefCounted) -> void:
	agent.previous_position = agent.position
	settle(sim, agent)
	if agent.path.is_empty():
		agent.move_budget = 0.0
		agent.position = center(agent.cell)
		return
	var speed: float = Balance.number("agents.cells_per_tick") * (0.6 + 0.4 * agent.capacity())
	if agent.activity == "fleeing":
		speed *= 1.3
	if agent.is_child:
		speed *= 0.85
	agent.move_budget += speed
	var cost: float = 1.0
	while not agent.path.is_empty():
		var next: Vector3i = agent.path[0]
		if not sim.nav.is_walkable(next):
			# The way changed under their feet; the step will ask for a new path.
			agent.path.clear()
			break
		cost = sim.nav.move_cost(agent.cell, next)
		if agent.move_budget < cost:
			break
		agent.move_budget -= cost
		agent.cell = next
		agent.path.pop_front()
	if agent.path.is_empty():
		agent.move_budget = 0.0
		agent.position = center(agent.cell)
	else:
		agent.position = center(agent.cell).lerp(center(agent.path[0]), clampf(agent.move_budget / cost, 0.0, 1.0))
