extends RefCounted
## M13 village growth: new buildings with real uses, settlement standing,
## more people, and founding a second settlement.
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const World = preload("res://scripts/world/voxel_world.gd")
const Structures = preload("res://scripts/world/structures.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const Stores = preload("res://tools/checks/stores.gd")
const Work = preload("res://tools/checks/checks_work.gd")
const Construction = preload("res://scripts/sim/construction.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const PlansNeeds = preload("res://scripts/agents/plan_library_needs.gd")
const Plans = preload("res://scripts/agents/plans.gd")
const Places = preload("res://scripts/sim/places.gd")
const ExecuteLife = preload("res://scripts/sim/execute_life.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Daily = preload("res://scripts/sim/daily.gd")
const JobBoard = preload("res://scripts/sim/job_board.gd")
const Perception = preload("res://scripts/sim/perception.gd")

const Need = Personality.Need


## Each valley design is recognised for the function it was made for, both as
## a template and once raised in the world.
func check_valley_designs_have_their_functions():
	var expected: Dictionary = {"timber_cottage": "dwelling", "store_shed": "storehouse", "village_hall": "hall", "garden_patch": "garden"}
	var ids: Array = expected.keys()
	ids.sort()
	for id in ids:
		var design: RefCounted = Template.from_starter(Data.starter(id))
		if not design.functions.has(expected[id]):
			return "%s is not a %s as a design: %s" % [id, expected[id], str(design.functions)]
		var world := World.new(Vector3i(20, 12, 20))
		for z in range(20):
			for x in range(20):
				world.fill(Vector3i(x, 0, z), Registry.id("grass"))
		for block in design.placement(0):
			world.set_block(Vector3i(4, 1, 4) + block[0], block[1], block[2])
		var structures := Structures.new()
		structures.initialize(world)
		var found: Array = []
		for entry in structures.built():
			found.append_array(entry.functions)
		if not found.has(expected[id]):
			return "%s raised in the world is not a %s: %s" % [id, expected[id], str(found)]
		if id == "garden_patch" and found.count("garden") != 1:
			return "one patch of planters was counted as %d gardens" % found.count("garden")
	return ""


## A cottage offered where nobody knows of any stone still goes up: the
## builders raise its walls in planks and the chronicle says why.
func check_builders_raise_walls_in_timber_without_stone():
	var sim: RefCounted = Sim.create(21, {"world": "flat", "size": Vector3i(64, 16, 64), "ground": 4})
	Stores.fill(sim, 1, {"berries": 40, "wood": 60, "thatch": 30})
	sim.run_ticks(12)
	sim.apply_command({"type": "offer_template", "template": Work.cottage()})
	sim.run_ticks(sim.calendar.ticks_per_day * 2)
	if sim.construction.sites.is_empty():
		return "nobody founded a home without stone"
	for id in sim.construction.ids():
		var site: Dictionary = sim.construction.get_site(id)
		if not site.get("made_do", false):
			return "a site was laid out in stone nobody has"
		for entry in site.order:
			if Construction.is_walling(int(entry[1])):
				return "stone walling is still on a timber site"
	if not _chronicled(sim, "site_made_do"):
		return "the chronicle does not say why the walls are timber"
	return ""


## A settlement rises from camp to hamlet to village as it gains people,
## homes, food and the buildings a village needs, and falls back when it
## loses one, with the reason chronicled.
func check_standing_follows_what_a_settlement_has():
	var sim: RefCounted = Sim.create(23, {"world": "flat", "size": Vector3i(80, 16, 80), "ground": 4})
	sim.run_ticks(12)
	Standing.daily(sim)
	if str(sim.settlements.entries[1].standing) != "camp":
		return "two travellers are already a %s" % sim.settlements.entries[1].standing
	var camp: Vector3i = sim.settlements.entries[1].camp
	var spots: Array = [Vector3i(-14, 0, -14), Vector3i(-7, 0, -14), Vector3i(0, 0, -14), Vector3i(7, 0, -14), Vector3i(-14, 0, 8), Vector3i(-7, 0, 8), Vector3i(0, 0, 8)]
	var designs: Array = ["timber_cottage", "timber_cottage", "timber_cottage", "timber_cottage", "timber_cottage", "store_shed", "village_hall"]
	for i in range(designs.size()):
		_raise(sim, designs[i], Vector3i(camp.x, 5, camp.z) + spots[i])
	_raise(sim, "garden_patch", Vector3i(camp.x + 8, 5, camp.z + 8))
	while Standing.present(sim, 1) < 10:
		var agent: RefCounted = Generation.adult(sim.rng, sim.agents.size())
		Population.arrive(sim, agent, sim.nav.nearest_walkable(camp, 6), 1, "")
	var homes: Array = []
	for entry in sim.structures.built():
		if entry.functions.has("dwelling"):
			homes.append(entry.id)
	var index: int = 0
	for agent_id in sim.settlements.entries[1].residents:
		sim.set_home(sim.agents[agent_id], homes[index / 2])
		index += 1
	Stores.fill(sim, 1, {"berries": 80})
	sim.faith.shrines[1].state = "active"
	Standing.daily(sim)
	var standing: String = str(sim.settlements.entries[1].standing)
	if standing != "village":
		return "a housed, fed settlement with a hall, garden and stores is a %s: %s" % [standing, str(Standing.report(sim, 1, "village"))]
	if not _chronicled(sim, "standing_rose"):
		return "becoming a village was not chronicled"
	for entry in sim.structures.built():
		if entry.functions.has("hall"):
			for cell in entry.components.get("table", []):
				sim.set_block(cell, 0, 0, "test")
	Standing.daily(sim)
	if str(sim.settlements.entries[1].standing) != "village":
		return "a village fell on its first day without a hall"
	Standing.daily(sim)
	if str(sim.settlements.entries[1].standing) != "hamlet":
		return "losing the hall for two days did not make the village a hamlet again"
	var last: Dictionary = sim.chronicle.entries.back()
	if last.kind != "standing_fell" or not str(last.cause).contains("cause_lack_hall"):
		return "the fall was not chronicled with the missing hall: " + str(last)
	return ""


static func _raise(sim: RefCounted, id: String, origin: Vector3i) -> void:
	var design: RefCounted = Template.from_starter(Data.starter(id))
	for block in design.placement(0):
		sim.set_block(origin + block[0], block[1], block[2], "test")


static func _chronicled(sim: RefCounted, kind: String) -> bool:
	for entry in sim.chronicle.entries:
		if entry.kind == kind:
			return true
	return false


static func _flat(size: int = 64) -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(size, 16, size), "ground": 4})


static func _structure_with(sim: RefCounted, function: String) -> Dictionary:
	for entry in sim.structures.built():
		if entry.functions.has(function):
			return entry
	return {}


## Time in a hall restores recreation twice as fast as a stroll, and someone
## who knows a hall chooses to gather there.
func check_a_hall_is_where_people_gather():
	var sim: RefCounted = _flat()
	var camp: Vector3i = sim.settlements.entries[1].camp
	_raise(sim, "village_hall", Vector3i(camp.x - 3, 5, camp.z + 5))
	var hall: Dictionary = _structure_with(sim, "hall")
	if hall.is_empty():
		return "the raised hall is not a hall"
	var agent: RefCounted = sim.agents[0]
	agent.beliefs.structures[hall.id] = {"functions": hall.functions.duplicate(), "cell": hall.anchor, "template_id": "", "seen_tick": 0}
	var ids: Array = []
	for option in PlansNeeds.relax(sim, agent):
		ids.append(option.id)
	if not ids.has("gather_in_the_hall"):
		return "someone who knows the hall does not think to gather there: " + str(ids)
	var gain: Array = []
	for inside in [-1, int(hall.id)]:
		agent.inside = inside
		agent.cell = Places.structure_access(sim, int(hall.id), agent.cell) if inside >= 0 else camp
		agent.needs[Need.RECREATION] = 20.0
		ExecuteLife.run(sim, agent, Plans.step(Plans.Op.RELAX, {"ticks": 60}), 1)
		gain.append(agent.need(Need.RECREATION) - 20.0)
	if gain[1] < gain[0] * 1.9:
		return "relaxing in the hall is not faster: %s" % str(gain)
	return ""


## Bushes in planters ripen twice as fast, and people plant berries in empty
## planters of their own accord.
func check_a_garden_is_planted_and_ripens_faster():
	var sim: RefCounted = _flat()
	var camp: Vector3i = sim.settlements.entries[1].camp
	_raise(sim, "garden_patch", Vector3i(camp.x + 4, 5, camp.z + 4))
	var garden: Dictionary = _structure_with(sim, "garden")
	if garden.is_empty():
		return "the raised garden is not a garden"
	var wild: Vector3i = sim.nav.surface(camp.x - 8, camp.z - 8)
	sim.set_block(wild, Registry.id("berry_bush"), 0, "test")
	var tended: Vector3i = Vector3i(-1, -1, -1)
	for planter in garden.components.planter:
		if sim.voxels.get_block(planter + Vector3i.UP) == Registry.id("berry_bush"):
			tended = planter + Vector3i.UP
			sim.set_block(tended, Registry.id("berry_bush"), 0, "test")
			break
	Daily._regrow(sim)
	if sim.voxels.block_meta(tended) != 2 or sim.voxels.block_meta(wild) != 1:
		return "garden bush ripened %d, wild bush %d" % [sim.voxels.block_meta(tended), sim.voxels.block_meta(wild)]
	Stores.fill(sim, 1, {"berries": 40})
	var empty: int = JobBoard.plots(sim, 1).size()
	sim.run_ticks(sim.calendar.ticks_per_day * 2)
	var left: int = JobBoard.plots(sim, 1).size()
	if empty == 0 or left >= empty:
		return "nobody planted the %d empty planters in two days" % empty
	print("      garden: %d empty planters, %d left after two days" % [empty, left])
	return ""


## Wolves will not walk into lantern light, nor hunt someone standing in it;
## the same person in the dark is hunted.
func check_lanterns_keep_wolves_away():
	for lit in [false, true]:
		var sim: RefCounted = _flat()
		var agent: RefCounted = sim.agents[0]
		var spot: Vector3i = agent.cell
		var lantern: Vector3i = spot + Vector3i(1, 0, 1)
		if lit:
			sim.set_block(lantern, Registry.id("lantern"), 0, "test")
			if not sim.is_lit(spot):
				return "a lantern beside someone does not light them"
		var wolf: int = sim.threats.spawn("wolf", sim.nav.nearest_walkable(spot + Vector3i(-9, 0, 0), 2))
		sim.calendar.tick = sim.calendar.ticks_per_day - 60
		var hunted: bool = false
		for _i in range(240):
			sim.step()
			agent.cell = spot
			agent.intention = {}
			if not sim.threats.exists(wolf):
				break
			hunted = hunted or int(sim.threats.entries[wolf].target) == agent.id
			if lit and sim.is_lit(sim.threats.entries[wolf].cell):
				return "a wolf walked into lantern light"
		if hunted != not lit:
			return "a wolf %s someone %s" % ["hunted" if hunted else "ignored", "in lantern light" if lit else "in the dark"]
	return ""


## From a village, believers asked to found a settlement on open land they
## know carry wood there, set down a chest, live there, and the chronicle
## says who founded it; a camp cannot be asked.
func check_a_village_founds_a_second_settlement():
	var sim: RefCounted = Sim.create(11)
	var camp: Vector3i = sim.settlements.entries[1].camp
	for i in range(4):
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), sim.nav.nearest_walkable(camp + Vector3i(i, 0, 2), 4), 1, "")
	for agent in sim.agents:
		if agent.settlement_id == 1:
			agent.faith.knows = true
			agent.faith.devotion = 85.0
			Perception.note_ground(sim, agent, 0)
	sim.faith.shrines[1].favour = 60.0
	sim.run_ticks(12)
	Stores.fill(sim, 1, {"wood": 40, "berries": 40})
	sim.run_ticks(sim.calendar.ticks_per_day / 2)
	var refused: Dictionary = sim.apply_command({"type": "post_request", "kind": "found_settlement", "target": 0, "boon": 10, "slots": 3})
	if refused.ok or refused.reason != "request_not_village":
		return "a camp was asked to found a settlement: " + str(refused)
	sim.settlements.entries[1].standing = "village"
	var posted: Dictionary = sim.apply_command({"type": "post_request", "kind": "found_settlement", "target": 0, "boon": 10, "slots": 3, "days": 15.0})
	if not posted.ok:
		return "the request was refused: " + str(posted)
	var founded: int = -1
	for day in range(10):
		sim.run_ticks(sim.calendar.ticks_per_day)
		founded = sim.settlements.on_ground(0)
		var request: Dictionary = sim.requests.get_request(int(posted.id))
		if request.state == "done":
			break
	if founded < 0:
		return "nobody founded a settlement on %s in ten days" % sim.features.grounds[0].name
	var request: Dictionary = sim.requests.get_request(int(posted.id))
	if request.state != "done":
		return "the founding request is %s with %d living there" % [request.state, Standing.present(sim, founded)]
	if sim.settlements.chest_cells(sim, founded).is_empty():
		return "the new settlement has no chest"
	if not _chronicled(sim, "settlement_founded"):
		return "the founding was not chronicled"
	print("      %s founded on day %d with %d people" % [sim.settlements.entries[founded].name, sim.calendar.day(), Standing.present(sim, founded)])
	return ""
