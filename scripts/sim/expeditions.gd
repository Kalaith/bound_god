extends RefCounted
## Expeditions into the hidden realm (M23). Once the tree's roots open the
## realm (unlock `root_realm`, campaign.gd), a cultivator of the sect at the
## tree may go in (goal ENTER_REALM: walk to the trunk, step into the roots),
## a few at a time (`tree.json` `realm.party`). They leave the valley for
## `realm.expedition_days` and live in the realm as visitors, cultivating in
## its dense qi; each day there carries `realm.lost_chance` of being lost.
## Coming out, they bring their share of its herbs (`realm.haul`) to the
## stores and their cultivation home. The road in and out is the campaign's
## (sim.outbound, sim/travel.gd). backstory.expedition = {home, region, until}.
const Data = preload("res://scripts/core/data.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const Mind = preload("res://scripts/agents/mind.gd")


static func config() -> Dictionary:
	return Data.tree_growth().realm


static func is_visitor(agent: RefCounted) -> bool:
	return agent.backstory.has("expedition")


## Whether a member of the sect at the tree would go in now: {utility} or {}.
static func wants(sim: RefCounted, agent: RefCounted, abstract: bool = false) -> Dictionary:
	if sim.region_id != 0 or not bool(sim.sanctuary.get("realm", false)) or agent.is_child or (not abstract and Schedule.is_sleep_time(sim, agent)):
		return {}
	var c: Dictionary = agent.cultivation
	if c.is_empty() or int(c.get("sect_id", -1)) < 0 or int(c.realm) < 1 or CultivationState.at_peak(c):
		return {}
	var hollow: int = sim.settlements.at_cell(sim.features.get("sacred_tree", Vector3i.ZERO))
	if agent.settlement_id != hollow:
		return {}
	var gone: int = 0
	for other in sim.agents:
		if other.life == "away" and other.backstory.get("in_realm", false):
			gone += 1
	if gone + sim.pursuers(_key()).size() >= int(config().party) and not sim.pursuers(_key()).has(agent.id):
		return {}
	return {"utility": float(config().pull) * (0.6 + 0.6 * float(c.drive)) * agent.capacity()}


static func _key() -> int:
	var Goals = preload("res://scripts/agents/goals.gd")
	return Goals.key_of(Goals.Kind.ENTER_REALM, -1)


## While the valley passes abstractly: those who would go, go now and then
## (the same want, `realm.abstract_chance` × its weight a day), in id order.
static func abstract_day(sim: RefCounted) -> void:
	if sim.region_id != 0 or not bool(sim.sanctuary.get("realm", false)):
		return
	for agent in sim.agents:
		if not agent.is_present():
			continue
		var want: Dictionary = wants(sim, agent, true)
		if not want.is_empty() and sim.rng.randf() < float(config().abstract_chance) * float(want.utility):
			set_out(sim, agent)


## The cultivator steps into the roots: away from the valley until they return.
static func set_out(sim: RefCounted, agent: RefCounted) -> void:
	agent.life = "away"
	agent.backstory["in_realm"] = true
	agent.intention = {}
	agent.path.clear()
	sim.goal_version += 1
	sim.outbound.append({"kind": "expedition", "region": -2, "agent": agent.id, "record": agent.to_dict()})
	sim.chronicle_event("realm_set_out", agent.settlement_id, {"name": agent.full_name()}, "cause_expedition", [agent.id])


## A visitor arrives in the realm (sim/travel.gd), with provisions.
static func arrive(sim: RefCounted, agent: RefCounted, trip: Dictionary) -> void:
	agent.backstory["wayfarer"] = true
	agent.backstory["expedition"] = {"home": int(trip.agent), "region": int(trip.from), "until": sim.calendar.tick + sim.calendar.ticks_for_days(float(config().expedition_days))}
	var camp: Vector3i = sim.settlements.entries[1].camp
	sim.settlements.store_any(sim, 1, "berries", int(config().provisions), camp)
	sim.chronicle_event("realm_entered", 1, {"name": agent.full_name()}, "cause_expedition", [agent.id])


## Daily in the realm: some are lost; those whose time is up come out.
static func daily(sim: RefCounted) -> void:
	for agent in sim.agents.duplicate():
		if not agent.is_present() or not is_visitor(agent):
			continue
		var trip: Dictionary = agent.backstory.expedition
		if sim.rng.randf() < float(config().lost_chance):
			var Lifecycle = load("res://scripts/sim/lifecycle.gd")
			sim.chronicle_event("lost_in_realm", 1, {"name": agent.full_name()}, "cause_lost_in_realm", [agent.id])
			sim.outbound.append({"kind": "expedition_home", "region": int(trip.region), "home": int(trip.home), "record": agent.to_dict(), "dead": true})
			Lifecycle.die(sim, agent, "cause_lost_in_realm")
			continue
		if int(trip.until) > sim.calendar.tick:
			continue
		sim.outbound.append({"kind": "expedition_home", "region": int(trip.region), "home": int(trip.home), "record": agent.to_dict(), "haul": config().haul.duplicate()})
		var EffectsApply = load("res://scripts/sim/effects_apply.gd")
		EffectsApply._leave(sim, agent, "cause_expedition", false)


## A visitor comes out of the roots: their cultivation home, their haul to
## the stores; or the news that they were lost.
static func come_home(sim: RefCounted, trip: Dictionary) -> void:
	var agent: RefCounted = sim.agents[int(trip.home)] if int(trip.home) < sim.agents.size() else null
	if agent == null or agent.life != "away":
		return
	agent.life = "present"
	agent.backstory.erase("in_realm")
	agent.next_deliberation = sim.calendar.tick
	sim.goal_version += 1
	if bool(trip.get("dead", false)):
		load("res://scripts/sim/lifecycle.gd").die(sim, agent, "cause_lost_in_realm")
		return
	var c: Dictionary = trip.record.get("cultivation", {})
	for key in ["realm", "progress", "foundation", "trials", "peak_tick", "hours"]:
		if c.has(key):
			agent.cultivation[key] = c[key]
	var haul: Dictionary = trip.get("haul", {})
	var parts: Array = []
	var camp: Vector3i = sim.settlements.get_settlement(agent.settlement_id).get("camp", agent.cell)
	var keys: Array = haul.keys()
	keys.sort()
	for resource in keys:
		sim.settlements.store_any(sim, agent.settlement_id, resource, int(haul[resource]), camp)
		parts.append("%d %s" % [int(haul[resource]), resource])
	sim.chronicle_event("realm_returned", agent.settlement_id, {"name": agent.full_name(), "haul": ", ".join(parts)}, "cause_realm_haul", [agent.id])
