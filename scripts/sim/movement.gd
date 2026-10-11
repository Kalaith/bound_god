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


## Someone walled in where they stand (a pit dug around them, a wall raised
## beside them, a roof finished under their feet) clambers to the nearest
## cell close by from which `goal` can be reached. Tried at most once a
## while, as it searches several paths.
static func scramble(sim: RefCounted, agent: RefCounted, goal: Vector3i) -> bool:
	var now: int = sim.calendar.tick
	if agent.beliefs.recently_failed("scramble", now, Balance.integer("agents.failure_memory_ticks")):
		return false
	agent.beliefs.note_failure("scramble", now)
	var near: Array = []
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			for dy in range(-5, 4):
				var cell: Vector3i = agent.cell + Vector3i(dx, dy, dz)
				if cell != agent.cell and sim.nav.is_walkable(cell):
					near.append([absi(dx) + absi(dz) + absi(dy), cell.y, cell.z, cell.x, cell])
	near.sort()
	for i in range(mini(near.size(), 8)):
		var cell: Vector3i = near[i][4]
		if not sim.nav.find_path(cell, goal).is_empty():
			agent.cell = cell
			agent.position = center(cell)
			agent.path.clear()
			agent.record(now, "message", {"text": "log_scrambled_out", "args": {}})
			return true
	return false


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
		sim.paths.step_on(next)
	if agent.path.is_empty():
		agent.move_budget = 0.0
		agent.position = center(agent.cell)
	else:
		agent.position = center(agent.cell).lerp(center(agent.path[0]), clampf(agent.move_budget / cost, 0.0, 1.0))
