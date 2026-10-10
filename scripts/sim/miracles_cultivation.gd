extends RefCounted
## Miracles for cultivators. None grants a realm: Bless Cultivation speeds a
## day of one person's own practice; Shield the Trial lowers the severity of
## a storm already called, never to nothing; Defy Heaven turns aside a death
## that storm would bring, and the breakthrough it leaves is imperfect.
const Balance = preload("res://scripts/core/balance.gd")
const Mind = preload("res://scripts/agents/mind.gd")


## A day of faster progress for one person in the presence.
static func bless(sim: RefCounted, args: Dictionary) -> Dictionary:
	var id: int = int(args.get("agent", -1))
	if id < 0 or id >= sim.agents.size() or not sim.agents[id].is_present():
		return {"ok": false, "reason": "whisper_nobody"}
	var agent: RefCounted = sim.agents[id]
	if not sim.in_zone(agent.position):
		return {"ok": false, "reason": "edit_outside_zone"}
	if agent.cultivation.is_empty() or float(agent.cultivation.drive) < 0.05 and int(agent.cultivation.realm) == 0:
		return {"ok": false, "reason": "miracle_not_cultivating"}
	agent.cultivation.blessed_until = sim.calendar.tick + sim.calendar.ticks_for_days(Balance.number("cultivation.bless_days"))
	Mind.add(agent, "blessed", sim.calendar.ticks_per_day)
	return {"ok": true, "reason": "miracle_blessed_cultivation"}


## Shield or defy the nearest trial called within reach of `cell`.
static func trial(sim: RefCounted, effect: String, cell: Vector3i, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	var ids: Array = sim.tribulations.entries.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = sim.tribulations.entries[id]
		if entry.state == "done":
			continue
		var at: Vector3i = sim.agents[int(entry.agent)].cell
		var d: float = Vector2(at.x - cell.x, at.z - cell.z).length()
		if d <= radius and d < best_distance and sim.in_zone(Vector3(at) + Vector3(0.5, 0, 0.5)):
			best = entry
			best_distance = d
	if best.is_empty():
		return {"ok": false, "reason": "miracle_no_trial"}
	if effect == "shield_trial":
		if float(best.shield) > 0.0:
			return {"ok": false, "reason": "miracle_already_shielded"}
		best.shield = Balance.number("cultivation.shield_amount")
		return {"ok": true, "reason": "miracle_shielded"}
	if bool(best.defy):
		return {"ok": false, "reason": "miracle_already_defied"}
	best.defy = true
	return {"ok": true, "reason": "miracle_defied"}
