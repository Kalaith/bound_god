extends RefCounted
## M17 The tree learns: diminishing insight, unlocks gated on insight, the
## sect deciding who gets the fruit, and the tree's history kept in saves.
const Sim = preload("res://scripts/sim/sim.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const FruitChoice = preload("res://scripts/agents/fruit_choice.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")


static func _trial(agent: RefCounted, sanctuary: bool, id: int) -> Dictionary:
	return {"id": id, "agent": agent.id, "kind": "lightning", "severity": 0.6, "shield": 0.0, "defy": false, "site": agent.cell,
		"sanctuary": sanctuary, "outcome": "passed", "state": "done"}


## The first lightning trial in the sanctuary teaches the tree most; each
## after teaches less; a trial away from the tree teaches it nothing.
func check_insight_diminishes():
	var sim: RefCounted = Sim.create(11)
	var agent: RefCounted = sim.agents[0]
	var tree: RefCounted = sim.tree_growth
	tree.on_trial(sim, _trial(agent, false, 1), agent)
	if not tree.insights.is_empty():
		return "a trial away from the tree taught it"
	var gains: Array = []
	for i in range(3):
		var before: float = float(tree.insights.get("lightning", 0.0))
		tree.on_trial(sim, _trial(agent, true, 2 + i), agent)
		gains.append(float(tree.insights.lightning) - before)
	if not (gains[0] > gains[1] and gains[1] > gains[2] and gains[2] > 0.0):
		return "insight did not diminish: %s" % str(gains)
	var first: bool = false
	for entry in sim.chronicle.entries:
		first = first or (entry.kind == "tree_insight" and str(entry.cause) == "cause_first_insight")
	return "" if first else "the first insight was not chronicled as such"


## No fruit grows before the tree has learned enough of lightning; once it
## has, fruit ripens within the season, a few at a time.
func check_fruit_waits_for_the_unlock():
	var sim: RefCounted = Sim.create(11)
	var tree: RefCounted = sim.tree_growth
	for _day in range(5):
		tree.daily(sim)
	if tree.fruit > 0 or tree.has_unlock("spirit_fruit"):
		return "fruit grew before any insight"
	tree.on_trial(sim, _trial(sim.agents[0], true, 1), sim.agents[0])
	if not tree.has_unlock("spirit_fruit"):
		return "a first lightning trial at the tree did not unlock spirit fruit (%s)" % str(tree.insights)
	for _day in range(sim.calendar.days_per_season):
		sim.calendar.tick += sim.calendar.ticks_per_day
		tree.daily(sim)
	if tree.fruit <= 0 or tree.fruit > int(tree.data().fruit.most):
		return "%d fruit after a season" % tree.fruit
	return ""


## A sect's master gives the fruit to the disciple their judgement picks,
## carries it to them, and the chronicle says who and why; the disciple
## holds it for their trial.
func check_the_sect_decides_who_gets_the_fruit():
	var sim: RefCounted = Sim.create(11)
	var camp: Vector3i = sim.settlements.entries[1].camp
	for i in range(3):
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), sim.nav.nearest_walkable(camp + Vector3i(i, 0, 2), 4), 1, "")
	sim.run_ticks(60)
	var hollow: Array = []
	for agent in sim.agents:
		if agent.settlement_id == 1:
			hollow.append(agent)
	var master: RefCounted = hollow[0]
	master.cultivation = CultivationState.fresh(0.6, "none", 0.8)
	master.cultivation.realm = 2
	master.cultivation.techniques = ["tree_breath"]
	master.personality.leadership = 0.8
	for i in range(1, hollow.size()):
		var disciple: RefCounted = hollow[i]
		disciple.cultivation = CultivationState.fresh(0.3 + 0.2 * i, "none", 0.8)
		disciple.cultivation.realm = 1
		disciple.cultivation.teacher = master.id
		disciple.cultivation.progress = CultivationState.needed(disciple.cultivation) * 0.85
		master.cultivation.students.append(disciple.id)
	if sim.sects.found(sim, master) <= 0:
		return "the sect could not be founded"
	sim.tree_growth.unlocks.append("spirit_fruit")
	sim.tree_growth.fruit = 1
	var expected: Array = FruitChoice.choose(sim, sim.sects.entries[1], master)
	for _i in range(sim.calendar.ticks_per_day * 2 / 10):
		sim.run_ticks(10)
		for entry in sim.chronicle.entries:
			if entry.kind != "fruit_given":
				continue
			var recipient: RefCounted = sim.agents[int(entry.agents[1])]
			if not str(entry.cause).begins_with("cause_fruit_"):
				return "the gift has no reason: %s" % str(entry.cause)
			if recipient.id != int(expected[0]):
				return "the fruit went to %s, not the master's choice" % recipient.full_name()
			for _j in range(20):
				sim.run_ticks(10)
				if bool(recipient.cultivation.fruit):
					return ""
			return "the chosen disciple never received the fruit"
	return "no fruit was given in two days: %s" % str(master.decisions.slice(0, 5))


## The tree's insights, scars, fruit and maturity come back from a save.
func check_the_tree_is_saved():
	var sim: RefCounted = Sim.create(11)
	var agent: RefCounted = sim.agents[0]
	sim.tree_growth.on_trial(sim, _trial(agent, true, 1), agent)
	sim.tree_growth.nurture(sim, agent.cell)
	if sim.tree_growth.scars.is_empty():
		return "lightning in the sanctuary left no scars"
	var saved: Dictionary = SimState.capture(sim)
	var restored: RefCounted = SimState.restore(saved.sim, saved.chunks)
	if var_to_bytes(restored.tree_growth.to_dict()) != var_to_bytes(sim.tree_growth.to_dict()):
		return "the tree came back different"
	if absf(restored.qi.density(restored, agent.cell) - sim.qi.density(sim, agent.cell)) > 0.001:
		return "the nurtured qi did not survive the save"
	return ""
