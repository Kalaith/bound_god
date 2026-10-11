extends RefCounted
## Sects: institutions cultivators found by their own choice inside a
## settlement. A sect has a name, a master, members with ranks and doctrine
## weights that drift with its leaders. Founding comes from a person's
## FoundSect goal; joining from being taught by a member; succession and
## ranks are settled each day, and every change is chronicled with its cause.
## id -> {id, name: {adjective, noun} label keys, settlement_id, founded_tick, founder,
##        master, members: {agent id: rank}, doctrine: {openness, martial, secrecy, mercy, ambition},
##        manuals: Array of technique ids its dead teachers left}
const Balance = preload("res://scripts/core/balance.gd")
const Data = preload("res://scripts/core/data.gd")
const Text = preload("res://scripts/core/text.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const SectHalls = preload("res://scripts/sim/sect_halls.gd")

const DOCTRINE: Array[String] = ["openness", "martial", "secrecy", "mercy", "ambition"]
const RANKS: Array[String] = ["disciple", "elder", "master"]

var entries: Dictionary = {}
var next_id: int = 1


func ids() -> Array:
	var keys: Array = entries.keys()
	keys.sort()
	return keys


func get_sect(id: int) -> Dictionary:
	return entries.get(id, {})


## The sect of a settlement, or {}.
func in_settlement(settlement_id: int) -> Dictionary:
	for id in ids():
		if int(entries[id].settlement_id) == settlement_id:
			return entries[id]
	return {}


## A settlement may hold one sect, and only where qi is dense enough to
## cultivate.
func can_found_in(sim: RefCounted, settlement_id: int) -> bool:
	var settlement: Dictionary = sim.settlements.get_settlement(settlement_id)
	if settlement.is_empty() or not in_settlement(settlement_id).is_empty():
		return false
	return sim.qi.density(sim, settlement.center) >= Balance.number("cultivation.sect_place_qi")


## The sect's display name, from its label keys.
static func name_of(sect: Dictionary) -> String:
	if sect.is_empty():
		return ""
	return Text.format(str(Data.cultivation().sect_names.pattern), {"adjective": Text.label(sect.name.adjective), "noun": Text.label(sect.name.noun)})


## The sect's name as the chronicle keeps it: label keys, worded on display.
static func name_key(sect: Dictionary) -> String:
	return "sect_name|%s|%s" % [sect.name.adjective, sect.name.noun]


## Doctrine as a person's nature would set it.
static func leaning(agent: RefCounted) -> Dictionary:
	var p: Dictionary = agent.personality
	return {
		"openness": clampf(0.5 + 0.25 * (float(p.sociability) + float(p.curiosity)), 0.0, 1.0),
		"martial": clampf(0.5 + 0.25 * (float(p.bravery) + float(p.temper)), 0.0, 1.0),
		"secrecy": clampf(0.5 - 0.4 * float(p.sociability), 0.0, 1.0),
		"mercy": clampf(0.5 + 0.45 * float(p.kindness), 0.0, 1.0),
		"ambition": clampf(0.5 + 0.25 * (float(p.leadership) + float(p.diligence)), 0.0, 1.0),
	}


## A founder gathers their students (and theirs) into a sect. Returns its id,
## or 0 when it cannot be founded.
func found(sim: RefCounted, founder: RefCounted) -> int:
	if int(founder.cultivation.sect_id) >= 0 or not can_found_in(sim, founder.settlement_id):
		return 0
	var names: Dictionary = Data.cultivation().sect_names
	var adjective: String = str(names.default_adjective)
	for id in founder.traits:
		if names.adjectives.has(id):
			adjective = str(names.adjectives[id])
			break
	var nouns: Array = names.nouns
	var noun: String = str(nouns[(founder.id + sim.settlements.get_settlement(founder.settlement_id).name.length()) % nouns.size()])
	var id: int = next_id
	next_id += 1
	var sect: Dictionary = {"id": id, "name": {"adjective": adjective, "noun": noun}, "settlement_id": founder.settlement_id,
		"founded_tick": sim.calendar.tick, "founder": founder.id, "master": founder.id, "members": {}, "doctrine": leaning(founder), "manuals": []}
	entries[id] = sect
	_join(sect, founder, "master")
	var queue: Array = founder.cultivation.students.duplicate()
	while not queue.is_empty():
		var student: RefCounted = sim.agents[int(queue.pop_front())]
		if student.is_present() and student.settlement_id == founder.settlement_id and int(student.cultivation.sect_id) < 0:
			_join(sect, student, "disciple")
			queue.append_array(student.cultivation.students)
	_rank(sim, sect)
	for member in sect.members:
		Mind.add(sim.agents[member], "sect_founded", sim.calendar.ticks_per_day)
	sim.chronicle_event("sect_founded", founder.settlement_id, {"founder": founder.full_name(), "sect": name_key(sect), "count": sect.members.size() - 1},
		"cause_sect_students|%d" % founder.cultivation.students.size(), sect.members.keys())
	return id


func _join(sect: Dictionary, agent: RefCounted, rank: String) -> void:
	sect.members[agent.id] = rank
	agent.cultivation.sect_id = int(sect.id)


## Being taught by a member makes a disciple of the sect.
func on_taught(sim: RefCounted, teacher: RefCounted, student: RefCounted) -> void:
	var sect: Dictionary = entries.get(int(teacher.cultivation.sect_id), {})
	if sect.is_empty() or int(student.cultivation.sect_id) >= 0 or student.settlement_id != int(sect.settlement_id):
		return
	_join(sect, student, "disciple")


## Ranks from realm and students: an elder has reached Foundation
## Establishment, or Qi Refining with students of their own.
func _rank(sim: RefCounted, sect: Dictionary) -> void:
	for id in sect.members.keys():
		var agent: RefCounted = sim.agents[id]
		if id == int(sect.master):
			sect.members[id] = "master"
		elif int(agent.cultivation.realm) >= 2 or (int(agent.cultivation.realm) >= 1 and not agent.cultivation.students.is_empty()):
			sect.members[id] = "elder"
		else:
			sect.members[id] = "disciple"


## Respect for a member among the rest, the higher realm first.
static func respect(sim: RefCounted, sect: Dictionary, id: int) -> float:
	var score: float = 0.0
	for other in sect.members:
		if other != id:
			score += sim.agents[other].beliefs.opinion_of(id)
	return score + 100.0 * int(sim.agents[id].cultivation.realm)


func daily(sim: RefCounted) -> void:
	for id in ids():
		var sect: Dictionary = entries[id]
		for member in sect.members.keys():
			var agent: RefCounted = sim.agents[member]
			if not agent.is_present() or agent.settlement_id != int(sect.settlement_id):
				sect.members.erase(member)
				agent.cultivation.sect_id = -1
		_recruit(sim, sect)
		if sect.members.is_empty():
			entries.erase(id)
			sim.chronicle_event("sect_ended", int(sect.settlement_id), {"sect": name_key(sect)}, "cause_nobody_left_in_sect")
			continue
		if not sect.members.has(int(sect.master)):
			_succeed(sim, sect)
		_rank(sim, sect)
		_drift(sim, sect)
		_copy(sim, sect)
		_study(sim, sect)


## The most respected member becomes master.
func _succeed(sim: RefCounted, sect: Dictionary) -> void:
	var best: int = -1
	var best_score: float = -INF
	var members: Array = sect.members.keys()
	members.sort()
	for id in members:
		var score: float = respect(sim, sect, id)
		if score > best_score:
			best = id
			best_score = score
	sect.master = best
	sim.chronicle_event("sect_master", int(sect.settlement_id), {"name": sim.agents[best].full_name(), "sect": name_key(sect)}, "cause_master_gone", [best])


## Doctrine drifts toward the nature of its master and elders.
func _drift(sim: RefCounted, sect: Dictionary) -> void:
	var sum: Dictionary = {}
	var count: int = 0
	for id in sect.members:
		if str(sect.members[id]) == "disciple":
			continue
		var weight: int = 2 if id == int(sect.master) else 1
		var lean: Dictionary = leaning(sim.agents[id])
		for key in DOCTRINE:
			sum[key] = float(sum.get(key, 0.0)) + lean[key] * weight
		count += weight
	if count == 0:
		return
	# Precepts carved on a stele hold the doctrine steady.
	var rate: float = Balance.number("cultivation.doctrine_drift") * SectHalls.drift_factor(sim, int(sect.settlement_id))
	for key in DOCTRINE:
		sect.doctrine[key] = clampf(float(sect.doctrine[key]) + (float(sum[key]) / count - float(sect.doctrine[key])) * rate, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "next_id": next_id}


func from_dict(data: Dictionary) -> void:
	entries = data.entries
	next_id = int(data.next_id)


## A dead teacher's techniques are written down for the sect.
func keep_manual(sim: RefCounted, sect_id: int, teacher: RefCounted) -> void:
	var sect: Dictionary = entries.get(sect_id, {})
	if sect.is_empty():
		return
	if not sect.has("manuals"):
		sect["manuals"] = []
	for technique in teacher.cultivation.techniques:
		if not sect.manuals.has(technique):
			sect.manuals.append(technique)
			sim.chronicle_event("manual_kept", int(sect.settlement_id), {"name": teacher.full_name(), "technique": "technique_" + str(technique), "sect": name_key(sect)},
				"cause_teacher_died", [teacher.id])


## Members who lack a technique the sect keeps in its manuals may learn it
## from the page, now and then, without a teacher.
func _study(sim: RefCounted, sect: Dictionary) -> void:
	var manuals: Array = sect.get("manuals", [])
	if manuals.is_empty():
		return
	var chance: float = Balance.number("cultivation.manual_chance")
	# A library keeps the manuals where anyone may read them.
	if SectHalls.has(sim, int(sect.settlement_id), "library"):
		chance = minf(chance * Balance.number("halls.library_study_factor"), 1.0)
	var members: Array = sect.members.keys()
	members.sort()
	for id in members:
		var member: RefCounted = sim.agents[id]
		for technique in manuals:
			if member.cultivation.techniques.has(technique) or sim.rng.randf() >= chance:
				continue
			member.cultivation.techniques.append(technique)
			sim.chronicle_event("learned_from_manual", int(sect.settlement_id), {"name": member.full_name(), "technique": "technique_" + str(technique)},
				"cause_sect_manual", [id])
			break


## With a library, a living member's techniques are copied into the sect's
## manuals now and then, without waiting for their death.
func _copy(sim: RefCounted, sect: Dictionary) -> void:
	if not SectHalls.has(sim, int(sect.settlement_id), "library"):
		return
	if not sect.has("manuals"):
		sect["manuals"] = []
	var members: Array = sect.members.keys()
	members.sort()
	for id in members:
		var member: RefCounted = sim.agents[id]
		for technique in member.cultivation.techniques:
			if sect.manuals.has(technique) or sim.rng.randf() >= Balance.number("halls.library_copy_chance"):
				continue
			sect.manuals.append(technique)
			sim.chronicle_event("manual_copied", int(sect.settlement_id), {"name": member.full_name(), "technique": "technique_" + str(technique), "sect": name_key(sect)},
				"cause_library", [id])


## Cultivators living where a sect stands may choose to join it, the more
## readily the more open it is.
func _recruit(sim: RefCounted, sect: Dictionary) -> void:
	var chance: float = Balance.number("cultivation.join_chance") * (0.5 + float(sect.doctrine.openness)) * SectHalls.join_factor(sim, int(sect.settlement_id))
	for agent_id in sim.settlements.entries.get(int(sect.settlement_id), {}).get("residents", []):
		var agent: RefCounted = sim.agents[agent_id]
		if not agent.is_present() or agent.cultivation.is_empty() or int(agent.cultivation.sect_id) >= 0:
			continue
		if not CultivationState.is_cultivator(agent.cultivation) or sim.rng.randf() >= chance:
			continue
		_join(sect, agent, "disciple")
		sim.chronicle_event("joined_sect", int(sect.settlement_id), {"name": agent.full_name(), "sect": name_key(sect)}, "cause_cultivates_here", [agent.id])
