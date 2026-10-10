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
## worlds the sanctuary's trials face better odds and pass more often (judged
## on the odds, over 24 seeds), and lightning scorches
## the ground and is chronicled.
func long_check_breakthroughs_at_the_tree_and_elsewhere():
	var tally: Dictionary = {"sanctuary": [0, 0, 0.0], "elsewhere": [0, 0, 0.0]}
	var scorched: int = 0
	for seed in range(11, 35):
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
				tally[key][2] += float(trial.get("odds", 0.0))
		for entry in sim.chronicle.entries:
			scorched += 1 if entry.kind == "trial_scorched" else 0
	var rates: Dictionary = {}
	var odds: Dictionary = {}
	for key in tally:
		rates[key] = float(tally[key][1]) / maxf(float(tally[key][0]), 1.0)
		odds[key] = float(tally[key][2]) / maxf(float(tally[key][0]), 1.0)
	print("      sanctuary %d/%d passed (%.0f%%, mean odds %.2f), elsewhere %d/%d (%.0f%%, mean odds %.2f), %d scorchings chronicled" % [tally.sanctuary[1], tally.sanctuary[0],
		rates.sanctuary * 100.0, odds.sanctuary, tally.elsewhere[1], tally.elsewhere[0], rates.elsewhere * 100.0, odds.elsewhere, scorched])
	if tally.sanctuary[0] < 20 or tally.elsewhere[0] < 8:
		return "too few trials in one place or the other: %s" % str(tally)
	# Judged on the odds each trial faced: a hundred-odd rolls are too few to
	# show a 0.2 bonus through the other differences every run.
	if odds.sanctuary < odds.elsewhere + 0.1:
		return "the sanctuary did not help: mean odds %s, passed %s" % [str(odds), str(rates)]
	if scorched == 0:
		return "no scorching was chronicled"
	return ""


## M17 exit: after a lightning tribulation at the tree, spirit fruit
## appears within a season and a cultivator eats it before a breakthrough;
## the chronicle records who got it and why.
func long_check_the_tree_bears_fruit_for_a_trial():
	var sim: RefCounted = Sim.create(11)
	var camp: Vector3i = sim.settlements.entries[1].camp
	for i in range(5):
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), sim.nav.nearest_walkable(camp + Vector3i(i % 3, 0, 2), 4), 1, "")
	sim.run_ticks(12)
	Stores.place_chest(sim, 1)
	Stores.fill(sim, 1, {"berries": 90, "wood": 20})
	var hollow: Array = []
	for agent in sim.agents:
		if agent.settlement_id == 1:
			hollow.append(agent)
	var master: RefCounted = hollow[0]
	master.cultivation = CultivationState.fresh(0.6, "none", 0.8)
	master.cultivation.realm = 2
	master.cultivation.techniques = ["tree_breath"]
	for i in range(1, hollow.size()):
		var disciple: RefCounted = hollow[i]
		disciple.cultivation = CultivationState.fresh(0.5, "none", 0.85)
		disciple.cultivation.realm = 1
		disciple.cultivation.techniques = ["tree_breath"]
		disciple.cultivation.teacher = master.id
		disciple.cultivation.progress = CultivationState.needed(disciple.cultivation) if i == 1 else 140.0 + i * 15.0
		master.cultivation.students.append(disciple.id)
	sim.sects.found(sim, master)
	var first_trial: int = -1
	var ripened: int = -1
	var given: Dictionary = {}
	var eaten: Dictionary = {}
	for _day in range(sim.calendar.days_per_season * 2):
		sim.run_ticks(sim.calendar.ticks_per_day)
		for entry in sim.chronicle.entries:
			match str(entry.kind):
				"tree_insight":
					first_trial = int(entry.day) if first_trial < 0 else first_trial
				"fruit_ripened":
					ripened = int(entry.day) if ripened < 0 else ripened
				"fruit_given", "fruit_kept", "fruit_taken":
					given = entry if given.is_empty() else given
				"fruit_eaten":
					eaten = entry if eaten.is_empty() else eaten
		if not eaten.is_empty():
			break
	print("      first insight day %d, fruit ripened day %d, %s, eaten: %s" % [first_trial, ripened,
		"%s day %d (%s)" % [given.get("kind", "none"), int(given.get("day", -1)), str(given.get("cause", ""))], str(eaten.get("args", {}))])
	if first_trial < 0:
		return "no trial in the sanctuary taught the tree"
	if ripened < 0 or ripened - first_trial > sim.calendar.days_per_season:
		return "no fruit within a season of the first insight"
	if given.is_empty() or str(given.cause).is_empty():
		return "nobody was given the fruit with a reason"
	if eaten.is_empty():
		return "no fruit was eaten before a trial"
	var trial_after: bool = false
	for entry in sim.chronicle.entries:
		if str(entry.kind).begins_with("trial_") and entry.kind != "trial_announced" and entry.agents == eaten.agents and int(entry.tick) >= int(eaten.tick):
			trial_after = true
	return "" if trial_after else "the one who ate the fruit did not face Heaven after"
