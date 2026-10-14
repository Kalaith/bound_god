extends RefCounted
## Schools and schisms (M21). A branch's doctrine drifts with its own master
## and elders (sects.gd). One whose mercy, martial pride or secrecy stays at
## or beyond `branches.school_at` for `branches.school_days` days takes a
## school, each with one effect: a healing school's people heal faster, a
## sword school's defend more readily and strike harder, a hidden school's
## wealth tempts raiders less. A school is lost when its doctrine falls back.
## A branch whose doctrine lies far from its parent's, while its master
## thinks ill of the parent's master (or very far, whatever they think),
## breaks away: no parent, no traffic between them. All chronicled.
const Balance = preload("res://addons/hatchery/core/balance.gd")
const Mind = preload("res://scripts/agents/mind.gd")

## School id per doctrine weight; the order breaks ties.
const SCHOOLS: Dictionary = {"mercy": "healing", "martial": "sword", "secrecy": "hidden"}
const ORDER: Array[String] = ["mercy", "martial", "secrecy"]
const DOCTRINE: Array[String] = ["openness", "martial", "secrecy", "mercy", "ambition"]


static func daily(sim: RefCounted) -> void:
	if sim.sects == null:
		return
	for id in sim.sects.ids():
		var sect: Dictionary = sim.sects.entries[id]
		if str(sect.get("branch", "")).is_empty():
			continue
		_school(sim, sect)
		_schism(sim, sect)


static func _school(sim: RefCounted, sect: Dictionary) -> void:
	var school: String = str(sect.get("school", ""))
	if not school.is_empty():
		var weight: String = SCHOOLS.find_key(school)
		if float(sect.doctrine[weight]) < Balance.number("branches.school_lose"):
			sect.school = ""
			sect.school_days = 0
			sim.chronicle_event("school_lost", int(sect.settlement_id), {"sect": sim.sects.name_key(sect), "school": "school_" + school},
				"cause_doctrine_faded|doctrine_" + weight)
		return
	var best: String = ""
	for weight in ORDER:
		if float(sect.doctrine[weight]) >= Balance.number("branches.school_at") and (best.is_empty() or float(sect.doctrine[weight]) > float(sect.doctrine[best])):
			best = weight
	if best.is_empty():
		sect["school_days"] = 0
		return
	sect["school_days"] = int(sect.get("school_days", 0)) + 1
	if int(sect.school_days) < Balance.integer("branches.school_days"):
		return
	sect["school"] = SCHOOLS[best]
	for member in sect.members:
		Mind.add(sim.agents[member], "school_taken", sim.calendar.ticks_per_day)
	sim.chronicle_event("school_taken", int(sect.settlement_id), {"sect": sim.sects.name_key(sect), "school": "school_" + SCHOOLS[best]},
		"cause_doctrine_held|doctrine_%s|%d" % [best, roundi(float(sect.doctrine[best]) * 100.0)], [int(sect.master)])


## How far two doctrines lie apart: the sum of their differences.
static func distance(a: Dictionary, b: Dictionary) -> float:
	var sum: float = 0.0
	for key in DOCTRINE:
		sum += absf(float(a.get(key, 0.5)) - float(b.get(key, 0.5)))
	return sum


static func _schism(sim: RefCounted, sect: Dictionary) -> void:
	var parent: Dictionary = sim.sects.get_sect(int(sect.get("parent", -1)))
	if parent.is_empty():
		if int(sect.get("parent", -1)) >= 0:
			# The parent sect is gone: the branch stands alone, without a schism.
			sect.parent = -1
		return
	var apart: float = distance(sect.doctrine, parent.doctrine)
	if apart < Balance.number("branches.schism_distance"):
		return
	var master: RefCounted = sim.agents[int(sect.master)]
	var opinion: float = master.beliefs.opinion_of(int(parent.master))
	if opinion >= Balance.number("branches.schism_opinion") and apart < Balance.number("branches.schism_far"):
		return
	sect.parent = -1
	sect["broke_from"] = int(parent.id)
	for member in sect.members:
		Mind.add(sim.agents[member], "schism", sim.calendar.ticks_per_day)
	var cause: String = "cause_schism_grudge|%s" % sim.agents[int(parent.master)].full_name() if opinion < Balance.number("branches.schism_opinion") else "cause_schism_doctrine"
	sim.chronicle_event("schism", int(sect.settlement_id), {"sect": sim.sects.name_key(sect), "parent": sim.sects.name_key(parent)}, cause, [int(sect.master)])


## The school of a settlement's sect, or "".
static func of(sim: RefCounted, settlement_id: int) -> String:
	if sim.sects == null:
		return ""
	# One sect to a settlement, so the order looked in does not matter (and
	# this is asked for every person every hour).
	for sect in sim.sects.entries.values():
		if int(sect.settlement_id) == settlement_id:
			return str(sect.get("school", ""))
	return ""


## How fast a person heals: a healing school's people faster.
static func heal_factor(sim: RefCounted, agent: RefCounted) -> float:
	return Balance.number("schools.heal_factor") if of(sim, agent.settlement_id) == "healing" else 1.0


## How readily a person defends: a sword school's people more.
static func defend_factor(sim: RefCounted, agent: RefCounted) -> float:
	return Balance.number("schools.defend_factor") if of(sim, agent.settlement_id) == "sword" else 1.0


static func strike_factor(sim: RefCounted, agent: RefCounted) -> float:
	return Balance.number("schools.strike_factor") if of(sim, agent.settlement_id) == "sword" else 1.0


## How much of a settlement's wealth raiders see: a hidden school's less.
static func wealth_factor(sim: RefCounted, settlement_id: int) -> float:
	return Balance.number("schools.hidden_wealth") if of(sim, settlement_id) == "hidden" else 1.0
