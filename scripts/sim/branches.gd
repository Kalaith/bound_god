extends RefCounted
## Branches (M21): an elder of a crowded or ambitious sect carries a cutting
## of the sacred tree to a free founding ground, plants it by the new camp
## and founds a branch sect there; the founder's students and admirers may
## follow. The cutting is a shrine anchor (faith.gd) and a qi source, so a
## branch can cultivate far from the tree. Every founding is the founder's
## own choice (goal FOUND_BRANCH) and is chronicled with its cause.
## A branch sect is an ordinary sect with `parent` (the sect it came from,
## -1 once it breaks away) and `branch` (the place's label key).
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Text = preload("res://scripts/core/text.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")
const Qi = preload("res://scripts/sim/qi.gd")

const NONE := Vector3i(-1, -1, -1)
## Why a founder set out, carried in the goal's `extra`.
enum Cause { CROWDED = 1, AMBITION = 2, SCHISM = 3 }
const CAUSES: Dictionary = {Cause.CROWDED: "cause_branch_crowded", Cause.AMBITION: "cause_branch_ambition", Cause.SCHISM: "cause_branch_schism"}
## A goal target at or above this names a ground abroad: region * ABROAD + ground (M22).
const ABROAD: int = 1000


static func is_abroad(target: int) -> bool:
	return target >= ABROAD


## The first free ground in another region the world knows of, as a target, or -1.
static func ground_abroad(sim: RefCounted) -> int:
	for entry in sim.abroad:
		return int(entry.region) * ABROAD + int(entry.ground)
	return -1


# --- Cuttings -------------------------------------------------------------------

## Every living cutting shrine (not fallen), in id order.
static func cuttings(sim: RefCounted) -> Array:
	var result: Array = []
	if sim.faith == null:
		return result
	for id in sim.faith.ids():
		var shrine: Dictionary = sim.faith.shrines[id]
		if str(shrine.kind) == "cutting" and str(shrine.state) != "fallen":
			result.append(shrine)
	return result


## The living cutting of a settlement, or {}.
static func cutting_of(sim: RefCounted, settlement_id: int) -> Dictionary:
	for shrine in cuttings(sim):
		if int(shrine.settlement_id) == settlement_id:
			return shrine
	return {}


## The densest qi any living cutting gives a cell.
static func cutting_qi(sim: RefCounted, cell: Vector3i) -> float:
	return Qi.cutting_qi(sim.voxels, cell)


## Where a cutting is planted: open grass a few steps from the camp, away
## from the chest.
static func cutting_spot(sim: RefCounted, camp: Vector3i) -> Vector3i:
	if camp.x < 0:
		return NONE
	var grass: int = Registry.id("grass")
	for side in [Vector3i(0, 0, -3), Vector3i(-3, 0, 0), Vector3i(3, 0, 3), Vector3i(-3, 0, -3), Vector3i(0, 0, 4), Vector3i(4, 0, 0)]:
		var cell: Vector3i = sim.nav.surface(camp.x + side.x, camp.z + side.z)
		if cell.x < 0 or sim.voxels.get_block(cell) != 0 or sim.is_occupied(cell) or sim.is_reserved_cell(cell):
			continue
		if sim.voxels.get_block(cell + Vector3i.DOWN) == grass:
			return cell
	return NONE


# --- Grounds and sects --------------------------------------------------------

## A founding ground nobody lives on.
static func ground_free(sim: RefCounted, index: int) -> bool:
	var id: int = sim.settlements.on_ground(index)
	if id < 0:
		return true
	for agent_id in sim.settlements.entries[id].residents:
		if sim.agents[agent_id].is_present():
			return false
	return true


## The free founding ground nearest `from`, or -1.
static func nearest_free_ground(sim: RefCounted, from: Vector3i) -> int:
	var best: int = -1
	var best_distance: float = INF
	var grounds: Array = sim.features.get("grounds", [])
	for index in range(grounds.size()):
		if not ground_free(sim, index):
			continue
		var d: float = Vector2(grounds[index].center.x - from.x, grounds[index].center.z - from.z).length()
		if d < best_distance:
			best = index
			best_distance = d
	return best


## Branches of a sect that still stand (have members and keep the link).
static func living_branches(sim: RefCounted, sect_id: int) -> Array:
	var result: Array = []
	for id in sim.sects.ids():
		var sect: Dictionary = sim.sects.entries[id]
		if int(sect.get("parent", -1)) == sect_id and not sect.members.is_empty():
			result.append(id)
	return result


static func is_branch(sect: Dictionary) -> bool:
	return not str(sect.get("branch", "")).is_empty()


static func parent_of(sim: RefCounted, sect: Dictionary) -> Dictionary:
	return sim.sects.get_sect(int(sect.get("parent", -1)))


## How many of a sect's members sit round the tree's ring more than it holds.
static func crowded(sim: RefCounted, sect: Dictionary) -> bool:
	return sect.members.size() >= Balance.integer("branches.crowded")


# --- Wants --------------------------------------------------------------------

## An elder weighs carrying a cutting to free land: {utility, ground, cause},
## or {} when they would not.
static func founding(sim: RefCounted, agent: RefCounted, abstract: bool = false) -> Dictionary:
	if sim.sects == null or agent.is_child or int(agent.cultivation.get("sect_id", -1)) < 0:
		return {}
	var sect: Dictionary = sim.sects.get_sect(int(agent.cultivation.sect_id))
	if sect.is_empty() or str(sect.members.get(agent.id, "")) != "elder" or int(agent.cultivation.realm) < 1:
		return {}
	if sim.calendar.day() - agent.joined_day < Balance.integer("branches.settled_days") or (not abstract and Schedule.is_sleep_time(sim, agent)):
		return {}
	if float(sim.calendar.tick - int(sect.founded_tick)) / sim.calendar.ticks_per_day < Balance.number("branches.after_days"):
		return {}
	if living_branches(sim, int(sect.id)).size() >= Balance.integer("branches.most"):
		return {}
	# A sect keeps enough of its own to go on with.
	if sect.members.size() - 1 < Balance.integer("branches.keep"):
		return {}
	# A sect sends out one founder at a time, and lets a branch take root first.
	if sim.calendar.tick - int(sect.get("last_branch_tick", -sim.calendar.ticks_per_day * 1000)) < sim.calendar.ticks_for_days(Balance.number("branches.between_days")):
		return {}
	for member in sect.members:
		var other: RefCounted = sim.agents[member]
		if int(member) != agent.id and not other.intention.is_empty() and int(other.intention.goal.kind) == Goals.Kind.FOUND_BRANCH and int(other.intention.goal.extra) > 0:
			return {}
	var crowd: bool = crowded(sim, sect)
	var p: Dictionary = agent.personality
	var ambition: float = clampf(float(p.leadership) * 0.6 + float(agent.cultivation.drive) * 0.6 - 0.4, 0.0, 1.0)
	# An elder at odds with the master, and the master with them, may leave
	# to found a rival sect (M22: a schism within the sect).
	var feud: bool = at_odds(sim, agent, sect)
	if not crowd and ambition <= 0.0 and not feud:
		return {}
	var ground: int = nearest_free_ground(sim, sim.settlements.get_settlement(agent.settlement_id).get("center", agent.cell))
	var far: float = 1.0
	if ground < 0:
		# Every ground at home is taken: a ground in another region (M22).
		ground = ground_abroad(sim)
		far = Balance.number("branches.abroad_factor")
	if ground < 0:
		return {}
	# One founding at a time sets out for a ground.
	for other in sim.pursuers(Goals.key_of(Goals.Kind.FOUND_BRANCH, ground)):
		if int(other) != agent.id:
			return {}
	var utility: float = (Balance.number("branches.found_base") + (Balance.number("branches.found_crowd") if crowd else 0.0)
		+ Balance.number("branches.found_ambition") * ambition) * agent.capacity() * far
	if feud:
		return {"utility": utility + Balance.number("branches.found_ambition"), "ground": ground, "cause": Cause.SCHISM}
	return {"utility": utility, "ground": ground, "cause": Cause.CROWDED if crowd else Cause.AMBITION}


## An elder and the master who think ill of one another.
static func at_odds(sim: RefCounted, agent: RefCounted, sect: Dictionary) -> bool:
	var master: int = int(sect.master)
	if master == agent.id or not sim.agents[master].is_present():
		return false
	var line: float = Balance.number("branches.schism_opinion")
	return agent.beliefs.opinion_of(master) < line and sim.agents[master].beliefs.opinion_of(agent.id) < line


## A member of a sect weighs following a branch of it founded on a ground:
## its founder taught them or they think well of the founder, and the branch
## is not yet full. {utility, ground} or {}.
static func following(sim: RefCounted, agent: RefCounted, abstract: bool = false) -> Dictionary:
	if sim.sects == null or agent.is_child or int(agent.cultivation.get("sect_id", -1)) < 0:
		return {}
	var sect: Dictionary = sim.sects.get_sect(int(agent.cultivation.sect_id))
	if sect.is_empty() or str(sect.members.get(agent.id, "")) == "master" or (not abstract and Schedule.is_sleep_time(sim, agent)):
		return {}
	if sect.members.size() - 1 < Balance.integer("branches.keep"):
		return {}
	var abroad: Dictionary = _follow_abroad(sim, agent, sect)
	if not abroad.is_empty():
		return abroad
	for branch_id in living_branches(sim, int(sect.id)) + rivals(sim, agent, sect):
		var branch: Dictionary = sim.sects.entries[branch_id]
		var ground: int = int(sim.settlements.get_settlement(int(branch.settlement_id)).get("ground", -1))
		if ground < 0 or branch.members.size() > Balance.integer("branches.followers"):
			continue
		var left: int = int(agent.cultivation.get("left_branches", {}).get(int(branch_id), -1))
		if left >= 0 and sim.calendar.tick - left < sim.calendar.ticks_for_days(Balance.number("branches.left_days")):
			continue
		var founder: int = int(branch.founder)
		var taught: bool = int(agent.cultivation.teacher) == founder
		var opinion: float = agent.beliefs.opinion_of(founder)
		# Their teacher's branch, a founder they admire, or, from a crowded
		# sect, any founder they do not dislike: room to sit under a cutting.
		var room: bool = crowded(sim, sect) and opinion >= 0.0
		if not taught and not room and opinion < Balance.number("branches.follow_opinion"):
			continue
		var utility: float = Balance.number("branches.follow_base") * (1.3 if taught else 1.0) * (1.0 + clampf(opinion / 100.0, 0.0, 0.5))
		if crowded(sim, sect):
			utility *= 1.3
		return {"utility": utility * agent.capacity(), "ground": ground}
	return {}


## A branch of the sect abroad whose founder taught this person or whom they
## admire: {utility, ground (as an abroad target)} or {}.
static func _follow_abroad(sim: RefCounted, agent: RefCounted, sect: Dictionary) -> Dictionary:
	for entry in sect.get("abroad", []):
		if int(entry.get("followers", 0)) >= Balance.integer("branches.followers"):
			continue
		var founder: int = int(entry.founder)
		var taught: bool = int(agent.cultivation.teacher) == founder
		if not taught and agent.beliefs.opinion_of(founder) < Balance.number("branches.follow_opinion"):
			continue
		return {"utility": Balance.number("branches.follow_base") * Balance.number("branches.abroad_factor") * agent.capacity(),
			"ground": int(entry.region) * ABROAD + int(entry.ground)}
	return {}


## Someone sets out from the valley for a ground in another region: they
## leave this world (the campaign carries them, sim/travel.gd), the parent
## sect's name, doctrine and manuals with them.
static func emigrate(sim: RefCounted, agent: RefCounted, target: int, cause: int) -> void:
	var sect: Dictionary = sim.sects.get_sect(int(agent.cultivation.get("sect_id", -1))) if sim.sects != null else {}
	var parent: Dictionary = {"region": sim.region_id, "sect": int(sect.get("id", -1)), "founder": agent.id if cause > 0 else -1,
		"name": sect.get("name", {}).duplicate(), "doctrine": sect.get("doctrine", {}).duplicate(), "manuals": sect.get("manuals", []).duplicate()}
	var region: int = target / ABROAD
	var ground: int = target % ABROAD
	if cause <= 0:
		for entry in sect.get("abroad", []):
			if int(entry.region) == region and int(entry.ground) == ground:
				entry["followers"] = int(entry.get("followers", 0)) + 1
				parent.founder = int(entry.founder)
	elif not sect.is_empty():
		sect["last_branch_tick"] = sim.calendar.tick
	sim.outbound.append({"kind": "emigrant", "region": region, "ground": ground, "cause": cause, "agent": agent.id, "record": agent.to_dict(), "parent": parent})
	var EffectsApply = load("res://scripts/sim/effects_apply.gd")
	EffectsApply._leave(sim, agent, "cause_carried_cutting_abroad" if cause > 0 else "cause_followed_abroad", false)


## An emigrant settled on a ground abroad (sim/travel.gd): the first founds
## a branch of the sect they came from (kin across regions, `parent_abroad`),
## later ones join it. Returns the branch's sect id, or 0.
static func settle_abroad(sim: RefCounted, agent: RefCounted, settlement_id: int, cause: int, parent: Dictionary) -> int:
	var here: Dictionary = sim.sects.in_settlement(settlement_id)
	if here.is_empty():
		if cutting_of(sim, settlement_id).is_empty():
			var spot: Vector3i = cutting_spot(sim, sim.settlements.get_settlement(settlement_id).camp)
			if spot.x >= 0:
				sim.set_block(spot, Registry.id("spirit_cutting"), 0, "npc:%d" % agent.id)
		var place: String = str(sim.features.grounds[int(sim.settlements.get_settlement(settlement_id).ground)].name)
		var stub: Dictionary = {"id": int(parent.sect), "name": parent.name, "doctrine": parent.doctrine, "manuals": parent.manuals}
		var id: int = sim.sects.found_branch(sim, agent, stub, settlement_id, place)
		here = sim.sects.entries[id]
		here.parent = -1
		here["parent_abroad"] = {"region": int(parent.region), "sect": int(parent.sect)}
		Mind.add(agent, "founded_branch", sim.calendar.ticks_per_day)
		sim.chronicle_event("branch_founded_abroad", settlement_id, {"name": agent.full_name(), "sect": sim.sects.name_key(here)},
			CAUSES.get(cause, "cause_branch_ambition"), [agent.id])
	elif here.get("parent_abroad", {}).get("sect", -2) == int(parent.sect):
		sim.sects.join(here, agent, "disciple")
		Mind.add(agent, "joined_branch", sim.calendar.ticks_per_day)
		sim.chronicle_event("branch_joined", settlement_id, {"name": agent.full_name(), "sect": sim.sects.name_key(here)}, "cause_came_from_afar", [agent.id])
	else:
		return 0
	_attend(sim, agent, settlement_id)
	return int(here.id)


## Sects that broke from this one in a schism, which a member who thinks ill
## of the master and not ill of the rival's founder may follow.
static func rivals(sim: RefCounted, agent: RefCounted, sect: Dictionary) -> Array:
	var result: Array = []
	if agent.beliefs.opinion_of(int(sect.master)) >= 0.0:
		return result
	for id in sim.sects.ids():
		var other: Dictionary = sim.sects.entries[id]
		if int(other.get("broke_from", -1)) == int(sect.id) and not other.members.is_empty() and agent.beliefs.opinion_of(int(other.founder)) >= 0.0:
			result.append(id)
	return result


# --- Founding -----------------------------------------------------------------

## Someone who set out for a branch arrived and settled (effects_apply.gd):
## the first plants the cutting and founds the branch; later ones join it.
## `parent_id` is the sect they belonged to before settling.
static func on_settled(sim: RefCounted, agent: RefCounted, settlement_id: int, cause: int, parent_id: int) -> void:
	var parent: Dictionary = sim.sects.get_sect(parent_id)
	if parent.is_empty():
		return
	var here: Dictionary = sim.sects.in_settlement(settlement_id)
	if here.is_empty():
		found_branch(sim, agent, parent, settlement_id, cause)
		_attend(sim, agent, settlement_id)
	elif int(here.get("parent", -1)) == parent_id or int(here.get("broke_from", -1)) == parent_id:
		parent.members.erase(agent.id)
		sim.sects.join(here, agent, "disciple")
		Mind.add(agent, "joined_branch", sim.calendar.ticks_per_day)
		_attend(sim, agent, settlement_id)
		sim.chronicle_event("branch_joined", settlement_id, {"name": agent.full_name(), "sect": sim.sects.name_key(here)},
			"cause_followed|%s" % sim.agents[int(here.founder)].full_name(), [agent.id])


## A settler knows their branch's cutting and prays there from now on.
static func _attend(sim: RefCounted, agent: RefCounted, settlement_id: int) -> void:
	var shrine: Dictionary = cutting_of(sim, settlement_id)
	if shrine.is_empty():
		return
	agent.beliefs.places["shrine:%d" % int(shrine.id)] = {"kind": "shrine", "id": int(shrine.id), "cell": shrine.cell, "state": shrine.state, "seen_tick": sim.calendar.tick}
	if agent.faith.get("knows", false):
		agent.faith.shrine_id = int(shrine.id)


## The founder plants a cutting by the camp (if none lives there) and
## becomes master of a branch sect carrying the parent's doctrine.
static func found_branch(sim: RefCounted, founder: RefCounted, parent: Dictionary, settlement_id: int, cause: int) -> int:
	var settlement: Dictionary = sim.settlements.get_settlement(settlement_id)
	if cutting_of(sim, settlement_id).is_empty():
		var spot: Vector3i = cutting_spot(sim, settlement.camp)
		if spot.x >= 0:
			sim.set_block(spot, Registry.id("spirit_cutting"), 0, "npc:%d" % founder.id)
	parent.members.erase(founder.id)
	founder.cultivation.sect_id = -1
	var place: String = str(sim.features.grounds[int(settlement.ground)].name) if settlement.has("ground") else "somewhere"
	var id: int = sim.sects.found_branch(sim, founder, parent, settlement_id, place)
	parent["last_branch_tick"] = sim.calendar.tick
	var sect: Dictionary = sim.sects.entries[id]
	if cause == Cause.SCHISM:
		# A rival, not a branch: a name of its own, no parent, and no love
		# lost (relations.gd).
		sect.parent = -1
		sect["broke_from"] = int(parent.id)
		sect.erase("branch")
		sect.name = sim.sects.name_for(sim, founder)
		sim.outbound.append({"kind": "relation", "sect": id, "other_region": sim.region_id, "other_sect": int(parent.id),
			"amount": Balance.number("branches.schism_relation"), "cause": "cause_branch_schism"})
	Mind.add(founder, "founded_branch", sim.calendar.ticks_per_day)
	sim.chronicle_event("sect_split" if cause == Cause.SCHISM else "branch_founded", settlement_id, {"name": founder.full_name(), "sect": sim.sects.name_key(sect), "parent": sim.sects.name_key(parent)},
		CAUSES.get(cause, "cause_branch_ambition"), [founder.id])
	return id


## A cultivation spot on the ring round a settlement's living cutting, for
## its own people; NONE when it has none.
static func ring_cell(sim: RefCounted, agent: RefCounted) -> Vector3i:
	var shrine: Dictionary = cutting_of(sim, agent.settlement_id)
	if shrine.is_empty():
		return NONE
	var at: Vector3i = shrine.cell
	return H.ring_cell(sim, Vector3(at.x + 0.5, at.y, at.z + 0.5), agent.id, Balance.number("branches.spot_inner"), Balance.number("branches.spot_outer"))
