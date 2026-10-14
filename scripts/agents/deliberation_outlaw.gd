extends RefCounted
## An outlaw's choices (M22): raid while the raid can still go well, fall
## back when it cannot. They weigh their own wounds, how many fight them
## against how many of the band remain, whether the place is veiled from
## them, and whether there is anything left to do. The ordinary needs keep
## their pull on survival only (a raid lasts hours, not days).
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Outlaws = preload("res://scripts/sim/outlaws.gd")
const TreeAbilities = preload("res://scripts/sim/tree_abilities.gd")

const Kind = Goals.Kind


static func _candidate(kind: int, utility: float, reason: String, target: int = -1, extra: int = 0) -> Dictionary:
	return {"goal": Goals.make(kind, target, extra), "utility": utility, "reason": reason, "value": NAN}


## Why an outlaw would fall back now, or "" (a cause key).
static func fall_back(sim: RefCounted, agent: RefCounted) -> String:
	var o: Dictionary = agent.backstory.outlaw
	var band: Dictionary = sim.raids.bands.get(int(o.band), {})
	if band.is_empty() or str(band.get("state", "")) == "over":
		return "cause_raid_over"
	# The tree's formation turns them back (M23).
	if TreeAbilities.warded(sim, agent.cell):
		return "cause_formation"
	if float(agent.health.hp) < Balance.number("threats.outlaw_flee_hp"):
		return "cause_outlaw_hurt"
	var odds: Array = Outlaws.odds(sim, agent)
	if int(odds[0]) >= int(odds[1]):
		return "cause_defenders|%d" % int(odds[0])
	var settlement: Dictionary = sim.settlements.get_settlement(int(o.target))
	if settlement.is_empty():
		return "cause_raid_over"
	if not bool(o.looted) and sim.is_veiled(settlement.center, agent.cell):
		return "cause_veiled"
	if bool(o.looted) and (not bool(o.altar) or bool(o.desecrated) or Outlaws.target_shrine(sim, int(o.target)).is_empty()):
		return "cause_raid_done"
	return ""


static func candidates(sim: RefCounted, agent: RefCounted) -> Array:
	var why: String = fall_back(sim, agent)
	if not why.is_empty():
		return [_candidate(Kind.RETREAT, 2.0, "reason_outlaw_%s" % why.split("|")[0].trim_prefix("cause_"))]
	return [_candidate(Kind.RAID, 1.2, "reason_outlaw_raid", int(agent.backstory.outlaw.target))]
