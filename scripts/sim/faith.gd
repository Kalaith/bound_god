extends RefCounted
## Shrines and the god's reach. A shrine is the sacred tree or an altar
## recognised as a Shrine structure; its congregation is whoever prays there.
## Support (devotion of recent worshippers) makes it active; Favour from
## prayers pays for miracles there; condition decays unless tended. Losing
## the shrine the god stands at expels the avatar, or leaves the god dormant.
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Text = preload("res://scripts/core/text.gd")
const FaithPeople = preload("res://scripts/sim/faith_people.gd")
const Miracles = preload("res://scripts/sim/miracles.gd")
const Template = preload("res://scripts/building/template.gd")
const Data = preload("res://scripts/core/data.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const FaithState = preload("res://scripts/agents/faith_state.gd")

const NONE := Vector3i(-1, -1, -1)

## id -> {id, name, kind (tree|altar), cell, settlement_id, condition, favour,
##        support, below_days, state (active|dormant|fallen), prayers, layout}
var shrines: Dictionary = {}
var next_id: int = 1
## Altar or tree cell -> shrine id, to notice edits quickly.
var by_cell: Dictionary = {}
## Miracle events for perception: {id, cell, radius, aspect, tick}
var events: Array = []
## The god's view of prayers at each shrine: shrine id -> Array of prayer
var feed: Dictionary = {}


func setup(sim: RefCounted) -> void:
	# A neighbouring region has no tree: the god is not there until a
	# shrine is raised and it steps through (M22).
	if not sim.features.has("sacred_tree"):
		sim.god.active_shrine_id = -1
		return
	var tree: Vector3i = sim.features.sacred_tree
	var hollow: int = sim.settlements.at_cell(tree)
	var id: int = add(sim, "tree", tree, hollow, Text.label("shrine_sacred_tree"), "active")
	shrines[id].favour = Balance.number("shrines.start_favour")
	sim.god.active_shrine_id = id
	sim.god.avatar_cell = tree + Vector3i(0, 0, 4)
	if sim.features.has("ruin"):
		var ruin: Dictionary = sim.features.ruin
		var ridge: int = add(sim, "altar", ruin.altar, sim.settlements.at_cell(ruin.altar), Text.label("shrine_ridge_altar"), "fallen")
		shrines[ridge].condition = 0.0
		var template: RefCounted = Template.from_starter(Data.starter(ruin.template))
		var layout: Array = []
		for entry in template.placement(int(ruin.rotation)):
			layout.append([ruin.origin + entry[0], entry[1], entry[2]])
		shrines[ridge].layout = layout


func add(sim: RefCounted, kind: String, cell: Vector3i, settlement_id: int, name: String, state: String) -> int:
	var id: int = next_id
	next_id += 1
	shrines[id] = {"id": id, "name": name, "kind": kind, "cell": cell, "settlement_id": settlement_id,
		"condition": 100.0, "favour": 0.0, "support": 0.0, "below_days": 0, "state": state, "prayers": [], "layout": [],
		"created_tick": sim.calendar.tick}
	by_cell[cell] = id
	feed[id] = []
	if settlement_id >= 0 and not sim.settlements.entries[settlement_id].shrine_ids.has(id):
		sim.settlements.entries[settlement_id].shrine_ids.append(id)
	return id


func ids() -> Array:
	var keys: Array = shrines.keys()
	keys.sort()
	return keys


func get_shrine(id: int) -> Dictionary:
	return shrines.get(id, {})


func shrine_name(_sim: RefCounted, id: int) -> String:
	return str(shrines.get(id, {}).get("name", ""))


func current(sim: RefCounted) -> Dictionary:
	return shrines.get(sim.god.active_shrine_id, {})


# --- Presence -----------------------------------------------------------------

func zone_center(sim: RefCounted) -> Vector3:
	var shrine: Dictionary = current(sim)
	if shrine.is_empty():
		return Vector3(sim.features.get("sacred_tree", sim.features.get("home", {}).get("center", Vector3i.ZERO)))
	var cell: Vector3i = shrine.cell
	if shrine.kind == "tree":
		return Vector3(cell.x + 1.0, cell.y, cell.z + 1.0)
	return Vector3(cell.x + 0.5, cell.y, cell.z + 0.5)


func zone_radius(sim: RefCounted) -> float:
	var shrine: Dictionary = current(sim)
	if shrine.is_empty() or sim.god.dormant:
		return 4.0
	return radius_of(shrine)


## Altars reach 16 + 6 * sqrt(support). The sacred tree always holds a small
## circle around itself, widening toward that reach as support nears the
## active threshold and shrinking back when prayers fade.
static func radius_of(shrine: Dictionary) -> float:
	var support: float = maxf(float(shrine.support), 0.0)
	var radius: float = Balance.number("shrines.radius_base") + Balance.number("shrines.radius_per_sqrt_support") * sqrt(support)
	radius = minf(radius, Balance.number("shrines.radius_max"))
	if shrine.kind == "tree":
		var share: float = clampf(support / Balance.number("shrines.active_support"), 0.0, 1.0)
		radius = lerpf(Balance.number("shrines.tree_min_radius"), radius, share)
	return radius


## Where a worshipper stands: beside the altar or the tree.
func shrine_access(sim: RefCounted, id: int, from: Vector3i) -> Vector3i:
	var shrine: Dictionary = shrines.get(id, {})
	if shrine.is_empty():
		return NONE
	var cached: Vector3i = shrine.get("access", NONE)
	if cached.x >= 0 and sim.nav.is_walkable(cached):
		return cached
	var target: Vector3i = shrine.cell + (Vector3i(1, 0, 3) if shrine.kind == "tree" else Vector3i.ZERO)
	var cell: Vector3i = sim.nav.nearest_walkable(target, 3)
	shrine["access"] = cell
	return cell


# --- Edits --------------------------------------------------------------------

## The block that anchors a shrine of each kind (the tree has none: its
## blocks are protected).
const ANCHORS: Dictionary = {"altar": "altar", "cutting": "spirit_cutting"}


## Keep shrines true to the grid: a broken altar or cutting is a fallen
## shrine, one placed again (or newly) raises one. Called for every block change.
func on_block(sim: RefCounted, cell: Vector3i, old: int, block: int, source: String) -> void:
	if source == "god" and old != 0:
		_harm(sim, cell)
	if by_cell.has(cell):
		var shrine: Dictionary = shrines[by_cell[cell]]
		if not ANCHORS.has(str(shrine.kind)):
			return
		var anchor: int = Registry.id(ANCHORS[shrine.kind])
		if block != anchor and shrine.state != "fallen":
			_fall(sim, shrine, source)
		elif block == anchor and shrine.state == "fallen":
			shrine.state = "dormant"
			shrine.condition = 60.0
			shrine.below_days = 0
			shrine["restored_tick"] = sim.calendar.tick
			sim.chronicle_event("shrine_restored", int(shrine.settlement_id), {"shrine": shrine.name}, _cause(source), _people(sim, source))
		if shrine.kind == "cutting":
			sync_sources(sim)
		return
	for kind in ANCHORS:
		if block != Registry.id(ANCHORS[kind]) or old == block:
			continue
		var settlement: int = sim.settlements.at_cell(cell)
		var place: String = sim.settlements.get_settlement(settlement).get("name", Text.label("somewhere"))
		var name: String = Text.format("shrine_named" if kind == "altar" else "shrine_cutting_named", {"place": place})
		var id: int = add(sim, kind, cell, settlement, name, "dormant")
		if kind == "cutting":
			sync_sources(sim)
		sim.chronicle_event("shrine_raised" if kind == "altar" else "cutting_planted", settlement, {"shrine": shrines[id].name}, _cause(source), _people(sim, source))


## The god breaking someone's home is felt: most lose faith, but the
## cautious, the pessimist and the hot-headed may fear it into worship.
func _harm(sim: RefCounted, cell: Vector3i) -> void:
	for entry in sim.structures.built():
		if entry.residents.is_empty() or not entry.cells.has(cell):
			continue
		for agent_id in entry.residents:
			var agent: RefCounted = sim.agents[agent_id]
			if not agent.is_present() or not agent.faith.knows or sim.calendar.tick - int(agent.faith.get("harmed_tick", -1)) < sim.calendar.ticks_per_day:
				continue
			agent.faith["harmed_tick"] = sim.calendar.tick
			var fearful: bool = not agent.has_trait("sceptic") and (agent.has_trait("cautious") or agent.has_trait("pessimist") or agent.has_trait("hot_headed"))
			if fearful:
				FaithPeople.gain(agent, 5.0)
				FaithPeople.shift_aspect(agent, FaithState.ASPECTS.find("wrath"), 0.2)
			else:
				FaithPeople.gain(agent, -Balance.number("faith.harm_loss"))
			Mind.add(agent, "feared_the_god", sim.calendar.ticks_per_day)


static func _cause(source: String) -> String:
	if source.begins_with("npc:"):
		return "cause_npc"
	if source.begins_with("raid"):
		return "cause_raid"
	return "cause_god" if source == "god" else "cause_npc"


static func _people(sim: RefCounted, source: String) -> Array:
	return [int(source.trim_prefix("npc:"))] if source.begins_with("npc:") else []


func _fall(sim: RefCounted, shrine: Dictionary, source: String) -> void:
	shrine.state = "fallen"
	shrine.condition = 0.0
	sim.chronicle_event("shrine_fell", int(shrine.settlement_id), {"shrine": shrine.name}, "cause_altar_broken|" + _cause(source), _people(sim, source))
	for agent in sim.agents:
		if agent.is_present() and int(agent.faith.shrine_id) == int(shrine.id):
			Mind.add(agent, "shrine_fell", sim.calendar.ticks_per_day)
	if int(shrine.id) == sim.god.active_shrine_id:
		expel(sim, "cause_altar_broken")


## The god leaves a shrine it can no longer hold: to the strongest active
## shrine, or into dormancy.
func expel(sim: RefCounted, cause: String) -> void:
	var best: int = -1
	for id in ids():
		var shrine: Dictionary = shrines[id]
		if id != sim.god.active_shrine_id and shrine.state == "active" and (best < 0 or float(shrine.support) > float(shrines[best].support)):
			best = id
	var from: String = shrine_name(sim, sim.god.active_shrine_id)
	if best >= 0:
		sim.god.active_shrine_id = best
		sim.god.events.append({"kind": "expelled", "to": best})
		sim.chronicle_event("god_expelled", int(shrines[best].settlement_id), {"from": from, "to": shrines[best].name}, cause)
	else:
		sim.god.dormant = true
		sim.god.events.append({"kind": "dormant"})
		sim.chronicle_event("god_dormant", -1, {"from": from}, cause)


# --- Time ---------------------------------------------------------------------

## Hourly: support from recent prayers, and the radius that follows from it.
func hourly(sim: RefCounted) -> void:
	var window: int = sim.calendar.ticks_for_days(Balance.number("shrines.support_window_days"))
	var now: int = sim.calendar.tick
	for id in ids():
		var shrine: Dictionary = shrines[id]
		var latest: Dictionary = {}
		for prayer in shrine.prayers:
			if now - int(prayer.tick) <= window:
				latest[int(prayer.agent)] = true
		var support: float = 0.0
		for agent_id in latest:
			var agent: RefCounted = sim.agents[agent_id]
			if agent.is_present():
				support += float(agent.faith.devotion) / 100.0
		shrine.support = support
	FaithPeople.hourly(sim)


## Daily: condition decays, shrines wake and sleep with their support, renown
## is counted, people's faith drifts and old prayers are forgotten.
func daily(sim: RefCounted) -> void:
	var threshold: float = Balance.number("shrines.active_support")
	_forget_old_prayers(sim)
	for id in ids():
		var shrine: Dictionary = shrines[id]
		if shrine.state == "fallen":
			continue
		shrine.condition = maxf(float(shrine.condition) - Balance.number("shrines.condition_decay_per_day"), 0.0)
		# The sacred tree never sleeps; its reach shrinks with its support instead.
		# A cutting carries the tree's own life, so fewer prayers wake it.
		var needed: float = threshold * (Balance.number("shrines.cutting_support") if shrine.kind == "cutting" else 1.0)
		var supported: bool = float(shrine.support) >= needed or shrine.kind == "tree"
		if supported:
			shrine.below_days = 0
			if shrine.state != "active":
				shrine.state = "active"
				sim.chronicle_event("shrine_active", int(shrine.settlement_id), {"shrine": shrine.name}, "cause_support|%.1f" % float(shrine.support))
		else:
			shrine.below_days = int(shrine.below_days) + 1
			if shrine.state == "active" and shrine.below_days >= Balance.integer("shrines.dormant_days"):
				shrine.state = "dormant"
				sim.chronicle_event("shrine_dormant", int(shrine.settlement_id), {"shrine": shrine.name}, "cause_low_support")
				if id == sim.god.active_shrine_id:
					expel(sim, "cause_low_support")
	if sim.god.dormant:
		for id in ids():
			if shrines[id].state == "active":
				sim.god.dormant = false
				sim.god.active_shrine_id = id
				sim.god.events.append({"kind": "awakened", "to": id})
				sim.chronicle_event("god_awakened", int(shrines[id].settlement_id), {"shrine": shrines[id].name}, "cause_support|%.1f" % float(shrines[id].support))
				break
	var renown: int = 0
	for agent in sim.agents:
		if agent.is_present() and agent.faith.knows:
			renown += 1
	sim.god.renown = renown
	FaithPeople.daily(sim)
	var keep: Array = []
	for event in events:
		if sim.calendar.tick - int(event.tick) < sim.calendar.ticks_per_day:
			keep.append(event)
	events = keep


# --- Prayer -------------------------------------------------------------------

## Prayers older than a few days leave the god's feed and the shrine's
## memory (support counts only recent ones), so years of meditation do not
## leave a long-dead plea at the top of the feed.
func _forget_old_prayers(sim: RefCounted) -> void:
	var oldest: int = sim.calendar.tick - sim.calendar.ticks_for_days(Balance.number("shrines.prayer_keep_days"))
	for id in ids():
		for list in [shrines[id].prayers, feed.get(id, [])]:
			while not list.is_empty() and int(list[0].tick) < oldest:
				list.pop_front()


## A finished prayer: Favour for the shrine, a line in the god's feed.
func record_prayer(sim: RefCounted, agent: RefCounted, shrine_id: int, intent: Dictionary) -> void:
	var shrine: Dictionary = shrines.get(shrine_id, {})
	var entry: Dictionary = {"tick": sim.calendar.tick, "agent": agent.id, "intent": intent.duplicate(), "shrine": shrine_id, "answered": false}
	if not shrine.is_empty() and shrine.state != "fallen":
		var gain: float = float(agent.faith.devotion) * Balance.number("shrines.favour_per_devotion")
		if float(shrine.condition) < Balance.number("shrines.low_condition"):
			gain *= 0.5
		if sim.meditating:
			gain *= Balance.number("shrines.meditation_favour")
		shrine.favour = minf(float(shrine.favour) + gain, Balance.number("shrines.favour_cap"))
		shrine.prayers.append(entry)
		if shrine.prayers.size() > 20:
			shrine.prayers.pop_front()
		agent.faith.shrine_id = shrine_id
		feed[shrine_id].append(entry)
		if feed[shrine_id].size() > 20:
			feed[shrine_id].pop_front()
	agent.faith.last_prayer_tick = sim.calendar.tick
	agent.faith.last_intent = intent.duplicate()
	agent.stats.prayers += 1


## A shrine's remembered blocks that are missing now, the altar first.
func missing_blocks(sim: RefCounted, id: int) -> Array:
	var shrine: Dictionary = shrines.get(id, {})
	var altar: int = Registry.id("altar")
	var rubble: int = Registry.id("cobble")
	var result: Array = []
	for entry in shrine.get("layout", []):
		var current: int = sim.voxels.get_block(entry[0])
		if entry[1] == 0 or current == entry[1] or (current != 0 and current != rubble):
			continue
		if entry[1] == altar:
			result.push_front(entry)
		else:
			result.append(entry)
	return result


## The world's qi sources follow the living cuttings.
func sync_sources(sim: RefCounted) -> void:
	sim.voxels.qi_sources.clear()
	for id in ids():
		if str(shrines[id].kind) == "cutting" and str(shrines[id].state) != "fallen":
			sim.voxels.qi_sources[shrines[id].cell] = true
	sim.qi.clear_cache()


# --- Contract used by other systems -------------------------------------------

func perceive(sim: RefCounted, agent: RefCounted, radius: float) -> bool:
	return FaithPeople.perceive(sim, agent, radius)


## Who learns a design offered at the shrine: those who know the god.
func hears_offer(_sim: RefCounted, agent: RefCounted) -> bool:
	return bool(agent.faith.knows)


func wants_shrine(sim: RefCounted, agent: RefCounted) -> bool:
	return FaithState.is_believer(agent.faith) and not settlement_has_shrine(sim, agent.settlement_id)


func settlement_has_shrine(sim: RefCounted, settlement_id: int) -> bool:
	if not sim.settlements.entries.has(settlement_id):
		return false
	for id in sim.settlements.entries[settlement_id].shrine_ids:
		if shrines.has(id) and shrines[id].state != "fallen":
			return true
	return false


## How much a settlement's living shrine draws newcomers.
func settlement_renown(sim: RefCounted, settlement_id: int) -> float:
	for id in sim.settlements.get_settlement(settlement_id).get("shrine_ids", []):
		if shrines.has(id) and shrines[id].state == "active":
			return 0.1 + minf(float(sim.god.renown) / 40.0, 0.3)
	return 0.0


func tell_story(sim: RefCounted, teller: RefCounted, listener: RefCounted) -> void:
	FaithPeople.tell_story(sim, teller, listener)


func apply_command(sim: RefCounted, command: Dictionary) -> Dictionary:
	return Miracles.apply_command(sim, command)


func to_dict() -> Dictionary:
	return {"shrines": shrines.duplicate(true), "next_id": next_id, "events": events.duplicate(true), "feed": feed.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	shrines = data.shrines
	next_id = int(data.next_id)
	events = data.events
	feed = data.feed
	by_cell.clear()
	for id in shrines:
		by_cell[shrines[id].cell] = id
