extends RefCounted
## M20b The sect's alchemy, its herbs: each kind grows only where its own
## conditions hold (ginseng in shade, thunder root on Heaven's scars, frost
## lotus by winter water and gone in spring), a herb garden's beds sprout
## spirit herbs in the sun and ginseng in shade and ripen faster, the
## alchemy designs carry their functions, and the new state saves.
const Sim = preload("res://scripts/sim/sim.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Herbs = preload("res://scripts/sim/herbs.gd")
const Alchemy = preload("res://scripts/sim/alchemy.gd")
const Build = preload("res://tools/checks/build.gd")
const Data = preload("res://scripts/core/data.gd")
const Template = preload("res://scripts/building/template.gd")

## Each alchemy design and the function it is built for.
const DESIGNS: Dictionary = {
	"herbalist_hut": "herbal_workshop", "alchemy_room": "alchemy_room", "alchemy_hall": "alchemy_hall",
	"pill_pavilion": "pill_pavilion", "herb_garden": "herb_garden", "ginseng_house": "herb_garden",
}


static func _days(sim: RefCounted, days: int) -> void:
	for day in range(days):
		sim.calendar.tick += sim.calendar.ticks_per_day
		sim.tree_growth.daily(sim)
		sim.herbs.daily(sim)


static func _grown(sim: RefCounted) -> RefCounted:
	sim.tree_growth.maturity = 12.0
	_days(sim, 1)
	return sim


static func _cells_of(sim: RefCounted, id: String) -> Array:
	var result: Array = []
	for cell in sim.herbs.plants:
		if sim.voxels.get_block(cell) == Herbs.block_id(id):
			result.append(cell)
	return result


static func _flat() -> RefCounted:
	var sim: RefCounted = Sim.create(21, {"world": "flat", "size": Vector3i(64, 16, 64), "ground": 4})
	sim.tree_growth.unlocks.append("spirit_herbs")
	return sim


## Ginseng takes only in shade, on grass or earth, where the qi is deep
## enough for it; never under the open sky.
func check_ginseng_grows_in_shade():
	var sim: RefCounted = _grown(Sim.create(11))
	_days(sim, 8)
	var cells: Array = _cells_of(sim, "jade_ginseng")
	if cells.is_empty():
		return "no ginseng sprouted in eight days"
	var config: Dictionary = Herbs.kind("jade_ginseng")
	for cell in cells:
		if sim.voxels.sees_sky(cell):
			return "ginseng sprouted under the open sky at %s" % cell
		if sim.qi.density(sim, cell) < float(config.qi):
			return "ginseng sprouted in thin qi (%.2f)" % sim.qi.density(sim, cell)
		if not sim.voxels.get_block(cell + Vector3i.DOWN) in [Registry.id("grass"), Registry.id("dirt")]:
			return "ginseng sprouted off the ground"
	return ""


## Thunder root waits for Heaven: none grows until lightning scorches the
## earth, then it takes only on the scorched cells.
func check_thunder_root_grows_on_heavens_scars():
	var sim: RefCounted = _grown(Sim.create(11))
	_days(sim, 3)
	if not _cells_of(sim, "thunder_root").is_empty():
		return "thunder root grew before Heaven scorched anything"
	var tree: Vector3i = sim.features.sacred_tree
	var scorched: Array = []
	for i in range(6):
		var x: int = tree.x + 10 + i
		var top: int = sim.voxels.top_solid_y(x, tree.z + 10)
		var cell := Vector3i(x, top, tree.z + 10)
		if sim.set_block(cell, Registry.id("scorched_earth"), 0, "heaven"):
			scorched.append(cell)
	if not sim.herbs.scorched.has(scorched[0]):
		return "the scorched earth was not remembered"
	_days(sim, 4)
	var roots: Array = _cells_of(sim, "thunder_root")
	if roots.is_empty():
		return "no thunder root took on the scars"
	for cell in roots:
		if sim.voxels.get_block(cell + Vector3i.DOWN) != Registry.id("scorched_earth"):
			return "thunder root grew off the scars at %s" % cell
	var noted: bool = false
	for entry in sim.chronicle.entries:
		noted = noted or (entry.kind == "herb_found" and entry.args.get("herb", "") == "resource_thunder_root")
	return "" if noted else "the first thunder root was not chronicled"


## Frost lotus opens only in winter, beside water, and is gone when spring
## comes.
func check_frost_lotus_blooms_by_winter_water():
	var sim: RefCounted = _grown(Sim.create(11))
	_days(sim, 3)
	if not _cells_of(sim, "frost_lotus").is_empty():
		return "frost lotus grew in spring"
	sim.calendar.tick = (3 * sim.calendar.days_per_season) * sim.calendar.ticks_per_day
	_days(sim, 4)
	var lotus: Array = _cells_of(sim, "frost_lotus")
	if lotus.is_empty():
		return "no frost lotus bloomed in winter"
	var water: int = Registry.id("water")
	var reach: int = int(Herbs.search().water_reach)
	for cell in lotus:
		var wet: bool = false
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				for dy in range(-Herbs.BANK, 1):
					wet = wet or sim.voxels.get_block(cell + Vector3i(dx, dy, dz)) == water
		if not wet:
			return "frost lotus bloomed away from water at %s" % cell
	sim.calendar.tick = (4 * sim.calendar.days_per_season) * sim.calendar.ticks_per_day
	_days(sim, 1)
	return "" if _cells_of(sim, "frost_lotus").is_empty() else "frost lotus outlived the winter"


## A herb garden's empty beds sprout spirit herbs in the sun and ginseng
## under a roof, and a bed's herb ripens before a wild one.
func check_a_garden_grows_herbs_in_its_beds():
	var sim: RefCounted = _flat()
	Build.stamp(sim, 1, "herb_garden")
	Build.stamp(sim, 1, "ginseng_house")
	var gardens: Array = []
	for entry in sim.structures.built():
		if entry.functions.has("herb_garden"):
			gardens.append(entry)
	if gardens.size() != 2:
		return "%d herb gardens stand of two" % gardens.size()
	_days(sim, 1)
	var sun: int = 0
	var shade: int = 0
	for cell in sim.herbs.plants:
		if Registry.component(sim.voxels.get_block(cell + Vector3i.DOWN)) != "herb_bed":
			continue
		var name: String = Registry.block_name(sim.voxels.get_block(cell))
		var open: bool = sim.voxels.sees_sky(cell)
		if (name == "spirit_herb") != open:
			return "a bed grew %s %s" % [name, "in the sun" if open else "in shade"]
		sun += 1 if open else 0
		shade += 0 if open else 1
	if sun == 0 or shade == 0:
		return "the beds grew %d herbs in the sun and %d in shade" % [sun, shade]
	var bed: Vector3i = Vector3i(-1, -1, -1)
	for cell in sim.herbs.plants:
		if sim.voxels.get_block(cell) == Herbs.block_id() and sim.voxels.get_block(cell + Vector3i.DOWN) == Registry.id("herb_bed"):
			bed = cell
			break
	# Sprouted today, it ripens in the garden's share of a wild herb's days.
	var days: int = ceili(float(Herbs.settings().ripen_days) / float(Herbs.garden().ripen))
	if days >= int(Herbs.settings().ripen_days):
		return "a bed's herb ripens no faster than a wild one"
	_days(sim, days)
	if sim.voxels.block_meta(bed) < Herbs.RIPE:
		return "a bed's herb was not ripe in %d days" % days
	return ""


## Every alchemy design carries its function, and the tiers and crafters
## rise from the workshop to the pavilion.
func check_the_alchemy_designs_have_their_functions():
	var crafters: Dictionary = {}
	for id in DESIGNS:
		var template: RefCounted = Template.from_starter(Data.starter(id))
		if not template.functions.has(DESIGNS[id]):
			return "the %s design is not a %s (%s)" % [id, DESIGNS[id], template.functions]
		var sim: RefCounted = _flat()
		Build.stamp(sim, 1, id)
		for entry in sim.structures.built():
			if entry.functions.has(DESIGNS[id]) and Alchemy.tier_of(entry) > 0:
				crafters[id] = [Alchemy.tier_of(entry), Alchemy.crafters(entry)]
	if crafters.get("herbalist_hut", []) != [1, 1] or crafters.get("alchemy_room", []) != [2, 1]:
		return "the small buildings are %s" % crafters
	if crafters.get("alchemy_hall", [0, 0])[0] != 3 or int(crafters.alchemy_hall[1]) < 2:
		return "the alchemy hall is %s" % [crafters.get("alchemy_hall")]
	if crafters.get("pill_pavilion", [0, 0])[0] != 4 or int(crafters.pill_pavilion[1]) <= int(crafters.alchemy_hall[1]):
		return "the pill pavilion is %s" % [crafters.get("pill_pavilion")]
	return ""


## Herb kinds, scars, found kinds, benches and what pills left in a person
## all survive a save.
func check_the_alchemy_state_saves():
	var sim: RefCounted = _grown(Sim.create(11))
	_days(sim, 4)
	var tree: Vector3i = sim.features.sacred_tree
	sim.set_block(Vector3i(tree.x + 12, sim.voxels.top_solid_y(tree.x + 12, tree.z), tree.z), Registry.id("scorched_earth"), 0, "heaven")
	sim.alchemy.benches[Vector2i(3, 1)] = {"recipe": "qi_pill", "pot": {"herb": 2}, "at": tree}
	var agent: RefCounted = sim.agents[0]
	agent.cultivation["toxicity"] = 0.3
	agent.cultivation["longevity"] = 20.0
	agent.cultivation["warding"] = true
	var saved: Dictionary = SimState.capture(sim)
	var restored: RefCounted = SimState.restore(saved.sim, saved.chunks)
	if restored.herbs.to_dict() != sim.herbs.to_dict():
		return "the herbs changed in the save"
	if restored.alchemy.to_dict() != sim.alchemy.to_dict():
		return "the benches changed in the save"
	var c: Dictionary = restored.agents[0].cultivation
	if float(c.get("toxicity", 0.0)) != 0.3 or float(c.get("longevity", 0.0)) != 20.0 or not bool(c.get("warding", false)):
		return "what pills left in a person changed in the save"
	return ""
