extends RefCounted
## Applies food actions at the end of the tick: a seed goes into open
## farmland, a ripe crop is reaped into the reaper's arms (its seed falls
## loose beside them), weeding tends the crops within reach, and cooks fill
## a kitchen's pot and cook it into meals. A settlement's first harvest and
## first meal are chronicled.
const Crafts = preload("res://scripts/sim/crafts.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Crops = preload("res://scripts/sim/crops.gd")
const Alchemy = preload("res://scripts/sim/alchemy.gd")
const EffectsAlchemy = preload("res://scripts/sim/effects_alchemy.gd")


## Applies one food action; false when the action is not a food action.
static func apply(sim: RefCounted, agent: RefCounted, action: Dictionary) -> bool:
	match str(action.type):
		"sow":
			_sow(sim, agent, action.cell)
		"reap":
			_reap(sim, agent, action.cell)
		"tend_crops":
			_tend(sim, agent)
		"add_to_pot":
			if str(action.get("station", "")) == Alchemy.STATION:
				EffectsAlchemy.add(sim, agent, int(action.kitchen), int(action.seat), str(action.recipe), int(action.batches))
			else:
				_add_to_pot(sim, agent, int(action.kitchen), int(action.batches), str(action.get("station", "kitchen")))
		"cook":
			if str(action.get("station", "")) == Alchemy.STATION:
				EffectsAlchemy.refine(sim, agent, int(action.kitchen), int(action.seat))
			else:
				_cook(sim, agent, int(action.kitchen), str(action.get("station", "kitchen")))
		_:
			return false
	return true


static func _sow(sim: RefCounted, agent: RefCounted, cell: Vector3i) -> void:
	var crop: Dictionary = Crops.staple()
	if not Crops.open_plot(sim, cell) or agent.carried(crop.seed) < 1.0 or not Crops.can_sow(sim, crop):
		agent.step_result = {"sown": 0}
		return
	agent.carrying.amount = float(agent.carrying.amount) - 1.0
	if float(agent.carrying.amount) < 0.05:
		agent.carrying = {}
	sim.crops.sow(sim, cell, crop, "npc:%d" % agent.id)
	agent.step_result = {"sown": 1}


static func _reap(sim: RefCounted, agent: RefCounted, cell: Vector3i) -> void:
	if not sim.crops.is_ripe(sim, cell):
		agent.step_result = {"reaped": 0}
		return
	var gain: Dictionary = sim.crops.reap_yield(cell)
	if not agent.carrying.is_empty() and agent.carrying.resource != gain.harvest:
		agent.step_result = {"reaped": 0}
		return
	sim.set_block(cell, 0, 0, "npc:%d" % agent.id)
	agent.carrying = {"resource": gain.harvest, "amount": agent.carried(gain.harvest) + float(gain.amount)}
	sim.drop_item(agent.cell, gain.seed, float(gain.seed_amount))
	agent.step_result = {"reaped": int(gain.amount)}
	var place: int = sim.settlements.at_cell(cell)
	if place >= 0 and not sim.settlements.entries[place].get("harvested", false):
		sim.settlements.entries[place]["harvested"] = true
		sim.chronicle_event("first_harvest", place, {"place": sim.settlements.entries[place].name, "name": agent.full_name()}, "cause_field_tended", [agent.id])


static func _tend(sim: RefCounted, agent: RefCounted) -> void:
	var reach: float = Balance.number("agents.reach") + 0.5
	var cells: Array = sim.crops.plots.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return sim.voxels.index_of(a) < sim.voxels.index_of(b))
	var tended: int = 0
	for cell in cells:
		if Vector3(cell).distance_to(Vector3(agent.cell + Vector3i.UP)) <= reach and sim.crops.tend(sim, cell):
			tended += 1
	agent.step_result = {"tended": maxi(tended, 1)}


static func _add_to_pot(sim: RefCounted, agent: RefCounted, kitchen: int, batches: int, station: String) -> void:
	var entry: Dictionary = sim.structures.entries.get(kitchen, {})
	if entry.is_empty() or not entry.functions.has(station) or agent.carrying.is_empty():
		agent.step_result = {"added": 0}
		return
	var resource: String = agent.carrying.resource
	var added: int = sim.station(station).add(kitchen, resource, int(floor(float(agent.carrying.amount))), batches, entry.anchor)
	agent.carrying.amount = float(agent.carrying.amount) - added
	if float(agent.carrying.amount) < 0.05:
		agent.carrying = {}
	agent.step_result = {"added": added}


static func _cook(sim: RefCounted, agent: RefCounted, kitchen: int, station: String) -> void:
	var entry: Dictionary = sim.structures.entries.get(kitchen, {})
	if entry.is_empty() or not entry.functions.has(station) or not agent.carrying.is_empty():
		agent.step_result = {"cooked": 0}
		return
	var made: Dictionary = sim.station(station).cook(kitchen)
	if made.is_empty():
		agent.step_result = {"cooked": 0}
		return
	var resource: String = made.keys()[0]
	agent.carrying = {"resource": resource, "amount": float(made[resource])}
	agent.step_result = {"cooked": int(made[resource])}
	var place: int = sim.settlements.at_cell(entry.anchor)
	if station != "kitchen":
		Crafts.first_made(sim, agent, place, resource)
		return
	if place >= 0 and not sim.settlements.entries[place].get("cooked", false):
		sim.settlements.entries[place]["cooked"] = true
		sim.chronicle_event("first_meal", place, {"place": sim.settlements.entries[place].name, "name": agent.full_name()}, "cause_kitchen_built", [agent.id])
