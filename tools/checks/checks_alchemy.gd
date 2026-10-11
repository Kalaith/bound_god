extends RefCounted
## M20 Herbs, alchemy and tools: spirit herbs wait for the tree's growth and
## its deep qi, ripen and grow again when gathered.
const Sim = preload("res://scripts/sim/sim.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Herbs = preload("res://scripts/sim/herbs.gd")
const EffectsApply = preload("res://scripts/sim/effects_apply.gd")


## Days of herb growth without the rest of the world.
static func _herb_days(sim: RefCounted, days: int) -> void:
	for day in range(days):
		sim.calendar.tick += sim.calendar.ticks_per_day
		sim.tree_growth.daily(sim)
		sim.herbs.daily(sim)


## No herb grows before the tree reaches its Spirit Root phase; then they
## sprout only where its qi is deep, ripen, and none sprout in winter.
func check_herbs_wait_for_the_tree_and_its_qi():
	var sim: RefCounted = Sim.create(11)
	_herb_days(sim, 3)
	if sim.herbs.count() > 0:
		return "herbs sprouted before the tree had grown"
	sim.tree_growth.maturity = 12.0
	_herb_days(sim, 1)
	if not sim.tree_growth.has_unlock("spirit_herbs"):
		return "the Spirit Root phase did not unlock herbs"
	_herb_days(sim, 4)
	if sim.herbs.count() < 3:
		return "only %d herbs sprouted in five days" % sim.herbs.count()
	for cell in sim.herbs.plants:
		if sim.qi.density(sim, cell) < float(Herbs.settings().qi):
			return "a herb sprouted in thin qi (%.2f at %s)" % [sim.qi.density(sim, cell), cell]
		if sim.voxels.get_block(cell + Vector3i.DOWN) != Registry.id("grass"):
			return "a herb sprouted off the grass"
	var noted: bool = false
	for entry in sim.chronicle.entries:
		noted = noted or entry.kind == "herbs_sprouted"
	if not noted:
		return "the first herbs were not chronicled"
	_herb_days(sim, int(Herbs.settings().ripen_days) + 1)
	var ripe: int = 0
	for cell in sim.herbs.plants:
		if sim.voxels.block_meta(cell) >= Herbs.RIPE:
			ripe += 1
			var site: int = int(sim.sites.by_cell.get(cell, -1))
			if site < 0 or sim.sites.get_site(site).kind != "herb" or int(sim.sites.get_site(site).amount) != 1:
				return "a ripe herb is not a site to gather"
	if ripe == 0:
		return "no herb ripened"
	if sim.herbs.count() > int(Herbs.settings().most):
		return "more herbs than the valley holds"
	# Winter: none sprout.
	var before: int = sim.herbs.count()
	for cell in sim.herbs.plants.keys():
		sim.set_block(cell, 0, 0, "test")
	sim.calendar.tick = (3 * sim.calendar.days_per_season + 1) * sim.calendar.ticks_per_day
	_herb_days(sim, 3)
	if before == 0 or sim.herbs.count() > 0:
		return "herbs sprouted in winter"
	return ""


## Gathering takes a ripe herb and leaves its root to grow again; an unripe
## herb gives nothing; the herbs are saved.
func check_a_gathered_herb_grows_again():
	var sim: RefCounted = Sim.create(11)
	sim.tree_growth.maturity = 12.0
	_herb_days(sim, 3 + int(Herbs.settings().ripen_days) + 1)
	var cell: Vector3i = Vector3i(-1, -1, -1)
	for candidate in sim.herbs.plants:
		if sim.voxels.block_meta(candidate) >= Herbs.RIPE:
			cell = candidate
			break
	if cell.x < 0:
		return "no ripe herb to gather"
	var agent: RefCounted = sim.agents[0]
	agent.carrying = {}
	var site: int = int(sim.sites.by_cell[cell])
	EffectsApply._harvest(sim, agent, {"site": site, "as": ""})
	if agent.carried("herb") != 1.0:
		return "gathering a ripe herb gave %s" % agent.carrying
	if sim.voxels.get_block(cell) != Herbs.block_id() or sim.voxels.block_meta(cell) != 0:
		return "the herb's root did not stay to grow again"
	EffectsApply._harvest(sim, agent, {"site": site, "as": ""})
	if agent.carried("herb") != 1.0:
		return "an unripe herb was gathered"
	_herb_days(sim, int(Herbs.settings().ripen_days))
	if sim.voxels.block_meta(cell) < Herbs.RIPE:
		return "the gathered herb did not ripen again"
	var saved: Dictionary = SimState.capture(sim)
	var restored: RefCounted = SimState.restore(saved.sim, saved.chunks)
	if restored.herbs.to_dict() != sim.herbs.to_dict() or not restored.tree_growth.has_unlock("spirit_herbs"):
		return "the herbs changed in the save"
	return ""
