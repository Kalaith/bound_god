extends RefCounted
## The god's miracles and faith commands: casting a miracle where the avatar
## stands, paid from the Favour of that shrine; whispering to one person;
## transferring to another active shrine; and the avatar's position, which
## people can see. Every miracle is a visible event people interpret.
const Balance = preload("res://scripts/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")
const FaithPeople = preload("res://scripts/sim/faith_people.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const MiraclesCultivation = preload("res://scripts/sim/miracles_cultivation.gd")

## The nudges a whisper can carry, as goal kinds.
const NUDGES: Dictionary = {
	"rest": Goals.Kind.SLEEP, "pray": Goals.Kind.PRAY, "build": Goals.Kind.BUILD, "gather": Goals.Kind.GATHER,
	"talk": Goals.Kind.CHAT, "make_peace": Goals.Kind.RECONCILE, "shelter": Goals.Kind.TAKE_SHELTER,
}


static func apply_command(sim: RefCounted, command: Dictionary) -> Dictionary:
	match str(command.get("type", "")):
		"cast_miracle":
			return cast(sim, str(command.get("miracle", "")), command.get("cell", Vector3i(-1, -1, -1)), command)
		"transfer_shrine":
			return _transfer(sim, int(command.get("shrine", -1)))
		"avatar_moved":
			sim.god.avatar_cell = command.cell
			return {"ok": true, "reason": ""}
		"post_request":
			return sim.requests.post(sim, command) if sim.requests != null else {"ok": false, "reason": "command_unknown"}
	return {"ok": false, "reason": "command_unknown"}


## The god's identity: the devotion-weighted aspects of everyone who knows it.
static func identity(sim: RefCounted) -> PackedFloat32Array:
	var result := PackedFloat32Array([0, 0, 0, 0, 0])
	for agent in sim.agents:
		if agent.is_present() and agent.faith.knows:
			for i in range(result.size()):
				result[i] += agent.faith.aspects[i] * float(agent.faith.devotion)
	FaithState.normalise(result)
	return result


## [cost, contradicts] for a miracle given who the god is believed to be.
static func cost_of(sim: RefCounted, definition: Dictionary) -> Array:
	var cost: float = float(definition.cost)
	var aspect: int = FaithState.ASPECTS.find(str(definition.aspect))
	if aspect < 0:
		return [cost, false]
	var who: PackedFloat32Array = identity(sim)
	var dominant: int = FaithState.strongest_aspect(who)
	if aspect == dominant and who[dominant] > 0.25:
		return [cost * (1.0 - Balance.number("miracle_costs.identity_discount")), false]
	if who[aspect] < 0.12 and who[dominant] >= 0.35:
		return [cost * (1.0 + Balance.number("miracle_costs.identity_penalty")), true]
	return [cost, false]


## Why a miracle cannot be cast now, or "".
static func problem(sim: RefCounted, id: String, cell: Vector3i) -> String:
	var definition: Dictionary = Data.miracle(id)
	if definition.is_empty():
		return "miracle_unknown"
	var shrine: Dictionary = sim.faith.current(sim)
	if sim.god.dormant:
		return "" if id == "whisper" else "edit_dormant"
	if shrine.is_empty() or shrine.state != "active":
		return "miracle_no_shrine"
	if not sim.in_zone(Vector3(cell) + Vector3(0.5, 0, 0.5)):
		return "edit_outside_zone"
	if sim.god.renown < int(definition.renown_required):
		return "miracle_renown"
	if float(shrine.favour) < float(cost_of(sim, definition)[0]):
		return "miracle_favour"
	if str(definition.effect) == "calm_sky" and not sim.weather.is_wet() and sim.weather.kind != "snow":
		return "miracle_sky_clear"
	return ""


static func cast(sim: RefCounted, id: String, cell: Vector3i, args: Dictionary) -> Dictionary:
	var reason: String = problem(sim, id, cell)
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	var definition: Dictionary = Data.miracle(id)
	var priced: Array = cost_of(sim, definition)
	var shrine: Dictionary = sim.faith.current(sim)
	var cost: float = float(priced[0])
	if sim.god.dormant:
		cost = Balance.number("miracle_costs.dormant_whisper_cost")
	var result: Dictionary
	match str(definition.effect):
		"whisper":
			result = _whisper(sim, args)
		"bless_growth":
			result = _bless_growth(sim, cell, float(definition.radius))
		"kindle":
			sim.kindled.append({"cell": cell, "radius": float(definition.radius), "until": _next_dawn(sim)})
			result = {"ok": true, "reason": "miracle_kindled"}
		"veil_of_fog":
			sim.veils.append({"cell": cell, "radius": float(definition.radius), "until": sim.calendar.tick + sim.calendar.ticks_per_day})
			result = {"ok": true, "reason": "miracle_veiled"}
		"mend":
			result = _mend(sim, cell, float(definition.radius))
		"bless_cultivation":
			result = MiraclesCultivation.bless(sim, args)
		"shield_trial", "defy_heaven":
			result = MiraclesCultivation.trial(sim, str(definition.effect), cell, float(definition.radius))
		"nurture":
			sim.tree_growth.nurture(sim, cell)
			result = {"ok": true, "reason": "miracle_nurtured"}
		"calm_sky":
			result = {"ok": sim.weather.calm(sim), "reason": "miracle_calmed"}
		_:
			result = {"ok": false, "reason": "miracle_unknown"}
	if not result.ok:
		return result
	if not shrine.is_empty():
		shrine.favour = maxf(float(shrine.favour) - cost, 0.0)
	if id != "whisper":
		sim.faith.events.append({"uid": sim.calendar.tick * 16 + sim.faith.events.size(), "id": id, "cell": cell,
			"radius": float(definition.radius), "aspect": definition.aspect, "tick": sim.calendar.tick, "contradicts": priced[1]})
		var answered: int = FaithPeople.answer_prayers(sim, id, cell, float(definition.radius))
		sim.chronicle_event("miracle", int(shrine.get("settlement_id", -1)), {"miracle": id}, "cause_answered|%d" % answered if answered > 0 else "cause_god")
	return result


static func _next_dawn(sim: RefCounted) -> int:
	var day_ticks: int = sim.calendar.ticks_per_day
	var dawn: int = int(Balance.number("time.dawn_hour") / 24.0 * day_ticks)
	var start: int = (sim.calendar.tick / day_ticks) * day_ticks + dawn
	return start if start > sim.calendar.tick else start + day_ticks


static func _bless_growth(sim: RefCounted, cell: Vector3i, radius: float) -> Dictionary:
	var bush: int = Registry.id("berry_bush")
	var most: int = Balance.integer("world.bush_max_berries")
	var ripened: int = 0
	for id in sim.sites.ids_sorted():
		var site: Dictionary = sim.sites.get_site(id)
		if site.kind != "bush" or site.cells.is_empty():
			continue
		var at: Vector3i = site.cells[0]
		if Vector2(at.x - cell.x, at.z - cell.z).length() <= radius and sim.voxels.get_block(at) == bush and sim.voxels.block_meta(at) < most:
			sim.set_block(at, bush, most, "god")
			ripened += 1
	ripened += sim.crops.bless(sim, cell, radius)
	if ripened > 0:
		return {"ok": true, "reason": "miracle_blessed"}
	if _sprout_bushes(sim, cell, radius, bush, most) > 0:
		return {"ok": true, "reason": "miracle_sprouted"}
	return {"ok": false, "reason": "miracle_nothing_to_bless"}


## With every bush already ripe, new ones spring from open grass nearby,
## nearest first and a few cells apart.
static func _sprout_bushes(sim: RefCounted, cell: Vector3i, radius: float, bush: int, berries: int) -> int:
	var grass: int = Registry.id("grass")
	var tall_grass: int = Registry.id("tall_grass")
	var reach: int = int(radius)
	var candidates: Array = []
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var distance: float = Vector2(dx, dz).length()
			if distance < 2.0 or distance > radius:
				continue
			var x: int = cell.x + dx
			var z: int = cell.z + dz
			var top: int = sim.voxels.top_solid_y(x, z)
			var at := Vector3i(x, top + 1, z)
			if top < 0 or sim.voxels.get_block(Vector3i(x, top, z)) != grass or not sim.voxels.in_bounds(at):
				continue
			var current: int = sim.voxels.get_block(at)
			if (current != 0 and current != tall_grass) or sim.is_occupied(at) or sim.is_reserved_cell(at) or not sim.in_zone(Vector3(at) + Vector3(0.5, 0, 0.5)):
				continue
			candidates.append([distance, at])
	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return [a[1].x, a[1].z] < [b[1].x, b[1].z])
	var planted: Array = []
	for candidate in candidates:
		if planted.size() >= Balance.integer("world.bless_sprouts"):
			break
		var at: Vector3i = candidate[1]
		var crowded: bool = false
		for other in planted:
			crowded = crowded or Vector2(at.x - other.x, at.z - other.z).length() < 3.0
		if not crowded:
			sim.set_block(at, bush, berries, "god")
			planted.append(at)
	return planted.size()


## Missing blocks of remembered buildings and shrines nearby return.
static func _mend(sim: RefCounted, cell: Vector3i, radius: float) -> Dictionary:
	var mended: int = 0
	var layouts: Array = []
	for id in sim.settlement_life.layouts:
		layouts.append(sim.settlement_life.layouts[id].layout)
	for id in sim.faith.ids():
		if not sim.faith.shrines[id].layout.is_empty():
			layouts.append(sim.faith.shrines[id].layout)
	for layout in layouts:
		for entry in layout:
			var at: Vector3i = entry[0]
			if entry[1] == 0 or Vector2(at.x - cell.x, at.z - cell.z).length() > radius:
				continue
			if sim.voxels.get_block(at) == entry[1] or sim.is_occupied(at):
				continue
			var current: int = sim.voxels.get_block(at)
			if current != 0 and current != Registry.id("cobble") and Registry.passable[current] == 0:
				continue
			sim.set_block(at, entry[1], entry[2], "god")
			mended += 1
	if mended == 0:
		return {"ok": false, "reason": "miracle_nothing_to_mend"}
	return {"ok": true, "reason": "miracle_mended"}


static func _whisper(sim: RefCounted, args: Dictionary) -> Dictionary:
	var id: int = int(args.get("agent", -1))
	if id < 0 or id >= sim.agents.size() or not sim.agents[id].is_present():
		return {"ok": false, "reason": "whisper_nobody"}
	var agent: RefCounted = sim.agents[id]
	if not sim.in_zone(agent.position):
		return {"ok": false, "reason": "edit_outside_zone"}
	if sim.god.dormant and FaithState.stage(agent.faith) < 4:
		return {"ok": false, "reason": "whisper_unheard"}
	var nudge: String = str(args.get("nudge", ""))
	if not NUDGES.has(nudge):
		return {"ok": false, "reason": "whisper_nudge"}
	sim.effects.message(-1, id, "whisper", sim.calendar.tick, {"goal_kind": NUDGES[nudge], "target": int(args.get("target", -1)), "nudge": nudge})
	return {"ok": true, "reason": "whisper_sent"}


static func _transfer(sim: RefCounted, id: int) -> Dictionary:
	var shrine: Dictionary = sim.faith.get_shrine(id)
	if shrine.is_empty() or shrine.state != "active":
		return {"ok": false, "reason": "transfer_inactive"}
	if id == sim.god.active_shrine_id:
		return {"ok": false, "reason": "transfer_here"}
	var from: String = sim.faith.shrine_name(sim, sim.god.active_shrine_id)
	sim.god.active_shrine_id = id
	sim.god.events.append({"kind": "transfer", "to": id})
	sim.chronicle_event("god_transferred", int(shrine.settlement_id), {"from": from, "to": shrine.name}, "cause_god")
	return {"ok": true, "reason": "transfer_done"}
