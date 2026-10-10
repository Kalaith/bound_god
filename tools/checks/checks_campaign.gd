extends RefCounted
## Long-run scenarios (run with --long before a milestone commit): whole
## seasons of a settlement living on its own.
const Sim = preload("res://scripts/sim/sim.gd")
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const Stores = preload("res://tools/checks/stores.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const Standing = preload("res://scripts/sim/standing.gd")


## M14 exit: on seed 11, ten people at Tree Hollow offered a field among the
## village designs, the stores supplied once, sow in spring, harvest, store
## grain and see the first winter through with nobody starving in 40 days;
## the chronicle records the first harvest.
func long_check_a_village_farms_through_its_first_winter():
	var sim: RefCounted = Sim.create(11)
	var camp: Vector3i = sim.settlements.entries[1].camp
	for i in range(8):
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), sim.nav.nearest_walkable(camp + Vector3i(i % 4, 0, 2), 4), 1, "")
	sim.run_ticks(12)
	Stores.place_chest(sim, 1)
	Stores.fill(sim, 1, {"berries": 40, "wood": 40})
	for id in ["timber_cottage", "store_shed", "village_hall", "garden_patch", "field_plot"]:
		var design: Dictionary = Template.from_starter(Data.starter(id)).to_dict()
		design.id = id + "_offered"
		sim.apply_command({"type": "offer_template", "template": design})
	var sown_in_spring: bool = false
	var grain_stored: int = 0
	var winter_people: int = 0
	for _day in range(40):
		sim.run_ticks(sim.calendar.ticks_per_day)
		sown_in_spring = sown_in_spring or (sim.calendar.season_name() == "spring" and not sim.crops.plots.is_empty())
		grain_stored = maxi(grain_stored, sim.settlements.amount(1, "grain"))
		if sim.calendar.day() == 31:
			winter_people = Standing.present(sim, 1)
	var harvest: String = ""
	var starved: Array = []
	for entry in sim.chronicle.entries:
		if entry.kind == "first_harvest" and entry.place == sim.settlements.entries[1].name:
			harvest = "day %d" % entry.day
		if entry.kind == "death" and str(entry.cause) == "cause_starvation":
			starved.append(entry.args.name)
	print("      sown in spring %s, first harvest %s, most grain stored %d, %d people at winter, %d at the end" % [sown_in_spring, harvest, grain_stored, winter_people, Standing.present(sim, 1)])
	if not sown_in_spring:
		return "nothing was sown in spring"
	if harvest.is_empty():
		return "no first harvest was chronicled"
	if grain_stored <= 0:
		return "no grain reached the stores"
	if not starved.is_empty():
		return "people starved: %s" % str(starved)
	if Standing.present(sim, 1) < 10:
		return "Tree Hollow did not keep ten people through the winter (%d)" % Standing.present(sim, 1)
	return ""
