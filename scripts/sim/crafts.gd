extends RefCounted
## Pills and tools (M20): how many a settlement wants, the buildings that
## make them, and tools in hand. An alchemy room's furnace refines spirit
## herbs into foundation pills that steady a breakthrough; a smithy's anvil
## forges ore and wood into tools. A worker without tools takes a set at
## the stores whenever they use them; tools speed gathering and building
## and wear out with the work.
const Balance = preload("res://scripts/core/balance.gd")
const Kitchens = preload("res://scripts/sim/kitchens.gd")
const Personality = preload("res://scripts/agents/personality.gd")

const Skill = Personality.Skill
## The chronicle's word for the first of each thing made.
const FIRST: Dictionary = {"pill": "first_pill", "tools": "first_tools"}


## Structures of a function in a settlement, by id.
static func stations(sim: RefCounted, id: int, function: String) -> Array:
	var result: Array = []
	for entry in sim.structures.built():
		if entry.functions.has(function) and sim.settlements.at_cell(entry.anchor) == id:
			result.append(int(entry.id))
	return result


## Pills the stores should hold: one for each cultivator who will soon face
## Heaven, at least `alchemy.pills_kept`, less what is there.
static func pills_short(sim: RefCounted, id: int) -> int:
	return maxi(Balance.integer("alchemy.pills_kept") - sim.settlements.amount(id, "pill"), 0)


## Herbs wanted in the stores for the pills still to refine.
static func herbs_wanted(sim: RefCounted, id: int) -> int:
	if stations(sim, id, "alchemy_room").is_empty():
		return 0
	var per: int = int(Kitchens.recipe_for("alchemy_room").inputs.herb)
	return maxi(pills_short(sim, id) * per - sim.settlements.amount(id, "herb"), 0)


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
	sim.chronicle_event(FIRST.get(resource, "first_pill"), place, {"place": sim.settlements.entries[place].name, "name": agent.full_name()}, "", [agent.id])
