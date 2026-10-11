extends RefCounted
## One abstract hour of a settlement's food (plan §3.1). The same rates as
## the detailed world, without the walking: bushes ripen a berry a day (two in
## a planter's tended soil; only planters in winter) and are picked by
## whoever works; fields are sown when a crop could still ripen, grow a stage
## every few days, and are reaped for the crop's yield; a kitchen turns grain
## and berries into meals. What is produced goes into the chests (what does
## not fit is lost, as a full chest would leave it rotting loose).
## A settlement's record: {bushes: [ids], planted: int, ripe: float,
##   fields: [farmland cells], growth: int (days since sowing, -1 fallow),
##   weedy: bool, made: {resource: float not yet stored}}
const Balance = preload("res://scripts/core/balance.gd")
const Registry = preload("res://scripts/world/block_registry.gd")
const Schedule = preload("res://scripts/agents/schedule.gd")
const Food = preload("res://scripts/sim/food.gd")
const Standing = preload("res://scripts/sim/standing.gd")
const Crops = preload("res://scripts/sim/crops.gd")
const Kitchens = preload("res://scripts/sim/kitchens.gd")
const AbstractPeople = preload("res://scripts/sim/abstract/abstract_people.gd")

## Berries a gatherer brings in an hour, walking between bushes and chests
## included (a pick takes 6 ticks; most of an hour is walking).
const BERRIES_PER_HOUR: float = 4.0
## How far beyond a settlement's edge its people walk to forage.
const FORAGE_REACH: float = 36.0
## Food days in the chests above which nobody goes picking.
const PICK_UNTIL_DAYS: float = 4.0


## The record of what feeds a settlement, read from the world as it stands.
static func survey(sim: RefCounted, id: int) -> Dictionary:
	var settlement: Dictionary = sim.settlements.entries[id]
	var bushes: Array = []
	var planted: int = 0
	var ripe: float = 0.0
	var bush: int = Registry.id("berry_bush")
	for site_id in sim.sites.ids_sorted():
		var site: Dictionary = sim.sites.get_site(site_id)
		if site.kind != "bush" or site.cells.is_empty() or _forager_of(sim, site.cells[0]) != id:
			continue
		var cell: Vector3i = site.cells[0]
		if sim.voxels.get_block(cell) != bush:
			continue
		bushes.append(site_id)
		ripe += sim.voxels.block_meta(cell)
		if Registry.component(sim.voxels.get_block(cell + Vector3i.DOWN)) == "planter":
			planted += 1
	var fields: Array = []
	var growth: int = -1
	for entry in sim.structures.built():
		if entry.functions.has("field") and sim.settlements.at_cell(entry.anchor) == id:
			for cell in entry.components.get("farmland", []):
				fields.append(cell)
				var above: Vector3i = cell + Vector3i.UP
				if sim.crops.plots.has(above):
					var crop: Dictionary = Crops.definition(sim.crops.plots[above].crop)
					growth = maxi(growth, sim.crops.stage(sim, above) * int(crop.days_per_stage) + int(sim.crops.plots[above].days))
	return {"bushes": bushes, "planted": planted, "ripe": ripe, "fields": fields, "growth": growth, "weedy": false,
		"made": {}, "kitchen": _has_function(sim, id, "kitchen")}


## The settlement whose people would pick a bush: the nearest, if it lies
## within a forager's walk of its edge (people forage well beyond their area).
static func _forager_of(sim: RefCounted, cell: Vector3i) -> int:
	var best: int = -1
	var best_distance: float = INF
	for id in sim.settlements.ids():
		var settlement: Dictionary = sim.settlements.entries[id]
		var d: float = Vector2(cell.x - settlement.center.x, cell.z - settlement.center.z).length()
		if d <= float(settlement.radius) + FORAGE_REACH and d < best_distance:
			best = id
			best_distance = d
	return best


static func _has_function(sim: RefCounted, id: int, function: String) -> bool:
	for entry in sim.structures.built():
		if entry.functions.has(function) and sim.settlements.at_cell(entry.anchor) == id:
			return true
	return false


## Working hands this hour: adults in their work hours, by their health.
static func hands(sim: RefCounted, id: int) -> float:
	var sum: float = 0.0
	for agent_id in sim.settlements.entries[id].residents:
		var agent: RefCounted = sim.agents[agent_id]
		if agent.is_present() and not agent.is_child and Schedule.is_work_hours(sim, agent):
			sum += agent.capacity()
	return sum


## Returns the hands left over for building.
static func hour(sim: RefCounted, id: int, record: Dictionary, labour: float, people: int) -> float:
	if labour <= 0.0 or people <= 0:
		return 0.0
	# Food work first while the chests run low; the rest is free for building.
	var food_days: float = Standing.food_days(sim, id)
	if food_days < PICK_UNTIL_DAYS and record.ripe >= 1.0:
		# Only what the stores lack and have room for: the rest keeps on the bush.
		var wanted: float = (PICK_UNTIL_DAYS - food_days) * people * Food.daily_need() / Food.value("berries")
		var picked: float = minf(minf(record.ripe, wanted), labour * BERRIES_PER_HOUR * minf(float(sim.settlements.entries[id].culture.gather), 1.5))
		var stored: int = AbstractPeople.store(sim, id, "berries", int(floor(picked)))
		record.ripe -= stored
		labour -= stored / BERRIES_PER_HOUR
	# Fields want hands at sowing and reaping (a quarter of a hand per bed).
	if int(record.growth) == 0 or int(record.growth) >= (int(Crops.staple().stages) - 1) * int(Crops.staple().days_per_stage) - 1:
		labour -= record.fields.size() * 0.02
	if bool(record.kitchen):
		_cook(sim, id, people)
	return maxf(labour, 0.0)


## Daily: bushes ripen, fields are sown, grow, are reaped or frozen.
static func day(sim: RefCounted, id: int, record: Dictionary) -> void:
	# Fields, kitchens and gardens raised while abstract join the record
	# (looked at again when buildings change, and every ten days).
	if int(record.get("surveyed", -1)) != int(sim.structures.version) or sim.calendar.day() % 10 == 0:
		record["surveyed"] = int(sim.structures.version)
		var fresh: Dictionary = survey(sim, id)
		if fresh.fields.size() != record.fields.size():
			record.fields = fresh.fields
		record.kitchen = fresh.kitchen
		if fresh.bushes.size() != record.bushes.size():
			record.bushes = fresh.bushes
			record.planted = fresh.planted
	var winter: bool = sim.calendar.is_winter()
	var bushes: int = record.bushes.size()
	var most: float = float(bushes * Balance.integer("world.bush_max_berries"))
	var grow: float = float(record.planted) if winter else float(bushes - int(record.planted)) + float(record.planted) * Balance.integer("world.garden_regrow")
	record.ripe = minf(float(record.ripe) + grow / maxf(Balance.number("world.berry_regrow_days"), 1.0), most)
	_fields(sim, id, record)


static func _fields(sim: RefCounted, id: int, record: Dictionary) -> void:
	if record.fields.is_empty():
		return
	var crop: Dictionary = Crops.staple()
	var ripe_at: int = (int(crop.stages) - 1) * int(crop.days_per_stage)
	if not crop.seasons.has(sim.calendar.season_name()):
		if int(record.growth) >= 0:
			sim.chronicle_event("crops_lost", id, {"place": sim.settlements.entries[id].name, "amount": record.fields.size()}, "cause_winter_frost")
		record.growth = -1
		return
	if int(record.growth) < 0:
		if Crops.can_sow(sim, crop):
			record.growth = 0
			record.weedy = false
		return
	# A dry spell stalls the fields as it does the detailed crops.
	if sim.weather != null and sim.weather.dry_days(sim) > int(crop.rain_need):
		sim.weather.note_drought(sim, id, record.fields.size())
		return
	record.growth = int(record.growth) + 1
	if int(record.growth) >= ripe_at:
		var amount: int = int(crop.yield)
		var harvest: float = float(record.fields.size() * amount)
		_make(sim, id, record, str(crop.harvest), harvest)
		if not sim.settlements.entries[id].get("harvested", false):
			sim.settlements.entries[id]["harvested"] = true
			sim.chronicle_event("first_harvest", id, {"place": sim.settlements.entries[id].name, "amount": int(harvest)}, "")
		record.growth = -1


## Fractions carry over; whole units go into the chests.
static func _make(sim: RefCounted, id: int, record: Dictionary, resource: String, amount: float) -> void:
	var made: Dictionary = record.made
	var total: float = float(made.get(resource, 0.0)) + amount
	var whole: int = int(floor(total))
	if whole > 0:
		AbstractPeople.store(sim, id, resource, whole)
	made[resource] = total - whole


## The kitchen cooks while the stores are short of meals and hold a batch.
static func _cook(sim: RefCounted, id: int, people: int) -> void:
	var recipe: Dictionary = Kitchens.recipe()
	var short: int = Food.meals_wanted(people) - sim.settlements.amount(id, "meal")
	var batches: int = mini(short / maxi(int(recipe.outputs.values()[0]), 1), Balance.integer("food.batch_most"))
	for _i in range(batches):
		for resource in recipe.inputs:
			if sim.settlements.amount(id, resource) < int(recipe.inputs[resource]):
				return
		for resource in recipe.inputs:
			AbstractPeople.take(sim, id, resource, int(recipe.inputs[resource]))
		for resource in recipe.outputs:
			AbstractPeople.store(sim, id, resource, int(recipe.outputs[resource]))
