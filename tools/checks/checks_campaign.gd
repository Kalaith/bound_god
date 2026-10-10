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
const Work = preload("res://tools/checks/checks_work.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")


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


## M15 exit: on seed 11, with the usual cottage and chest help and no other
## prompting, at least three people reach Qi Refining and a sect forms with
## a master within 30 days.
func long_check_a_sect_forms_under_the_tree():
	var sim: RefCounted = Sim.create(11)
	sim.run_ticks(12)
	Stores.place_chest(sim, 1)
	Stores.fill(sim, 1, {"berries": 40, "wood": 40})
	sim.apply_command({"type": "offer_template", "template": Work.cottage()})
	var founded: int = -1
	while sim.calendar.day() <= 30:
		sim.run_ticks(sim.calendar.ticks_per_day)
	var refining: Array = []
	for agent in sim.agents:
		if agent.is_present() and int(agent.cultivation.realm) >= 1:
			refining.append(agent.given_name)
	for entry in sim.chronicle.entries:
		if entry.kind == "sect_founded" and founded < 0:
			founded = int(entry.day)
	var master: String = ""
	for id in sim.sects.ids():
		var sect: Dictionary = sim.sects.entries[id]
		if sim.agents[int(sect.master)].is_present():
			master = sim.agents[int(sect.master)].full_name()
	print("      %d in Qi Refining by day 30 (%s); sect founded day %d, master %s" % [refining.size(), ", ".join(refining), founded, master])
	if refining.size() < 3:
		return "only %d people reached Qi Refining" % refining.size()
	if founded < 0 or master.is_empty():
		return "no sect with a living master formed"
	return ""


## M16 exit: cultivators at Qi Refining's peak decide for themselves to face
## Heaven, most at the tree and a few (loners) away from it; over several
## worlds the sanctuary's trials succeed more often, and lightning scorches
## the ground and is chronicled.
func long_check_breakthroughs_at_the_tree_and_elsewhere():
	var tally: Dictionary = {"sanctuary": [0, 0], "elsewhere": [0, 0]}
	var scorched: int = 0
	for seed in range(11, 23):
		var sim: RefCounted = Sim.create(seed)
		var camp: Vector3i = sim.settlements.entries[1].camp
		for i in range(6):
			Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), sim.nav.nearest_walkable(camp + Vector3i(i % 3, 0, 2), 4), 1, "")
		sim.run_ticks(12)
		Stores.place_chest(sim, 1)
		Stores.fill(sim, 1, {"berries": 60, "wood": 20})
		var n: int = 0
		for agent in sim.agents:
			if agent.settlement_id != 1:
				continue
			agent.cultivation = CultivationState.fresh(0.6, "none", 0.85)
			agent.cultivation.realm = 1
			agent.cultivation.progress = CultivationState.needed(agent.cultivation) - 5.0
			agent.cultivation.techniques = ["tree_breath"]
			if n % 3 == 2 and not agent.has_trait("loner"):
				agent.traits.append("loner")
			n += 1
		sim.run_ticks(sim.calendar.ticks_per_day * 4)
		for agent in sim.agents:
			for trial in agent.cultivation.get("trials", []):
				var key: String = "sanctuary" if bool(trial.sanctuary) else "elsewhere"
				tally[key][0] += 1
				tally[key][1] += 1 if trial.outcome == "passed" else 0
		for entry in sim.chronicle.entries:
			scorched += 1 if entry.kind == "trial_scorched" else 0
	var rates: Dictionary = {}
	for key in tally:
		rates[key] = float(tally[key][1]) / maxf(float(tally[key][0]), 1.0)
	print("      sanctuary %d/%d passed (%.0f%%), elsewhere %d/%d (%.0f%%), %d scorchings chronicled" % [tally.sanctuary[1], tally.sanctuary[0], rates.sanctuary * 100.0,
		tally.elsewhere[1], tally.elsewhere[0], rates.elsewhere * 100.0, scorched])
	if tally.sanctuary[0] < 10 or tally.elsewhere[0] < 4:
		return "too few trials in one place or the other: %s" % str(tally)
	if rates.sanctuary <= rates.elsewhere:
		return "the sanctuary did not help: %s" % str(rates)
	if scorched == 0:
		return "no scorching was chronicled"
	return ""
