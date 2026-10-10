extends RefCounted
## Check helpers for meditation: a valley with a young sect beneath the tree,
## and a god who meditates the way a player would: sitting down for a span,
## waking when the world wakes them, playing a pinned person's trial out in
## full, then sitting down again until the span is spent.
const Sim = preload("res://scripts/sim/sim.gd")
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")
const Stores = preload("res://tools/checks/stores.gd")
const Build = preload("res://tools/checks/build.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const AbstractWorld = preload("res://scripts/sim/abstract/abstract_world.gd")
const DeliberationCultivation = preload("res://scripts/agents/deliberation_cultivation.gd")

const DESIGNS: Array[String] = ["timber_cottage", "store_shed", "village_hall", "garden_patch", "field_plot", "granary", "cookhouse"]


## Seed `seed`: Tree Hollow with a dozen people, stores, a field, the valley
## designs offered, and a sect whose master is old (so time can take them).
## Returns {sim, master, members}.
static func valley(seed: int) -> Dictionary:
	var sim: RefCounted = Sim.create(seed)
	var camp: Vector3i = sim.settlements.entries[1].camp
	for i in range(10):
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), sim.nav.nearest_walkable(camp + Vector3i(i % 4 - 2, 0, 2 + i / 4), 4), 1, "")
	sim.run_ticks(12)
	Stores.place_chest(sim, 1)
	Stores.fill(sim, 1, {"berries": 60, "grain": 40, "wood": 40})
	Build.stamp(sim, 1, "field_plot")
	for id in DESIGNS:
		sim.apply_command({"type": "offer_template", "template": Template.from_starter(Data.starter(id)).to_dict()})
	var hollow: Array = []
	for agent in sim.agents:
		if agent.settlement_id == 1 and agent.is_present():
			hollow.append(agent)
	var master: RefCounted = hollow[0]
	# An old master who no longer pushes hard at the Way.
	master.age_years = 115.0
	master.cultivation = CultivationState.fresh(0.4, "wood", 0.0)
	master.cultivation.realm = 1
	master.cultivation.techniques = ["tree_breath"]
	var members: Array = [master.id]
	for i in range(1, 4):
		var disciple: RefCounted = hollow[i]
		disciple.cultivation = CultivationState.fresh(0.5, "none", 0.7)
		disciple.cultivation.realm = 1
		disciple.cultivation.techniques = ["tree_breath"]
		disciple.cultivation.teacher = master.id
		disciple.cultivation.progress = 120.0 + i * 40.0
		master.cultivation.students.append(disciple.id)
		members.append(disciple.id)
	sim.sects.found(sim, master)
	return {"sim": sim, "master": master.id, "members": members}


## Meditates for `days`. `on_trial` is called (sim, agent) when a pinned
## person is about to face Heaven; the trial is then played out in the
## detailed world before meditation resumes. Returns {wakes: Array of kinds,
## abstract_ms, detailed_ms}.
static func meditate(sim: RefCounted, days: float, on_trial: Callable = Callable()) -> Dictionary:
	var end: int = sim.calendar.tick + sim.calendar.ticks_for_days(days)
	var wakes: Array = []
	var abstract_ms: int = 0
	var detailed_ms: int = 0
	var step: int = AbstractWorld.step_for(days, float(sim.calendar.days_per_season * 4))
	while sim.calendar.tick < end - sim.calendar.ticks_per_hour() * step:
		var began: int = Time.get_ticks_msec()
		var model: RefCounted = AbstractWorld.begin(sim)
		model.step = step
		sim.meditating = true
		var reason: Dictionary = model.run_hours(sim, (end - sim.calendar.tick) / sim.calendar.ticks_per_hour())
		model.finish(sim)
		sim.meditating = false
		abstract_ms += Time.get_ticks_msec() - began
		if reason.is_empty():
			break
		wakes.append(str(reason.kind))
		if str(reason.kind) == "trial":
			began = Time.get_ticks_msec()
			var agent: RefCounted = sim.agents[int(reason.agent)]
			sim.tribulations.announce(sim, agent, DeliberationCultivation.trial_site(sim, agent))
			if on_trial.is_valid():
				on_trial.call(sim, agent)
			var guard: int = 0
			while not sim.tribulations.of(agent.id).is_empty() and guard < sim.calendar.ticks_per_day:
				sim.step()
				guard += 1
			detailed_ms += Time.get_ticks_msec() - began
	return {"wakes": wakes, "abstract_ms": abstract_ms, "detailed_ms": detailed_ms}
