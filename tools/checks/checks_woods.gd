extends RefCounted
## The woods: a tree seed set in open ground grows into a tree, leaves left
## without a trunk fall away over the hours, people plant trees where the
## woods near home are thin, and a crowd by the sacred tree spreads round it.
const Sim = preload("res://scripts/sim/sim.gd")
const Balance = preload("res://scripts/core/balance.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Commands = preload("res://scripts/sim/commands.gd")
const Woods = preload("res://scripts/sim/woods.gd")
const Stores = preload("res://tools/checks/stores.gd")
const Goals = preload("res://scripts/agents/goals.gd")
const DeliberationWork = preload("res://scripts/agents/deliberation_work.gd")
const H = preload("res://scripts/agents/plan_helpers.gd")


func _flat() -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(64, 16, 64), "ground": 4})


## Grows a tree on open ground a little way from the camp; returns its site id.
static func _tree(sim: RefCounted, at: Vector3i) -> int:
	sim.set_block(at, Registry.id("sapling"), 0, "test")
	return sim.woods.grow(sim, at)


static func _leaves(sim: RefCounted, cells: Array) -> int:
	var count: int = 0
	for cell in cells:
		if sim.voxels.get_block(cell) == Registry.id("leaves"):
			count += 1
	return count


func check_a_sapling_grows_into_a_tree():
	var sim: RefCounted = _flat()
	var days: int = Balance.integer("world.sapling_grow_days")
	var cell := Vector3i(8, 5, 8)
	sim.set_block(cell, Registry.id("sapling"), 0, "test")
	if not sim.woods.saplings.has(cell):
		return "a planted sapling is not counted"
	for day in range(days - 1):
		sim.woods.daily(sim)
	if sim.voxels.get_block(cell) != Registry.id("sapling"):
		return "the sapling rose before its growing days"
	sim.woods.daily(sim)
	var site: int = int(sim.sites.by_cell.get(cell, -1))
	if site < 0 or sim.sites.get_site(site).kind != "tree":
		return "after its growing days the sapling is not a tree"
	if sim.sites.get_site(site).get("leaves", []).is_empty():
		return "the grown tree has no crown"
	# Winter halts growth.
	var winter := Vector3i(20, 5, 8)
	sim.set_block(winter, Registry.id("sapling"), 0, "test")
	sim.calendar.tick = 3 * sim.calendar.days_per_season * sim.calendar.ticks_per_day + 10
	for day in range(days + 2):
		sim.woods.daily(sim)
	if sim.voxels.get_block(winter) != Registry.id("sapling"):
		return "a sapling grew in winter"
	return ""


func check_leaves_without_a_trunk_fall_over_time():
	var sim: RefCounted = _flat()
	var id: int = _tree(sim, Vector3i(8, 5, 8))
	if id < 0:
		return "no tree grew to test with"
	var site: Dictionary = sim.sites.get_site(id)
	var logs: Array = site.cells.duplicate()
	var leaves: Array = site.leaves.duplicate()
	var full: int = _leaves(sim, leaves)
	if not sim.woods.falling.is_empty():
		return "a whole tree's leaves are falling"
	# Cutting the top log leaves the topmost layer hanging, not the rest.
	logs.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y > b.y)
	sim.set_block(logs[0], 0, 0, "test")
	var hanging: int = sim.woods.falling.size()
	if hanging == 0 or hanging >= full:
		return "cutting the top log left %d of %d leaves falling" % [hanging, full]
	# Felling the rest leaves the whole crown to fall, a few leaves an hour.
	for index in range(1, logs.size()):
		sim.set_block(logs[index], 0, 0, "test")
	if sim.woods.falling.size() != full:
		return "a felled tree has %d of %d leaves falling" % [sim.woods.falling.size(), full]
	sim.woods.hourly(sim)
	var after_hour: int = _leaves(sim, leaves)
	if after_hour == 0 or after_hour == full:
		return "an hour after felling, %d of %d leaves remain" % [after_hour, full]
	for hour in range(48):
		sim.woods.hourly(sim)
	if _leaves(sim, leaves) > 0 or not sim.woods.falling.is_empty():
		return "two days after felling, %d leaves still hang" % _leaves(sim, leaves)
	return ""


func check_the_god_plants_saplings_in_ground_and_finds_seeds_in_leaves():
	var sim: RefCounted = _flat()
	var tree: Vector3i = sim.features.sacred_tree
	var ground := Vector3i(tree.x + 4, 5, tree.z + 1)
	var sapling: int = Registry.id("sapling")
	if Commands.edit_problem(sim, ground, sapling) != "edit_no_stock":
		return "planting without a seed: %s" % Commands.edit_problem(sim, ground, sapling)
	sim.god.add_stock("tree_seed", 2)
	if Commands.edit_problem(sim, ground, sapling) != "":
		return "a seed cannot go in grass: %s" % Commands.edit_problem(sim, ground, sapling)
	var on_stone := Vector3i(tree.x + 5, 6, tree.z + 1)
	sim.set_block(on_stone + Vector3i.DOWN, Registry.id("stone"), 0, "test")
	if Commands.edit_problem(sim, on_stone, sapling) != "edit_needs_ground":
		return "a seed was allowed on stone: %s" % Commands.edit_problem(sim, on_stone, sapling)
	var result: Dictionary = sim.apply_command({"type": "edit_block", "cell": ground, "id": sapling})
	if not result.ok or not sim.woods.saplings.has(ground) or sim.god.stock("tree_seed") != 1:
		return "the god's planting failed: %s" % str(result)
	# About a quarter of leaves hold a seed.
	var holding: int = 0
	for x in range(40):
		if Woods.leaf_holds_seed(Vector3i(x, 9, 7)):
			holding += 1
	if holding < 4 or holding > 18:
		return "%d of 40 leaves hold a seed" % holding
	return ""


func check_the_god_picks_up_seeds_fallen_from_leaves():
	var sim: RefCounted = _flat()
	var tree: Vector3i = sim.features.sacred_tree
	var ground := Vector3i(tree.x + 4, 5, tree.z + 1)
	sim.drop_item(ground, "tree_seed", 1.0)
	sim.drop_item(ground + Vector3i(6, 0, 0), "tree_seed", 1.0)
	var before: int = sim.god.stock("tree_seed")
	var result: Dictionary = sim.apply_command({"type": "gather_items", "cell": ground + Vector3i(1, 0, 0)})
	if not result.ok or sim.god.stock("tree_seed") != before + 1:
		return "walking beside a fallen seed did not pick it up: %s" % str(result)
	if sim.items.size() != 1:
		return "%d items remain where 1 was out of reach" % sim.items.size()
	if sim.command_log.is_empty() or sim.command_log[-1].command.type != "gather_items":
		return "picking up is not in the command log, so a replay would differ"
	if Registry.id("sapling") < 0 or Registry.resource(Registry.id("sapling")) != "tree_seed":
		return "the sapling block is not planted from tree seeds"
	return ""


func check_people_plant_trees_where_the_woods_are_thin():
	var sim: RefCounted = _flat()
	Stores.fill(sim, 1, {"berries": 40, "tree_seed": 4})
	sim.run_ticks(12)
	var board: Dictionary = sim.settlement_life.board(1)
	if board.get("groves", []).is_empty():
		return "a treeless settlement sees nowhere to plant trees"
	var agent: RefCounted = sim.agents[0]
	agent.beliefs.stock = sim.settlements.stock_of(1).duplicate()
	var out: Array = []
	DeliberationWork.add(sim, agent, out)
	if out.filter(func(c: Dictionary) -> bool: return int(c.goal.kind) == Goals.Kind.PLANT_TREES).is_empty():
		return "nobody thinks to plant trees with seed in the stores"
	for day in range(3):
		sim.run_ticks(sim.calendar.ticks_per_day)
		if not sim.woods.saplings.is_empty():
			break
	if sim.woods.saplings.is_empty():
		return "no tree was planted in three days with seed in the stores"
	print("      %d saplings planted by day %d" % [sim.woods.saplings.size(), sim.calendar.day()])
	# Saplings and falling leaves survive a save.
	var saved: Dictionary = SimState.capture(sim)
	var restored: RefCounted = SimState.restore(saved.sim, saved.chunks)
	if restored.woods.saplings.size() != sim.woods.saplings.size():
		return "saplings were lost in a save"
	return ""


func check_a_crowd_spreads_round_the_tree():
	var sim: RefCounted = _flat()
	var tree: Vector3i = sim.features.sacred_tree
	var center := Vector3(tree.x + 1.0, tree.y, tree.z + 1.0)
	var spots: Dictionary = {}
	for id in range(8):
		var cell: Vector3i = H.ring_cell(sim, center, id, 2.5, 5.0)
		if cell.x < 0:
			return "no spot by the tree for person %d" % id
		spots[cell] = true
	if spots.size() < 7:
		return "eight people share only %d spots by the tree" % spots.size()
	return ""
