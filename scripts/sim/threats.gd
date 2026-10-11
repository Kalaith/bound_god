extends RefCounted
## Wolves and raiders. Neither is a reasoning agent: wolves wander the woods,
## chase people they see and flee when outnumbered; raiders follow a simple
## plan (approach, loot the stores, break the altar of a god they have heard
## of, retreat) and turn back when defenders outnumber them. Both walk the
## same navigation grid as people. Their harm goes straight to the sim.
const Schools = preload("res://scripts/sim/schools.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Movement = preload("res://scripts/sim/movement.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Personality = preload("res://scripts/agents/personality.gd")

## id -> {id, kind, cell, position, previous_position, path, hp, state, target,
##        home, carry, band, aggressive, targets_altar, settlement_id, next_think}
var entries: Dictionary = {}
var next_id: int = 1
var dens: Array = []


func list() -> Array:
	var result: Array = []
	for id in ids():
		var entry: Dictionary = entries[id]
		result.append({"id": id, "kind": entry.kind, "cell": entry.cell, "aggressive": entry.aggressive})
	return result


func ids() -> Array:
	var keys: Array = entries.keys()
	keys.sort()
	return keys


func exists(id: int) -> bool:
	return entries.has(id)


func spawn(kind: String, cell: Vector3i, extra: Dictionary = {}) -> int:
	var id: int = next_id
	next_id += 1
	var stats: Dictionary = Balance.dict("threats." + kind)
	var entry: Dictionary = {"id": id, "kind": kind, "cell": cell, "position": Movement.center(cell), "previous_position": Movement.center(cell),
		"path": [], "hp": float(stats.health), "state": "wander", "target": -1, "home": cell, "carry": {}, "band": -1,
		"aggressive": bool(stats.aggressive), "targets_altar": false, "settlement_id": -1, "next_think": 0, "budget": 0.0, "strike": 0}
	entry.merge(extra, true)
	entries[id] = entry
	return id


## Wolves den in the woods, well away from where people live.
func setup_wolves(sim: RefCounted) -> void:
	var count: int = Balance.integer("threats.wolf.count")
	var tries: int = 0
	while dens.size() < count and tries < 200:
		tries += 1
		var x: int = sim.rng.randi_range(12, sim.voxels.size.x - 13)
		var z: int = sim.rng.randi_range(12, sim.voxels.size.z - 13)
		var far: bool = true
		for id in sim.settlements.ids():
			var center: Vector3i = sim.settlements.entries[id].center
			far = far and Vector2(x - center.x, z - center.z).length() > 45.0
		if not far:
			continue
		var cell: Vector3i = sim.nav.surface(x, z)
		if cell.x < 0:
			continue
		dens.append(cell)
		spawn("wolf", cell)


func step(sim: RefCounted) -> void:
	for id in ids():
		if not entries.has(id):
			continue
		var entry: Dictionary = entries[id]
		entry.previous_position = entry.position
		if entry.kind == "wolf":
			_wolf(sim, entry)
		else:
			_raider(sim, entry)
		_move(sim, entry)


func _people_near(sim: RefCounted, cell: Vector3i, radius: float) -> Array:
	var result: Array = []
	for agent_id in sim.spatial.near("agents", cell, radius):
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present() and agent.inside < 0 and Vector2(agent.cell.x - cell.x, agent.cell.z - cell.z).length() <= radius:
			result.append(agent)
	return result


func _path_to(sim: RefCounted, entry: Dictionary, goal: Vector3i) -> void:
	if goal.x < 0 or (not entry.path.is_empty() and entry.path.back() == goal):
		return
	var route: Array[Vector3i] = sim.nav.find_path(entry.cell, goal)
	entry.path = route


func _move(sim: RefCounted, entry: Dictionary) -> void:
	if entry.path.is_empty():
		entry.position = Movement.center(entry.cell)
		return
	entry.budget = float(entry.budget) + Balance.number("threats.%s.speed" % entry.kind)
	while not entry.path.is_empty() and float(entry.budget) >= 1.0:
		var next: Vector3i = entry.path[0]
		# Wolves will not walk into lantern light.
		if not sim.nav.is_walkable(next) or (entry.kind == "wolf" and sim.is_lit(next)):
			entry.path.clear()
			break
		entry.budget = float(entry.budget) - 1.0
		entry.cell = next
		entry.path.pop_front()
	if entry.path.is_empty():
		entry.position = Movement.center(entry.cell)
	else:
		entry.position = Movement.center(entry.cell).lerp(Movement.center(entry.path[0]), clampf(float(entry.budget), 0.0, 1.0))


## Strike whoever stands beside the threat, every few ticks.
func _strike(sim: RefCounted, entry: Dictionary, victim: RefCounted) -> void:
	entry.strike = int(entry.strike) + 1
	if int(entry.strike) % 8 != 0:
		return
	var damage: float = Balance.number("threats.%s.damage" % entry.kind)
	victim.health.hp = maxf(float(victim.health.hp) - damage, 0.0)
	victim.health.injuries = int(victim.health.injuries) + 1
	if float(victim.health.hp) <= 0.0:
		victim.life_cause = "cause_" + str(entry.kind)
	Mind.add(victim, "injured", sim.calendar.ticks_per_day)
	for witness in _people_near(sim, victim.cell, 8.0):
		if witness.id != victim.id:
			Mind.add(witness, "witnessed_attack", sim.calendar.ticks_per_day)


func _wolf(sim: RefCounted, entry: Dictionary) -> void:
	var sight: float = Balance.number("threats.wolf.sight")
	if sim.calendar.tick < int(entry.next_think):
		var target: RefCounted = sim.agents[int(entry.target)] if int(entry.target) >= 0 else null
		if target != null and target.is_present() and absi(target.cell.x - entry.cell.x) <= 1 and absi(target.cell.z - entry.cell.z) <= 1:
			_strike(sim, entry, target)
		return
	entry.next_think = sim.calendar.tick + 6
	if sim.is_veiled(entry.cell, entry.cell):
		entry.target = -1
	if sim.is_lit(entry.cell):
		entry.state = "flee"
		entry.target = -1
		_path_to(sim, entry, entry.home)
		return
	var near: Array = []
	for agent in _people_near(sim, entry.cell, sight):
		if not sim.is_lit(agent.cell):
			near.append(agent)
	var close: int = 0
	for agent in near:
		if Vector2(agent.cell.x - entry.cell.x, agent.cell.z - entry.cell.z).length() <= 4.0:
			close += 1
	if close >= 2 or float(entry.hp) < Balance.number("threats.wolf.health") * 0.4:
		entry.state = "flee"
		entry.target = -1
		_path_to(sim, entry, entry.home)
		return
	if not near.is_empty() and entry.state != "flee" and sim.calendar.is_daylight() == false or (not near.is_empty() and sim.rng.randf() < 0.15):
		var prey: RefCounted = near[0]
		entry.state = "chase"
		entry.target = prey.id
		_path_to(sim, entry, prey.cell)
		return
	if entry.path.is_empty():
		entry.state = "wander"
		var roam: Vector3i = entry.home + Vector3i(sim.rng.randi_range(-10, 10), 0, sim.rng.randi_range(-10, 10))
		_path_to(sim, entry, sim.nav.nearest_walkable(roam, 4))


func _raider(sim: RefCounted, entry: Dictionary) -> void:
	if sim.calendar.tick < int(entry.next_think):
		var target: RefCounted = sim.agents[int(entry.target)] if int(entry.target) >= 0 else null
		if target != null and target.is_present() and absi(target.cell.x - entry.cell.x) <= 1 and absi(target.cell.z - entry.cell.z) <= 1:
			_strike(sim, entry, target)
		return
	entry.next_think = sim.calendar.tick + 5
	var settlement: Dictionary = sim.settlements.get_settlement(int(entry.settlement_id))
	if settlement.is_empty():
		entry.state = "retreat"
	match str(entry.state):
		"approach":
			if sim.is_veiled(settlement.center, entry.cell):
				entry.state = "retreat"
				sim.raids.on_turned_back(sim, entry, "cause_veiled")
				return
			# Raiders make for the nearest chest with goods in it, or the camp.
			var goal: Vector3i = sim.settlements.store_access(sim, int(settlement.id), entry.cell)
			if goal.x < 0:
				goal = settlement.camp
			if Vector2(entry.cell.x - goal.x, entry.cell.z - goal.z).length() <= 1.5:
				entry.state = "loot"
			else:
				_path_to(sim, entry, goal)
		"loot":
			_loot(sim, entry, settlement)
		"altar":
			_desecrate(sim, entry, settlement)
		"retreat":
			_path_to(sim, entry, entry.home)
			if entry.cell == entry.home or (entry.path.is_empty() and Vector2(entry.cell.x - entry.home.x, entry.cell.z - entry.home.z).length() < 3.0):
				sim.raids.on_left(sim, entry)
				entries.erase(entry.id)
				return
	if str(entry.state) != "retreat":
		var defenders: Array = _people_near(sim, entry.cell, 6.0)
		var band: int = sim.raids.band_size(int(entry.band))
		var fighters: int = 0
		for agent in defenders:
			if agent.activity == "fighting":
				fighters += 1
		if fighters >= band:
			entry.state = "retreat"
			sim.raids.on_turned_back(sim, entry, "cause_defenders|%d" % fighters)
			return
		if not defenders.is_empty():
			entry.target = defenders[0].id


func _loot(sim: RefCounted, entry: Dictionary, settlement: Dictionary) -> void:
	var room: int = int(Balance.number("threats.raider.carry")) - int(entry.carry.get("amount", 0))
	var taken: int = 0
	var resources: Array = sim.settlements.stock_of(int(settlement.id)).keys()
	resources.sort()
	for resource in resources:
		if room <= 0:
			break
		var got: int = sim.settlements.take(sim, int(settlement.id), resource, room, entry.cell)
		if got > 0:
			entry.carry = {"resource": resource, "amount": int(entry.carry.get("amount", 0)) + got}
			sim.raids.note_loot(int(entry.band), resource, got)
			room -= got
			taken += got
	entry.state = "altar" if bool(entry.targets_altar) else "retreat"


## Raiders who have heard of the god break its altar.
func _desecrate(sim: RefCounted, entry: Dictionary, settlement: Dictionary) -> void:
	var altar: Vector3i = Vector3i(-1, -1, -1)
	var torn: bool = false
	for id in settlement.get("shrine_ids", []):
		var shrine: Dictionary = sim.faith.get_shrine(id)
		if not shrine.is_empty() and shrine.kind in ["altar", "cutting"] and shrine.state != "fallen":
			altar = shrine.cell
			# A branch's cutting is torn up rather than smashed.
			torn = shrine.kind == "cutting"
			break
	if altar.x < 0:
		entry.state = "retreat"
		return
	if Vector2(entry.cell.x - altar.x, entry.cell.z - altar.z).length() > 2.0:
		_path_to(sim, entry, sim.nav.nearest_walkable(altar, 2))
		return
	sim.set_block(altar, 0 if torn else Registry.id("cobble"), 0, "raid:%d" % int(entry.band))
	sim.raids.note_desecration(int(entry.band))
	entry.state = "retreat"


## A defender's blow; a threat at no health is killed or driven off.
func hit(sim: RefCounted, id: int, damage: float, by: RefCounted) -> void:
	if not entries.has(id):
		return
	var entry: Dictionary = entries[id]
	entry.hp = float(entry.hp) - damage
	if float(entry.hp) <= 0.0:
		if entry.kind == "raider":
			sim.raids.on_driven_off(sim, entry)
		sim.chronicle_event("threat_driven_off", by.settlement_id, {"name": by.given_name, "kind": entry.kind}, "", [by.id])
		entries.erase(id)
	elif entry.kind == "wolf":
		entry.state = "flee"
		_path_to(sim, entry, entry.home)


## Defend step: close in on a threat and strike it while it stays.
func attack_step(sim: RefCounted, agent: RefCounted, step: Dictionary, step_ticks: int) -> int:
	var id: int = int(step.get("threat", -1))
	if id < 0:
		var nearest: float = INF
		for other in list():
			var d: float = Vector2(other.cell.x - agent.cell.x, other.cell.z - agent.cell.z).length()
			if d < nearest and d < 16.0:
				nearest = d
				id = other.id
	if not entries.has(id):
		return Plans.DONE
	if float(agent.health.hp) < 40.0:
		return Plans.Fail.TOO_DANGEROUS
	if step_ticks > 300:
		return Plans.Fail.TIMED_OUT
	var target: Vector3i = entries[id].cell
	agent.inside = -1
	if absi(target.x - agent.cell.x) > 1 or absi(target.z - agent.cell.z) > 1:
		if agent.path.is_empty() or step_ticks % 6 == 0:
			if not sim.nav.can_path():
				return Plans.RUNNING
			var route: Array[Vector3i] = sim.nav.find_path(agent.cell, sim.nav.nearest_walkable(target, 1))
			if route.is_empty():
				return Plans.Fail.NO_PATH
			agent.path = route
		agent.activity = "walking"
		return Plans.RUNNING
	agent.path.clear()
	agent.activity = "fighting"
	if step_ticks % 6 == 0:
		var damage: float = 1.2 * 6.0 * (1.0 + maxf(agent.personality.bravery, 0.0)) * agent.capacity() * Schools.strike_factor(sim, agent)
		sim.effects.action("attack_threat", agent.id, {"threat": id, "damage": damage})
	Personality.practise(agent, Personality.Skill.DEFENCE)
	return Plans.RUNNING


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "next_id": next_id, "dens": dens.duplicate()}


func from_dict(data: Dictionary) -> void:
	entries = data.entries
	next_id = int(data.next_id)
	dens = data.dens
