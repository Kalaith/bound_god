extends RefCounted
## M14 food: berries and meals spoil in the stores, granary bins hold grain,
## people eat the best food they believe is stored, kitchens make meals, and
## older saves load with their food dated.
const Sim = preload("res://scripts/sim/sim.gd")
const SimState = preload("res://scripts/sim/sim_state.gd")
const Personality = preload("res://scripts/agents/personality.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const PlansNeeds = preload("res://scripts/agents/plan_library_needs.gd")
const Spoilage = preload("res://scripts/sim/spoilage.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const Stores = preload("res://tools/checks/stores.gd")
const Mind = preload("res://scripts/agents/mind.gd")
const Template = preload("res://scripts/building/template.gd")
const Data = preload("res://scripts/core/data.gd")

const Need = Personality.Need


func _flat(people: bool = true) -> RefCounted:
	return Sim.create(21, {"world": "flat", "size": Vector3i(48, 16, 48), "ground": 4, "people": people})


## Moves the calendar to the dawn of `day` and runs the daily rot.
static func _rot_on(sim: RefCounted, day: int) -> void:
	sim.calendar.tick = (day - 1) * sim.calendar.ticks_per_day
	Spoilage.daily(sim)


## Meals keep three days and berries six, oldest taken first; grain keeps,
## loose food rots too, and the settlement hears where its food went.
func check_berries_and_meals_spoil_in_the_stores():
	var sim: RefCounted = _flat()
	var chest: Vector3i = Stores.place_chest(sim, 1)
	sim.settlements.today = 1
	sim.settlements.chest_add(chest, "berries", 10)
	sim.settlements.chest_add(chest, "meal", 4)
	sim.settlements.chest_add(chest, "grain", 5)
	sim.drop_item(sim.settlements.entries[1].camp, "berries", 3.0)
	_rot_on(sim, 3)
	sim.settlements.chest_add(chest, "berries", 5)
	if sim.settlements.chest_take(chest, "berries", 2) != 2:
		return "berries could not be taken"
	_rot_on(sim, 4)
	if sim.settlements.amount(1, "meal") != 0:
		return "meals kept four days: %s" % str(sim.settlements.chest_contents(chest))
	if sim.settlements.amount(1, "berries") != 13:
		return "berries rotted early or the oldest were not taken first: %s" % str(sim.settlements.chest_contents(chest))
	_rot_on(sim, 7)
	if sim.settlements.amount(1, "berries") != 5 or sim.settlements.amount(1, "grain") != 5:
		return "after six days the old berries should be gone and grain kept: %s" % str(sim.settlements.chest_contents(chest))
	if not sim.items.is_empty():
		return "loose berries did not rot: %s" % str(sim.items)
	var noted: int = 0
	for entry in sim.chronicle.entries:
		if entry.kind == "food_spoiled":
			noted += 1
	if noted != 1:
		return "rotting food was chronicled %d times in one season" % noted
	return ""


## A granary bin takes only grain, twice what a chest holds; a load of
## berries is carried past it to a chest.
func check_a_granary_bin_holds_only_grain():
	var sim: RefCounted = _flat()
	var camp: Vector3i = sim.settlements.entries[1].camp
	var bin: Vector3i = sim.nav.surface(camp.x + 3, camp.z)
	sim.set_block(bin, Registry.id("granary_bin"), 0, "test")
	if not sim.settlements.bins.has(bin):
		return "a granary bin is not a store"
	if sim.settlements.chest_add(bin, "berries", 5) != 0:
		return "a granary bin took berries"
	if sim.settlements.chest_add(bin, "grain", 100) != 80:
		return "a granary bin does not hold 80 grain"
	sim.settlements.chest_take(bin, "grain", 70)
	var chest: Vector3i = Stores.place_chest(sim, 1)
	var from: Vector3i = sim.nav.nearest_walkable(bin + Vector3i(1, 0, 0), 1)
	var berries: Vector3i = sim.settlements.store_access(sim, 1, from, "berries", true)
	if Vector3(berries).distance_to(Vector3(chest)) > 1.9:
		return "berries were taken to the bin, not the chest"
	if Standing.food_days(sim, 1) <= 0.0:
		return "grain in a bin is not counted as food"
	sim.set_block(bin, 0, 0, "test")
	var spilled: float = 0.0
	for id in sim.items:
		if sim.items[id].resource == "grain":
			spilled += float(sim.items[id].amount)
	if spilled != 10.0 or sim.settlements.bins.has(bin):
		return "a broken bin did not spill its grain"
	return ""


## Stores holding meals, grain and berries: a hungry person goes for a meal
## first, and a meal does more good than berries.
func check_people_eat_the_best_food_they_believe_is_stored():
	var sim: RefCounted = _flat()
	Stores.fill(sim, 1, {"berries": 6, "grain": 6, "meal": 6})
	var agent: RefCounted = sim.agents[0]
	agent.carrying = {}
	agent.beliefs.stock = sim.settlements.stock_of(1).duplicate()
	var plans: Array = PlansNeeds.eat(sim, agent)
	var order: Array = []
	for plan in plans:
		order.append(plan.id)
	if order.find("meal_stores") < 0 or order.find("meal_stores") > order.find("grain_stores") or order.find("grain_stores") > order.find("raw_stores"):
		return "eating does not prefer meals, then grain, then berries: %s" % str(order)
	agent.needs[Need.FOOD] = 10.0
	agent.intention = {}
	agent.next_deliberation = sim.calendar.tick
	for _i in range(160):
		sim.step()
		if sim.settlements.amount(1, "meal") < 6:
			break
	if sim.settlements.amount(1, "meal") >= 6:
		return "nobody took a meal: %s" % str(agent.decisions.slice(0, 4))
	for _i in range(40):
		sim.step()
	if not Mind.has(agent, "ate_a_meal"):
		return "eating a meal left no thought"
	return ""


## A save from before fields (schema 3) loads with its food dated the day
## it loads, keeps its people and plays on for a day. Long since M25: the
## schema-5 fixture (checks_release.gd) runs the newer migrations by default.
func long_check_the_village_save_loads_through_migration():
	var file := FileAccess.open_compressed("res://tools/fixtures/save_v3_village.zst", FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return "the village fixture save is missing"
	var saved: Variant = bytes_to_var(file.get_buffer(file.get_length()))
	if not saved is Dictionary or int(saved.sim.get("schema_version", -1)) != 3:
		return "the fixture is not a schema 3 save"
	var problem: String = SimState.problem(saved.sim, saved.chunks)
	if not problem.is_empty():
		return "the village save is refused: " + problem
	var sim: RefCounted = SimState.restore(saved.sim, saved.chunks)
	if sim.present_count() != 12 or sim.calendar.day() != 6:
		return "the village save restored the wrong world: %d people on day %d" % [sim.present_count(), sim.calendar.day()]
	var dated: int = 0
	for cell in sim.settlements.lots:
		for lot in sim.settlements.lots[cell].get("berries", []):
			if int(lot[0]) != 6:
				return "old berries were dated day %d" % int(lot[0])
			dated += int(lot[1])
	var held: int = 0
	for cell in sim.settlements.chests:
		held += int(sim.settlements.chests[cell].get("berries", 0))
	if dated != held:
		return "%d berries in the chests but %d dated" % [held, dated]
	sim.run_ticks(sim.calendar.ticks_per_day)
	if sim.present_count() < 10:
		return "the migrated world lost its people within a day"
	var again: Dictionary = SimState.capture(sim)
	if int(again.sim.schema_version) != SimState.SCHEMA:
		return "the migrated world does not save in the current schema"
	return ""


## With a kitchen and grain and berries in the stores, someone fills the pot,
## cooks, and puts meals in the stores; the first meal is chronicled.
func check_a_kitchen_turns_grain_and_berries_into_meals():
	var sim: RefCounted = _flat()
	var camp: Vector3i = sim.settlements.entries[1].camp
	var origin := Vector3i(camp.x + 4, 5, camp.z + 4)
	for block in Template.from_starter(Data.starter("cookhouse")).placement(0):
		sim.set_block(origin + block[0], block[1], block[2], "test")
	Stores.fill(sim, 1, {"grain": 6, "berries": 30})
	for agent in sim.agents:
		agent.beliefs.stock = sim.settlements.stock_of(1).duplicate()
	for _i in range(sim.calendar.ticks_per_day):
		sim.step()
		if sim.settlements.amount(1, "meal") > 0:
			break
	if sim.settlements.amount(1, "meal") <= 0:
		return "no meals were cooked in a day: %s" % str(sim.agents[0].decisions.slice(0, 6))
	for entry in sim.chronicle.entries:
		if entry.kind == "first_meal" and entry.place == sim.settlements.entries[1].name:
			return ""
	return "the first meal was not chronicled for the settlement"
