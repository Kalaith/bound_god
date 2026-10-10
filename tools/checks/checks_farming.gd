extends RefCounted
## M14 fields: farmland makes a field under the open sky, crops grow a stage
## every few days when tended, weeds stop them, frost kills them, Bless
## Growth hurries them, and people sow, weed and reap a field they know.
const Sim = preload("res://scripts/sim/sim.gd")
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const World = preload("res://scripts/world/voxel_world.gd")
const Structures = preload("res://scripts/world/structures.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Crops = preload("res://scripts/sim/crops.gd")
const Stores = preload("res://tools/checks/stores.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const DeliberationFood = preload("res://scripts/agents/deliberation_food.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Balance = preload("res://scripts/core/balance.gd")


func _flat() -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(48, 16, 48), "ground": 4})


## Raises a starter design beside the camp; returns its origin.
static func _raise(sim: RefCounted, id: String, offset: Vector3i) -> Vector3i:
	var camp: Vector3i = sim.settlements.entries[1].camp
	var origin := Vector3i(camp.x + offset.x, 5, camp.z + offset.z)
	for block in Template.from_starter(Data.starter(id)).placement(0):
		sim.set_block(origin + block[0], block[1], block[2], "test")
	return origin


static func _with(sim: RefCounted, function: String) -> Dictionary:
	for entry in sim.structures.built():
		if entry.functions.has(function):
			return entry
	return {}


## The field, granary and cookhouse designs have their functions as designs
## and in the world; a field needs nothing brought, and a roof over it or
## too few beds unmake it.
func check_food_designs_have_their_functions():
	var expected: Dictionary = {"field_plot": "field", "granary": "granary", "cookhouse": "kitchen"}
	for id in ["cookhouse", "field_plot", "granary"]:
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
		if found.count(expected[id]) != 1:
			return "%s raised in the world makes %s" % [id, str(found)]
	if not Template.from_starter(Data.starter("field_plot")).bill.is_empty():
		return "a field asks builders to bring soil"
	var sim: RefCounted = _flat()
	var origin: Vector3i = _raise(sim, "field_plot", Vector3i(4, 0, 4))
	if _with(sim, "field").is_empty():
		return "a field of farmland is not a field"
	sim.set_block(origin + Vector3i(2, 3, 1), Registry.id("planks"), 0, "test")
	if not _with(sim, "field").is_empty():
		return "a field with a roof over it is still a field"
	return ""


## Sown crops grow a stage every few days while tended; untended they gain
## weeds and stop; weeding starts them again; a weedy crop yields half; a
## ripe crop gathers no weeds; frost kills what stands, and the chronicle
## says so.
func check_crops_grow_when_tended_and_die_in_winter():
	var sim: RefCounted = _flat()
	var origin: Vector3i = _raise(sim, "field_plot", Vector3i(4, 0, 4))
	var crop: Dictionary = Crops.staple()
	var a: Vector3i = origin + Vector3i(0, 1, 0)
	var b: Vector3i = origin + Vector3i(5, 1, 3)
	sim.crops.sow(sim, a, crop, "test")
	sim.crops.sow(sim, b, crop, "test")
	var per_stage: int = int(crop.days_per_stage)
	for _day in range(per_stage):
		sim.calendar.tick += sim.calendar.ticks_per_day
		sim.crops.tend(sim, a)
		sim.crops.daily(sim)
	if sim.voxels.block_meta(a) != 1:
		return "a tended crop is at stage %d after %d days" % [sim.voxels.block_meta(a), per_stage]
	if not sim.crops.plots[b].weedy or sim.voxels.block_meta(b) != 0:
		return "an untended crop did not gain weeds and stop growing"
	for _day in range(per_stage * 4):
		sim.calendar.tick += sim.calendar.ticks_per_day
		sim.crops.tend(sim, a)
		sim.crops.tend(sim, b)
		sim.crops.daily(sim)
	# Left alone once ripe, a crop gathers no weeds.
	for _day in range(Balance.integer("farming.weed_days") + 1):
		sim.calendar.tick += sim.calendar.ticks_per_day
		sim.crops.daily(sim)
	if not sim.crops.is_ripe(sim, a) or sim.crops.plots[a].weedy:
		return "a crop did not ripen, or gathered weeds once ripe"
	sim.crops.plots[b].weedy = true
	var full: int = int(sim.crops.reap_yield(a).amount)
	if int(sim.crops.reap_yield(b).amount) >= full:
		return "a weedy crop yields as much as a tended one"
	sim.calendar.tick = 30 * sim.calendar.ticks_per_day
	sim.crops.daily(sim)
	if not sim.crops.plots.is_empty() or sim.voxels.get_block(a) != 0:
		return "winter left crops standing"
	for entry in sim.chronicle.entries:
		if entry.kind == "crops_lost" and str(entry.cause) == "cause_winter_frost":
			return ""
	return "the frost was not chronicled"


## Bless Growth brings every crop in its reach on a stage at once.
func check_bless_growth_hurries_crops():
	var sim: RefCounted = _flat()
	var origin: Vector3i = _raise(sim, "field_plot", Vector3i(4, 0, 4))
	var cell: Vector3i = origin + Vector3i(2, 1, 2)
	sim.crops.sow(sim, cell, Crops.staple(), "test")
	if sim.crops.bless(sim, cell, 6.0) != 1 or sim.voxels.block_meta(cell) != 1:
		return "a blessed crop did not grow a stage"
	return ""


## People who know a field and have seed in their stores sow it in spring,
## weed it and reap the ripe grain into the stores; the first harvest is
## chronicled with who reaped it, and the seed comes back.
func check_people_sow_weed_and_reap_a_field():
	var sim: RefCounted = _flat()
	var camp: Vector3i = sim.settlements.entries[1].camp
	for i in range(2):
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), sim.nav.nearest_walkable(camp + Vector3i(i, 0, 2), 4), 1, "")
	_raise(sim, "field_plot", Vector3i(5, 0, -3))
	Stores.fill(sim, 1, {"berries": 30, "seed": 6})
	for agent in sim.agents:
		agent.beliefs.stock = sim.settlements.stock_of(1).duplicate()
	sim.run_ticks(sim.calendar.ticks_per_day)
	if sim.crops.plots.size() < 4:
		return "only %d crops were sown in a day: %s" % [sim.crops.plots.size(), str(sim.agents[0].decisions.slice(0, 4))]
	for _day in range(int(Crops.staple().days_per_stage) * 3 + 3):
		sim.run_ticks(sim.calendar.ticks_per_day)
		Stores.fill(sim, 1, {"berries": 20, "grain": mini(sim.settlements.amount(1, "grain"), 12), "seed": mini(sim.settlements.amount(1, "seed"), 6)})
	if sim.settlements.amount(1, "grain") <= 0:
		var stages: Array = []
		for cell in sim.crops.plots:
			stages.append([sim.voxels.block_meta(cell), sim.crops.plots[cell].weedy])
		return "no grain reached the stores: crops %s" % str(stages)
	for entry in sim.chronicle.entries:
		if entry.kind == "first_harvest":
			return ""
	return "the first harvest was not chronicled"


## Seed may be shaken from wild grass: someone who knows grass and a field
## to sow counts it as a way to get seed.
func check_wild_grass_gives_seed():
	var sim: RefCounted = Sim.create(11)
	var agent: RefCounted = sim.agents[0]
	sim.run_ticks(30)
	if not agent.beliefs.has_site("grass"):
		return "a traveller by the tree knows no grass"
	if not DeliberationFood.has_seed_means(sim, agent):
		return "wild grass is not counted as a source of seed"
	return ""


## In autumn with little put by, leaders who know a field and a granary
## want both, and say it is fear of winter.
func check_fear_of_winter_drives_fields_and_granaries():
	var sim: RefCounted = _flat()
	sim.calendar.tick = 21 * sim.calendar.ticks_per_day
	Stores.fill(sim, 1, {"berries": 10, "grain": 4})
	var wants: Array = DeliberationFood.wants(sim, 1, 6, {"field": 1})
	var reasons: Dictionary = {}
	for want in wants:
		reasons[want[0]] = want[1]
	if reasons.get("granary", "") != "reason_fear_of_winter":
		return "fear of winter does not make a granary wanted: %s" % str(wants)
	sim.calendar.tick = 2 * sim.calendar.ticks_per_day
	if not DeliberationFood.wants(sim, 1, 6, {"field": 1}).filter(func(w: Array) -> bool: return w[0] == "granary").is_empty():
		return "a granary is wanted in spring with nothing to keep"
	return ""
