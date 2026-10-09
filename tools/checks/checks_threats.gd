extends RefCounted
## M10 acceptance: wolves frighten people and the frightened warn others; a
## wealthy, lightly defended hamlet is raided and its shrine can fall with
## the cause written down; empty buildings decay.
const Sim = preload("res://scripts/sim/sim.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")


func _flat() -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(64, 16, 64), "ground": 4})


func check_a_sighted_wolf_interrupts_and_warns_others():
	var sim: RefCounted = _flat()
	var watcher: RefCounted = sim.agents[0]
	var other: RefCounted = sim.agents[1]
	other.cell = sim.nav.nearest_walkable(watcher.cell + Vector3i(6, 0, 0), 3)
	sim.threats.spawn("wolf", sim.nav.nearest_walkable(watcher.cell + Vector3i(-3, 0, 0), 2))
	for agent in [watcher, other]:
		agent.activity = "idle"
		agent.intention = {}
	sim.run_ticks(6)
	var goal: Dictionary = watcher.current_goal()
	if goal.is_empty() or not int(goal.kind) in [Goals.Kind.FLEE, Goals.Kind.DEFEND]:
		return "a person beside a wolf did not flee or stand: %s" % str(goal)
	if other.beliefs.threats.is_empty():
		return "nobody else was warned of the wolf"
	return ""


func check_a_wealthy_hamlet_is_raided_and_its_shrine_can_fall():
	var sim: RefCounted = Sim.create(11)
	var ruin: Dictionary = sim.features.ruin
	sim.set_block(ruin.altar, Registry.id("altar"), 0, "test")
	var ridge: Dictionary = sim.faith.shrines[2]
	ridge.state = "active"
	sim.settlements.entries[2].stock = {"berries": 30, "stone": 25, "ore": 20, "wood": 25}
	sim.calendar.tick = sim.calendar.ticks_per_day * 11
	var raided: bool = false
	var fell: Dictionary = {}
	for _day in range(14):
		sim.run_ticks(sim.calendar.ticks_per_day)
		for entry in sim.chronicle.entries:
			if entry.kind == "raid_begins" and entry.place == sim.settlements.entries[2].name:
				raided = true
			if entry.kind == "shrine_fell" and fell.is_empty():
				fell = entry
		if not fell.is_empty():
			break
	if not raided:
		return "no raid came to the wealthy hamlet in 14 days"
	if fell.is_empty():
		return "the raiders never reached the ridge altar"
	if not str(fell.cause).contains("cause_raid"):
		return "the fallen shrine's cause does not name the raid: " + str(fell.cause)
	return ""


func check_an_empty_building_decays():
	var sim: RefCounted = _flat()
	var hut: RefCounted = Template.from_starter(Data.starter("miner_hut"))
	var origin: Vector3i = sim.features.sacred_tree + Vector3i(10, 0, 10)
	var layout: Array = []
	for entry in hut.placement(0):
		sim.set_block(origin + entry[0], entry[1], entry[2], "test")
		layout.append([origin + entry[0], entry[1], entry[2]])
	var id: int = sim.structure_id_at(origin + Vector3i(2, 0, 2))
	if id < 0:
		return "the test hut was not recognised"
	sim.settlement_life.remember(sim, id, {"template_id": "miner_hut", "settlement_id": 1}, layout)
	sim.settlement_life.layouts[id].built_tick = -sim.calendar.ticks_for_days(30)
	# Nobody is left to live in it or mend it, and no newcomers arrive.
	sim.director = null
	for agent in sim.agents:
		sim.set_home(agent, -1)
		agent.life = "departed"
	# A block goes with chance 0.15 a day; a month makes the loss near certain.
	sim.run_ticks(sim.calendar.ticks_per_day * 30)
	var missing: int = 0
	for part in layout:
		if sim.voxels.get_block(part[0]) != part[1]:
			missing += 1
	if missing == 0:
		return "an empty, unmended building lost no blocks in 30 days"
	return ""
