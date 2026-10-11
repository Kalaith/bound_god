extends RefCounted
## M20 Pills and tools: a pill steadies a trial and is refined at a furnace
## by a sect member; tools speed work, wear out, are taken at the stores and
## forged at an anvil; who wants the furnace and the anvil; the abstract
## counterparts.
const Sim = preload("res://scripts/sim/sim.gd")
const Balance = preload("res://scripts/core/balance.gd")
const EffectsApply = preload("res://scripts/sim/effects_apply.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Tribulations = preload("res://scripts/sim/tribulations.gd")
const Stores = preload("res://tools/checks/stores.gd")
const Build = preload("res://tools/checks/build.gd")
const PlanLibrary = preload("res://scripts/agents/plan_library.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const WorkPace = preload("res://scripts/sim/work_pace.gd")
const Crafts = preload("res://scripts/sim/crafts.gd")
const SectHallWants = preload("res://scripts/sim/sect_hall_wants.gd")
const AbstractCrafts = preload("res://scripts/sim/abstract/abstract_crafts.gd")
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const Meditation = preload("res://tools/checks/meditation.gd")

const Need = Personality.Need


static func _flat() -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(64, 16, 64), "ground": 4})


static func _with(sim: RefCounted, function: String) -> Dictionary:
	for entry in sim.structures.built():
		if entry.functions.has(function):
			return entry
	return {}


## Everyone present knows the stores and the building.
static func _know(sim: RefCounted, entry: Dictionary) -> void:
	for agent in sim.agents:
		if agent.is_present():
			agent.beliefs.stock = sim.settlements.stock_of(1).duplicate()
			agent.beliefs.structures[int(entry.id)] = {"functions": entry.functions.duplicate(), "cell": entry.anchor, "template_id": "", "seen_tick": 0}


## A foundation pill kept for a trial adds to its preparation and is
## swallowed, chronicled, when Heaven answers; taking one from the stores
## keeps it for the trial, not in the hands.
func check_a_pill_steadies_a_breakthrough():
	var sim: RefCounted = Sim.create(11)
	var agent: RefCounted = sim.agents[0]
	agent.cultivation = CultivationState.fresh(0.6, "none", 0.9)
	agent.cultivation.realm = 1
	agent.cultivation.progress = CultivationState.needed(agent.cultivation)
	agent.needs[Need.REST] = 50.0
	agent.needs[Need.FOOD] = 50.0
	var plain: float = Tribulations.preparation(sim, agent)
	Stores.fill(sim, agent.settlement_id, {"pill": 2})
	agent.cell = sim.settlements.chest_cells(sim, agent.settlement_id)[0] + Vector3i(1, 0, 0)
	agent.carrying = {}
	EffectsApply._take_stock(sim, agent, {"resource": "pill", "amount": 1, "settlement": agent.settlement_id})
	if not bool(agent.cultivation.get("pill", false)) or not agent.carrying.is_empty():
		return "taking a pill did not keep it for the trial (%s, %s)" % [agent.cultivation.get("pill"), agent.carrying]
	if sim.settlements.amount(agent.settlement_id, "pill") != 1:
		return "taking a pill left %d in the stores" % sim.settlements.amount(agent.settlement_id, "pill")
	var helped: float = Tribulations.preparation(sim, agent)
	# The pill's help, less what its toxicity takes back.
	var expected: float = float(Data.elixir("pill").preparation) - float(Data.alchemy().toxicity.preparation) * float(Data.elixir("pill").toxicity)
	if not is_equal_approx(helped - plain, expected):
		return "a pill added %.2f to preparation" % (helped - plain)
	var id: int = sim.tribulations.announce(sim, agent, agent.cell)
	var trial: Dictionary = sim.tribulations.entries[id]
	sim.tribulations._begin(sim, trial, agent)
	if not bool(trial.get("pill", false)) or agent.cultivation.has("pill") or not is_equal_approx(float(trial.preparation), helped):
		return "the pill was not swallowed when the storm broke"
	var noted: bool = false
	for entry in sim.chronicle.entries:
		noted = noted or entry.kind == "pill_eaten"
	if not noted:
		return "the pill was not chronicled"
	# A cultivator at the peak who believes in a pill takes it on the way.
	sim.tribulations.entries.erase(id)
	agent.beliefs.stock = sim.settlements.stock_of(agent.settlement_id).duplicate()
	var options: Array = PlanLibrary.plans_for(sim, agent, Goals.make(Goals.Kind.BREAKTHROUGH))
	if options.is_empty() or str(options[0].id) != "take_a_pill_first":
		return "the breakthrough plan did not take the pill first: %s" % [options]
	return ""


## An alchemy room's furnace takes herbs from the stores and refines them
## into pills for the stores, by a sect member's own choice.
func check_the_furnace_refines_herbs_into_pills():
	var sim: RefCounted = _flat()
	Build.stamp(sim, 1, "alchemy_room")
	var room: Dictionary = _with(sim, "alchemy_room")
	if room.is_empty():
		return "the Alchemy Room design is not an alchemy room"
	Stores.fill(sim, 1, {"herb": 6, "berries": 40})
	for agent in sim.agents:
		if agent.is_present():
			agent.cultivation = CultivationState.fresh(0.6, "none", 0.9)
			agent.cultivation.sect_id = 1
			agent.cultivation.realm = 1
	_know(sim, room)
	sim.run_ticks(sim.calendar.ticks_per_day)
	if sim.settlements.amount(1, "pill") < 1:
		return "no pill was refined in a day (herbs left %d, furnace %s)" % [sim.settlements.amount(1, "herb"), sim.alchemy.benches]
	var noted: bool = false
	for entry in sim.chronicle.entries:
		noted = noted or entry.kind == "first_pill"
	if not noted:
		return "the first pill was not chronicled"
	return ""


## Tools speed gathering and building (not cooking) and wear with the work;
## a worker takes a set at the stores; a smithy forges them from ore and wood.
func check_tools_speed_work_and_wear_out():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	sim.weather.kind = "clear"
	var bare: float = WorkPace.speed(sim, agent, Personality.Skill.GATHERING)
	Stores.fill(sim, 1, {"tools": 1})
	agent.cell = sim.settlements.chest_cells(sim, 1)[0] + Vector3i(1, 0, 0)
	Crafts.take_tool(sim, agent, 1)
	if float(agent.tool) <= 0.0 or sim.settlements.amount(1, "tools") != 0:
		return "a worker did not take tools from the stores"
	var wear: float = float(agent.tool)
	var tooled: float = WorkPace.speed(sim, agent, Personality.Skill.GATHERING)
	if not is_equal_approx(tooled / bare, Balance.number("tools.speed")):
		return "tools made gathering %.2f times as fast" % (tooled / bare)
	if float(agent.tool) != wear - 1.0:
		return "a tick of work did not wear the tools"
	if not is_equal_approx(WorkPace.speed(sim, agent, Personality.Skill.CRAFTING), Personality.speed(agent, Personality.Skill.CRAFTING)):
		return "tools sped cooking"
	agent.tool = 1.0
	WorkPace.speed(sim, agent, Personality.Skill.CONSTRUCTION)
	if float(agent.tool) != 0.0 or WorkPace.speed(sim, agent, Personality.Skill.GATHERING) != bare:
		return "worn-out tools still helped"
	# The smithy: ore and wood become tools by someone's choice.
	Build.stamp(sim, 1, "smithy")
	var smithy: Dictionary = _with(sim, "smithy")
	if smithy.is_empty():
		return "the Smithy design is not a smithy"
	Stores.fill(sim, 1, {"ore": 4, "wood": 10, "berries": 40})
	_know(sim, smithy)
	sim.run_ticks(sim.calendar.ticks_per_day)
	var made: int = sim.settlements.amount(1, "tools")
	for other in sim.agents:
		made += 1 if float(other.tool) > 0.0 else 0
	if made < 1:
		return "no tools were forged in a day (ore left %d)" % sim.settlements.amount(1, "ore")
	return ""


## The sect wants an alchemy room once herbs grow and one of them is
## refined; a village with ore and hands wants a smithy.
func check_who_wants_the_furnace_and_the_anvil():
	var sim: RefCounted = _flat()
	var agent: RefCounted = sim.agents[0]
	agent.cultivation = CultivationState.fresh(0.6, "none", 0.9)
	agent.cultivation.realm = 1
	var sect: Dictionary = {"members": [agent.id], "master": agent.id, "manuals": [], "doctrine": {"openness": 0.0}, "founded_tick": sim.calendar.tick}
	var have: Dictionary = {}
	var wanted: Callable = func() -> bool:
		for want in SectHallWants.wants(sim, 1, sect, have):
			if want[0] == "alchemy_room":
				return true
		return false
	if wanted.call():
		return "the sect wanted an alchemy room with no herbs growing"
	sim.herbs.plants[Vector3i(1, 5, 1)] = 0
	if not wanted.call():
		return "the sect did not want an alchemy room with herbs growing"
	have["alchemy_room"] = 1
	if wanted.call():
		return "the sect wanted a second alchemy room"
	Stores.fill(sim, 1, {"ore": Balance.integer("tools.smithy_ore")})
	var village: Array = Crafts.village_wants(sim, 1, Balance.integer("tools.smithy_people"), {})
	if village.is_empty() or village[0][0] != "smithy":
		return "a village with ore and hands did not want a smithy"
	for want in Crafts.village_wants(sim, 1, Balance.integer("tools.smithy_people") - 1, {}):
		if want[0] == "smithy":
			return "a small camp wanted a smithy"
	return ""


## The M20 exit, the sect's half: on seed 11 with a sect, offered the
## alchemy room design and the tree at Spirit Root, herbs sprout in the
## tree's qi, the sect raises an alchemy room by its own proposal, refines a
## pill and a cultivator swallows it before facing Heaven within 40 days.
func long_check_the_sect_refines_pills_for_its_trials():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	sim.apply_command({"type": "offer_template", "template": Template.from_starter(Data.starter("alchemy_room")).to_dict()})
	sim.tree_growth.maturity = 12.0
	var seen: Dictionary = _watch(sim, 40, ["herbs_sprouted", "first_pill", "pill_eaten"], ["alchemy_room"], false)
	return "" if seen.size() >= 4 else "after 40 days only %s" % str(seen)


## The M20 exit, the village's half: a settled village (housed, with its
## hall, garden and storehouse, and nobody new on the road) with ore in its
## stores, offered the smithy design, raises one by its own proposal, forges
## tools and carries them to work within 30 days. While migrants keep coming
## every free site goes to a home first (see PROGRESS.md, Known issues).
func long_check_a_village_forges_tools():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	sim.director = null
	for id in ["village_hall", "garden_patch", "store_shed", "timber_cottage", "timber_cottage", "timber_cottage", "timber_cottage"]:
		Build.stamp(sim, 1, id)
	sim.apply_command({"type": "offer_template", "template": Template.from_starter(Data.starter("smithy")).to_dict()})
	var stock: Dictionary = sim.settlements.stock_of(1).duplicate()
	stock["ore"] = 8
	Stores.fill(sim, 1, stock)
	var seen: Dictionary = _watch(sim, 30, ["first_tools"], ["smithy"], true)
	return "" if seen.size() >= 3 else "after 30 days only %s" % str(seen)


## Runs up to `days`, noting the day each chronicle kind, building function
## and (when asked) tools in someone's hands first appear; stops when all have.
static func _watch(sim: RefCounted, days: int, kinds: Array, functions: Array, tools: bool) -> Dictionary:
	var start: int = sim.calendar.tick
	var seen: Dictionary = {}
	var wanted: int = kinds.size() + functions.size() + (1 if tools else 0)
	for day in range(days):
		sim.run_ticks(sim.calendar.ticks_per_day)
		for entry in sim.chronicle.since(start):
			if entry.kind in kinds and not seen.has(entry.kind):
				seen[entry.kind] = sim.calendar.day()
		for function in functions:
			if not seen.has(function) and not _with(sim, function).is_empty():
				seen[function] = sim.calendar.day()
		if tools and not seen.has("tools_carried") and sim.agents.any(func(a: RefCounted) -> bool: return a.is_present() and float(a.tool) > 0.0):
			seen["tools_carried"] = sim.calendar.day()
		if seen.size() >= wanted:
			break
	print("      days: %s" % str(seen))
	return seen


## While abstract, herbs from the pool become pills, ore and wood tools,
## and the tools quicken the settlement's labour.
func check_abstract_pills_and_tools():
	var sim: RefCounted = _flat()
	Build.stamp(sim, 1, "alchemy_room")
	Build.stamp(sim, 1, "smithy")
	Stores.fill(sim, 1, {"ore": 4, "wood": 10})
	sim.tree_growth.unlocks.append("spirit_herbs")
	sim.herbs.pool = {"spirit_herb": {"plants": 8, "ripe": 8.0}}
	sim.agents[0].cultivation.realm = 1
	AbstractCrafts.day(sim, 1, {})
	if sim.settlements.amount(1, "pill") < 1:
		return "no pill was refined abstractly (herbs %d, pool %s)" % [sim.settlements.amount(1, "herb"), sim.herbs.pool]
	if sim.settlements.amount(1, "tools") < 1:
		return "no tools were forged abstractly"
	if AbstractCrafts.pace(sim, 1, 4) <= 1.0 or AbstractCrafts.pace(sim, 1, 0) != 1.0:
		return "tools did not quicken abstract labour"
	return ""
