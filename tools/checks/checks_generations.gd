extends RefCounted
## M18 long-run scenarios (run with --long): the abstract model against the
## detailed world over twenty days, fifty years of meditation with no word
## from the god, and the key test.
const Meditation = preload("res://tools/checks/meditation.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")
const MeditationSummary = preload("res://scripts/presentation/ui/meditation_summary.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")


## What a valley looks like, for comparing two ways of living twenty days.
static func _tally(sim: RefCounted, from_tick: int) -> Dictionary:
	var result: Dictionary = {"people": sim.present_count(), "hollow": Standing.present(sim, 1), "deaths": 0, "built": 0, "realms": 0, "food": 0.0}
	for entry in sim.chronicle.since(from_tick):
		match str(entry.kind):
			"death":
				result.deaths += 1
			"built":
				result.built += 1
			"realm_reached", "trial_passed", "trial_defied":
				result.realms += 1
	result.food = Standing.food_days(sim, 1)
	return result


## The consistency rule, checked statistically: the same valley lives twenty
## days in the detailed world and twenty in the abstract model, over three
## seeds; people, deaths, building and cultivation land within tolerances.
func long_check_abstract_and_detailed_agree_over_twenty_days():
	var detailed: Dictionary = {"people": 0, "hollow": 0, "deaths": 0, "built": 0, "realms": 0}
	var abstract: Dictionary = detailed.duplicate()
	for seed in [11, 12, 13]:
		var a: Dictionary = Meditation.valley(seed)
		var start: int = a.sim.calendar.tick
		a.sim.run_ticks(a.sim.calendar.ticks_per_day * 20)
		var b: Dictionary = Meditation.valley(seed)
		var model: RefCounted = AbstractWorld.begin(b.sim)
		var end: int = b.sim.calendar.tick + b.sim.calendar.ticks_per_day * 20
		while b.sim.calendar.tick < end - 30:
			model.run_hours(b.sim, (end - b.sim.calendar.tick) / 30)
		model.finish(b.sim)
		var ta: Dictionary = _tally(a.sim, start)
		var tb: Dictionary = _tally(b.sim, start)
		print("      seed %d detailed %s | abstract %s" % [seed, str(ta), str(tb)])
		for key in detailed:
			detailed[key] += int(ta[key])
			abstract[key] += int(tb[key])
	print("      totals detailed %s | abstract %s" % [str(detailed), str(abstract)])
	var people: float = float(abstract.people) / maxf(float(detailed.people), 1.0)
	if people < 0.7 or people > 1.3:
		return "population differs too much: %s against %s" % [abstract.people, detailed.people]
	if absi(int(abstract.deaths) - int(detailed.deaths)) > 6:
		return "deaths differ too much: %d against %d" % [abstract.deaths, detailed.deaths]
	if int(abstract.built) == 0 or int(detailed.built) == 0:
		return "one side built nothing: %d against %d" % [abstract.built, detailed.built]
	var realms: float = float(abstract.realms + 2) / float(detailed.realms + 2)
	if realms < 0.4 or realms > 2.5:
		return "cultivation differs too much: %d against %d" % [abstract.realms, detailed.realms]
	return ""


## Fifty years of meditation with no word from the god: the valley is not
## emptied, the sect's mastery passes on at least once, stock never goes
## below zero, and afterwards nobody is stuck in one plan for two days and
## every open site can still be reached.
func long_check_fifty_years_without_a_word():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var start: int = sim.calendar.tick
	var run: Dictionary = Meditation.meditate(sim, 50.0 * sim.calendar.days_per_season * 4)
	var successions: int = 0
	for entry in sim.chronicle.since(start):
		successions += 1 if entry.kind == "sect_master" else 0
	print("      fifty years in %.1f s abstract; %d present, %d successions, wakes %s" % [run.abstract_ms / 1000.0, sim.present_count(), successions, str(run.wakes)])
	if sim.present_count() == 0:
		return "the valley emptied"
	if successions == 0:
		return "no succession in fifty years"
	for cell in sim.settlements.chests:
		for resource in sim.settlements.chests[cell]:
			if int(sim.settlements.chests[cell][resource]) < 0:
				return "negative stock"
	sim.run_ticks(sim.calendar.ticks_per_day * 3)
	for agent in sim.agents:
		if agent.is_present() and not agent.intention.is_empty() and sim.calendar.tick - int(agent.intention.started_tick) > sim.calendar.ticks_per_day * 2:
			return "%s has held one plan for over two days: %s" % [agent.full_name(), str(agent.intention.goal)]
	var camp: Vector3i = sim.settlements.entries[1].camp
	for id in sim.construction.ids():
		var site: Dictionary = sim.construction.get_site(id)
		if sim.construction.next_entry(id).is_empty():
			continue
		if sim.construction.access(sim, id, sim.nav.nearest_walkable(camp, 3)).x < 0:
			return "an open site of %s cannot be reached" % site.template_id
	return ""


## The key test (plan M18): follow one novice, spend Favour on them at one
## tribulation, meditate fifty years in under a minute, and come back to a
## valley where the sect has new buildings, a new master and older or
## departed members, the followed person's fate is in the summary with its
## cause, and the tree shows the insight and scars of the period.
func long_check_the_key_test():
	var valley: Dictionary = Meditation.valley(11)
	var sim: RefCounted = valley.sim
	var start: int = sim.calendar.tick
	var camp: Vector3i = sim.settlements.entries[1].camp
	var novice: RefCounted = Generation.adult(sim.rng, sim.agents.size())
	novice.cultivation = CultivationState.fresh(0.75, "wood", 0.95)
	novice.age_years = 19.0
	Population.arrive(sim, novice, sim.nav.nearest_walkable(camp + Vector3i(2, 0, 3), 4), 1, "")
	sim.apply_command({"type": "follow", "agent": novice.id})
	var ages: Dictionary = {}
	for id in valley.members:
		ages[id] = sim.agents[id].age_years
	var helped: Array = []
	var before: int = sim.present_count()
	var run: Dictionary = Meditation.meditate(sim, 50.0 * sim.calendar.days_per_season * 4, func(world: RefCounted, agent: RefCounted) -> void:
		if agent.id != novice.id or not helped.is_empty():
			return
		world.faith.get_shrine(1).favour = maxf(float(world.faith.get_shrine(1).favour), 40.0)
		world.god.avatar_cell = agent.cell
		var result: Dictionary = world.apply_command({"type": "cast_miracle", "miracle": "shield_trial", "cell": agent.cell})
		helped.append(result.ok))
	var summary: String = MeditationSummary.text(sim, start, before, {})
	var built: int = 0
	var insights: int = 0
	for entry in sim.chronicle.since(start):
		built += 1 if entry.kind == "built" else 0
		insights += 1 if entry.kind == "tree_insight" else 0
	var sect: Dictionary = sim.sects.in_settlement(1)
	var changed: int = 0
	for id in ages:
		var member: RefCounted = sim.agents[id]
		changed += 1 if not member.is_present() or member.age_years > float(ages[id]) + 40.0 else 0
	print("      abstract %.1f s, detailed %.1f s; wakes %s; shield cast %s" % [run.abstract_ms / 1000.0, run.detailed_ms / 1000.0, str(run.wakes), str(helped)])
	print("      novice: %s, realm %d, trials %s" % [novice.life, int(novice.cultivation.realm), str(novice.cultivation.trials.map(func(t: Dictionary) -> String: return str(t.outcome)))])
	print("      %d built, master %s (was %s), %d of %d first members aged or gone, %d insights, %d scars" % [built, sim.agents[int(sect.get("master", -1))].full_name() if not sect.is_empty() else "none",
		sim.agents[int(valley.master)].full_name(), changed, ages.size(), insights, sim.tree_growth.scars.size()])
	if run.abstract_ms > 60000:
		return "fifty years of meditation took %.1f s" % (run.abstract_ms / 1000.0)
	if helped.is_empty() or not bool(helped[0]):
		return "Favour was never spent on the novice at a trial"
	if built == 0:
		return "nothing new was built"
	if sect.is_empty() or int(sect.master) == int(valley.master) or not sim.agents[int(sect.master)].is_present():
		return "the sect has no new living master"
	if changed < ages.size():
		return "some first members neither aged nor left"
	if not summary.contains(novice.full_name()):
		return "the novice's fate is not in the summary"
	if not novice.is_present() and not summary.contains(novice.full_name() + " ("):
		return "the novice's death is not told with its cause"
	if insights == 0 or sim.tree_growth.scars.is_empty():
		return "the tree shows nothing of the period"
	return ""
