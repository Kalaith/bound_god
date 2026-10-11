extends RefCounted
## Tools (M20): how many a settlement wants, the smithy that makes them,
## and tools in hand. A smithy's anvil forges ore and wood into tools. A
## worker without tools takes a set at the stores whenever they use them;
## tools speed gathering and building and wear out with the work. (What an
## alchemy building refines is `alchemy.gd`'s; the first of each thing made
## is remembered here for both.)
const Balance = preload("res://scripts/core/balance.gd")
const Personality = preload("res://scripts/agents/personality.gd")

const Skill = Personality.Skill
## The chronicle's word for the first of each thing made (any other
## preparation is `first_preparation`).
const FIRST: Dictionary = {"pill": "first_pill", "tools": "first_tools"}


## Structures of a function in a settlement, by id.
static func stations(sim: RefCounted, id: int, function: String) -> Array:
	var result: Array = []
	for entry in sim.structures.built():
		if entry.functions.has(function) and sim.settlements.at_cell(entry.anchor) == id:
			result.append(int(entry.id))
	return result


## Tools wanted: a set for every `tools.people_per_set` adults, less what the
## stores hold and the hands already carry.
static func tools_short(sim: RefCounted, id: int) -> int:
	var adults: int = 0
	var held: int = 0
	for agent in sim.agents:
		if agent.is_present() and not agent.is_child and agent.settlement_id == id:
			adults += 1
			held += 1 if float(agent.tool) > 0.0 else 0
	var wanted: int = ceili(float(adults) / Balance.number("tools.people_per_set"))
	return maxi(wanted - held - sim.settlements.amount(id, "tools"), 0)


## Village buildings for crafts, as [function, reason, weight]: a smithy
## once ore is known, the stores hold some, and the settlement has hands.
static func village_wants(sim: RefCounted, id: int, people: int, have: Dictionary) -> Array:
	var result: Array = []
	if int(have.get("smithy", 0)) == 0 and people >= Balance.integer("tools.smithy_people") \
			and sim.settlements.amount(id, "ore") >= Balance.integer("tools.smithy_ore"):
		result.append(["smithy", "reason_no_smithy", 0.72])
	# A herbalist's workshop once herbs grow in reach (M20b): anyone may brew
	# a healing draught; a sect's alchemy room does the same and more.
	var alchemy: int = int(have.get("herbal_workshop", 0)) + int(have.get("alchemy_room", 0))
	if alchemy == 0 and people >= Balance.integer("alchemy.workshop_people") and sim.herbs != null and sim.herbs.count() > 0:
		result.append(["herbal_workshop", "reason_no_herbal_workshop", 0.5])
	return result


## Work with tools in hand goes faster; each tick of it wears them.
static func tool_pace(agent: RefCounted, skill: int) -> float:
	if float(agent.tool) <= 0.0 or not skill in [Skill.GATHERING, Skill.CONSTRUCTION]:
		return 1.0
	agent.tool = maxf(float(agent.tool) - 1.0, 0.0)
	return Balance.number("tools.speed")


## At the stores a worker without tools takes a set, if the chests hold one.
static func take_tool(sim: RefCounted, agent: RefCounted, settlement_id: int) -> void:
	if float(agent.tool) > 0.0 or agent.is_child or settlement_id < 0:
		return
	if sim.settlements.amount(settlement_id, "tools") <= 0:
		return
	if sim.settlements.take(sim, settlement_id, "tools", 1, agent.cell) <= 0:
		return
	agent.tool = Balance.number("tools.wear_hours") * sim.calendar.ticks_per_hour()
	agent.record(sim.calendar.tick, "message", {"text": "log_took_tools", "args": {}})


## The first pill a settlement refines, and its first tools, are remembered.
static func first_made(sim: RefCounted, agent: RefCounted, place: int, resource: String) -> void:
	if place < 0:
		return
	var key: String = "made_" + resource
	if sim.settlements.entries[place].get(key, false):
		return
	sim.settlements.entries[place][key] = true
	sim.chronicle_event(FIRST.get(resource, "first_preparation"), place, {"place": sim.settlements.entries[place].name, "name": agent.full_name(), "made": "resource_" + resource}, "", [agent.id])
