extends RefCounted
## Branches while the valley passes abstractly (M21): each day an elder who
## wants to found a branch (the same want as in the detailed world) sets out
## now and then, packing a log from the stores for the new chest, and those
## who would follow a branch of their sect go after it. Each arrives and
## settles at once by the same rules (the camp's chest and the cutting are
## set as they arrive). People in id order, randomness from the sim's rng.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Branches = preload("res://scripts/sim/branches.gd")
const EffectsApply = preload("res://scripts/sim/effects_apply.gd")
const Movement = preload("res://scripts/sim/movement.gd")


static func day(sim: RefCounted) -> void:
	if sim.sects == null:
		return
	var chance: float = Balance.number("branches.abstract_found")
	for agent in sim.agents:
		if not agent.is_present():
			continue
		var want: Dictionary = Branches.founding(sim, agent, true)
		if not want.is_empty():
			if sim.rng.randf() < chance * float(want.utility):
				_set_out(sim, agent, int(want.ground), int(want.cause), true)
			continue
		want = Branches.following(sim, agent, true)
		if not want.is_empty() and sim.rng.randf() < chance * 3.0 * float(want.utility):
			_set_out(sim, agent, int(want.ground), Branches.Cause.AMBITION, false)


## Walks (in an instant) to the ground and settles there; the first founder
## carries a log for the chest.
static func _set_out(sim: RefCounted, agent: RefCounted, ground: int, cause: int, founder: bool) -> void:
	# A ground in another region: they leave this world at once (M22).
	if Branches.is_abroad(ground):
		Branches.emigrate(sim, agent, ground, cause if founder else 0)
		return
	var settled: bool = sim.settlements.on_ground(ground) >= 0
	if founder and not settled:
		if not agent.carrying.is_empty():
			return
		# From the stores, or felled on the way as a founder in the detailed
		# world gathers their provisions.
		sim.settlements.take_any(sim, agent.settlement_id, "wood", 1)
		agent.carrying = {"resource": "wood", "amount": 1.0}
	var camp: Vector3i = sim.nav.nearest_walkable(sim.features.grounds[ground].center, 4)
	if camp.x < 0:
		return
	agent.cell = camp
	agent.position = Movement.center(camp)
	agent.previous_position = agent.position
	EffectsApply._settle(sim, agent, ground, cause)
	agent.step_result = {}
