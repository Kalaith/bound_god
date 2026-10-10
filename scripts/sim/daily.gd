extends RefCounted
## Day and hour hooks: the stores' stock reaches everyone's beliefs, stale
## beliefs fade, opinions cool, berries regrow, and the larger systems take
## their daily and hourly turns.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Lifecycle = preload("res://scripts/sim/lifecycle.gd")


static func new_day(sim: RefCounted) -> void:
	var now: int = sim.calendar.tick
	var day_ticks: int = sim.calendar.ticks_per_day
	var decay: float = Balance.number("social.opinion_decay_per_day")
	for agent in sim.agents:
		if not agent.is_present():
			continue
		if sim.settlements.entries.has(agent.settlement_id):
			agent.beliefs.stock = sim.settlements.stock_of(agent.settlement_id).duplicate()
		agent.beliefs.forget_stale(now, day_ticks)
		for other in agent.beliefs.relations:
			var relation: Dictionary = agent.beliefs.relations[other]
			relation.opinion = move_toward(float(relation.opinion), 0.0, decay)
	_regrow(sim)
	Lifecycle.daily(sim)
	if sim.settlement_life != null:
		sim.settlement_life.daily(sim)
	if sim.faith != null:
		sim.faith.daily(sim)
	if sim.requests != null:
		sim.requests.daily(sim)
	if sim.director != null:
		sim.director.daily(sim)


static func new_hour(sim: RefCounted) -> void:
	Lifecycle.hourly(sim)
	if sim.faith != null:
		sim.faith.hourly(sim)


## Bushes ripen again every few days, but not in winter.
static func _regrow(sim: RefCounted) -> void:
	if sim.calendar.is_winter():
		return
	var every: int = maxi(1, int(round(Balance.number("world.berry_regrow_days"))))
	if sim.calendar.day() % every != 0:
		return
	var bush: int = Registry.id("berry_bush")
	var most: int = Balance.integer("world.bush_max_berries")
	var tended: int = Balance.integer("world.garden_regrow")
	for id in sim.sites.ids_sorted():
		var site: Dictionary = sim.sites.get_site(id)
		if site.kind != "bush" or site.cells.is_empty():
			continue
		var cell: Vector3i = site.cells[0]
		var berries: int = sim.voxels.block_meta(cell)
		if sim.voxels.get_block(cell) == bush and berries < most:
			# A bush in a planter is tended soil and ripens faster.
			var grow: int = tended if Registry.component(sim.voxels.get_block(cell + Vector3i.DOWN)) == "planter" else 1
			sim.set_block(cell, bush, mini(berries + grow, most), "growth")
