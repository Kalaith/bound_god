extends RefCounted
## Outlaws (M22): the raid director's bands are people now. When a band
## forms (raids.gd keeps the odds and the target), its members walk in from
## the valley's edge as agents of no settlement who decide for themselves
## (agents/deliberation_outlaw.gd): make for the target's stores and take
## what they can carry, break the altar of a settlement whose people pray,
## and go; or fall back when they are hurt, outnumbered or the place is
## veiled from them. Each outlaw has a stand-in among the threats (kind
## "raider", with `agent`), so people see, flee, ring the bell and fight as
## they did; blows on the stand-in wound the outlaw, and the outlaw strikes
## back at whoever fights them. backstory.outlaw = {band, target, altar,
## proxy, home, looted, desecrated}.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const Mind = preload("res://scripts/agents/mind.gd")


static func is_outlaw(agent: RefCounted) -> bool:
	return agent.backstory.has("outlaw")


## An outlaw of band `band` enters at `cell`, with a stand-in among the
## threats. Returns the stand-in's threat id.
static func spawn(sim: RefCounted, band: Dictionary, cell: Vector3i, altar: bool) -> int:
	var agent: RefCounted = Generation.adult(sim.rng, sim.agents.size())
	agent.cell = cell
	agent.position = Movement.center(cell)
	agent.previous_position = agent.position
	agent.joined_day = sim.calendar.day()
	agent.next_deliberation = sim.calendar.tick + agent.id % 3
	agent.settlement_id = -1
	agent.faith.knows = false
	sim.agents.append(agent)
	var proxy: int = sim.threats.spawn("raider", cell, {"state": "outlaw", "settlement_id": int(band.settlement_id), "band": int(band.id),
		"targets_altar": altar, "agent": agent.id, "last_hp": Balance.number("threats.raider.health")})
	agent.backstory["outlaw"] = {"band": int(band.id), "target": int(band.settlement_id), "altar": altar, "proxy": proxy, "home": cell,
		"looted": false, "desecrated": false}
	sim.goal_version += 1
	return proxy


## The stand-in follows its outlaw: where they stand, what blows they took
## (passed on as wounds), and a blow back at whoever fights them. Returns
## false when the outlaw is gone (the stand-in should go too).
static func follow(sim: RefCounted, entry: Dictionary) -> bool:
	var agent: RefCounted = sim.agents[int(entry.agent)]
	if not agent.is_present():
		return false
	var most: float = Balance.number("threats.raider.health")
	var dealt: float = float(entry.get("last_hp", entry.hp)) - float(entry.hp)
	if dealt > 0.0:
		agent.health.hp = maxf(float(agent.health.hp) - dealt * 100.0 / most, 0.0)
		agent.health.injuries = int(agent.health.injuries) + 1
	entry.hp = float(agent.health.hp) * most / 100.0
	entry["last_hp"] = entry.hp
	entry.previous_position = entry.position
	entry.cell = agent.cell
	entry.position = agent.position
	entry.path = []
	return true


## Whoever fights an outlaw close by takes a blow back now and then.
static func strike_back(sim: RefCounted, entry: Dictionary, near: Array) -> RefCounted:
	for other in near:
		if other.activity == "fighting" and absi(other.cell.x - entry.cell.x) <= 1 and absi(other.cell.z - entry.cell.z) <= 1:
			return other
	return null


## People fighting this outlaw's band close by, and how many of the band remain.
static func odds(sim: RefCounted, agent: RefCounted) -> Array:
	var fighters: int = 0
	for agent_id in sim.spatial.near("agents", agent.cell, 6.0):
		var other: RefCounted = sim.agents[agent_id]
		if other.is_present() and not is_outlaw(other) and other.activity == "fighting":
			fighters += 1
	return [fighters, sim.raids.band_size(int(agent.backstory.outlaw.band))]


## The stores: take what an outlaw can carry, the band's loot noted.
static func loot(sim: RefCounted, agent: RefCounted) -> void:
	var o: Dictionary = agent.backstory.outlaw
	var room: int = int(Balance.number("threats.raider.carry"))
	var resources: Array = sim.settlements.stock_of(int(o.target)).keys()
	resources.sort()
	for resource in resources:
		if room <= 0:
			break
		var got: int = sim.settlements.take(sim, int(o.target), resource, room, agent.cell)
		if got > 0:
			agent.carrying = {"resource": resource, "amount": float(agent.carried(resource)) + got}
			sim.raids.note_loot(int(o.band), resource, got)
			room -= got
	o.looted = true


## The altar of a god the settlement prays to: smashed (a cutting torn up).
static func desecrate(sim: RefCounted, agent: RefCounted) -> void:
	var o: Dictionary = agent.backstory.outlaw
	var shrine: Dictionary = target_shrine(sim, int(o.target))
	o.desecrated = true
	if shrine.is_empty():
		return
	sim.set_block(shrine.cell, 0 if str(shrine.kind) == "cutting" else Registry.id("cobble"), 0, "raid:%d" % int(o.band))
	sim.raids.note_desecration(int(o.band))


## The settlement's standing altar or cutting, or {}.
static func target_shrine(sim: RefCounted, settlement_id: int) -> Dictionary:
	for id in sim.settlements.get_settlement(settlement_id).get("shrine_ids", []):
		var shrine: Dictionary = sim.faith.get_shrine(int(id))
		if not shrine.is_empty() and str(shrine.kind) in ["altar", "cutting"] and str(shrine.state) != "fallen":
			return shrine
	return {}


## Turning back is chronicled once for the band, with why.
static func turn_back(sim: RefCounted, agent: RefCounted, cause: String) -> void:
	var proxy: int = int(agent.backstory.outlaw.proxy)
	var entry: Dictionary = sim.threats.entries.get(proxy, {"band": int(agent.backstory.outlaw.band), "id": proxy})
	sim.raids.on_turned_back(sim, entry, cause)


## An outlaw who reaches the edge leaves the valley with what they carry.
static func leave(sim: RefCounted, agent: RefCounted) -> void:
	agent.life = "departed"
	agent.life_day = sim.calendar.day()
	agent.intention = {}
	agent.path.clear()
	sim.goal_version += 1
