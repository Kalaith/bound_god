extends RefCounted
## The campaign (M22): the home valley and its neighbouring regions, each a
## world (`Sim`) of its own. Only the region the god is manifested in runs
## the detailed simulation; every other region is frozen in the abstract
## model and stepped in lockstep with it, in region id order, so the world
## does not wait. The god steps between regions through their shrines; what
## it carries (divine stock, offered designs, hotbar, renown) goes with it.
## Each region draws from its own random stream (Sim.setup), so stepping one
## never changes another's rolls.
const Sim = preload("res://scripts/sim/sim.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")
const Regions = preload("res://scripts/sim/regions.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Miracles = preload("res://scripts/sim/miracles.gd")
const Travel = preload("res://scripts/sim/travel.gd")
const Relations = preload("res://scripts/sim/relations.gd")
const Ages = preload("res://scripts/sim/ages.gd")
const Deeds = preload("res://scripts/sim/deeds.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")

var world_seed: int = 1
## Array of {id, archetype, name, sim}, index == id; region 0 is the valley.
var regions: Array = []
## The region the god is in (its Sim runs in detail).
var active: int = 0
## region id -> AbstractWorld model, for every frozen region.
var models: Dictionary = {}
## People on the road between regions (sim/travel.gd), oldest first.
var travellers: Array = []
## Relations between sects across the regions.
var relations: RefCounted = Relations.new()
## The day the regions last shared what they know of each other.
var _shared_day: int = -1
## How the world was begun (new-world options, M23).
var options: Dictionary = {}
## The named ages so far (ages.gd), oldest first.
var ages: Array = []
## Deed id -> the day it was done (deeds.gd).
var deeds: Dictionary = {}
## Region id -> how many of its chronicle entries the saga has read.
var chronicle_read: Dictionary = {}
## Chronicle kind -> times seen (and "valley:<kind>" for the valley's).
var kinds_seen: Dictionary = {}
## The book is closed (the epilogue was read); the world may go on.
var book_closed: bool = false
## The hidden realm's region id, or -1 while the roots keep it shut (M23).
var realm: int = -1


static func create(seed: int, options: Dictionary = {}) -> RefCounted:
	var campaign = load("res://scripts/sim/campaign.gd").new()
	campaign.world_seed = maxi(seed, 1)
	campaign.options = options.duplicate(true)
	var home: RefCounted = Sim.create(seed, options)
	campaign.regions.append({"id": 0, "archetype": "", "name": "region_home_valley", "sim": home})
	if options.get("regions", true) and options.get("world", "valley") == "valley":
		campaign.add_neighbours(int(options.get("neighbours", Regions.number("count"))))
	Ages.begin(campaign)
	return campaign


## The neighbouring regions, generated from the seed, frozen from the start.
func add_neighbours(count: int = -1) -> void:
	var home: RefCounted = regions[0].sim
	var archetypes: Array = Regions.archetypes()
	if count < 0:
		count = int(Regions.number("count"))
	for i in range(mini(count, archetypes.size())):
		var archetype: Dictionary = archetypes[i]
		var sim: RefCounted = Sim.create(world_seed, {"region": i + 1, "archetype": str(archetype.id), "outlaws": options.get("outlaws", true), "pace": options.get("pace", 1.0)})
		sim.calendar.tick = home.calendar.tick
		sim.settlements.today = sim.calendar.day()
		regions.append({"id": i + 1, "archetype": str(archetype.id), "name": str(archetype.name), "sim": sim})
		freeze(i + 1)


func sim_of(id: int) -> RefCounted:
	return regions[id].sim if id >= 0 and id < regions.size() else null


func active_sim() -> RefCounted:
	return regions[active].sim


func is_frozen(id: int) -> bool:
	return models.has(id)


## A region leaves the detailed simulation: its people freeze as they are.
func freeze(id: int) -> void:
	var sim: RefCounted = sim_of(id)
	var model: RefCounted = AbstractWorld.begin(sim)
	model.step = Regions.number("abstract_step")
	models[id] = model


## A region materialises: finished sites stamped, people thawed.
func thaw(id: int) -> void:
	if not models.has(id):
		return
	models[id].finish(sim_of(id))
	models.erase(id)


## Brings every frozen region up to the active region's hour (call after
## the active region steps). Wakes are the active region's affair; a frozen
## region's are ignored.
func sync() -> void:
	_catch_up()
	Travel.drain(self)
	Travel.arrive(self)
	var day: int = active_sim().calendar.day()
	if day != _shared_day:
		_shared_day = day
		Travel.share_grounds(self)
		Travel.share_sanctuary(self)
		Travel.share_traders(self)
		_realm()
		Ages.daily(self)
		Deeds.daily(self)
	_expulsion()


func _catch_up() -> void:
	var now: int = active_sim().calendar.tick
	for region in regions:
		var id: int = int(region.id)
		if not models.has(id):
			continue
		var sim: RefCounted = region.sim
		var model: RefCounted = models[id]
		var per_step: int = sim.calendar.ticks_per_hour() * model.step
		while sim.calendar.tick + per_step <= now:
			sim.meditating = active_sim().meditating
			model.step_hour(sim)


## Runs the active region `count` ticks, the others in step (headless).
func run_ticks(count: int) -> void:
	for _i in range(count):
		active_sim().step()
		if active_sim().calendar.is_new_hour():
			sync()


## Every shrine in every region: Array of {region, shrine} in region, then id order.
func shrines() -> Array:
	var result: Array = []
	for region in regions:
		var sim: RefCounted = region.sim
		if sim.faith == null:
			continue
		for id in sim.faith.ids():
			result.append({"region": int(region.id), "shrine": sim.faith.shrines[id]})
	return result


## Why the god cannot go to shrine `shrine_id` in region `to`, or "".
func transfer_refusal(to: int, shrine_id: int) -> String:
	if to == active:
		return Miracles.transfer_refusal(active_sim(), shrine_id)
	var target: RefCounted = sim_of(to)
	if target == null:
		return "transfer_inactive"
	var shrine: Dictionary = target.faith.get_shrine(shrine_id)
	if shrine.is_empty() or shrine.state != "active":
		return "transfer_inactive"
	var here: RefCounted = active_sim()
	if here.god.last_transfer_tick >= 0 and here.calendar.tick - here.god.last_transfer_tick < Miracles.transfer_cooldown_ticks(here):
		return "transfer_cooldown"
	var current: Dictionary = here.faith.current(here)
	if not current.is_empty() and float(current.favour) < cost_to(to):
		return "transfer_favour"
	return ""


## What a journey to region `to` costs from where the god stands.
func cost_to(to: int) -> float:
	return Balance.number("shrines.transfer_cost") + (Regions.number("transfer_cost") if to != active else 0.0)


## The god steps through to a shrine of another region (or of this one).
func transfer(to: int, shrine_id: int) -> Dictionary:
	if to == active:
		return active_sim().apply_command({"type": "transfer_shrine", "shrine": shrine_id})
	var refusal: String = transfer_refusal(to, shrine_id)
	if not refusal.is_empty():
		return {"ok": false, "reason": refusal}
	var here: RefCounted = active_sim()
	var current: Dictionary = here.faith.current(here)
	var cost: float = cost_to(to)
	if not current.is_empty():
		current.favour = maxf(float(current.favour) - cost, 0.0)
	_move(to, shrine_id, "cause_transfer_paid|%d" % roundi(cost))
	return {"ok": true, "reason": "transfer_done", "region": to}


## The god leaves the active region for `to`: the old region freezes, the
## new one materialises, and what the god carries goes with it.
func _move(to: int, shrine_id: int, cause: String) -> void:
	_catch_up()
	var here: RefCounted = active_sim()
	var there: RefCounted = sim_of(to)
	var from_name: String = here.faith.shrine_name(here, here.god.active_shrine_id)
	freeze(active)
	thaw(to)
	carry_god(here.god, there.god)
	here.god.active_shrine_id = -1
	here.god.dormant = false
	there.god.active_shrine_id = shrine_id
	there.god.dormant = false
	there.god.last_transfer_tick = there.calendar.tick
	there.god.events.append({"kind": "transfer", "to": shrine_id, "region": to})
	var shrine: Dictionary = there.faith.get_shrine(shrine_id)
	there.chronicle_event("god_transferred", int(shrine.settlement_id), {"from": from_name, "to": shrine.name}, cause)
	active = to


## What the god carries between regions.
static func carry_god(from: RefCounted, to: RefCounted) -> void:
	to.divine_stock = from.divine_stock.duplicate()
	to.offered = from.offered.duplicate(true)
	to.offered_at = from.offered_at.duplicate()
	to.hotbar = from.hotbar.duplicate()
	to.renown = from.renown
	to.prompts_dismissed = from.prompts_dismissed.duplicate()
	to.last_transfer_tick = from.last_transfer_tick


## When every shrine of the god's region fails, the god goes to the
## strongest active shrine in any region (free), else stays dormant.
func _expulsion() -> void:
	var here: RefCounted = active_sim()
	if not here.god.dormant or regions.size() < 2:
		return
	var best: Dictionary = {}
	for entry in shrines():
		if int(entry.region) == active or str(entry.shrine.state) != "active":
			continue
		if best.is_empty() or float(entry.shrine.support) > float(best.shrine.support):
			best = entry
	if best.is_empty():
		return
	_move(int(best.region), int(best.shrine.id), "cause_low_support")


## The hidden realm opens once the tree has grown the unlock (M23): a small
## hand-built world of its own, frozen like any region the god is not in.
func _realm() -> void:
	var home: RefCounted = sim_of(0)
	if realm >= 0:
		home.sanctuary["realm"] = true
		return
	if home.tree_growth == null or not home.tree_growth.has_unlock("root_realm"):
		return
	var archetype: Dictionary = Regions.config().realm
	var size: Array = archetype.size
	realm = regions.size()
	var sim: RefCounted = Sim.create(world_seed, {"region": realm, "archetype": str(archetype.id), "size": Vector3i(int(size[0]), int(size[1]), int(size[2])), "threats": false})
	sim.calendar.tick = home.calendar.tick
	sim.settlements.today = sim.calendar.day()
	regions.append({"id": realm, "archetype": str(archetype.id), "name": str(archetype.name), "sim": sim})
	freeze(realm)
	home.sanctuary["realm"] = true
	var tree_place: int = home.settlements.at_cell(home.features.get("sacred_tree", Vector3i.ZERO))
	home.chronicle_event("realm_opened", tree_place, {}, "cause_realm_opened")


## The god has faded: dormant, and nobody anywhere believes in it.
func faded() -> bool:
	if not active_sim().god.dormant:
		return false
	for region in regions:
		for agent in region.sim.agents:
			if agent.is_present() and agent.faith.get("knows", false) and FaithState.is_believer(agent.faith):
				return false
	return true


## A fingerprint of every region.
func state_hash() -> int:
	var parts: Array = [active]
	for region in regions:
		parts.append(region.sim.state_hash())
	return hash(parts)
