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
	if str(sim.settlements.entries[1].standing) != "hamlet":
		return "losing the hall did not make the village a hamlet again"
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
