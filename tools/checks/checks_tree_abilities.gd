extends RefCounted
## The tree keeps learning (user request, 2026-10-11): winters and droughts
## its people came through, teaching beneath it and deaths in its shade
## give it insight; insight and its growth phase unlock deep roots, a
## sheltering canopy, awakening fruit and a root network along the paths;
## the god can ripen a fruit for Favour.
const Sim = preload("res://scripts/sim/sim.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Crops = preload("res://scripts/sim/crops.gd")
const Body = preload("res://scripts/sim/body.gd")
const Lifecycle = preload("res://scripts/sim/lifecycle.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const CultivationState = preload("res://scripts/agents/cultivation_state.gd")
const EffectsCultivation = preload("res://scripts/sim/effects_cultivation.gd")
const FruitChoice = preload("res://scripts/agents/fruit_choice.gd")
const TreeAbilities = preload("res://scripts/sim/tree_abilities.gd")
const Miracles = preload("res://scripts/sim/miracles.gd")
const Generation = preload("res://scripts/agents/generation.gd")
const Population = preload("res://scripts/sim/population.gd")

const Need = Personality.Need


## A standable cell `offset` blocks east of the trunk.
static func _near_tree(sim: RefCounted, offset: int) -> Vector3i:
	var tree: Vector3i = sim.features.sacred_tree
	return sim.nav.nearest_walkable(tree + Vector3i(offset, 0, 0), 4)


## Grants an unlock as if the tree had learned it.
static func _unlock(sim: RefCounted, id: String) -> void:
	if not sim.tree_growth.unlocks.has(id):
		sim.tree_growth.unlocks.append(id)


func check_the_tree_learns_from_more_than_lightning():
	var sim: RefCounted = Sim.create(11)
	var tree: RefCounted = sim.tree_growth
	# A drought the valley came through, twice: the second teaches less.
	var gains: Array = []
	for i in range(2):
		var before: float = float(tree.insights.get("drought", 0.0))
		sim.weather.drought_noted = true
		sim.weather.kind = "rain"
		sim.weather.hourly(sim)
		gains.append(float(tree.insights.get("drought", 0.0)) - before)
	if not (gains[0] > gains[1] and gains[1] > 0.0):
		return "droughts did not teach the tree, less each time: %s" % str(gains)
	# Spring after a winter.
	sim.calendar.tick = sim.calendar.ticks_for_days(float(sim.calendar.days_per_season * 4)) + 1
	tree.fruit_season = 3
	tree.daily(sim)
	if float(tree.insights.get("winter", 0.0)) <= 0.0:
		return "a winter came and went and the tree learned nothing"
	# Teaching beneath the crown, and not far away.
	var teacher: RefCounted = sim.agents[0]
	var student: RefCounted = sim.agents[1]
	teacher.cultivation = CultivationState.fresh(0.5, "none", 0.5)
	teacher.cultivation.realm = 1
	teacher.cultivation.techniques = ["tree_breath"]
	teacher.cell = _near_tree(sim, 3)
	EffectsCultivation._teach(sim, teacher, student.id, "tree_breath")
	if float(tree.insights.get("teaching", 0.0)) <= 0.0:
		return "teaching beneath the tree taught it nothing"
	var far: RefCounted = sim.agents[sim.agents.size() - 1]
	far.cultivation = teacher.cultivation.duplicate(true)
	var learner: RefCounted = sim.agents[sim.agents.size() - 2]
	var taught: float = float(tree.insights.teaching)
	EffectsCultivation._teach(sim, far, learner.id, "tree_breath")
	if float(tree.insights.teaching) != taught:
		return "teaching at the hamlet (%s) taught the tree" % str(far.cell)
	# A death in its shade, and one far off.
	Lifecycle.die(sim, far, "cause_old_age")
	if tree.insights.has("mortality"):
		return "a death at the hamlet taught the tree"
	student.cell = _near_tree(sim, 4)
	Lifecycle.die(sim, student, "cause_old_age")
	if float(tree.insights.get("mortality", 0.0)) <= 0.0:
		return "a death in the tree's shade taught it nothing"
	var firsts: Dictionary = {}
	for entry in sim.chronicle.entries:
		if entry.kind == "tree_learned":
			if firsts.has(entry.args.kind):
				return "the tree's lessons of %s were chronicled more than once" % entry.args.kind
			firsts[entry.args.kind] = true
	if firsts.size() != 4:
		return "the first lessons chronicled: %s" % str(firsts.keys())
	return ""


func check_abilities_wait_for_insight_and_phase():
	var sim: RefCounted = Sim.create(11)
	var tree: RefCounted = sim.tree_growth
	tree.insights = {"drought": 6.0, "winter": 9.0, "mortality": 6.0, "teaching": 11.0}
	tree.maturity = 5.0
	tree.daily(sim)
	for id in ["deep_roots", "sheltering_canopy", "awakening_fruit", "root_network"]:
		if tree.has_unlock(id):
			return "%s came before the tree grew to its phase" % id
	tree.maturity = 45.0
	tree.daily(sim)
	if not tree.has_unlock("deep_roots") or not tree.has_unlock("sheltering_canopy"):
		return "deep roots and the canopy did not come at the Ancient Canopy (%s)" % str(tree.unlocks)
	if tree.has_unlock("awakening_fruit"):
		return "awakening fruit came before the tree bore any fruit"
	if tree.has_unlock("root_network"):
		return "the root network came before the Heaven-Touched Tree"
	tree.insights["lightning"] = 6.0
	tree.daily(sim)
	if not tree.has_unlock("awakening_fruit"):
		return "awakening fruit did not follow spirit fruit"
	return ""


func check_deep_roots_water_fields_in_the_qi():
	var sim: RefCounted = Sim.create(11)
	var near: Vector3i = _near_tree(sim, 14) + Vector3i(0, 0, 3)
	near = sim.nav.nearest_walkable(near, 3)
	var far: Vector3i = sim.nav.nearest_walkable(sim.settlements.entries[2].center, 4)
	for cell in [near, far]:
		sim.set_block(cell + Vector3i.DOWN, Registry.id("farmland"), 0, "test")
		sim.crops.sow(sim, cell, Crops.staple(), "test")
	sim.weather.kind = "clear"
	sim.weather.last_wet_day = sim.calendar.day() - int(Crops.staple().rain_need) - 2
	sim.crops.daily(sim)
	if int(sim.crops.plots[near].days) != 0:
		return "a crop by the tree grew in a dry spell without deep roots"
	_unlock(sim, "deep_roots")
	sim.crops.daily(sim)
	if int(sim.crops.plots[near].days) != 1:
		return "deep roots did not water a crop in qi %.2f" % sim.qi.density(sim, near)
	if int(sim.crops.plots[far].days) != 0:
		return "deep roots watered a crop at the hamlet (qi %.2f)" % sim.qi.density(sim, far)
	return ""


func check_the_canopy_shelters_the_homeless():
	var sim: RefCounted = Sim.create(11)
	var agent: RefCounted = sim.agents[0]
	agent.cell = _near_tree(sim, 8)
	agent.inside = -1
	if Body.cover(sim, agent) >= 1.0:
		return "the open ground by the tree was already roofed"
	_unlock(sim, "sheltering_canopy")
	if Body.cover(sim, agent) < 1.0:
		return "the crown did not roof %s, %.1f from the trunk" % [str(agent.cell), Vector2(agent.cell.x - sim.features.sacred_tree.x, agent.cell.z - sim.features.sacred_tree.z).length()]
	agent.cell = sim.nav.nearest_walkable(sim.settlements.entries[2].center, 4)
	if Body.cover(sim, agent) >= 1.0:
		return "the crown roofed the hamlet"
	if not TreeAbilities.shelters_settlement(sim, 1) or TreeAbilities.shelters_settlement(sim, 2):
		return "the canopy's abstract shelter was not Tree Hollow's alone"
	return ""


func check_awakening_fruit_wakes_a_mortal_without_a_realm():
	var sim: RefCounted = Sim.create(11)
	var camp: Vector3i = sim.settlements.entries[1].camp
	for i in range(2):
		Population.arrive(sim, Generation.adult(sim.rng, sim.agents.size()), sim.nav.nearest_walkable(camp + Vector3i(i, 0, 2), 4), 1, "")
	var hollow: Array = []
	for agent in sim.agents:
		if agent.settlement_id == 1:
			hollow.append(agent)
	var master: RefCounted = hollow[0]
	master.cultivation = CultivationState.fresh(0.6, "none", 0.8)
	master.cultivation.realm = 2
	master.cultivation.techniques = ["tree_breath"]
	var disciple: RefCounted = hollow[1]
	disciple.cultivation = CultivationState.fresh(0.5, "none", 0.8)
	disciple.cultivation.realm = 1
	disciple.cultivation.teacher = master.id
	master.cultivation.students.append(disciple.id)
	var mortal: RefCounted = hollow[2]
	mortal.cultivation = CultivationState.fresh(0.2, "none", 0.6)
	if sim.sects.found(sim, master) <= 0:
		return "the sect could not be founded"
	_unlock(sim, "spirit_fruit")
	if int(FruitChoice.choose(sim, sim.sects.entries[1], master)[0]) >= 0:
		return "with nobody near a trial the fruit still found a taker before it could awaken"
	_unlock(sim, "awakening_fruit")
	var choice: Array = FruitChoice.choose(sim, sim.sects.entries[1], master)
	if int(choice[0]) != mortal.id or str(choice[1]) != "cause_fruit_awaken":
		return "the master chose %s (%s), not the mortal" % [str(choice[0]), str(choice[1])]
	var talent: float = float(mortal.cultivation.talent)
	var drive: float = float(mortal.cultivation.drive)
	TreeAbilities.receive(sim, mortal, master)
	var c: Dictionary = mortal.cultivation
	if int(c.realm) != 0 or bool(c.fruit):
		return "the fruit gave a realm or was kept (realm %d)" % int(c.realm)
	if float(c.talent) <= talent and float(c.drive) <= drive:
		return "the fruit woke nothing (talent %.2f, drive %.2f)" % [float(c.talent), float(c.drive)]
	if int(FruitChoice.choose(sim, sim.sects.entries[1], master)[0]) == mortal.id:
		return "an awakened mortal was chosen again"
	# A cultivator keeps the fruit for their trial, as before.
	TreeAbilities.receive(sim, disciple, master)
	if not bool(disciple.cultivation.fruit):
		return "a cultivator did not keep the fruit for their trial"
	return ""


func check_the_god_can_ripen_a_fruit():
	var sim: RefCounted = Sim.create(11)
	var cell: Vector3i = Vector3i(sim.zone_center())
	if Miracles.problem(sim, "ripen_fruit", cell) != "miracle_no_fruit":
		return "fruit could be ripened before the tree bore any: %s" % Miracles.problem(sim, "ripen_fruit", cell)
	_unlock(sim, "spirit_fruit")
	sim.faith.shrines[1].favour = 100.0
	var result: Dictionary = Miracles.cast(sim, "ripen_fruit", cell, {})
	if not result.ok or int(sim.tree_growth.fruit) != 1:
		return "the miracle did not ripen a fruit: %s" % str(result)
	if float(sim.faith.shrines[1].favour) >= 100.0:
		return "ripening cost no Favour"
	sim.tree_growth.fruit = int(sim.tree_growth.data().fruit.most)
	if Miracles.problem(sim, "ripen_fruit", cell) != "miracle_fruit_full":
		return "fruit could be ripened onto full boughs"
	return ""


func check_the_roots_run_along_worn_paths():
	var sim: RefCounted = Sim.create(11)
	var tree: Vector3i = sim.features.sacred_tree
	# A worn path from inside the tree's circle out beyond it, eastward.
	var path: int = Registry.id("path")
	var start: int = tree.x + 14
	var columns: Array = []
	for x in range(start, start + 30):
		var top: int = sim.voxels.top_solid_y(x, tree.z + 12)
		if top < 0:
			continue
		sim.set_block(Vector3i(x, top, tree.z + 12), path, 0, "test")
		sim.paths.wear[Vector2i(x, tree.z + 12)] = 40.0
		columns.append(Vector2i(x, tree.z + 12))
	var end := Vector3(columns.back().x + 0.5, 0.0, columns.back().y + 0.5)
	var beside := Vector3(columns.back().x + 0.5, 0.0, columns.back().y + 8.5)
	TreeAbilities.refresh_roots(sim)
	if sim.in_zone(end):
		return "the path's end was in reach before the roots ran along it"
	_unlock(sim, "root_network")
	TreeAbilities.refresh_roots(sim)
	if not sim.in_zone(end):
		return "the god cannot reach the end of a rooted path"
	if sim.in_zone(beside):
		return "the god reaches off the path"
	var qi: float = sim.qi.density(sim, Vector3i(end))
	if qi < float(sim.tree_growth.data().roots.qi) - 0.001:
		return "the roots carried no qi to the path's end (%.2f)" % qi
	# The reach is derived, not saved: a loaded world finds the same roots.
	var saved: Dictionary = SimState.capture(sim)
	var loaded: RefCounted = SimState.restore(saved.sim, saved.chunks)
	if not loaded.in_zone(end) or loaded.tree_growth.rooted.size() != sim.tree_growth.rooted.size():
		return "a loaded world lost the roots' reach"
	return ""
